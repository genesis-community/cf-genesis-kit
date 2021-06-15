Bug Fixes for v1.x Migrated Environments:

* Environments migrated from v1.x were suppose to retain the blobstore name
  for the app packages blobstore (was <prefix>-packages-<unique-id> in v1.x,
  moved to <prefix>-app-packages-<unique-id> to better match canonical in
  v2.0.x for new environment).  This has been restored.

  If you upgraded to v2.0.x, you can keep the new blobstore name by adding the
  following to your environment:

  ```
  meta:
    blobstore_bucket_path:
      app-packages: (( concat meta.blobstore_bucket_prefix "-app-packages-" meta.blobstore_bucket_suffix ))
  ```

* Environment migraded from v1.x now correctly retain the original NATS user
  credentials.  Upstream used a different username, and as such, when
  upgrading to v2.0.x, there was a loss of connectivity to NATS.  Migrated
  environments now retain the original v1.x username.

  If you have already upgraded your environment from v1.x to 2.0.x, you can
  specify feature `v2-nats-credentials` to prevent nats username from
  switching back and causing further availaiblity outage during deployment.

