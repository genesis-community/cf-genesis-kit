# Cloud Foundry Genesis Kit Manual

The **Cloud Foundry Genesis Kit** deploys a single instance of
Cloud Foundry.  As of v2.0.0, this is now based on [cf-deployment][cf-deployment]

[cf-deployment]: https://https://github.com/cloudfoundry/cf-deployment

# Requirements

The Cloud Foundry Genesis Kit requires that BOSH DNS be already
available in the runtime config prior to Kit deployment. Please
refer to [bosh-deployment][bosh-deployment] for an example
runtime config.

Furthermore, this kit requires the BOSH director to be deployed with Credhub.
It is recommended that you use the latest release of
[bosh-genesis-kit][bosh-genesis-kit], as this will ensure everything is
correctly configured.


[bosh-deployment]: https://github.com/cloudfoundry/bosh-deployment/blob/master/runtime-configs/dns.yml
[bosh-genesis-kit]: https://github.com/genesis-community/bosh-genesis-kit

# General Usage Guidelines

As per usual with Genesis kits, you will need a Genesis deployment repository
to contain your environment file.  If you don't already have one from a
previous `cf` version, run `genesis init -k cf/<version>`, where <version> is
replaced with the current cf genesis kit version.  If you have this already,
you'll need to download the latest copy of this kit via `genesis fetch-kit`
from within that directory.

Once in the Genesis `cf` deployment repository, and run `genesis new <env>` to
create a new env file, replacing `<env>` with your desired env.  This will
walk you through a wizard that will populate the desired features and the
corresponding parameters.

Once you have an env file, you may want to manually change parameters or
features. The rest of this document covers how to modify your environment
files to make use of provided features.

# Features

In genesis kits features can be opted-in to on a per-environment bases by adding the `features` array to the environment file:
```
kit:
  features:
  - feature-a
  - feature-b
```

Using features is a way to configure the kit to suite the requirements of your specific deployment.

