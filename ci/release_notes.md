- Adds v1 vm support fix back in

  - Better support for vm_types, especially in context of upgrading from v1 environments.

    New feature `v1-vm-types` sets up the manifest to use the same VM types as was used in the v1.x versions of the kit, or as close to possible.  This allows you to use your existing cloud config and tuning.  Where the instance group name changes, it will use the vm type that the instance group was migrated from.

    The exceptions are `tcp-router`, which will use the `router` vm type, and `cc-worker` and `credhub`, which continue to use `minimum` as there was no prevous instance group for these functions.

    Fixes spelling of scheduler in MANUAL.MD
