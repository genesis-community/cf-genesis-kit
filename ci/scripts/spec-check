#!/bin/bash
set -e

# Resource Directories
REPO_ROOT="git"
CI_ROOT="git-ci"
TAG_ROOT="git-latest-tag"
OUTPUT_ROOT="spec-check"

CI_PATH="$(cd "${CI_ROOT}" && pwd)"
TAG="$(cat "${TAG_ROOT}/.git/ref")"
results_file="$(cd "${OUTPUT_ROOT}" && pwd)/diff-$(date -u +%Y%m%d%H%M%S)"

# Run as a script to preserve color output
export CI_PATH
export TAG
pushd "${REPO_ROOT}" &>/dev/null
script --flush --quiet \
  --return  "$results_file" \
  --command '"${CI_PATH}"/ci/scripts/compare-release-specs "$TAG"'

# Trim script header/footer (ignore error)
sed -i '1d;$d' "$results_file" || true
