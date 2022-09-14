#!/bin/bash
#
# ci/scripts/shipit
#
# Script for generating Github release / tag assets
# and managing release notes for a BOSH Release pipeline
#
# author:  James Hunt <james@niftylogic.com>
# created: 2016-03-30
# shellcheck disable=2291

set -eu

header() {
	echo
	echo "================================================================================"
	echo "$1"
	echo "--------------------------------------------------------------------------------"
	echo
}

bail() {
	echo >&2 "$*  Did you misconfigure Concourse?"
	exit 2
}
export REPO_ROOT="git"
export BUILD_ROOT="build"
export RELEASE_NOTES_ROOT="release-notes"
export VERSION_FROM="version/number"
[[ "${PRERELEASE:-0}" =~ (0|f|false|n|no) ]] && PRERELEASE=""


test -f "${VERSION_FROM}"     || bail "Version file (${VERSION_FROM}) not found."
VERSION=$(cat ${VERSION_FROM})
test -n "${VERSION}"          || bail "Version file (${VERSION_FROM}) was empty."

test -n "${DEVELOP_BRANCH:-}" || bail "DEVELOP_BRANCH must be set to the development Git repository branch."
test -n "${RELEASE_BRANCH:-}" || bail "RELEASE_BRANCH must be set to the main Git repository branch."

if [[ -n "${PRERELEASE}" ]] ; then
	RELEASE_NOTES_PATH="pre-release-notes"
	cat <<EOF > "$RELEASE_NOTES_PATH"
<!--- Release Notes for v${VERSION} -- Do not move --->
This is a prerelease - please see commit messages for changes
EOF
else 
  test -n "${GIT_EMAIL:-}"      || bail "GIT_EMAIL must be set to an email address to use for Git commits."
  test -n "${GIT_NAME:-}"       || bail "GIT_NAME must be set to something; it will be used for Git commits."
  test -n "${RELEASE_ROOT:-}"   || bail "RELEASE_ROOT must be set to the output directory where release artifacts should go."
  test -n "${RELEASE_NOTES:-}"  || bail "RELEASE_NOTES must be set to the filename of the release notes."
  RELEASE_NOTES_PATH="${RELEASE_NOTES_ROOT}/${RELEASE_NOTES}"
  test -f "${RELEASE_NOTES_PATH}" || \
    bail "Release notes file (${RELEASE_NOTES_PATH}) not found."
fi

test -n "${KIT_SHORTNAME:-}"  || bail "KIT_SHORTNAME must be set to the short name of this kit."
test -n "${GITHUB_OWNER:-}"   || bail "GITHUB_OWNER must be set to the name of the Github user or organization that owns the Git repository."
echo "Environment OK"

###############################################################
header "Assembling Github Release Artifacts..."
mkdir -p "${RELEASE_ROOT}/artifacts"
echo "v${VERSION}"           "-> ${RELEASE_ROOT}/tag"
echo "v${VERSION}"            > "${RELEASE_ROOT}/tag"
echo "v${VERSION}"           "-> ${RELEASE_ROOT}/name"
echo "v${VERSION}"            > "${RELEASE_ROOT}/name"
if [[ -n "$PRERELEASE" ]] ; then
  echo "$(cat git/.git/ref)" "-> ${RELEASE_ROOT}/commit (pre-release)"
  cp    git/.git/ref            "${RELEASE_ROOT}/commit"
fi
cp -av "${BUILD_ROOT}"/*.tar.gz "${RELEASE_ROOT}/artifacts"

if [[ -d spec-check ]] ; then
  if ! grep "No Spec Changes to Consider" spec-check/diff-* ; then
    echo spec-check/diff-* "-> ${RELEASE_ROOT}/artifacts/spec-diffs.html"
    cat spec-check/diff-* | aha > "${RELEASE_ROOT}/artifacts/spec-diffs.html"
  else
    echo "spec-check -> no changes in specs to release"
  fi
fi

header "Release Notes for v${VERSION}"
header="$(sed -i -e '1{w /dev/stdout' -e 'd}' "${RELEASE_NOTES_PATH}")"
re="^<\!--- Release Notes for v${VERSION} -- Do not move --->$"
if [[ "$header" =~ $re ]] ; then
  sed -i  '/^---8<--- This line and everything below will be ignored ---8<---$/,$d' "${RELEASE_NOTES_PATH}"
  cat "${RELEASE_NOTES_PATH}"
  cp "${RELEASE_NOTES_PATH}" "$RELEASE_ROOT/notes.md"
else
  echo "Failed to find release notes for v$VERSION in $RELEASE_NOTES_PATH.  Found this instead:"
  echo
  echo "$header"
  cat "${RELEASE_NOTES_PATH}"
  exit 1
fi

if [[ -z "${PRERELEASE}" && "$DEVELOP_BRANCH" != "$RELEASE_BRANCH" ]] ; then
  header "Fast-forward merge develop into ${RELEASE_BRANCH}"
  pushd git-main &>/dev/null
    git config --global user.name  "${GIT_NAME}"
    git config --global user.email "${GIT_EMAIL}"
    if ! git pull ../git -X theirs --no-edit --ff-only ; then
      # if this fails, manual intervention is required.
      echo >&2 \
        $'\n'"'$RELEASE_BRANCH' release branch contains commits that the '$DEVELOP_BRANCH' does not have" \
        $'\n'"Cannot push changes to release branch..."
      exit 1
    fi
  popd &>/dev/null
fi

cat > "${NOTIFICATION_OUT:-notifications}/message" <<EOS
New ${KIT_SHORTNAME} Genesis Kit v${VERSION} released. <https://github.com/${GITHUB_OWNER}/${KIT_SHORTNAME}-genesis-kit/releases/tag/v${VERSION}|Release notes>.
EOS

echo
echo "--------------------------------------------------------------------------------"
echo "SUCCESS"
exit 0
