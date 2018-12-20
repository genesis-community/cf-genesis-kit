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


# Core Components

| Release | Version | Release Date |
| ------- | ------- | ------------ |
| bosh-dns-aliases (new) | [0.0.3](https://github.com/cloudfoundry/bosh-dns-aliases-release/releases/tag/v0.0.3) | 24 October 2018 |
| bpm | [0.13.0](https://github.com/cloudfoundry-incubator/bpm-release/releases/tag/v0.13.0) | 12 October 2018 |
| capi | [1.70.0](https://github.com/cloudfoundry/capi-release/releases/tag/1.70.0) | 03 October 2018 |
| cf-smoke-tests | 40.0.5 | - |
| cflinuxfs2 | [1.242.0](https://github.com/cloudfoundry/cflinuxfs2-release/releases/tag/v1.242.0) | 12 October 2018 |
| cf-syslog-drain | [7.1](https://github.com/cloudfoundry/cf-syslog-drain-release/releases/tag/v7.1) | 13 September 2018 |
| consul | [193](https://github.com/cloudfoundry-incubator/consul-release/releases/tag/v193) | 30 May 2018 |
| diego | [2.19.0](https://github.com/cloudfoundry/diego-release/releases/tag/v2.19.0) | 11 October 2018 |
| garden-runc | [1.16.7](https://github.com/cloudfoundry/garden-runc-release/releases/tag/v1.16.7) | 18 October 2018 |
| loggregator | [104.0](https://github.com/cloudfoundry/loggregator-release/releases/tag/v104.0) | 01 October 2018 |
| loggregator-agent (renamed from metron_agent) | [2.3](https://github.com/cloudfoundry/log-cache-release/releases/tag/v2.3) | - |
| log-cache (new) | [2.0.2](https://github.com/cloudfoundry/log-cache-release/releases/tag/v2.0.2) | 20 November 2018 |
| nats | [26](https://github.com/cloudfoundry/nats-release/releases/tag/v26) | 02 October 2018 |
| routing | [0.182.0](https://github.com/cloudfoundry/routing-release/releases/tag/0.182.0) | 19 September 2018 |
| silk (renamed from cf-networking) | [2.17.0](https://github.com/cloudfoundry/silk-release/releases/tag/2.17.0) | 09 October 2018 |
| statsd-injector | [1.4.0](https://github.com/cloudfoundry/statsd-injector-release/releases/tag/v1.4.0) | 26 September 2018 |
| uaa | [62.0](https://github.com/cloudfoundry/uaa-release/releases/tag/v62.0) | 03 October 2018 |


# Buildpacks

| Release | Version | Release Date |
| ------- | ------- | ------------ |
| binary | [1.0.19](https://github.com/cloudfoundry/binary-buildpack/releases/tag/v1.0.19) | 05 June 2018 |
| dotnet-core | [2.1.5](https://github.com/cloudfoundry/dotnet-core-buildpack/releases/tag/v2.1.5) | 21 September 2018 |
| go | [1.8.28](https://github.com/cloudfoundry/go-buildpack/releases/tag/v1.8.28) | 12 October 2018 |
| java | [4.16.1](https://github.com/cloudfoundry/java-buildpack/releases/tag/v4.16.1) | 17 October 2018 |
| nodejs | [1.6.32](https://github.com/cloudfoundry/nodejs-buildpack/releases/tag/v1.6.32) | 13 September 2018 |
| php | [4.3.61](https://github.com/cloudfoundry/php-buildpack/releases/tag/v4.3.61) | 13 September 2018 |
| python | [1.6.21](https://github.com/cloudfoundry/python-buildpack/releases/tag/v1.6.21) | 24 August 2018 |
| ruby | [1.7.24](https://github.com/cloudfoundry/ruby-buildpack/releases/tag/v1.7.24) | 12 October 2018 |
| staticfile | [1.4.32](https://github.com/cloudfoundry/staticfile-buildpack/releases/tag/v1.4.32) | 10 September 2018 |

[1]: https://genesisproject.io/docs/migrations/gmp-cf-0002

