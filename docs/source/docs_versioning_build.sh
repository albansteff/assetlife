#!/usr/bin/env bash
# 
# Build the multi-version documentation site under ./docs/build/site/.
#
# Run from the repository root, through tox:
#   tox -e docs-versions
# or directly:
#   bash docs/source/docs_versioning_build.sh
#
# To check the result locally serve the site on the port site was built for:
#   DOCS_BASE_URL=http://localhost:8000/ tox -e docs-versions
#   python -m http.server 8000 -d docs/build/site
#
# Environment:
#   DOCS_BASE_URL: public root URL of the site, default https://docs.assetlife.org/
#
# "latest" is always built from the current working tree, so uncommitted
# changes are taken into account. The workflow decides what that working tree
# is through the ref it checks out.
#
# One folder per major.minor family that has a release tag, built from the
# highest patch of that family, plus "latest". versions.json feeds the
# theme version dropdown, see:
# https://pydata-sphinx-theme.readthedocs.io/en/stable/user_guide/version-dropdown.html
#
# The docs/ tree is taken from each tag, but conf.py always comes from "latest"
# so every version renders with the current build logic. This script must be
# updated if the docs/ layout changes.

set -euo pipefail

BASE_URL="${DOCS_BASE_URL:-https://docs.assetlife.org/}"
[[ "$BASE_URL" == */ ]] || BASE_URL="$BASE_URL/"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SITE_DIR="$REPO_ROOT/docs/build/site"
# Worktrees only, the cleanup below removes everything it finds here
WORK_DIR="$REPO_ROOT/docs/build/versions"
# Kept across runs, uv resyncs them against the lock of the version being built
VENV_DIR="$REPO_ROOT/docs/build/venvs"
CONF_MAIN="$REPO_ROOT/docs/build/conf_latest.py"

echo "=========================================="
echo "Site URL : $BASE_URL"
echo "=========================================="

# Leave no worktree behind, including when the build is interrupted
cleanup() {
    local dir
    for dir in "$WORK_DIR"/*/; do
        [ -d "$dir" ] || continue
        git worktree remove --force "$dir" 2>/dev/null || rm -rf "$dir"
    done
    git worktree prune
}
trap cleanup EXIT

# Latest patch tag of every major.minor family, newest first, as
# "<tag> <folder>" lines. Pre-release tags are ignored.
release_tags() {
    # `|| true`: a repository with no release tag yet is a valid case,
    # grep must not abort the whole script through pipefail
    git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true
}

select_versions() {
    local family
    release_tags | sed -E 's/\.[0-9]+$//' | sort -V -u | tac \
        | while read -r family; do
            echo "$(release_tags | grep -F "$family." | sort -V | tail -1) $family"
        done
}

# $1 - directory holding the repository at the revision to build
# $2 - version name ("latest" or "v0.1"), used as DOCS_VERSION and as the
#      output folder name under docs/build/site/
build_version() {
    local src="$1" version="$2"

    # Make sure the conf file in the same for all builds
    [ "$src" = "$REPO_ROOT" ] || cp "$CONF_MAIN" "$src/docs/source/conf.py"

    # A dedicated environment per version: the doc toolchain and the metadata
    # read by conf.py must be the ones of the revision being built.
    # -Ea forces a full rebuild, the output directory may be a stale one
    (
        cd "$src"
        export UV_PROJECT_ENVIRONMENT="$VENV_DIR/$version"
        DOCS_VERSION="$version" uv run --group docs \
            sphinx-build -M html ./docs/source ./docs/build -Ea
    ) || return 1

    rm -rf "${SITE_DIR:?}/$version"
    mkdir -p "$SITE_DIR/$version"
    cp -r "$src/docs/build/html/." "$SITE_DIR/$version/"
}

rm -rf "${SITE_DIR:?}"
mkdir -p "$WORK_DIR" "$VENV_DIR" "$SITE_DIR"
cleanup

cp "$REPO_ROOT/docs/source/conf.py" "$CONF_MAIN"

SELECTION=$(select_versions)

echo "=== Building the working tree into latest ==="
build_version "$REPO_ROOT" "latest"

# Newline separator, used to accumulate the versions actually built
NL='
'
BUILT=""
while read -r TAG FOLDER; do
    [ -n "$TAG" ] || continue
    echo "=== Building $TAG into $FOLDER ==="
    git worktree add --detach "$WORK_DIR/$FOLDER" "$TAG"
    if build_version "$WORK_DIR/$FOLDER" "$FOLDER"; then
        BUILT="$BUILT$TAG $FOLDER$NL"
    else
        echo "WARNING: skipped $TAG, documentation could not be built" >&2
    fi
done <<< "$SELECTION"

# Written after the builds so a version that failed to build leaves no dead
# entry in the dropdown
{
    printf '[\n  {"name": "latest (dev)", "version": "latest", "url": "%slatest/"}' "$BASE_URL"
    while read -r tag folder; do
        [ -n "$tag" ] || continue
        printf ',\n  {"name": "%s", "version": "%s", "url": "%s%s/"}' "$tag" "$folder" "$BASE_URL" "$folder"
    done <<< "$BUILT"
    printf '\n]\n'
} > "$SITE_DIR/versions.json"

# Jekyll ignores folders starting with _
touch "$SITE_DIR/.nojekyll"
cat > "$SITE_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<meta http-equiv="refresh" content="0; url=./latest/">
EOF

echo "=========================================="
echo "Build completed for $BASE_URL"
echo "Serve docs/build/site/ on the port that URL points to"
echo "=========================================="