## Features Provided by the Genesis Kit
General:
  - `compiled-releases` - Use pre-compiled releases to speed up initial deploy time (alias of upstream `cf-deployment/operations/use-compiled-releases`).
  - `small-footprint` - Use the minimal number of vms and only 1 az to deploy cf.
  - `nfs-volume-services` - Alias of `cf-deployment/operations/enable-nfs-volume-service`
  - `enable-service-discovery` - Enables bosh-dns support on diego cells.
  - `app-autoscaler-integration` - Add a uaa client for the app autoscaler (must be deployed via [cf-app-autoscaler-genesis-kit](https://github.com/genesis-community/cf-app-autoscaler-genesis-kit)).
  - `prometheus-integration` - Configure cf to export to prometheus (must deployed via [prometheus-genesis-kit](https://github.com/genesis-community/prometheus-genesis-kit)).
  - `bare` - Deploy _only_ the cf-deployment files without genesis packaged best-practices applied.
  - `migrated-v1-env` - Fix the database names after having migrated from v1 kit.
  - `no-nats-tls` - Nats over TLS was not part of cf-deployment v12.45, but has been turned on by default unless using bare mode.  Set this feature to disable it.
  - `ssh-proxy-on-routers` - moves the ssh-proxy from scheduler instance group to the router instance group, placing it on the edge network, and enabling scaling via scaling the routers.
  - `no-tcp-routers` - removes the tcp-router instance group and associated resource allocations for systems that don't need tcp routes.

Database related - choose one:
  - `postgres-db` - Use an external postgres instance to host persistent data.
  - `mysql-db` - Use an external postgres instance to host persistent data.
  - `local-mysql-db` - Use a mysql database and deploy it on a vm as part of this deployment.
  - `override-db-names` - When specifying `local-mysql-db` (or `local-postgresql-db` which is on by default) you can override the names of the databases that are created.

Load balancer related:
  - `haproxy` - Deploy an haproxy loadbalancer in front of cf.
  - `tls` - Configure haproxy to use tls.
  - `self-signed` - Generate self-signed certs for haproxy.

Blobstore related:
  - `aws-blobstore` - Use AWS S3 storage as external blobsore, via credentials.
  - `aws-blobstore-iam` - Use AWS S3 storage as external blobsore, via IAM
    configuration
  - `minio-blobstore` - Use Minio S3-compatible storage as external blobsore.
  - `azure-blobstore` - Use Azure blob storage as external blobstore.
  - `gcp-blobstore` - Use GCS as external blobstore.
  - `gcp-use-access-key` - Use use google storage access key/secret to access the external GCS blobstore (instead of service account credentials which is the default).

## Features Provided by `cf-deployment`

In addition to the bundled features that this kit exposes you can also include any ops files contained in the upstream [cf-deployment](https://https://github.com/cloudfoundry/cf-deployment) by referencing them via:
```
kit:
  features:
  - cf-deployment/path/to/file # omit .yml suffix
```

Caveat: Not all features are compatible with this kit and features are applied in order, so ordering may matter.

## Providing your Own Features

If you would like to apply additional ops-files for unsupported features you can do so by adding them under:
```
./ops/<feature-name>.yml
```

and reference them in your environment file via:
```
kit:
  features:
  - <feature-name>
```

## Feature Params
The following params are always included:
| param | description | default |
| --- | --- | --- |
| `cf_core_network` | What network should be used for cf core-components? | `cf-core` |
| `cf_edge_network` | What network should be used for cf edge-components? | `cf-edge` |
| `cf_runtime_network` | What network should be used for cf runtime-components? | `cf-runtime` |
| `base_domain` | What is the base domain for this Cloud Foundry? | |
| `system_domain` | What is the system domain for this Cloud Foundry? | `system.<base_domain>` |
| `apps_domain` | What is the apps domain for this Cloud Foundy? | `run.<system-domain>` |
| `identity_support_address` | Identity support address | `"https://github.com/genesis-community/cf-genesis-kit"` |
| `identity_description` | Identity description | `"Use 'genesis info' on environment file for more details"` |

These params need to be set when activating features:
  - **aws-blobstore/aws-blobstore-iam**:
    | param | description | default |
    | --- | --- | --- |
    | `blobstore_s3_region` | The s3 region of the blobstore | |
    | `blobstore_bucket_prefix` | Prefix for the path where blobs are stored in the bucket | `"$GENESIS_ENVIRONMENT-$GENESIS_TYPE"` |
    | `blobstore_bucket_suffix` | Suffix for the path where blobs are stored in the bucket | `"((cc_director_key))"` |
    | `blobstore_app_packages_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-app-packages-"` + `blobstore_bucket_suffix` |
    | `blobstore_buildpacks_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-buildpacks-"` + `blobstore_bucket_suffix` |
    | `blobstore_droplets_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-droplets-"` + `blobstore_bucket_suffix` |
    | `blobstore_resources_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-resources-"` + `blobstore_bucket_suffix` |

  - **minio-blobstore**:
    | param | description | default |
    | --- | --- | --- |
    | `blobstore_minio_endpoint` | The URL (including protocol and option port) of the Minio endpoint of the blobstore | |
    | `blobstore_bucket_prefix` | Prefix for the path where blobs are stored in the bucket | `"$GENESIS_ENVIRONMENT-$GENESIS_TYPE"` |
    | `blobstore_bucket_suffix` | Suffix for the path where blobs are stored in the bucket | `"((cc_director_key))"` |
    | `blobstore_app_packages_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-app-packages-"` + `blobstore_bucket_suffix` |
    | `blobstore_buildpacks_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-buildpacks-"` + `blobstore_bucket_suffix` |
    | `blobstore_droplets_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-droplets-"` + `blobstore_bucket_suffix` |
    | `blobstore_resources_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-resources-"` + `blobstore_bucket_suffix` |

  - **azure-blobstore**:
    | param | description | default |
    | --- | --- | --- |
    | `azure_environment` | What is environment where this blobstore exists? | `AzureCloud` |
    | `blobstore_bucket_prefix` | Prefix for the path where blobs are stored in the bucket | `"$GENESIS_ENVIRONMENT-$GENESIS_TYPE"` |
    | `blobstore_bucket_suffix` | Suffix for the path where blobs are stored in the bucket | `"((cc_director_key))"` |
    | `blobstore_app_packages_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-app-packages-"` + `blobstore_bucket_suffix` |
    | `blobstore_buildpacks_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-buildpacks-"` + `blobstore_bucket_suffix` |
    | `blobstore_droplets_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-droplets-"` + `blobstore_bucket_suffix` |
    | `blobstore_resources_directory` | Directory for the app packages | `blobstore_bucket_prefix` + `"-resources-"` + `blobstore_bucket_suffix` |

  - **bare**:
    | param | description | default |
    | --- | --- | --- |
    | `network` | What network should Cloud Foundry be deployed to? | `default` |

  - **external-mysql**:
    | param | description | default |
    | --- | --- | --- |
    | `external_db_host` | The default host for your mysql db | |
    | `external_db_port` | The default for your external mysql db | `3306` |
    | `external_db_password` | The password for the external mysql db | `((external_db_password))` (Credhub lookup) |
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

  - **external-postgres**:
    | param | description | default |
    | --- | --- | --- |
    | `external_db_host` | The external host for your postgres db | |
    | `external_db_port` | The port for your external postgres db | `5432` |
    | `external_db_password` | The password for the external postgres db | `((external_db_password))` (Credhub lookup) |
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

  - **haproxy**:
    | param | description | default |
    | --- | --- | --- |
    | `internal_only_domains` | Internal only domains | `[]` |
    | `trusted_domain_cidrs` | Trusted cidrs | `~` |
    | `haproxy_instances` | How many haproxy instances? | 2 |
    | `haproxy_vm_type` | The vm type in cloud-config for haproxy | `haproxy` |
    | `cf_lb_network` | What network should haproxy be deployed to? | `cf_edge_network` or `default` |
    | `haproxy_ips` | What static ips should be used for haproxy | |
    | `availability_zones` | What azs should haproxy be deployed to? | `[z1, z2, z3]` |

  - **haproxy** + **small-footprint**:
    | param | description | default |
    | --- | --- | --- |
    | `haproxy_instances` | How many haproxy instances? | 1 |

  - **haproxy** + **tls**:
    | param | description | default |
    | --- | --- | --- |
    | `disable_tls_10` | Disable tls 10? | `true` |
    | `disable_tls_11` | Disable tls 11? | `true` |

  - **override-db-names**:
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

# Retired Parameters (from v1.x)

## General

Some of these features may return in latter v2.x releases, but for the v2.0.0 release, they have been removed as they are not compatible with the upstream `cf-deployment` configuration, or have been replaced by an ops file.  If needed, `instance_groups` overrides in the environment file can be used to effect the desired configuration

  - `api_domain` - It was: *What is the api domain for this Cloud Foundry?*  It is now `api.<system_domain>`.

  - `default_app_memory` - It was: *How much memory (in megabytes) to assign a pushed application that did not specify its memory requirements, explicitly.  Defaults to `256`.*

  - `default_app_disk_in_mb` - It was: *How much disk (in megabytes) to assign a pushed application that did not specify its memory requirements, explicitly. Defaults to `1000`.*

  - `default_stack` - `cflinuxfs3` is the only stack supported.

  - `uaa_lockout_failure_count` - It was: *Number of failed UAA login attempts before lockout.*

  - `uaa_lockout_window` - It was: *How much time (in seconds) in which `uaa_lockout_failure_count` must occur in order for account to be locked. Defaults to `1200`.*

  - `uaa_lockout_time` - It was: *How long (in seconds) the account is locked out for violating `uaa_lockout_failure_count` within `uaa_lockout_failure_time_between_failures`. Defaults to `300`.*

  - `uaa_refresh_token_validity` - It was: *How long (in seconds) a CF refresh is valid for. Defaults to `2592000`.*

  - `grootfs_reserved_space` - It was: *The amount of space (in MB) the garbage collection for Garden should keep free for other jobs. GC will delete unneeded layers as need to keep this space free. `-1` disables GC. Defaults to `15360`.*

  - `vm_strategy` - The default is `delete-create`, but can be set to create-swap-delete by using the feature `cf-deployment/operations/experimental/use-create-swap-delete-vm-strategy`

  - `max_log_lines_per_second` - This has been replaced with the upstream feature `cf-deployment/operations/experimental/enable-app-log-rate-limiting` and setting `bosh-variables.app_log_rate_limit` to the desired value.

# Supported Kit Base Parameters

  - `base_domain` - The base domain for this Cloud Foundry deployment.  All domains (system, api, apps, etc.) will be based off of this base domain, unless you override them.  This parameter is **required**.

  - `system_domain` - The system domain.  Defaults to `system.` plus the base domain.

  - `apps_domains` - A list of global application domains.  Defaults to a list of one domain, `run.` plus the base domain.  Note: if using `bare` feature, this will default to the system domain.  The first listed domain will be used for smoke tests, and anything else that just uses a single domain.

  - `availability_zones` - Specify the desired availability zones, as a list.  If using `small-footprint` feature, only the first AZ will be used.  By default, AZs used will be [z1,z2], unless upgraded from the v1.x series, in which case, [z1,z2,z3] will be used.  Cannot be specified when deploying to Azure.

  - `randomize_az_placement` - Unless set to false, any instances that are remaining after evenly distributing them across the available availability zones for a given instance group, will be randomly assigned instead of sequentially assigned.  This prevents overutilizing the first listed AZs.

  - `skip_ssl_validation` - In v1.x kits, this defaulted to false, but as v2.0 is based on cf-deployment, it keeps to cf-deployments concept of defaulting to true.  If explicitly set to false, it enables the cf-deployment/operations/stop-skipping-tls-validation ops file.


## Branding

  - `cf_branding_product_logo` - A base64 encoded image to display on the web UI login prompt. Defaults to `nil`. Read more in the [Branding][2] section.

  - `cf_branding_square_logo` - A base64 encoded image to display in areas where a smaller logo is necessary. Defaults to `nil`.  Read more in the [Branding][2] section.

  - `cf_footer_legal_text` - A string to display in the footer, typically used for compliance text. Defaults to `nil`. Read more in the [Branding][2] section.

  - `cf_footer_links` - A YAML list of links to enumerate in the footer of the web UI. Defaults to `nil`. Read more in the [Branding][2] section.

    [2]: (#branding)

## Deployment Parameters

  - `stemcell_os`
  - `stemcell_version`

## VM Scaling Parameters

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

  - `haproxy_instances` - How many HAProxy instances to deploy.  Defaults to
    `2`, only valid if `haproxy` feature enabled.

  - `log_api_instances` - How many loggregator / traffic controller nodes to
    deploy.  (`loggregator_instances` from v1.x will be translated to this
    value during deployment)

  - `nats_instances` - How many NATS message bus nodes to deploy.

  - `router_instances` - How many gorouter nodes to deploy.

  - `scheduler_instances` - How many Diego auctioneers to deploy.
    (`diego_instances` from v1.x will be translated to this value during
    deployment)

  - `tcp_router_instances` - How many TCP router nodes to deploy.

  - `uaa_instances` - How many UAA nodes to deploy.

## VM Sizing

Upstream `cf-deployments` only supports three vm types: minimum, small and
small-highmem.  To fine-tune these vms for each instance type, you can use the
following:

  - `api_vm_type` - What type of VM to deploy for the nodes in
    the Cloud Controller API cluster.  Defaults to `api`.
    Recommend `2 cpu / 4g mem`.

  - `cc_worker_vm_type` - What type of VM to deploy for the cc-worker nodes.
    Recommend `1 cpu / 2g mem`.

  - `credhub_vm_type` -  What type of VM to deploy for the credhub nodes.
    Recommend `1 cpu / 2g mem`.

  - `diego_api_vm_type` - What type of VM to deploy for the Diego BBS
    nodes. (`bbs_vm_type` from v1.x will be translated to this value during
    deployment)
    Recommend `1 cpu / 2g mem`.

  - `diego_cell_vm_type` - What type of VM to deploy for the Diego Cells
    (application runtime).  These are usually very large machines.
    (`cell_instances` from v1.x will be translated to this value during
    deployment)
    Recommend `4 cpu / 16g mem`.

  - `doppler_vm_type` - What type of VM to deploy for the doppler nodes.
    Recommend `1 cpu / 2g mem`.

  - `nats_vm_type` - What type of VM to deploy for the nodes in
    the NATS message bus cluster.  Defaults to `nats`.
    Recommend `1 cpu / 2g mem`.

  - `log_api_vm_type` - What type of VM to deploy for the
    loggregator traffic controller nodes.  (`loggregator_vm_type` from v1.x
    will be translated to this value during deployment)
    Recommend `2 cpu / 4g mem`.

  - `router_vm_type` - What type of VM to deploy for the gorouter
    nodes.
    Recommend `1 cpu / 2g mem`.

  - `errand_vm_type` - What type of VM to deploy for the
    smoke-tests errand.  Defaults to `errand`. Recommend `1 cpu / 2g mem`.

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

*Note:*  For known instance groups, the underscores are automatically converted
to hyphens to determine the matching `instance_group` for the specified
`*_vm_type` params.  For user specified, you must specify the hyphen or
underscore as used in the `instance_group`.

Known instance groups are:
  api, cc-worker, credhub, database, diego-api, diego-cell, doppler,
  errand, haproxy, log-api, nats, rotate-cc-database-key, router, scheduler,
  singleton-blobstore, smoke-tests, tcp-router, and uaa


### Special Considerations for Migrating from v1.x

For environments that were migrated from v1.x version of the kit, the features
`v1-vm-type` will be automatically turned on, which will use the same VM types
as was used in the v1.x versions of the kit, or as close to possible.  This
allows you to use your existing cloud config and tuning.  Where the instance
group name changes, it will use the vm type that the instance group was
migrated from.

The exceptions are `tcp-router`, which will use the `router` vm type, and
`cc-worker` and `credhub`, which continue to use `minimum` as there was no
prevous instance group for these functions.

If you want to use the de facto vm types after migration, you can specify the
`no-v1-vm-types` feature.

The vm types are as follows:

| v2 instance group | prevous (v1) instance group | vm type |
=============================================================
| api | api | api |
| cc-worker | - | minimal |
| credhub | - | minimal |
| database | postgres | postgres |
| diego-api | bbs | bbs |
| diego-cell | cell | cell |
| doppler | doppler | doppler |
| log-api | loggregator | loggregator |
| nats | nats | nats |
| rotate-cc-database-key | - | errand |
| router | router | router |
| scheduler | diego | diego |
| singleton-blobstore | blobstore | blobstore |
| smoke-tests | smoke-tests | errand |
| tcp-router | -  | router |
| uaa | uaa | uaa |


## Networking Parameters

The Cloud Foundry Genesis Kit makes some assumptions about how
your networking has been set up, in cloud-config.  A lot of these
assumptions are based on the requirements of static IPs in order
to wire things up properly.

We define four networks, which serve to isolate components at
least into easily firewalled CIDR ranges:

  - **cf-core** - Contains core components of the apparatus of
    Cloud Foundry, namely the Cloud Controller API, log subsystem,
    NATS, UAA, etc.  If it doesn't fit into a more specific network,
    it goes in core.

  - **cf-edge** - A more exposed network, for components that
    directly receive traffic from the outside world, including the
    gorouter VMs that facilitate SSH / HTTP(S) traffic.

  - **cf-db** - A (very small) network that contains just the
    internal PostgreSQL node, if the `local-db` feature has been
    activated.

  - **cf-runtime** - Usually the largest network, _runtime_
    contains all of the Diego Cells.  Sequestering it into its own
    CIDR "subnet" allows firewall administrators to more
    aggressively firewall around running applications, to ensure
    that they cannot interact with core parts of the Cloud Foundry
    where they have no business.

These networks may be physically discrete, or they may be "soft"
segregation in a larger network (i.e. a /20 being carved up into
several /24 "networks").

Note: if using the `bare` feature, you will have a flat network model as
defined in upstream `cf-deployments`, defaulting to the name `default`

### Loadbalancer

In v1.7.2+, there was the single `cf-load-balanced` VM extension for external
load balancing.  In v2.x, this has been replaced with the following

     - cf-router-network-properties
     - cf-tcp-router-network-properties
     - diego-ssh-proxy-network-properties

Please be sure to update your cloud config accordingly.

## Choosing a Blobstore

Cloud Foundry uses an object storage system, or _blobstore_ to
keep track of things like application droplets (compiled bits of
app code), buildpacks, etc.  You can chose to host your blobstore
within the CF deployment itself (a _local blobstore_), or on a
cloud provider of your choice.

NOTE: You must choose one of the blobstore features, and you must
choose only one.

### Using a Local Blobstore

The `local-blobstore` feature will add a WebDAV node to the Cloud
Foundry deployment, which will be used to store all blobs on a
persistent disk provisioned by BOSH.

The following parameters are defined:

  - `blobstore_vm_type` - The type of VM (per cloud config) to use
    when deploying the WebDAV blobstore VM.  Defaults to `blobstore`.
    Recommend `1 cpu / 2g mem`.

  - `blobstore_disk_pool` - The disk type (per cloud config) to
    use when provisioning the persistent disk for the WebDAV VM.
    Defaults to `blobstore`.

### Using an AWS Blobstore

The `aws-blobstore` feature will configure Cloud Foundry to use an
Amazon S3 bucket (or an S3 work-alike like Scality or Minio), to
store all blobs in.

The following parameters are defined:

  - `blobstore_s3_region` - The name of the AWS region in which to
    find the S3 bucket.  This parameter is **required**.

The following secrets will be pulled from Credhub:

  - `blobstore_access_key_id`
  - `blobstore_secret_access_key`

### Using an Minio S3-compatible Blobstore

The `minio-blobstore` feature will configure Cloud Foundry to use a
local S3-compatible bucket to store all blobs in.

The following parameters are defined:

  - `blobstore_minio_endpoint` - This is the full URL, including protocol and
    optional port, of the Minio (or compatible) S3 service.  This parameter is **required**.

The following secrets will be pulled from Credhub:

  - `blobstore_access_key_id`
  - `blobstore_secret_access_key`

### Using an Azure Blobstore

The `azure-blobstore` feature will configure Cloud Foundry to use
Microsoft Azure Cloud's object storage offering.

The following parameters are defined:

  - `blobstore_environment` - The name of the Azure environment to use.  This
    will default to whatever is set in `azure_environment` param, or
    "AzureCloud" if that is not set.  Other valid values are:
    "AzureChinaCloud", "AzureUSGovernment", and "AzureGermanCloud"

  - `blobstore_app_packages_directory` - directory in the Azure Store that
    contains the app packages.  Defaults to "app-packages"

  - `blobstore_buildpacks_directory` - directory in the Azure Store that
    contains the buildpacks.  Defaults to "buildpacks"

  - `blobstore_droplets_directory` - directory in the Azure Store that
    contains the droplets.  Defaults to "droplets"

  - `blobstore_resources_directory` - directory in the Azure Store that
    contains the resources.  Defaults to "resources"

The following secrets will be pulled from the Credhub:

  - The Storage Account Name and Access Key, for use when dealing with the
    Microsoft Azure API.  These are stored in Credhub, under the deployment
    base path of `/<bosh_director_deployment_name>/<cf_deployment_name>/`:
    - `blobstore_storage_account_name`
    - `blobstore_storage_access_key`

### Using Google Cloud Platform's Blobstore

The `gcp-blobstore` feature will configure Cloud Foundry to use
Google Cloud Platform's object storage offering.

There are currently no parameters defined for this type of
blobstore.

The following secrets will be pulled from Credhub:
  - `gcs_project`: The name of project for accessing Google Cloud Storage.
  - `gcs_service_account_email`: The email for the GCS service account.
  - `gcs_service_account_json_key`: The JSON key containing the access credentials for the GCS service account.

These values will be generated by `genesis new`, or migrated from the
corresponding values in Vault during a v1.x migration.  Otherwise, you will
have to populate these values manually via the Credhub cli.

Note: prior versions of the Cloud Foundry kit leveraged legacy
Amazon-like access-key/secret-key credentials.  It now uses
service accounts because Google limits you to 5 legacy keys per
user account.

## Choosing a Database

Cloud Foundry stores its metadata in a set of relational databases,
either MySQL or PostgreSQL.  These databases house things like the
orgs and spaces defined, application instance counts, blobstore
pointers (tying an app to its droplet, for instance) and more.

You have a few options in how these databases are deployed, and
can rely on cloud provider RDBMS offerings when appropriate.

### Using a Local Database

There are two feature options that are available, `local-postgres-db`, a
single, non-HA PostgreSQL node, and `local-mysql-db`, the default PXC MySQL
database that comes with upstream cf-deployment.

Both features are a mostly hands-off change to the deployment, since
the kit will generate all internal passwords, and automatically wire
up to the new node for database DSNs.


### Using an External Database

The `mysql-db` feature configures Cloud Foundry to connect to a
single, external MySQL or MariaDB database server for all of its
RDBMS needs.

The `postgres-db` feature configures Cloud Foundry to connect to a
single, external PostgreSQL database server for all of its RDBMS
needs.

The following parameters are defined:

  - `external_db_host` - The hostname (FQDN) or IP address of the
    database server.  This parameter is **required**.

  - `external_db_port` - The TCP port that the database is
    listening on.  Defaults to `3306` for MySQL or 5678 for PostgreSQL.

#### Configurating Database Access

By default, each database used by CF has its own name, username and password.
The name and username have defaults, but you must specify the password for
each database.  Alternatively, you can configure the databases to share
username and password.

##### Shared Database User

To configure the databases to have a single common user, add the following to
your environment file:

```
params:
  external_db_username: ((external_db_user))
  external_db_password: ((external_db_password)
```

These were created when `genesis new` was added.  If the environment was not
created in this manner, you will have to add these values explicitly using the
`credhub` cli.

##### Per-database Users

The databases used by CloudFoundry are `cloud_controller`, `uaa`, `diego`,
`routing-api`, `network_policy`,`network_connectivity`,`locket`, and
`credhub`.  Each of these databases use a user by the same name as the
database.  To set the password for each of the users to the a common single
password, just set `external_db_password`, but don't set
`external_db_username`.

To set unique passwords, set the following parameters in the environment file
and add the corresponding secrets to credhub:

```
params:
  uaadb_password:          ((uaa_db_password))
  ccdb_password:           ((cloud_controller_db_password))
  diegodb_password:        ((diego_db_password))
  policyserverdb_password: ((network_policy_db_password))
  silkdb_password:         ((network_connectivity_db_password))
  routingapidb_password:   ((routing_api_db_password))
  locketdb_password:       ((locket_db_password))
  credhubdb_password:      ((credhub_db_password))
```


You can also customize the database `name`, `host`, `port` or `user` for any
of the above databases, by replacing `password` with the above params.  Any
parameter not overridden will use the default name and user, and the common
host and port.

### Special Database Consideration when Upgrading from v1.10.x

Upgrading from 1.10.x will result in a slightly different experience.
Existing local PostgreSQL databases will be renamed to match the expected
names for upstream `cf-deployment`, *EXCEPT* in the case where the names have
been overridden with v1.x parameters for setting the database name.

Similarly, local database usernames will be set to the common username for
that database *UNLESS* overridden by v1.x parameters for setting database
usernames.

As for External Databases, v1.x parameters will be kept as specified in the
environment files, with the single exception:  You must add the
`external_db_username` parameter.  The secret value will be transfered into
Credhub from vault, so just set it to `((external_db_user))`.

However, if you are specifying each database's user password individually, you
do not need to specify the `external_db_username` parameter.  You will need to
transfer the passwords from vault to Credhub manually, and update the
environment file accordingly in this case.

## Routing & TLS

The `haproxy` feature activates a pair of software load balancers,
running haproxy, that sit in front of the Cloud Foundry gorouter
layer.

You must specify the IP addressese to be used by the haproxy instances, using
the `haproxy_ips` parameter in list format.  These IPs must be in the
range used by the network specified in `cf_lb_network`, which defaults to the
same network as the `cf_edge_network`

If you also activate the `tls` feature, these haproxy instances
will terminate your SSL/TLS sessions, and present your
certificates to connecting clients.

The `tls` feature works in tandem with `haproxy`; on its own, it
does nothing.

The `tls` feature enables the following parameters:

  - `disable_tls_10` - Disable support for TLS v1.0 (ca. 1999)

  - `disable_tls_11` - Disable support for TLS v1.1 (ca. 2006)

Normally, you would provide your own SSL/TLS certificates to the
Cloud Foundry deployment.  Often, these certificates are signed by
a trusted root certificate authority.  However, if you do not have
your own certificates, and just want to automatically generate
self-signed certificates (which will not be trusted by _any_
browser), you can activate the `self-signed` feature.
Certificates will then be automatically generated with the proper
subject alternate names for all of the domains (system and apps)
that Cloud Foundry will use.

## Small Footprint Cloud Foundry

Sometimes, you may want to sacrifice redundancy and high
availability for a smaller cloud infrastructure bill.  In these
cases, you can activate the `small-footprint` feature to reduce
the size and scope of your entire Cloud Foundry deployment, above
and beyond what can be done by simply tuning instance counts.

Specifically, the `small-footprint` feature collapses all of the
availability zones into a single zone (z1), and instances all of
the VM types down to 1 instance each.

This is a great thing to do for sandboxes and test environments,
but not an advisable course of action for anything with production
SLAs or uptime guarantees.

There are currently no parameters defined for this feature.

## NFS Volume Services

The `nfs-volume-services` feature adds a volume driver to the
Cloud Foundry Diego cells, to allow application instances to mount
NFS volumes provided by the NFS Volume Services Broker.

There are currently no parameters defined for this feature.


# Zero-downtime App Deployments

This kit allows for using the v3 api's [Zero Downtime (ZDT) deployments](https://docs.cloudfoundry.org/devguide/deploy-apps/rolling-deploy.html) via the
capi release's cc_deployment_updater.

# DNS

This release makes use of the BOSH DNS, and uses DNS addresses instead of IP
addresses.  If IP addresses are needed instead, you can turn off this feature
for for this deployment by setting `features.use_dns_addresses` to `false`.
You may also have to turn off `director.local_dns.use_dns_addresses` as well.

See [Native DNS Support](https://bosh.io/docs/dns) for more information about
DNS, and [here](https://bosh.io/docs/dns/#links) for specific information
about using DNS entries in links.

# Branding
An operator may need to set the branding options available through a
typical UAA deployment. Genesis exposes these configuration options
via parameters. Use cases, and examples are below:

## Logos

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

## Footer Text & Legal

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

# Cloud Configuration

Aside from the different VM and disk types described above, in the
_Sizing & Scaling Parameters_ section, your cloud config must
define the following VM extensions:

  - `cf-elb` - Cloud-specific load balancing properties, for
    HTTP/HTTPS load balancing (i.e. via Amazon's ELBs).

  - `ssh-elb` - Cloud-specific load balancing properties, for TCP
    load balancing of `cf ssh` connections.

## Azure Availability Sets

The Microsoft Azure Cloud does not implement availability zones in
the sense that BOSH tends to use them.  Instead, it expects you to
assign each group of VMs that ought to be fault-tolerant to a
named *availability_set*.

If the kit detects that your BOSH director is using the Azure CPI,
it will automatically include some configuration to activate these
availability sets for things that need HA / fault-tolerance.

You must, in turn, define the following VM extensions in your
cloud config:

  1.  `haproxy_as` - HAProxy availability set.
  2.  `nats_as` - NATS Message Bus cluster availability set.
  3.  `uaa_as` - UAA nodes availability set.
  4.  `api_as` - Cloud Controller API nodes availability set.
  5.  `doppler_as` - Doppler node availability set.
  6.  `loggregator_tc_as` - Loggregator / Traffic Controller
      availability set.
  7.  `router_as` - Router / SSH Proxy availability set.
  8.  `bbs_as` - Diego BBS availability set.
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

# Available Addons

  - `setup-cli` - Installs cf CLI plugins, like 'Targets', which
    helps to manage multiple Cloud Foundries from a single jumpbox.

  - `login` - Log into the Cloud Foundry instance as the admin.

  - `asg` - Generates application security group (ASG) definitions,
    in JSON, which can then be fed into Cloud Foundry.


# History

Version 2.0.0 refactored to be based on upstream `cf-deployment` de-facto
deplo9yment repository (v12.45.0)

Version 1.7.0 primarily removes static IPs and consolidates the
`access` and `router` instance groups, without updating any
software or behavior.

Version 1.6.0 is based on changes up to v9.5.0 of the cf-deployment release

Version 1.5.0 completely removes usage of consul, instead relying on BOSH DNS.

Version 1.0.0 was the first version to support Genesis 2.6 hooks
for addon scripts and `genesis info`.

Up through version 0.3.1 of this kit, there was a subkit / feature
called `shield` which colocated the SHIELD agent for performing
local backups of the consul cluster.  As of version 1.0.0, this
model is no longer supported; operators are encouraged to use BOSH
runtime configs to colocate addon jobs instead.
