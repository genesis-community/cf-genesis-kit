# Params Restoration and Retirements

* Restored support for `*_vm_type` parameters, including instance group name
  translations.  If you are using an outdated instance group name, it will be
  translated to the appropriate one, but will also print out a warning to
  update it.

  The kit also preserves default vm types used with cf kit v1.x for ease of
  migration.

* Restore support for `params.availability_zones`.

  Also adds support for randomized az placement for any instances that are not
  a multiple of the number of availability zones.  This is on by default if
  you explicitly set the availability zones, or can be enabled/disabled by
  setting `params.randomize_az_placement` to true/false respectively.

  Also fixes small-footprint for haproxy, which would continue using the
  default z1/z2/z3 while everything else used z1.

* Add `params.api_domain` to the retired environment parameters, and added a
  check for the retired parameters in the `genesis` check phase.  The
  `api_domain` param was not actively being used, contrary to the
  documentation.  It was using, and will continue to use `api.<system_domain>`

* Restored the cf-db network for migrated environments

  v1.x kits used a cf-db network, whereas v2.0 puts any internal database in
  the cf-core network.  If using bare, everything gets put in the default
  network.  This can be overridden by specifying `params.cf_db_network`

* Add `skip_ssl_validation` back in as a valid param

  The `genesis new` wizard would set the `params.skip_ssl_validation`, and
  then the user would be told that this wasn't a valid param.  It was being
  done in the wizard to support self-signed certs.

  Rather than take it out of the wizard, it is now used to automatically add
  the `cf-deployment/operations/stop-skipping-tls-validation` TLS validation
  inforcement feature if explicitly set to fault, defaulting to skipping
  validation if true or unset.

# New Features

* Added aws-blobstore-iam and no-nats-tls features

  Adds ability to connect to AWS blobstore via IAM configuration instead of
  credentials.  To connect with IAM, users should use aws-blobstore-iam
  instead of the aws-blobstore.

  Adds nats-tls job to nats instance by default, but allows users to turn off
  this feature via the `no-nats-tls` feature (which will be discontinued in an
  upcoming release when nats-tls becomes required)

* Add ssh-proxy-on-routers feature

  Moves ssh-proxy job from scheduler to routers, better allowing for scaling
  and putting it on the edge network (if used)

# Improvements

* Support cached local ops features

  Genesis now fully supports the ops/ features natively, but this also has to
  be supported by the kits that provide for it.  This kit now correctly draws
  any local ops features from the cache if they exist there before trying to
  use uncached versions.

* Defer the Cloud Config validation

  Because we don't know what upstream extensions, networks or vm types are
  going to be used, we now defer the cloud config checks to after the manifest
  is generated and check the values referenced in the manifest with those
  available in the cloud config in the pre-deploy hook.

  Also improves output format and uses stderr in check and pre-deploy hooks,
  and requires Genesis v2.7.23.

* Suppress error when detecting external_db_user presence

  If external_db_user is present, we need to warn users that they need to set
  params.external_db_user to that value, as it is not picked up by default in
  cf kit v2.x.  However, while it can be normal for that value not to be
  present, the detection would log an extraneous warning that it couldn't be
  found.  This fixes that issue.

* Improve pre-deploy manifest check

  Now detects incomplete instance groups.  This is crucial for warning the
  user if they have left instance group overrides that use the old v1.x names
  in their environment file.

* Updated post-deploy hook to support v2.x

# Bug Fixes:

* Override NATS, diego and routing release from the upstream cf-deployment
  v12.45.0 to resolve a NATS outage (Fixes #156).

* Bump migrate-postgres to 1.0.1 for migrating the postgres database
  configuration used by the v1.10.1 cf kit to what v2.0.x requires.  This
  fixes the postgres version mismatch issue encountered when upgrating from
  v1.10.1 to 2.0.0 if a local postgres database was in use.

* Fix variables for aws blobstore

* Remove `*-network-properties` vm extensions from router and tcp-router when
  haproxy feature is enabled.

* `randomize_az_placement` want boolean and not string

