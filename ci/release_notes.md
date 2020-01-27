# Major Release Updates

This release brings the releases used by the CF Genesis Kit up to date with
v12.20.0 of the cf-deployment release.

# Potentially Breaking Changes

* Continuing the remove static IPs theme of 1.7.0, this release drops the
  static ranges in cloud config for haproxy feature.  Instead, the instances
  for haproxy instances need to be specified in the `haproxy_ips` parameter in
  list format.  These ips must be in the range of the `cf_lb_network`, which
  defaults to the same network that is specified by the `cf_edge_network`
  parameter.  This removes the requirement for the edge network to be at least
  a /28.

  If upgrading from versions before 1.7.0, you will need to remove the first
  10 static IPs from your cloud foundry, as these were used for the go routers
  and access vms.  The 11th through 15th were reserved for haproxy instances,
  so in order to not have to change your network addresses, simply use these
  ips in your `haproxy_ips` list in your environment file and keep them listed
  as static.

  If upgrading from 1.7.0 and later, same concept applies but will have to
  take into consideration what you did to remove the other static ips when you
  upgraded before.

# Improvements

* BBS uses localhost locker to prevent race conditions on cert changes
* Increased feature coverage for testflight ci process
* Move smoketests to uaa vm to reduce vm count and test time
* Added smoketest genesis addon: `genesis do <env> -- smoketest`

# Bug Fixes

* Corrects cert location for dns-service-discovery and haproxy features.  No
  manual remediation is necessary, as the existing certs will be moved on
  first check of the environment.

# Core Components

| Release | Version | Release Date |
| ------- | ------- | ------------ |
| bpm | [1.1.6](https://github.com/cloudfoundry/bpm-release/releases/tag/v1.1.6) | 05 December 2019 |
| capi | [1.89.0](https://github.com/cloudfoundry/capi-release/releases/tag/1.89.0) | 06 December 2019 |
| cf-networking | [2.27.0](https://github.com/cloudfoundry/cf-networking-release/releases/tag/2.27.0) | 02 December 2019 |
| cf-smoke-tests | [40.0.123](https://github.com/cloudfoundry/cf-smoke-tests-release/releases/tag/v40.0.123) | - |
| cflinuxfs3 | [0.151.0](https://github.com/cloudfoundry/cflinuxfs3-release/releases/tag/v0.151.0) | 10 December 2019 |
| cf-cli | [1.23.0](https://github.com/bosh-packages/cf-cli-release/releases/tag/v1.23.0) | 08 January 2020 |
| diego | [2.41.0](https://github.com/cloudfoundry/diego-release/releases/tag/v2.41.0) | 04 December 2019 |
| garden-runc | [1.19.9](https://github.com/cloudfoundry/garden-runc-release/releases/tag/v1.19.9) | 21 November 2019 |
| loggregator | [106.3.1](https://github.com/cloudfoundry/loggregator-release/releases/tag/v106.3.1) | 09 December 2019 |
| loggregator-agent | [5.3.1](https://github.com/cloudfoundry/loggregator-agent-release/releases/tag/v5.3.1) | 16 December 2019 |
| log-cache | [2.6.6](https://github.com/cloudfoundry/log-cache-release/releases/tag/v2.6.6) | 09 December 2019 |
| nats | [32](https://github.com/cloudfoundry/nats-release/releases/tag/v32) | - |
| routing | [0.196.0](https://github.com/cloudfoundry/routing-release/releases/tag/0.196.0) | 05 December 2019 |
| statsd-injector | [1.11.10](https://github.com/cloudfoundry/statsd-injector-release/releases/tag/v1.11.10) | 16 December 2019 |
| cf-syslog-drain | [10.2.7](https://github.com/cloudfoundry/cf-syslog-drain-release/releases/tag/v10.2.7) | 16 December 2019 |
| uaa | [74.12.0](https://github.com/cloudfoundry/uaa-release/releases/tag/v74.12.0) | 03 December 2019 |
| silk | [2.27.0](https://github.com/cloudfoundry/silk-release/releases/tag/2.27.0) | 02 December 2019 |
| bosh-dns-aliases | [0.0.3](https://github.com/cloudfoundry/bosh-dns-aliases-release/releases/tag/v0.0.3) | 24 October 2018 |
| cflinuxfs2 | [1.286.0](https://github.com/cloudfoundry/cflinuxfs2-release/releases/tag/v1.286.0) | 12 June 2019 |
| app-autoscaler | [2.0.0](https://github.com/cloudfoundry-incubator/app-autoscaler-release/releases/tag/v2.0.0) | 15 August 2019 |
| nfs-volume | [2.3.0](https://github.com/cloudfoundry/nfs-volume-release/releases/tag/v2.3.0) | 21 August 2019 |
| mapfs | [1.2.0](https://github.com/cloudfoundry/mapfs-release/releases/tag/v1.2.0) | 15 July 2019 |
| postgres | [3.2.0](https://github.com/cloudfoundry-community/postgres-boshrelease/releases/tag/v3.2.0) | 19 September 2019 |
| haproxy | [9.7.1](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/releases/tag/v9.7.1) | 05 September 2019 |


# Buildpacks

| Release | Version | Release Date |
| ------- | ------- | ------------ |
| binary | [1.0.35](https://github.com/cloudfoundry/binary-buildpack-release/releases/tag/1.0.35) | 10 October 2019 |
| dotnet-core | [2.3.2](https://github.com/cloudfoundry/dotnet-core-buildpack-release/releases/tag/2.3.2) | 05 November 2019 |
| go | [1.9.3](https://github.com/cloudfoundry/go-buildpack-release/releases/tag/1.9.3) | 05 November 2019 |
| java | [4.26](https://github.com/cloudfoundry/java-buildpack-release/releases/tag/4.26) | 21 November 2019 |
| nginx | [1.1.1](https://github.com/cloudfoundry/nginx-buildpack-release/releases/tag/1.1.1) | 05 November 2019 |
| nodejs | [1.7.4](https://github.com/cloudfoundry/nodejs-buildpack-release/releases/tag/1.7.4) | 22 November 2019 |
| php | [4.4.2](https://github.com/cloudfoundry/php-buildpack-release/releases/tag/4.4.2) | 22 November 2019 |
| python | [1.7.2](https://github.com/cloudfoundry/python-buildpack-release/releases/tag/1.7.2) | 22 November 2019 |
| r | [1.1.0](https://github.com/cloudfoundry/r-buildpack-release/releases/tag/1.1.0) | 22 November 2019 |
| ruby | [1.8.2](https://github.com/cloudfoundry/ruby-buildpack-release/releases/tag/1.8.2) | 05 November 2019 |
| staticfile | [1.5.1](https://github.com/cloudfoundry/staticfile-buildpack-release/releases/tag/1.5.1) | 05 November 2019 |

