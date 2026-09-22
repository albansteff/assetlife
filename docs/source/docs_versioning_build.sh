#!/usr/bin/env bash
#
# Build the multi-version documentation site under ./docs/build/site/.
# Usage :
#   DOCS_BASE_URL=http://localhost:8000/ uvx tox -e docs-versions   # local preview
#   python -m http.server 8000 -d docs/build/site                   # local server
#
#   uvx tox -e docs-versions                        # from the repository root
#   bash docs/source/docs_versioning_build.sh       # or directly
#
# One folder per major.minor family having a release tag, built from the highest
# patch of that family, plus "latest" built from main. The conf.py always comes 
# from the starting revision, so every version renders with the current build logic.

set -euo pipefail   # Stop script if error or undefined variable and show output

BASE_URL="${DOCS_BASE_URL:-https://docs.assetlife.org/}"   # URL of the site (localhost for debug), ending with /

SITE_DIR=docs/build/site                                   # final site, one folder per version
VENV_DIR=docs/build/venvs                                  # kept across runs, uv resyncs them per version

# Refuse to run over work in progress since it would delete the work with the multiple checkouts
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: commit or stash your changes, this script checks out tags in the working tree" >&2
    exit 1
fi

START_REF="$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)"   # branch or commit if detached (if on a tag)

# Put the repository back to initial state whe script ends (with or without error)
trap 'git checkout --force "$START_REF"' EXIT

# Release tags, pre-releases excluded
release_tags() {
    # `|| true`: no release tag is a valid case, grep must not abort the script through pipefail
    git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true
}

# Highest patch of every major.minor family, newest first, printed as "<tag> <folder>" lines
select_versions() {
    local family
    release_tags | sed -E 's/\.[0-9]+$//' | sort -V -u | tac \   # Delete patch number and sort by version (recent first)
        | while read -r family; do
            echo "$(release_tags | grep -F "$family." | sort -V | tail -1) $family"
        done
}

# $1 - version name ("latest" or "v0.1"), used as DOCS_VERSION (in conf.py) for switcher and as output folder
build_version() {
    local version="$1"

    # A dedicated environment per version build (UV_PROJECT_ENVIRONMENT is built-in uv)
    UV_PROJECT_ENVIRONMENT="$VENV_DIR/$version" DOCS_VERSION="$version" \
        uv run --group docs \
        sphinx-build -b html -d docs/build/doctrees -E ./docs/source "$SITE_DIR/$version"
}

rm -rf "$SITE_DIR"                                         # start from an empty site
mkdir -p "$SITE_DIR" "$VENV_DIR"

# Build main branch in "latest"
echo "=== Building latest ==="
git checkout --force main
git checkout "$START_REF" -- docs/source/conf.py
build_version latest

# Feeds the theme version dropdown
# https://pydata-sphinx-theme.readthedocs.io/en/stable/user_guide/version-dropdown.html
ENTRIES=$(printf '{"name": "latest (dev)", "version": "latest", "url": "%slatest/"}' "$BASE_URL")

while read -r TAG FOLDER; do
    echo "=== Building $TAG into $FOLDER ==="
    git checkout --force "$TAG"                            # --force because conf.py is a modified file
    git checkout "$START_REF" -- docs/source/conf.py       # same conf for all builds
    
    if build_version "$FOLDER"; then
        ENTRIES+=$(printf ',\n  {"name": "%s", "version": "%s", "url": "%s%s/"}' \
            "$TAG" "$FOLDER" "$BASE_URL" "$FOLDER")
    else
        echo "WARNING: skipped $TAG, documentation could not be built" >&2   # a failed tag must not fail the site
    fi
done < <(select_versions)

printf '[\n  %s\n]\n' "$ENTRIES" > "$SITE_DIR/versions.json"   # Write the versions.json file for the dropdown menu

touch "$SITE_DIR/.nojekyll"   # Jekyll ignores folders starting with _

# Create HTML index that redirects to "latest" (main) folder by default
printf '<meta http-equiv="refresh" content="0; url=./latest/">\n' > "$SITE_DIR/index.html"
