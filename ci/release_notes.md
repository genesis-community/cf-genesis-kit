# New Features

- Container to container networking and service discovery (via an
  internal Cloud Foundry domain) is now supported by the new
  `dns-service-discovery` feature.  This new feature subsumes and
  replaces the `app-bosh-dns` feature, which only implemented half
  of the solution for direct communication between CF application
  containers.
