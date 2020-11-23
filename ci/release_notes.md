# Major Release: 2.0.0

This is the official v2.0.0 release of the cf-genesis-kit, the Genesis kit for Cloud Foundry, and the first to be based on the `cf-deployment` de-facto method for deploying Cloud Foundry.  Previous v1.x kit releases were originally based on `cf-release` but heavily curated by Stark & Wayne.

This release is based on upstream `cf-deployment` v12.25.0.

See MANUAL.md for full details of the release, but the following are specific highlights and caveats, particularly for migration of existing v1 deployments:

- You will need to be on v1.10.1 of the cf-genesis-kit to upgrade.

- App Autoscaler is no longer part of the cf-genesis-kit.  Please use the standalone cf-app-autoscaler-genesis-kit.  If using external database, you can migrate by simply disabling the feature in cf kit, deploying, then deploying the cf-app-autoscaler kit using the same configuration.  If using internal databse for the app autoscaler, you will need to dump and restore the database as appropriate.

- NFS volume services is now part of the kit, thanks to upstream operations file.  Note, this is currently only compatible with local MySQL database.

- Most of the existing kit features are still available. See MANUAL.md for details.

- New explicit Minio blobstore support.  If you are currently using the `aws-blobstore` feature and overriding the endpoint, please switch to using `minio-blobstore` and configuring `params.blobstore_minio_endpoint`.  No need to set `params.aws_region` anymore, or specify a fog configuration block.

- Users of external databases, special action may be needed on your part during the migration.  See MANUAL.md for details regarding correct method to ensure access to the External Database after migrating to v2.0.0.

- Upstream `cf-deployment` uses a very concise set of vm_types and availability zones.  If you currently specify overrides to these, please be advised that they will not work as-is in 2.0.0 -- you will need to modify your cloud config to match what `cf-deployment` expects, or add `instance_groups` overrides in your environment file; setting `params` will not have any effect.

- For the most part, secrets stored in Vault are seamlessly migrated into Credhub.  The exception of course if for any non-default secrets that are specified in your environment file, such as per-database user passwords for external database.  These will have to be manually transferred into Credhub and the environment file updated to reflect the new location.

- Compiled release can now be used, but are opt-in.

- In addition to the normal features provided by the kit, you can now specify upstream `cf-deployment` operations as features, as well as your own operation files (using either go-patch or spruce overlay syntax).

- The following features are now included by default and do not need to be specified:
  - `loggregator-forwarder-agent`
  - `local-blobstore`
  - `container-routing-integrity`
  - `routing-api`
  - `omit-haproxy`

- The old kit acquired a cruft of feature renames, which are being dropped, as
  well as some features that no longer make sense:
  - `shield-dbs`, `shield-blobstores`: These features have been deprecated, in favor of BOSH add-ons
  - `blobstore-*`: these have been renamed `*-blobstore`
  - `db-external-*`: renamed `*-db`
  - `db-internal-postgres`, `local-db`: these were changed to `local-postgres-db`, as we now have a corresponding `local-mysql-db`
  - `haproxy-tls`, `haproxy-notls`, `haproxy-self-signed`: These are now compound features of `haproxy`, `tls` and `self-signed`, the latter two only having effect if `haproxy` feature is specified.
  - `minimum-vms`: this has been renamed `small-footprint`
  - `azure`: automatically used when deploying to MS Azure CPI
  - `cflinuxfs2` is no longer supported
  - `local-ha-db` is no longer supported - please use an external High Availability Database if this function is desired.
  - `autoscaler`, `autoscaler-postgres` - autoscaler is no longer included in the kit, please use the cf-app-autoscaler genesis kit.
  - `native-garden-runc`: replaced by the upstream `cf-deployment/operations/experimental/use-native-garden-runc-runner` feature
  - `app-bosh-dns`, `dns-service-discovery`: These features are now implemented as `cf-deployment/operations/enable-service-discovery` from the upstream

  - Additional feature: bare

    By default, the v2.0.0 kit is meant to be as close to the 1.x predecessor as possible, just based on upstream cf-deployment. To this end, the default best-practices hat were built into it are maintained going forward. This includes the separation of concerns regarding network subnets (cf-core, cf-edge, and cf-runtime instead of everything in default), usage of postgres, and a different domain for apps instead of putting them in system.<base-domain>, automatic azure tweaks when azure cpi is detected, etc. However, if you want a deployment as close to upstream as possible, we offer the the bare feature: this feature limits the default configuration to the base minimum required to support being deployed by genesis. Do not use this feature for existing v1.0 migrations.

As with any major upgrade, it is highly recommended that you test this with your configuration in a sandbox or lab environment thoroughly before applying it to your developer or production environments.  All care has been taken to ensure this product is fit for usability, but the shear complexity and permutations of configurations make it impossible to account for every possible scenario.  If you find an issue, please reach out to us on the Genesis Slack #help channel, or by opening a GitHub issue.
