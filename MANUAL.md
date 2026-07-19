# Cloud Foundry Genesis Kit Manual

The **Cloud Foundry Genesis Kit** deploys a single instance of Cloud Foundry. It is based on [cf-deployment][cf-deployment], the community standard deployment for Cloud Foundry.

## Table of Contents

- [Requirements](#requirements)
- [General Usage Guidelines](#general-usage-guidelines)
- [Features](#features)
  - [General Features](#general-features)
  - [Database Options](#database-options)
  - [Blobstore Options](#blobstore-options)
  - [Load Balancing Options](#load-balancing-options)
  - [Runtime Stack Options](#runtime-stack-options)
  - [Volume Service Options](#volume-service-options)
  - [OCFP Deployments](#ocfp-deployments)
  - [Custom and Upstream Features](#custom-and-upstream-features)
- [Feature Parameters](#feature-parameters)
  - [General Parameters](#general-parameters)
  - [Database Parameters](#database-parameters)
  - [Blobstore Parameters](#blobstore-parameters)
  - [HAProxy Parameters](#haproxy-parameters)
  - [Isolation Segment Parameters](#isolation-segment-parameters)
  - [OCFP Parameters](#ocfp-parameters)
- [Networking Configuration](#networking-configuration)
- [VM Sizing and Scaling](#vm-sizing-and-scaling)
- [Branding Configuration](#branding-configuration)
- [Cloud Configuration](#cloud-configuration)
- [Available Addons](#available-addons)
- [History](#history)

[cf-deployment]: https://github.com/cloudfoundry/cf-deployment

## Requirements

The Cloud Foundry Genesis Kit requires:

* BOSH DNS be available in the runtime config prior to deployment. Please
  refer to [bosh-deployment][bosh-deployment] for an example runtime config.

* A BOSH director deployed with Credhub. We recommend using the latest release of
  [bosh-genesis-kit][bosh-genesis-kit], as this will ensure everything is
  correctly configured.

[bosh-deployment]: https://github.com/cloudfoundry/bosh-deployment/blob/master/runtime-configs/dns.yml
[bosh-genesis-kit]: https://github.com/genesis-community/bosh-genesis-kit

## General Usage Guidelines

As per usual with Genesis kits, you will need a Genesis deployment repository
to contain your environment file. If you don't already have one from a previous
`cf` version, run `genesis init -k cf/<version>`, where <version> is replaced with
the current cf genesis kit version. If you have this already, you'll need to download
the latest copy of this kit via `genesis fetch-kit` from within that directory.

Once in the Genesis `cf` deployment repository, run `genesis new <env>` to
create a new env file, replacing `<env>` with your desired env. This will
walk you through a wizard that will populate the desired features and the
corresponding parameters.

Once you have an env file, you may want to manually change parameters or
features. The rest of this document covers how to modify your environment
files to make use of provided features.

## Features

In Genesis kits, features can be opted-in to on a per-environment basis by adding the `features` array to the environment file:
```
kit:
  features:
  - feature-a
  - feature-b
```

Using features is a way to configure the kit to suit the requirements of your specific deployment.

### General Features

- `compiled-releases` - Use pre-compiled releases to speed up initial deploy time (alias of upstream `cf-deployment/operations/use-compiled-releases`).
- `small-footprint` - Use the minimal number of VMs and only 1 AZ to deploy CF.
- `enable-service-discovery` - Enables bosh-dns support on Diego cells.
- `app-autoscaler-integration` - Add a UAA client for the app autoscaler (must be deployed via [cf-app-autoscaler-genesis-kit](https://github.com/genesis-community/cf-app-autoscaler-genesis-kit)).
- `app-scheduler-integration` - Add a UAA client for the app scheduler.
- `prometheus-integration` - Configure CF to export to Prometheus (must be deployed via [prometheus-genesis-kit](https://github.com/genesis-community/prometheus-genesis-kit)).
- `bare` - Deploy _only_ the cf-deployment files without Genesis packaged best-practices applied.
- `migrated-v1-env` - Fix the database names after having migrated from v1 kit.
- `no-nats-tls` - Nats over TLS was not part of cf-deployment v12.45 but has been turned on by default unless using bare mode. Set this feature to disable it.
- `ssh-proxy-on-routers` - Moves the ssh-proxy from scheduler instance group to the router instance group, placing it on the edge network, and enabling scaling via scaling the routers.
- `no-tcp-routers` - Removes the tcp-router instance group and associated resource allocations for systems that don't need tcp routes.
- `uaa-admin-client` - Enables a UAA admin client for scripting/automation.
- `cflinuxfs3` - Restore support for cflinuxfs3 to Diego cells and isolation segments (by default, only cflinuxfs4 is supported).

### Database Options

Choose one of the following database options:

- `postgres-db` - Use an external PostgreSQL instance to host persistent data.
- `mysql-db` - Use an external MySQL instance to host persistent data.
- `local-mysql-db` - Use a MySQL database and deploy it on a VM as part of this deployment.
- `local-postgres-db` - Use a PostgreSQL database and deploy it on a VM as part of this deployment (default if no DB feature is specified and not using bare mode).
- `override-db-names` - When specifying `local-mysql-db` or `local-postgres-db` you can override the names of the databases that are created.

### Blobstore Options

- `aws-blobstore` - Use AWS S3 storage as external blobstore, via credentials.
- `aws-blobstore-iam` - Use AWS S3 storage as external blobstore, via IAM configuration.
- `minio-blobstore` - Use Minio S3-compatible storage as external blobstore.
- `azure-blobstore` - Use Azure blob storage as external blobstore.
- `gcp-blobstore` - Use GCS as external blobstore.
- `gcp-use-access-key` - Use Google storage access key/secret to access the external GCS blobstore (instead of service account credentials which is the default).
- `blobstore-suffix` - Include the blobstore bucket suffix with a dash separator (e.g., `prefix-app-packages-suffix`).
- `no-blobstore-suffix` - Remove the blobstore bucket suffix entirely (e.g., `prefix-app-packages` instead of `prefix-app-packages-suffix`). This is the default.

### Load Balancing Options

- `haproxy` - Deploy an HAProxy loadbalancer in front of CF.
- `no-haproxy` (alias `external-lb`) - Skip HAProxy and expose the routers
  for an external load balancer. (`omit-haproxy` is a deprecated alias.)
- `tls` - Configure HAProxy to use TLS.
- `self-signed` - Generate self-signed certs for HAProxy.

The HAProxy default is IaaS-aware: on `aws`, `gcp`, and `azure` the platform
load balancer is assumed to front the routers, so HAProxy defaults to off
unless the environment file lists `haproxy` explicitly. On all other IaaSes
HAProxy is deployed by default unless the environment file lists `no-haproxy`
(or `external-lb`). Listing both `haproxy` and an opt-out flag is an error.

### Runtime Stack Options

- `cflinuxfs3` - Add support for cflinuxfs3 (Ubuntu 18.04 LTS) stack
- `cflinuxfs4` - Support cflinuxfs4 (Ubuntu 22.04 LTS) stack (default, automatically included)

### Volume Service Options

- `nfs-volume-services` - Alias of `cf-deployment/operations/enable-nfs-volume-service`
- `nfs-ldap` - Use LDAP to access NFS volume services (requires `nfs-volume-services` feature)
- `smb-volume-services` - Enable SMB volume service broker capabilities

### Windows Support Options

- `windows-diego-cells` - Adds Windows Diego cell functionality.

### Multi-Tenant Options

- `isolation-segments` - Enables usage of [isolation segments](https://docs.cloudfoundry.org/adminguide/routing-is.html#overview) using minimal configuration. Supports nfs-volume-services, nfs-ldap and smb-volume-services features.

### OCFP Deployments

As an alternative to customizable general CF deployments, this kit provides an `ocfp` (Opensource Cloud Foundry Platform) feature, which is a _very opinionated_ specific deployment. It provides a curated deployment experience with sane defaults and optimizations for each IaaS.

Features supported in OCFP deployments:

- `internal-blobstore` - Instead of using an external blobstore (default), make an internal blobstore instance.
- `internal-db` - Instead of using an external Postgres database, deploy an internal database instance.

### Custom and Upstream Features

In addition to the bundled features that this kit exposes, you can also include any ops files contained in the upstream [cf-deployment](https://github.com/cloudfoundry/cf-deployment) by referencing them via:
```
kit:
  features:
  - cf-deployment/path/to/file # omit .yml suffix
```

Caveat: Not all features are compatible with this kit, and features are applied in order, so ordering may matter.

## Feature Parameters

### General Parameters

The following params are always included:

| param | description | default |
| --- | --- | --- |
| `cf_core_network` | What network should be used for CF core-components? | `cf-core` |
| `cf_edge_network` | What network should be used for CF edge-components? | `cf-edge` |
| `cf_runtime_network` | What network should be used for CF runtime-components? | `cf-runtime` |
| `base_domain` | What is the base domain for this Cloud Foundry? | |
| `system_domain` | What is the system domain for this Cloud Foundry? | `system.<base_domain>` |
| `apps_domain` | What is the apps domain for this Cloud Foundy? | `run.<system-domain>` |
| `identity_support_address` | Identity support address | `"https://github.com/genesis-community/cf-genesis-kit"` |
| `identity_description` | Identity description | `"Use 'genesis info' on environment file for more details"` |

### Database Parameters

These params need to be set when using external databases:

#### `mysql-db` - External MySQL Parameters

| param | description | default |
| --- | --- | --- |
| `external_db_host` | The default host for your MySQL db | |
| `external_db_port` | The default for your external MySQL db | `3306` |
| `external_db_password` | The password for the external MySQL db | `((external_db_password))` (Credhub lookup) |
| `uaadb_name` | The name of the UAA Database | `uaadb` |
| `uaadb_host` | The host of the external UAA database | `external_db_host` |
| `uaadb_port` | The port of the external UAA database | `external_db_port` |
| `uaadb_user` | The UAA database used | `uuaadmin` |
| `uaadb_password` | The UAA database password | `external_db_password` |
| `ccdb_name` | The name of the Cloud Controller database | `ccdb` |
| `ccdb_host` | The host of the external Cloud Controller database | `external_db_host` |
| `ccdb_port` | The port of the external Cloud Controller database | `external_db_port` |
| `ccdb_user` | The Cloud Controller database user | `ccadmin` |
| `ccdb_password` | The Cloud Controller database password | `external_db_password` |
| `diegodb_name` | The name of the Diego Database | `diegodb` |
| `diegodb_host` | The host of the external Diego database | `external_db_host` |
| `diegodb_port` | The port of the external Diego database | `external_db_port` |
| `diegodb_user` | The Diego database used | `diegoadmin` |
| `diegodb_password` | The Diego database password | `external_db_password` |
| `policyserverdb_name` | The name of the Network Policy database | `policyserverdb` |
| `policyserverdb_host` | The host of the external Network Policy database | `external_db_host` |
| `policyserverdb_port` | The port of the external Network Policy database | `external_db_port` |
| `policyserverdb_user` | The Network Policy database used | `policyserveradmin` |
| `silkdb_name` | The name of the Silk Database | `silkdb` |
| `silkdb_host` | The host of the external Silk database | `external_db_host` |
| `silkdb_port` | The port of the external Silk database | `external_db_port` |
| `silkdb_user` | The Silk database used | `silkadmin` |
| `silkdb_password` | The Silk database password | `external_db_password` |
| `routingapidb_name` | The name of the Routing API database | `routingapidb` |
| `routingapidb_host` | The host of the external Routing API database | `external_db_host` |
| `routingapidb_port` | The port of the external Routing API database | `external_db_port` |
| `routingapidb_user` | The Routing API database used | `routingapiadmin` |
| `routingapidb_password` | The Routing API database password | `external_db_password` |
| `locketdb_name` | The name of the Locket database | `locketdb` |
| `locketdb_host` | The host of the external Locket database | `external_db_host` |
| `locketdb_port` | The port of the external Locket database | `external_db_port` |
| `locketdb_user` | The Locket database used | `locketadmin` |
| `locketdb_password` | The Locket database password | `external_db_password` |
| `credhubdb_name` | The name of the Credhub database | `credhubdb` |
| `credhubdb_host` | The host of the external Credhub database | `external_db_host` |
| `credhubdb_port` | The port of the external Credhub database | `external_db_port` |
| `credhubdb_user` | The Credhub database used | `credhubadmin` |
| `credhubdb_password` | The Credhub database password | `external_db_password` |

#### `postgres-db` - External PostgreSQL Parameters

| param | description | default |
| --- | --- | --- |
| `external_db_host` | The external host for your PostgreSQL db | |
| `external_db_port` | The port for your external PostgreSQL db | `5432` |
| `external_db_password` | The password for the external PostgreSQL db | `((external_db_password))` (Credhub lookup) |
| `uaadb_name` | The name of the UAA Database | `uaadb` |
| `uaadb_host` | The host of the external UAA database | `external_db_host` |
| `uaadb_port` | The port of the external UAA database | `external_db_port` |
| `uaadb_user` | The UAA database used | `uuaadmin` |
| `uaadb_password` | The UAA database password | `external_db_password` |
| `ccdb_name` | The name of the Cloud Controller database | `ccdb` |
| `ccdb_host` | The host of the external Cloud Controller database | `external_db_host` |
| `ccdb_port` | The port of the external Cloud Controller database | `external_db_port` |
| `ccdb_user` | The Cloud Controller database user | `ccadmin` |
| `ccdb_password` | The Cloud Controller database password | `external_db_password` |
| `diegodb_name` | The name of the Diego Database | `diegodb` |
| `diegodb_host` | The host of the external Diego database | `external_db_host` |
| `diegodb_port` | The port of the external Diego database | `external_db_port` |
| `diegodb_user` | The Diego database used | `diegoadmin` |
| `diegodb_password` | The Diego database password | `external_db_password` |
| `policyserverdb_name` | The name of the Network Policy database | `policyserverdb` |
| `policyserverdb_host` | The host of the external Network Policy database | `external_db_host` |
| `policyserverdb_port` | The port of the external Network Policy database | `external_db_port` |
| `policyserverdb_user` | The Network Policy database used | `policyserveradmin` |
| `silkdb_name` | The name of the Silk Database | `silkdb` |
| `silkdb_host` | The host of the external Silk database | `external_db_host` |
| `silkdb_port` | The port of the external Silk database | `external_db_port` |
| `silkdb_user` | The Silk database used | `silkadmin` |
| `silkdb_password` | The Silk database password | `external_db_password` |
| `routingapidb_name` | The name of the Routing API database | `routingapidb` |
| `routingapidb_host` | The host of the external Routing API database | `external_db_host` |
| `routingapidb_port` | The port of the external Routing API database | `external_db_port` |
| `routingapidb_user` | The Routing API database used | `routingapiadmin` |
| `routingapidb_password` | The Routing API database password | `external_db_password` |
| `locketdb_name` | The name of the Locket database | `locketdb` |
| `locketdb_host` | The host of the external Locket database | `external_db_host` |
| `locketdb_port` | The port of the external Locket database | `external_db_port` |
| `locketdb_user` | The Locket database used | `locketadmin` |
| `locketdb_password` | The Locket database password | `external_db_password` |
| `credhubdb_name` | The name of the Credhub database | `credhubdb` |
| `credhubdb_host` | The host of the external Credhub database | `external_db_host` |
| `credhubdb_port` | The port of the external Credhub database | `external_db_port` |
| `credhubdb_user` | The Credhub database used | `credhubadmin` |
| `credhubdb_password` | The Credhub database password | `external_db_password` |

#### `override-db-names` - Database Name Override Parameters

| param | description | default |
| --- | --- | --- |
| `uaadb_name` | Name of the UAA database | `uuadb` |
| `uaadb_user` | Name of the UAA database user | `uuaadmin` |
| `ccdb_name` | Name of the Cloud Controller database | `ccdb` |
| `ccdb_user` | Name of the Cloud Controller database user | `ccadmin` |
| `diegodb_name` | Name of the Diego database | `diegodb` |
| `diegodb_user` | Name of the Diego database user | `diegoadmin` |
| `policyserverdb_name` | Name of the Network Policy database | `policyserverdb` |
| `policyserverdb_user` | Name of the Network Policy database user | `policyserveradmin` |
| `silkdb_name` | Name of the Silk database | `silkdb` |
| `silkdb_user` | Name of the Silk database user | `silkadmin` |
| `routingapidb_name` | Name of the Routing API database | `routingapidb` |
| `routingapidb_user` | Name of the Routing API database user | `routingapiadmin` |
| `locketdb_name` | Name of the Locket database | `locketdb` |
| `locketdb_user` | Name of the Locket database user | `locketadmin` |
| `credhubdb_name` | Name of the Credhub database | `credhubdb` |
| `credhubdb_user` | Name of the Credhub database user | `credhubadmin` |

### Blobstore Parameters

#### `aws-blobstore/aws-blobstore-iam` - AWS Blobstore Parameters

| param | description | default |
| --- | --- | --- |
| `blobstore_s3_region` | The S3 region of the blobstore | |
| `blobstore_bucket_prefix` | Prefix for the path where blobs are stored in the bucket | `"$GENESIS_ENVIRONMENT-$GENESIS_TYPE"` |
| `blobstore_bucket_suffix` | Suffix for the path where blobs are stored in the bucket | `"((cc_director_key))"` |
| `blobstore_app_packages_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-app-packages-"` + `blobstore_bucket_suffix` |
| `blobstore_buildpacks_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-buildpacks-"` + `blobstore_bucket_suffix` |
| `blobstore_droplets_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-droplets-"` + `blobstore_bucket_suffix` |
| `blobstore_resources_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-resources-"` + `blobstore_bucket_suffix` |

#### `minio-blobstore` - Minio Blobstore Parameters

| param | description | default |
| --- | --- | --- |
| `blobstore_minio_endpoint` | The URL (including protocol and option port) of the Minio endpoint of the blobstore | |
| `blobstore_bucket_prefix` | Prefix for the path where blobs are stored in the bucket | `"$GENESIS_ENVIRONMENT-$GENESIS_TYPE"` |
| `blobstore_bucket_suffix` | Suffix for the path where blobs are stored in the bucket | `"((cc_director_key))"` |
| `blobstore_app_packages_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-app-packages-"` + `blobstore_bucket_suffix` |
| `blobstore_buildpacks_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-buildpacks-"` + `blobstore_bucket_suffix` |
| `blobstore_droplets_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-droplets-"` + `blobstore_bucket_suffix` |
| `blobstore_resources_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-resources-"` + `blobstore_bucket_suffix` |

#### `azure-blobstore` - Azure Blobstore Parameters

| param | description | default |
| --- | --- | --- |
| `azure_environment` | What is environment where this blobstore exists? | `AzureCloud` |
| `blobstore_bucket_prefix` | Prefix for the path where blobs are stored in the bucket | `"$GENESIS_ENVIRONMENT-$GENESIS_TYPE"` |
| `blobstore_bucket_suffix` | Suffix for the path where blobs are stored in the bucket | `"((cc_director_key))"` |
| `blobstore_app_packages_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-app-packages-"` + `blobstore_bucket_suffix` |
| `blobstore_buildpacks_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-buildpacks-"` + `blobstore_bucket_suffix` |
| `blobstore_droplets_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-droplets-"` + `blobstore_bucket_suffix` |
| `blobstore_resources_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-resources-"` + `blobstore_bucket_suffix` |

### HAProxy Parameters

#### `haproxy` - Basic HAProxy Parameters

| param | description | default |
| --- | --- | --- |
| `internal_only_domains` | Internal only domains | `[]` |
| `trusted_domain_cidrs` | Trusted cidrs | `~` |
| `haproxy_instances` | How many haproxy instances? | 2 |
| `haproxy_vm_type` | The vm type in cloud-config for haproxy | `haproxy` |
| `cf_lb_network` | What network should haproxy be deployed to? | `cf_edge_network` or `default` |
| `haproxy_ips` | What static ips should be used for haproxy | |
| `availability_zones` | What azs should haproxy be deployed to? | `[z1, z2, z3]` |

#### `haproxy` + `small-footprint` - HAProxy Small Footprint Parameters

| param | description | default |
| --- | --- | --- |
| `haproxy_instances` | How many haproxy instances? | 1 |

#### `haproxy` + `tls` - HAProxy TLS Parameters

| param | description | default |
| --- | --- | --- |
| `disable_tls_10` | Disable TLS 1.0? | `true` |
| `disable_tls_11` | Disable TLS 1.1? | `true` |

#### `ocfp` - HAProxy Service Route Parameters

`params.ocfp_haproxy_service_routes` host-routes non-CF service UIs (e.g.
SHIELD, Grafana, Doomsday, Concourse) through the CF haproxy, so they can
share its public IP and TLS termination instead of needing their own.
Requires the `haproxy` feature (an OCFP deployment enables it by default on
most IaaSes) and generates a dynamic ops file with a host-ACL frontend rule,
a dedicated backend, and a SAN entry on the haproxy cert for each route.

| param | description | default |
| --- | --- | --- |
| `hostname` | The Host header to match and route (also added as a SAN on the haproxy cert) | *required* |
| `backend` | The IP or hostname of the backend service | *required* |
| `port` | The backend port | `443` |
| `ssl` | `noverify` re-encrypts to the backend without verifying its certificate; `none` speaks plain HTTP to the backend | `noverify` |

```yaml
params:
  ocfp_haproxy_service_routes:
  - hostname: shield.example.com
    backend: 10.0.0.20
    port: 443
    ssl: noverify
  - hostname: grafana.example.com
    backend: 10.0.0.21
    port: 8080
    ssl: none
```

`ssl: verify` (validating the backend's certificate against a CA bundle) is
not supported yet -- it would require plumbing a CA bundle to the haproxy
job, which no route in this feature currently configures.

### Windows Diego Cell Parameters

#### `windows-diego-cells` - Windows Diego Cell Parameters

| param | description | default |
| --- | --- | ---- |
| `windows_diego_cell_vm_type` | Windows Diego cell VM Type | `small-highmem` |
| `windows_diego_cell_instances`| Windows Diego Cell Instance Count | `1` |

### Isolation Segment Parameters

#### `isolation-segments` - Isolation Segment Parameters

| param           | description                                                       | default |
| --------------- | ----------------------------------------------------------------- | ------- |
| `name`          | (required) Name of the isolation segment for cloud foundry        | |
| `azs`           | Availability zones network configuration                          | `[ z1, z2]` <sup>[1]</sup> |
| `instances`     | Amount of VM instances to be created                              | `1` |
| `vm_type`       | VM Type to be applied                                             | `small-highmem` <sup>[2]</sup> |
| `vm_extensions` | Extensions to be added to the created VM's                        | `[ 100GB_ephemeral_disk ]` |
| `network_name`  | Name of the network that VM's will be created with                | `default` <sup>[3]</sup> |
| `stemcell`      | Name of the stemcell to be used                                   | `default` |
| `tag`           | Name of the rep placement tag                                     | same as `name` param |
| `tags`          | List of rep placement tags (optional: overrides `tag` and `name`) | |
| `additional_trusted_certs` | List of additional trusted certs (optional)            | |

`[1]` The default azs are [z1,z2] unless migrating from cf kit v1.x, in
which case the default azs are [z1,z2,z3], or if the scale-to-single-az
feature is in use, in which case the default azs are [z1]. Setting
`params.availability_zones` will override the default availability zones
deployment-wide.

`[2]` The default vm_type for all diego-cell based instance groups can be
done by specifying `param.diego_cell_vm_type`

`[3]` The network name defaults to the `params.cf_runtime_network` when
using not using the base feature or if explicitly using the
partitioned-network feature. If that parameter is not specified, it
defaults to `cf-runtime`.

### OCFP Parameters

#### `ocfp` - OCFP Parameters

| param            | description                                                       | default |
| ---------------- | ----------------------------------------------------------------- | ------- |
| `ocfp_env_scale` | Deployment scale - 'dev' or 'prod'                               | `dev` |
| `router-ssl-path`| Path to the user provided certificate and key                     | will use a generated self-signed certificate |
| `split-network`  | Split network into core, edge, tcp-edge, runtime and db           | All VMs are in same network |

## Networking Configuration

The Cloud Foundry Genesis Kit makes some assumptions about how
your networking has been set up, in cloud-config. A lot of these
assumptions are based on the requirements of static IPs in order
to wire things up properly.

We define four networks, which serve to isolate components at
least into easily firewalled CIDR ranges:

- **cf-core** - Contains core components of the apparatus of Cloud Foundry, namely the Cloud Controller API, log subsystem,
  NATS, UAA, etc. If it doesn't fit into a more specific network, it goes in core.

- **cf-edge** - A more exposed network, for components that directly receive traffic from the outside world, including the
  gorouter VMs that facilitate SSH / HTTP(S) traffic.

- **cf-db** - A (very small) network that contains just the internal PostgreSQL node, if the `local-db` feature has been
  activated.

- **cf-runtime** - Usually the largest network, _runtime_ contains all of the Diego Cells. Sequestering it into its own
  CIDR "subnet" allows firewall administrators to more aggressively firewall around running applications, to ensure
  that they cannot interact with core parts of the Cloud Foundry where they have no business.

These networks may be physically discrete, or they may be "soft"
segregation in a larger network (i.e. a /20 being carved up into
several /24 "networks").

Note: if using the `bare` feature, you will have a flat network model as
defined in upstream `cf-deployments`, defaulting to the name `default`

### Loadbalancer

In v1.7.2+, there was the single `cf-load-balanced` VM extension for external
load balancing. In v2.x, this has been replaced with the following:

- cf-router-network-properties
- cf-tcp-router-network-properties
- diego-ssh-proxy-network-properties

Please be sure to update your cloud config accordingly.

## VM Sizing and Scaling

### VM Scaling Parameters

Defaults are as per `cf-deployment`

- `api_instances` - How many Cloud Controller API nodes to deploy

- `cc_worker_instances` - How many cc-worker nodes to deploy.

- `credhub_instances` - How many credhub nodes to deploy.

- `doppler_instances` - How many doppler nodes to deploy.

- `diego_api_instances` - How many Diego BBS nodes to deploy.
  (`bbs_instances` from v1.x will be translated to this value during
  deployment)

- `diego_cell_instances` - How many Diego Cells (runtimes) to deploy.
  (`cell_instances` from v1.x will be translated to this value during
  deployment)

- `haproxy_instances` - How many HAProxy instances to deploy. Defaults to
  `2`, only valid if `haproxy` feature enabled.

- `log_api_instances` - How many loggregator / traffic controller nodes to
  deploy. (`loggregator_instances` from v1.x will be translated to this
  value during deployment)

- `nats_instances` - How many NATS message bus nodes to deploy.

- `router_instances` - How many gorouter nodes to deploy.

- `scheduler_instances` - How many Diego auctioneers to deploy.
  (`diego_instances` from v1.x will be translated to this value during
  deployment)

- `tcp_router_instances` - How many TCP router nodes to deploy.

- `uaa_instances` - How many UAA nodes to deploy.

### VM Types

Upstream `cf-deployments` only supports three vm types: minimum, small and
small-highmem. To fine-tune these vms for each instance type, you can use the
following:

- `api_vm_type` - What type of VM to deploy for the nodes in
  the Cloud Controller API cluster. Defaults to `api`.
  Recommend `2 cpu / 4g mem`.

- `cc_worker_vm_type` - What type of VM to deploy for the cc-worker nodes.
  Recommend `1 cpu / 2g mem`.

- `credhub_vm_type` - What type of VM to deploy for the credhub nodes.
  Recommend `1 cpu / 2g mem`.

- `diego_api_vm_type` - What type of VM to deploy for the Diego BBS
  nodes. (`bbs_vm_type` from v1.x will be translated to this value during
  deployment)
  Recommend `1 cpu / 2g mem`.

- `diego_cell_vm_type` - What type of VM to deploy for the Diego Cells
  (application runtime). These are usually very large machines.
  (`cell_instances` from v1.x will be translated to this value during
  deployment)
  Recommend `4 cpu / 16g mem`.

- `doppler_vm_type` - What type of VM to deploy for the doppler nodes.
  Recommend `1 cpu / 2g mem`.

- `nats_vm_type` - What type of VM to deploy for the nodes in
  the NATS message bus cluster. Defaults to `nats`.
  Recommend `1 cpu / 2g mem`.

- `log_api_vm_type` - What type of VM to deploy for the
  loggregator traffic controller nodes. (`loggregator_vm_type` from v1.x
  will be translated to this value during deployment)
  Recommend `2 cpu / 4g mem`.

- `router_vm_type` - What type of VM to deploy for the gorouter
  nodes.
  Recommend `1 cpu / 2g mem`.

- `errand_vm_type` - What type of VM to deploy for the
  smoke-tests errand. Defaults to `errand`. Recommend `1 cpu / 2g mem`.

  Note: The known errands are `smoke-tests` and `rotate-cc-database-key`.
  If you need to change just one of these, you can use
  `<errand_type_with_underscores_replacing_dashes>_vm_type`

- `scheduler_vm_type` - What type of VM to deploy for the Diego
  orchestration nodes (not the cells, the auctioneers). (`diego_instances`
  from v1.x will be translated to this value during deployment)
  Recommend `2 cpu / 4g mem`.

- `tcp_router_vm_type` - What type of VM to deploy for the TCP router nodes.
  Recommend `1 cpu / 2g mem`.

- `uaa_vm_type` - What type of VM to deploy for the nodes in
  the UAA cluster.
  Recommend `2 cpu / 4g mem`.

*Note:* For known instance groups, the underscores are automatically converted
to hyphens to determine the matching `instance_group` for the specified
`*_vm_type` params. For user specified, you must specify the hyphen or
underscore as used in the `instance_group`.

Known instance groups are:
api, cc-worker, credhub, database, diego-api, diego-cell, doppler,
errand, haproxy, log-api, nats, rotate-cc-database-key, router, scheduler,
singleton-blobstore, smoke-tests, tcp-router, and uaa

## Branding Configuration

An operator may need to set the branding options available through a
typical UAA deployment. Genesis exposes these configuration options
via parameters. Use cases, and examples are below:

### Logos

- `cf_branding_product_logo`

The `cf_branding_product_logo` is base64 encoded image that's
displayed on pages such as `login.$system_domain`. Base64 is a
binary-to-text encoding scheme. This allows us to fit an image into
a YAML file. To convert your image into base64, use the following
command:

`cat logo.png | base64 | tr -d '\n' > logo.png.base64`

This shell command takes `logo.png` and converts it to base64,
and then strips the `\n` characters usually found in base64 output.
This content is then placed in `logo.png.base64`, whose contents
can be easily pasted into your Genesis environment file.

- `cf_branding_square_logo`

The `cf_branding_square_logo` is a smaller version of your
`cf_branding_product_logo`, used in the navigation header and other
places within the CF web UI. You can use the command listed directly
above to convert your image to base64.

### Footer Text & Legal

- `cf_footer_legal_text`
A string to display in the footer, typically used for compliance
text. This string is displayed on all UAA pages.

- `cf_footer_links`
A YAML list of links to display at the footer of all UAA pages.
Example:
```
params:
  cf_footer_links:
    Terms: /exampleTerms
    Privacy Agreement: privacy_example.html
    Plug: http://starkandwayne.com/
```

Where the resulting link will be the string "Terms" that directs to
`/exampleTerms`

## Cloud Configuration

Aside from the different VM and disk types described above, in the
_Sizing & Scaling Parameters_ section, your cloud config must
define the following VM extensions:

- `cf-elb` - Cloud-specific load balancing properties, for
  HTTP/HTTPS load balancing (i.e. via Amazon's ELBs).

- `ssh-elb` - Cloud-specific load balancing properties, for TCP
  load balancing of `cf ssh` connections.

### Azure Availability Sets

The Microsoft Azure Cloud does not implement availability zones in
the sense that BOSH tends to use them. Instead, it expects you to
assign each group of VMs that ought to be fault-tolerant to a
named *availability_set*.

If the kit detects that your BOSH director is using the Azure CPI,
it will automatically include some configuration to activate these
availability sets for things that need HA / fault-tolerance.

You must, in turn, define the following VM extensions in your
cloud config:

1. `haproxy_as` - HAProxy availability set.
2. `nats_as` - NATS Message Bus cluster availability set.
3. `uaa_as` - UAA nodes availability set.
4. `api_as` - Cloud Controller API nodes availability set.
5. `doppler_as` - Doppler node availability set.
6. `loggregator_tc_as` - Loggregator / Traffic Controller
    availability set.
7. `router_as` - Router / SSH Proxy availability set.
8. `bbs_as` - Diego BBS availability set.
9. `diego_as` - Diego auctioneer availability set.
10. `cell_as` - Diego Cell (runtime) availability set.

An example `vm_extension` might be:

```
---
vm_extensions:
  - name: uaa_as
    cloud_properties:
      availability_set: us-west-prod-uaa

    # etc.
```

## Available Addons

- `setup-cli` - Installs cf CLI plugins, like 'Targets', which
  helps to manage multiple Cloud Foundries from a single jumpbox.

- `login` - Log into the Cloud Foundry instance as the admin.

- `asg` - Generates application security group (ASG) definitions,
  in JSON, which can then be fed into Cloud Foundry.

- `smoketest` - Runs smoke tests to verify CF operation.

## History

Version 2.5.x adds STACKIT support, changes default runtime stack to cflinuxfs4.

Version 2.0.0 refactored to be based on upstream `cf-deployment` de-facto
deployment repository (v12.45.0)

Version 1.7.0 primarily removes static IPs and consolidates the
`access` and `router` instance groups, without updating any
software or behavior.

Version 1.6.0 is based on changes up to v9.5.0 of the cf-deployment release

Version 1.5.0 completely removes usage of consul, instead relying on BOSH DNS.

Version 1.0.0 was the first version to support Genesis 2.6 hooks
for addon scripts and `genesis info`.

Up through version 0.3.1 of this kit, there was a subkit / feature
called `shield` which colocated the SHIELD agent for performing
local backups of the consul cluster. As of version 1.0.0, this
model is no longer supported; operators are encouraged to use BOSH
runtime configs to colocate addon jobs instead.
