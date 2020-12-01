While the 1.x line concluded with 1.10.1, this release contains a fix that is
important for upgrading to 2.x if you have a non-standard system domain.  See
below:

# Bug Fix

* Respect `params.system_domain` from env file when generating TLS
  certificate SANs. This impacts the SANs for cc_public_tls, logcache_ssl,
  loggregator_rlp_gateway_tls, loggregator_trafficcontroller_tls,
  cc_logcache_tls, networ_policy.server_external, router.ssl, haproxy.ssl,
  autoscaler.servicebroker_public and autoscaler.apiserver_public.

  If `params.system_domain` was set in previous versions, the certs were
  erroneously created using `system.<base_domain>`.  Run `genesis
  rotate-secrets -P` to regenerate the certs and deploy.
  
