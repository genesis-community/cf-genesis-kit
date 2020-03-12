function lookup(){
  genesis -C "$GENESIS_ROOT" lookup "$GENESIS_ENVIRONMENT" "$@"
}
function run_local(){
  export tmpdir=$(mktemp -d -t cats.XXXXXXXXXX)
  trap "rm -rf ${tmpdir}" EXIT
  echo "REPO: $CATS_GIT_SSH_URL VERSION: $VERSION"
  git clone ${CATS_GIT_SSH_URL} ${tmpdir}
  pushd ${tmpdir}
    git checkout ${VERSION}
    git submodule update --init
  popd
}
function run_cats(){
  case $1 in
    "--local")
      RUN_LOCAL=true
      export CATS_GIT_SSH_URL=$(spruce json ci/settings.yml | jq -r '.meta.cats.git_ssh_url')
      export VERSION=$(spruce json ci/settings.yml | jq -r '.meta.cats.tag')
      RUN_CATS=""
    ;;
    "--deployment-dir")
      echo "FOUND DEPL. DIR FLAG"
      export BUILD_ROOT=$2
      export GENESIS_ROOT=$BUILD_ROOT/work/cf-deployments
      export GENESIS_ENVIRONMENT=ci-baseline
      export vault=/secret/ci/baseline/cf
    ;;
  esac
  echo "$GENESIS_ROOT"
  base=$(lookup params.base_domain)
  system_domain=$(lookup params.system_domain system.$base)
  export API_URL=api.$system_domain
  export ADMIN_PASSWORD=$(safe read $vault/admin_user:password)
  export APP_DOMAINS_0=run.$base
  case $RUN_CATS in
    "include_container_networking")
      sed -i "s#include_security_groups:.*#include_security_groups: true#g" manifests/cf/cats.yml
    ;;
    "include_deployments")
      sed -i "s#include_v3:.*#include_v3: true#g" manifests/cf/cats.yml
    ;;
    "include_service_instance_sharing")
      sed -i "s#include_services:.*#include_services: true#g" manifests/cf/cats.yml
    ;;
    "include_sso")
      sed -i "s#include_services:.*#include_services: true#g" manifests/cf/cats.yml
    ;;
    "include_tasks")
      sed -i "s#include_v3:.*#include_v3: true#g" manifests/cf/cats.yml
    ;;
    "include_zipkin")
      sed -i "s#include_routing:.*#include_routing: true#g" manifests/cf/cats.yml
    ;;
  esac
  if [[ ${RUN_LOCAL} ]]; then
    echo "RUNNING LOCALLY"
    run_local
  else
    sed -i "s#${RUN_CATS}:.*#${RUN_CATS}: true#g" manifests/cf/cats.yml
    tmpdir="$BUILD_ROOT/cats"
  fi
  export CONFIG=${tmpdir}/config.json
  spruce merge manifests/cf/cats.yml | spruce json | jq '.' > ${CONFIG}
  pushd ${tmpdir}
  FAILFAST_FLAG=""
  VERBOSE_FLAG=""
  if [[ ${FAILFAST}=="true" ]];then
    FAILFAST_FLAG="--failFast"
  fi
  if [[ ${VERBOSE}=="true" ]];then
    VERBOSE_FLAG="-v"
  fi
  ./bin/test -nodes=${CATS_NODES:-4} ${VERBOSE_FLAG}
}
