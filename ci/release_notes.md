# Bug Fixes

* Override NATS, diego and routing release from the upstream cf-deployment
  v12.45.0 to resolve a NATS outage (Fixes #156).

* Add `params.api_domain` to the retired environment parameters, and added a
  check for the retired parameters in the `genesis` check phase.  The
  `api_domain` param was not actively being used, contrary to the
  documentation.  It was using, and will continue to use `api.<system_domain>`

* Bump migrate-postgres to 1.0.1 for migrating the postgres database
  configuration used by the v1.10.1 cf kit to what v2.0.x requires.  This
  fixes the postgres version mismatch issue encountered when upgrating from
  v1.10.1 to 2.0.0 if a local postgres database was in use.

* fix variables for aws blobstore
