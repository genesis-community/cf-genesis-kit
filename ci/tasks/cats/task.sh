#!/bin/bash

source kit/ci/scripts/cats.sh
git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

ln -sf $(pwd)/kit/ $(pwd)/work/cf-deployments/dev

safe target da-vault "$VAULT_URI" -k
echo "$VAULT_TOKEN" | safe auth token
safe read secret/handshake
pushd kit
  run_cats --deployment-dir $(pwd)/../
popd