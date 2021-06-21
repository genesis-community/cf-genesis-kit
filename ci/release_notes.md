- Adds v1 vm support fix back in

  - Better support for vm_types, especially in context of upgrading from v1 environments.

    New feature `v1-vm-types` sets up the manifest to use the same VM types as was used in the v1.x versions of the kit, or as close to possible.  This allows you to use your existing cloud config and tuning.  Where the instance group name changes, it will use the vm type that the instance group was migrated from.

    The exceptions are `tcp-router`, which will use the `router` vm type, and `cc-worker` and `credhub`, which continue to use `minimum` as there was no prevous instance group for these functions.

    Fixes spelling of scheduler in MANUAL.MD

Bug Fixes:

* Environments migrated from v1.x were suppose to retain the blobstore name
  for the app packages blobstore (was <prefix>-packages-<unique-id> in v1.x,
  moved to <prefix>-app-packages-<unique-id> to better match canonical in
  v2.0.x for new environment).  This has been restored.  If you upgraded to
  v2.0.x, you can keep the new blobstore name by adding the following to your
  environment:

  ```
  meta:
    blobstore_bucket_path:
      app-packages: (( concat meta.blobstore_bucket_prefix "-app-packages-" meta.blobstore_bucket_suffix ))
  ```

* Environments migrated from v1.x now correctly retain the original NATS user
  credentials.  Upstream used a different username, and as such, when
  upgrading to v2.0.x, there was a loss of connectivity to NATS.  Migrated
  environments now retain the original v1.x username.

  If you have already upgraded your environment from v1.x to 2.0.x, you can
  specify feature `v2-nats-credentials` to prevent NATS username from
  switching back and causing further availability outage during deployment.
