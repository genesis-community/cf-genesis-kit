# Major Change

Consul is no longer supported, and has been removed from this release.  While
replacing consul with BOSH DNS was optional since v1.3.0 using the feature
`migrate-1.3-without-consul`, that feature has now been permanently turned on.

You should be able to directly upgrade to this version with no impact to your
existing Cloud Foundry system, it is recommended that you validate it by
upgrading to v1.4.1 with the `migrate-1.3.1-without-consul` so that if
something does occur, you can redeploy without that feature.

**Note**: You must [enable BOSH DNS](https://bosh.io/docs/dns/#enable) in your BOSH deployment and add it to  your
runtime config [(example)](https://github.com/cloudfoundry/bosh-deployment/blob/master/runtime-configs/dns.yml) to deploy this version.
