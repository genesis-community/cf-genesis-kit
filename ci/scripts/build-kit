#!/bin/bash
set -eu

# Resource Directories
export REPO_ROOT="git"
export BUILD_ROOT="build"
export CI_ROOT="git-ci"
export VERSION_FROM="version/number"

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
test -n "${KIT_SHORTNAME:-}"  || bail "KIT_SHORTNAME must be set to the short name of this kit."
test -n "${VAULT_URI:-}"      || bail "VAULT_URI must be set to an address for connecting to Vault."
test -n "${VAULT_TOKEN:-}"    || bail "VAULT_TOKEN must be set to something; it will be used for connecting to Vault."

test -f "${VERSION_FROM}"     || bail "Version file (${VERSION_FROM}) not found."
VERSION=$(cat "${VERSION_FROM}")
test -n "${VERSION}"          || bail "Version file (${VERSION_FROM}) was empty."

header "Connecting to vault..."
safe target da-vault "$VAULT_URI" -k
echo "$VAULT_TOKEN" | safe auth token
safe read secret/handshake

check_dirs=()
for dir in overlay manifests spec/results; do
  [[ -d "$REPO_ROOT/$dir" ]] && check_dirs+=( "$REPO_ROOT/$dir/" )
done
if [[ ${#check_dirs[@]} -gt 0 ]] ; then
  header "Checking SHA1s of specified components (not including bosh-deployment) ..."
  out="$(eval "spruce merge --skip-eval $( \
    grep -rl '^releases:' "${check_dirs[@]}" \
    | sed -e "s/\\(.*\\)/<(spruce json \\1 | jq -r '{releases: [ \"(( merge on sha1 ))\", .releases[] ]}')/" |tr "\n" " " \
  ) | spruce json | jq -r ." )"
  echo "$out" | spruce merge | spruce json | "${CI_ROOT}/ci/scripts/check-sha1s"
fi

header "Building $KIT_SHORTNAME kit v$VERSION"
genesis -C "$REPO_ROOT" compile-kit -v "$VERSION" -n "$KIT_SHORTNAME"

mv "${REPO_ROOT}/${KIT_SHORTNAME}-${VERSION}.tar.gz" "$BUILD_ROOT/"

echo
echo "================================================================================"
echo "SUCCESS!"
exit 0
