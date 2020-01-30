# Bug Fixes

* v1.9.0 required locket server TLS certificate to be valid for 127.0.0.1.
  This release fixes this problem by automatically regenerating that secret if
  this is not the case. (Issue #108)

* v1.9.0 fixed an issue where the certificates for the `dns-service-discovery`
  feature were placed incorrectly in v1.8.0, but the method to resolve this
  caused an error if these certificates were not present. (#107)
