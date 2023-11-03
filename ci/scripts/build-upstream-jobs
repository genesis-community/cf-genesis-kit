#!/bin/bash -
set -ue
base_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "${base_dir}/pipeline/upstream/"

_lookup() {
 echo "${1}" | base64 --decode | jq -r "${2}"
}

# Read upstream.yml
update_group=()
upstream_details="$(spruce json "${base_dir}/settings.yml" | jq -r '.meta.upstream.bosh_releases//[] | .[] | @base64')"

# For each release in upstream.yml,
for release in $upstream_details ; do
  name="$(_lookup "$release" .name)"
  type="$(_lookup "$release" '.type//"bosh-io-release"')"
  path="$(_lookup "$release" '.path//"manifests/releases/'"$name"'.yml"')"
  repo="$(_lookup "$release" '.repository')"
  if [[ $type == 'bosh-io-release' ]] ; then
    source=$'\n'"      repository: $repo";
  elif [[ $type == 'github-release' ]] ; then
    owner="$(_lookup "$release" '.owner//""')"
    if [[ -z "$owner" && "$repo" =~ / ]] ; then
      owner="${repo%%/*}"
      repo="${repo#*/}"
    fi
    source=$'\n'"      repository: $repo"$'\n'"      owner: $owner";

    token="$(_lookup "$release" '.access_token//""')"
    if [[ -n "$token" ]] ; then
      source="$source"$'\n      access_token: "'"$token"'"'
    fi
  else
    echo >&2 "Unknown resource type for $name upstream release: $type"
    echo >&2 "Expecting one of: bosh-io-release, github-release"
    echo >&2 "Update upstream.bosh-releases configuration in ci/settings.yml"
    exit 1
  fi
  job="update-${name}-release"
  release="${name}-release"

  update_group+=( "$job" )

  cat <<EOF >> "$base_dir/pipeline/upstream/update_${name}_release.yml"
jobs:
- (( append ))
- name: $job
  public: false
  serial: true
  serial_groups: [upstream-releases]
  plan:
  - do:
    - in_parallel:
      - { get: git,    trigger: false, passed: [spec-tests] }
      - { get: git-ci, trigger: false  }
      - get: $release
        trigger: true
        params:
          tarball: false
    - task: $job
      file: git-ci/ci/tasks/update-release.yml
      input_mapping: {bosh-release: $release}
      params:
        RELEASE_NAME:  $name
        RELEASE_PATH:  $path
        BRANCH:        (( grab meta.github.branch ))
        GIT_EMAIL:     (( grab meta.git.email ))
        GIT_NAME:      (( grab meta.git.name ))
    - put: git
      params:
        merge: true
        repository: git

resources:
  - (( append ))
  - name: $release
    type: $type
    check_every: 24h
    source: $source
EOF

done
group_file="$base_dir/pipeline/upstream/update_group.yml"
if [[ "${#update_group[@]}" -gt 0 ]] ; then
  (
  echo "groups:"
  echo "- (( merge on name ))"
  echo "- name: upstream"
  echo "  jobs:"
  echo "  - (( append ))"
  for job in ${update_group[@]+"${update_group[@]}"} ; do
    echo "  - $job"
  done
  ) >> "$group_file"
elif [[ -f "$group_file" ]] ; then
  rm -f "$group_file"
fi
