
# Overview

This release updates CF components to more recent versions. Most
notably, this version brings the following related CF changes:

- Diego now uses mTLS for communication.
- CAPI now supports IAM Service Accounts when authenticating with
  Google Cloud Storage
- Scalable Syslog is now used, allowing multiple VMs to handle log
  output.


To accommodate these changes, the following kit-related changes were
made:

* 3 new databases are necessary: `silkdb`, `locketdb`, and 
  `policyserverdb`
* The `rep` internal certificate needs to be signed for `127.0.0.1`
  for mTLS reasons. This Genesis kit now has a `pre-deploy` hook
  that will automatically delete and generate a new `rep`
  certificate with the appropriate alternative names if the prior
  `rep` certificate was not signed for `127.0.0.1`

Various configuration parameters were added, and are detailed below.

# New Parameters

## Scalable Syslog

  - `syslogger_instances` - How many scalable syslog VMs to deploy.

  - `syslogger_vm_type` - What type of VM to deploy for the scalable
    syslog. Defaults to `small`.

## UAA

  - `uaa_lockout_failure_count` - Amount of failed UAA login attempts
    before lockout.

  - `uaa_lockout_failure_time_between_failures` - How much time
    (in seconds) in which `uaa_lockout_failure_count` must occur in 
    order for account to be locked. Defaults to `1200`.
  
  - `uaa_lockout_punishment_time` - How long (in seconds) the account
    is locked out for violating `uaa_lock_failure_count` within 
    `uaa_lockout_failure_time_between_failures`. Defaults to `300`.

  - `uaa_refresh_token_validity` - How long (in seconds) a CF refresh
    is valid for. Defaults to `2592000`.

  - `cf_branding_product_logo` - A base64 encoded image to display on
    the web UI login prompt. Defaults to `nil`.

  - `cf_branding_square_logo` - A base64 encoded image to display
    in areas where a smaller logo is necessary. Defaults to `nil`.

  - `cf_footer_legal_text` - A string to display in the footer,
    typically used for compliance text. Defaults to `nil`.

  - `cf_footer_links` - A YAML list of links to enumerate in the footer
    of the web UI. Defaults to `nil`

# Upgrade Instructions

From `1.0.0`, the following actions need to be made:

## If CF was deployed with `local-db` or `local-ha-db` feature flags

No changes need to be performed for an in-situ upgrade of 
`cf-genesis-kit` 1.0.0 to 1.1

## If CF was deployed with `mysql-db` or `postgres-db` feature flags

1. Create 3 databases with the following names: `silkdb`, `locketdb`, and 
  `policyserverdb`.



# Core Components

| Release | Version | Release Date |
| --------- | ------- | ------------ |
bpm (new) | [0.6.0](https://github.com/cloudfoundry-incubator/bpm-release/releases/tag/v0.6.0) | 2 May 2018
capi | [1.60.0](https://github.com/cloudfoundry/capi-release/releases/tag/1.60.0) | 15 Jun 2018
cf-smoke-tests | 40.0.5 | 17 May 2018
cf-networking (new) | [1.9.0](https://github.com/cloudfoundry/cf-networking-release/releases/tag/v1.9.0) | 15 Dec 2017
cflinuxfs2 | [1.212.0](https://github.com/cloudfoundry/cflinuxfs2-release/releases/tag/v1.212.0) | 4 Jun 2018
cf-syslog-drain (new) | [6.5](https://github.com/cloudfoundry/cf-syslog-drain-release/releases/tag/v6.5) | 3 May 2018
consul | [193](https://github.com/cloudfoundry-incubator/consul-release/releases/tag/v193) | 29 May 2018
diego | [2.8.0](https://github.com/cloudfoundry/diego-release/releases/tag/v2.8.0) | 28 May 2018
garden-runc | [1.14.0](https://github.com/cloudfoundry/garden-runc-release/releases/tag/v1.14.0) | 4 Jun 2018
loggregator | [102.2](https://github.com/cloudfoundry/loggregator-release/releases/tag/v102.2) | 25 May 2018
nats | [24](https://github.com/cloudfoundry/nats-release/releases/tag/v24) | 16 May 2018 
cf-routing | [0.178.0](https://github.com/cloudfoundry/routing-release/releases/tag/0.178.0) | 17 May 2018
statsd-injector | [1.3.0](https://github.com/cloudfoundry/statsd-injector-release/releases/tag/v1.3.0) | 23 Mar 2018
uaa | [59](https://github.com/cloudfoundry/uaa-release/releases/tag/v59) | 22 May 2018


# Buildpacks

| Buildpack | Version | Release Date |
| --------- | ------- | ------------ |
binary | [1.0.19](https://github.com/cloudfoundry/binary-buildpack/releases/tag/v1.0.19) | 5 Jun 2018
dotnet-core | [2.0.7](https://github.com/cloudfoundry/dotnet-core-buildpack/releases/tag/v2.0.7) | 5 Jun 2018
go | [1.8.23](https://github.com/cloudfoundry/go-buildpack/releases/tag/v1.8.23) | 5 Jun 2018
java | [4.12](https://github.com/cloudfoundry/java-buildpack/releases/tag/v4.12) | 11 May 2018
nodejs | [1.6.25](https://github.com/cloudfoundry/nodejs-buildpack/releases/tag/v1.6.25) | 5 Jun 2018
php | [4.3.56](https://github.com/cloudfoundry/php-buildpack/releases/tag/v4.3.56) | 5 Jun 2018
python | [1.6.17](https://github.com/cloudfoundry/python-buildpack/releases/tag/v1.6.17) | 5 Jun 2018
ruby | [1.7.19](https://github.com/cloudfoundry/ruby-buildpack/releases/tag/v1.7.19) | 5 Jun 2018
staticfile | [1.4.28](https://github.com/cloudfoundry/staticfile-buildpack/releases/tag/v1.4.28) | 5 Jun 2018