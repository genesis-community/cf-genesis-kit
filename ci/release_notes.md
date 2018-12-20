# Overview

This release is an upgrade of various Cloud Foundry components, most
notably, it includes these changes:

 - Using Ubuntu Xenial stemcells
 - Migration from Consul to BOSH DNS
 - Log Cache is now used, which locally caches Doppler parcels for use
   in the new Cloud Foundry `cf logs --recent` architecture.
 - Etcd removed


We're also introducing the first "migration feature", which allows
operators the choice to optionally remove Consul VMs and linkage
entirely after a successful deploy of v1.3. To learn more, visit
[Genesis Migration Process CF-0002: Optionally Removing Consul in
1.3][1]

This update requires that BOSH DNS be added to the runtime
configuration of the environment you use. The kit will warn you if it
doesn't find BOSH DNS in your runtime config

[1]: https://genesisproject.io/docs/migrations/gmp-cf-0002