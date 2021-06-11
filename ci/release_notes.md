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

