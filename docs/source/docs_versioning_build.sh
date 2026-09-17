#!/usr/bin/env bash
# Build the multi-version Sphinx documentation site under ./_site/.
#
# Run from the repository root, on a checkout with all tags fetched
# (fetch-depth: 0 in the GH Actions checkout).
#
# Environment (set in .github/workflows/gh-pages.yml):
#   DOCS_BASE_URL    public root URL of the site
#   DOCS_N_VERSIONS  number of past major.minor releases to build, besides "latest"
#
# One folder per selected major.minor family, built from the highest patch tag
# of that family, plus "latest" built from main. _site/versions.json feeds the
# theme version dropdown, see:
# https://pydata-sphinx-theme.readthedocs.io/en/stable/user_guide/version-dropdown.html
#
# The docs/ tree is taken from each tag, but conf.py always comes from main so
# every version renders with the current build logic. This script must be
# updated if the docs/ layout changes.

set -euo pipefail

BASE_URL="${DOCS_BASE_URL:-https://docs.assetlife.org/}"
[[ "$BASE_URL" == */ ]] || BASE_URL="$BASE_URL/"

echo "=========================================="
echo "Deploying with URL: $BASE_URL"
echo "=========================================="

# Latest patch tag of each of the N most recent major.minor families,
# newest first, as "<tag> <folder>" lines. Pre-release tags are ignored.
release_tags() {
    # `|| true`: a repository with no release tag yet is a valid case,
    # grep must not abort the whole script through pipefail
    git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true
}

select_versions() {
    local family
    release_tags | sed -E 's/\.[0-9]+$//' | sort -V -u \
        | tail -n "${DOCS_N_VERSIONS:-3}" | tac \
        | while read -r family; do
            echo "$(release_tags | grep -F "$family." | sort -V | tail -1) $family"
        done
}

# $1 - version name ("latest" or "v2.8"), used as DOCS_VERSION and as the
#      output folder name under _site/
build_version() {
    local version="$1"

    cp /tmp/conf_main.py docs/source/conf.py

    # Dependencies of the checked out branch/tag, so that the version metadata
    # read by conf.py matches what is being built.
    # Explicit `return 1`: the caller tests the exit status, which would
    # otherwise be the one of the trailing `rm -rf`.
    python -m pip install . --group dev || return 1

    # -Ea forces a full rebuild: several versions are built on the same machine
    DOCS_VERSION="$version" sphinx-build -M html ./docs/source ./build_tmp -Ea || return 1

    # Keep only the HTML output, drop the sphinx working files
    mkdir -p "_site/$version"
    cp -r ./build_tmp/html/. "_site/$version/"
    rm -rf ./build_tmp
}

mkdir -p _site
# Read from main explicitly: a release published from a maintenance branch
# checks out that tag, not main
git show origin/main:docs/source/conf.py > /tmp/conf_main.py
SELECTION=$(select_versions)

echo "=== Building main into latest ==="
# --force drops changes made to versioned files by a previous build
git checkout --force origin/main
build_version "latest"

# Newline separator, used to accumulate the versions actually built
NL='
'
BUILT=""
while read -r TAG FOLDER; do
    [ -n "$TAG" ] || continue
    echo "=== Building $TAG into $FOLDER ==="
    # Make sure previous builds do not interfere with the current one
    rm -rf docs/ build_tmp/
    git checkout --force "$TAG"
    if build_version "$FOLDER"; then
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
} > _site/versions.json

# Jekyll ignores folders starting with _
touch _site/.nojekyll
cat > _site/index.html <<'EOF'
<!DOCTYPE html>
<meta http-equiv="refresh" content="0; url=./latest/">
EOF

echo "=========================================="
echo "Build completed"
echo "=========================================="
