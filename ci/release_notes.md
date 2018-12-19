# Overview

This release is an upgrade of various Cloud Foundry components, most
notably, it includes these changes:

 - Migration from Consul to BOSH DNS
 - Log Cache is now used, which locally caches Doppler parcels for
   use in the new Cloud Foundry `cf logs --recent` architecture.


We're also introducing the first "migration feature", which allows operators
the choice to 
