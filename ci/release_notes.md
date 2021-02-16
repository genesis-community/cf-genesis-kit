# Improvements

- Adds `no-tcp-routers` feature for systems that don't need TCP routing.
- Better support for vm_types, especially in context of upgrading from v1 environments.

  New feature `v1-vm-types` sets up the manifest to use the same VM types as was used in the v1.x versions of the kit, or as close to possible.  This allows you to use your existing cloud config and tuning.  Where the instance group name changes, it will use the vm type that the instance group was migrated from.

  The exceptions are `tcp-router`, which will use the `router` vm type, and `cc-worker` and `credhub`, which continue to use `minimum` as there was no prevous instance group for these functions.

# Bug Fix

- Adds to vm_extension list instead of overwrite existing extensions when specifying ssh-proxy-on-routers feature

- Supplied missing `params.*_vm_types`, warn instead of error if an unknown instance group is specified, so that custom instance groups can be managed in the same way.

  Note:  For known instance groups, the underscores are automatically converted to hyphens to determine the matching instance_group for the specified `*_vm_type` params.  For user specified, you must specify the hyphen or underscore as used in the instance_group.

  Known instance groups are:
    adapter, api, cc-worker, credhub, database, diego-api, diego-cell, doppler, errand, haproxy, log-api, nats, rotate-cc-database-key, router, scheduler, singleton-blobstore, smoke-tests, tcp-router, and uaa

