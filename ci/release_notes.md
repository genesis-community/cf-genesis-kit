# Bug Fix

* Use genesis.env, not params.env

  Once we updated the min genesi version to above 2.6.13, the
  autopopulation of `params.env` has been removed.  Therefore, v1.10.2
  causes genesis to complain that params.env exists, but won't work
  without it.

  The resolution is to use genesis.env instead of the outdated params.env
  in the kit's manifest fragments, which is only needed in the blobstore
  directory key settings.

* Properly handle internal domains for `dns_service_discovery`

  Due to some quirks of spruce, the apps.internal domain wasn't being applied
  by the inclusion of the `dns_service_discovery` feature; it had to be
  explicitly added to params.apps_domains.  This is no longer necessary and
  should be removed
