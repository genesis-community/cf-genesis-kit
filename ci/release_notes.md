# Major Update 

* This release brings the releases used by the CF Genesis Kit up to date with
  v12.5.0 of the cf-deployment release.  This should be a direct upgrade, but
  you will need to rotate the secrets, due to the re-alignment of the TLS
  certificates with cf-deployment (see below)

# TLS Certificate Refactor

* Cloud Foundry has upped its game regarding inter-process secure
  communications. In an attempt to better approximate the `cf-deployment`
  release for compatibility and ease of future updates, the `cf-genesis-kit`
  has remapped the internal generated certificates used to ensure they have
  the same CA signator and CN/SANs.

  This update requires that you run `genesis rotate-secrets <env> -f` to
  regenerate all the certificates used.  It will also regenerate any passwords
  that were generated, so ensure that if you use these values outside of your
  CF deployment, that the changes are propagated to those users and tools that
  need them.

  See [GMP-CF-0003 - TLS Certificate Refactor in v1.8.0](https://genesisproject.io/docs/migrations/gmp-cf-0003/) for more information.

# New Features

* Added the `prom_scraper` job from the `loggregator-agent` release. This replaces
  the, now deleted, `loggr-expvar-forwarder` and related jobs. Metrics are now 
  exposed directly via Prometheus endpoints rather than forwarding as it was 
  previously.

* Added cf-dot to diego, bbs and cell instance groups as an addon.

# Bug fixes

* Fixed spelling of `server_cert_domain_san` in uaa.

* Cleaned up defunct properties in multiple jobs.

# Core Components

| Release | Version | Release Date |
| ------- | ------- | ------------ |
| bpm | [1.1.5](https://github.com/cloudfoundry/bpm-release/releases/tag/v1.1.5) | 22 October 2019 |
| capi | [1.88.0](https://github.com/cloudfoundry/capi-release/releases/tag/1.88.0) | 01 November 2019 |
| cf-networking | [2.27.0](https://github.com/cloudfoundry/cf-networking-release/releases/tag/2.27.0) | 02 December 2019 |
| cf-smoke-tests | [40.0.123](https://github.com/cloudfoundry/cf-smoke-tests-release/releases/tag/v40.0.123) | - |
| cflinuxfs3 | [0.150.0](https://github.com/cloudfoundry/cflinuxfs3-release/releases/tag/v0.150.0) | 03 December 2019 |
| cf-cli | [1.22.0](https://github.com/bosh-packages/cf-cli-release/releases/tag/v1.22.0) | 05 November 2019 |
| diego | [2.41.0](https://github.com/cloudfoundry/diego-release/releases/tag/v2.41.0) | 04 December 2019 |
| garden-runc | [1.19.9](https://github.com/cloudfoundry/garden-runc-release/releases/tag/v1.19.9) | 21 November 2019 |
| loggregator | [106.2.1](https://github.com/cloudfoundry/loggregator-release/releases/tag/v106.2.1) | 20 November 2019 |
| loggregator-agent | [5.2.2](https://github.com/cloudfoundry/loggregator-agent-release/releases/tag/v5.2.2) | - |
| log-cache | [2.6.1](https://github.com/cloudfoundry/log-cache-release/releases/tag/v2.6.1) | 20 November 2019 |
| nats | [28](https://github.com/cloudfoundry/nats-release/releases/tag/v28) | 12 November 2019 |
| routing | [0.195.0](https://github.com/cloudfoundry/routing-release/releases/tag/0.195.0) | 23 November 2019 |
| statsd-injector | [1.11.4](https://github.com/cloudfoundry/statsd-injector-release/releases/tag/v1.11.4) | 20 November 2019 |
| cf-syslog-drain | [10.2.2](https://github.com/cloudfoundry/cf-syslog-drain-release/releases/tag/v10.2.2) | 21 October 2019 |
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
