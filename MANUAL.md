# Cloud Foundry Genesis Kit Manual

The **Cloud Foundry Genesis Kit** deploys a single instance of
Cloud Foundry.

# Requirements

The Cloud Foundry Genesis Kit requires that BOSH DNS be already
available in the runtime config prior to Kit deployment. Please
refer to [bosh-deployment][bosh-deployment] for an example
runtime config.


[bosh-deployment]: https://github.com/cloudfoundry/bosh-deployment/blob/master/runtime-configs/dns.yml

# Parameters

  - `base_domain` - The base domain for this Cloud Foundry
    deployment.  All domains (system, api, apps, etc.) will be
    based off of this base domain, unless you override them.
    This parameter is **required**.

  - `system_domain` - The system domain.  Defaults to `system.`
    plus the base domain.

  - `apps_domains` - A list of global application domains.
    Defaults to a list of one domain, `run.` plus the base domain.

  - `skip_ssl_validation` - Whether or not to enforce validation
    of X.509 certificates received during TLS negotiation.  If you
    have a self-signed certificate, or an untrusted authority, you
    should set this, but be aware that doing so reduces security
    slightly.  This affects the smoke-test errand as well as
    internal Cloud Foundry components.

    Defaults to `false`.

  - `default_app_memory` - How much memory (in megabytes) to
    assign a pushed application that did not specify its memory
    requirements, explicitly.  Defaults to `256`.

  - `default_app_disk_in_mb` - How much disk (in megabytes) to
    assign a pushed application that did not specify its memory
    requirements, explicitly. Defaults to `1000`.

  - `default_stack` - Which Cloud Foundry stack to use by default
    when pushing apps.  The options are currently `cflinuxfs2` and
    `cflinuxfs3`.  Defaults to `cflinuxfs3`

  - `availability_zones` - Which AZs to deploy to. Defaults to 
    `[z1, z2, z3]`

  - `uaa_lockout_failure_count` - Number of failed UAA login attempts
    before lockout.

  - `uaa_lockout_window` - How much time (in seconds) in which
    `uaa_lockout_failure_count` must occur in order for account
    to be locked. Defaults to `1200`.

  - `uaa_lockout_time` - How long (in seconds) the account
    is locked out for violating `uaa_lockout_failure_count` within 
    `uaa_lockout_failure_time_between_failures`. Defaults to `300`.

  - `uaa_refresh_token_validity` - How long (in seconds) a CF refresh
    is valid for. Defaults to `2592000`.

  - `cf_branding_product_logo` - A base64 encoded image to display on
    the web UI login prompt. Defaults to `nil`. Read more in the
    [Branding][2] section.

  - `cf_branding_square_logo` - A base64 encoded image to display
    in areas where a smaller logo is necessary. Defaults to `nil`.
    Read more in the [Branding][2] section.

  - `cf_footer_legal_text` - A string to display in the footer,
    typically used for compliance text. Defaults to `nil`. Read more
    in the [Branding][2] section.

  - `cf_footer_links` - A YAML list of links to enumerate in the footer
    of the web UI. Defaults to `nil`. Read more in the [Branding][2]
    section.

  - `grootfs_reserved_space` - The amount of space (in MB) the garbage
    collection for Garden should keep free for other jobs. GC will
    delete unneeded layers as need to keep this space free. `-1`
    disables GC. Defaults to `15360`.

  - `vm_strategy` - The method used for managing vm rotation.  By default, it
    is `delete-create`, but it can also be set to `create-swap-delete` to
    minimize downtime.

    [2]: (#branding)

## Deployment Parameters

  - `stemcell_os`
  - `stemcell_version`

## Sizing & Scaling Parameters

  - `nats_instances` - How many NATS message bus nodes to deploy.
    Defaults to `2`.

  - `nats_vm_type` - What type of VM to deploy for the nodes in
    the NATS message bus cluster.  Defaults to `nats`. 
    Recommend `1 cpu / 2g mem`.

  - `uaa_instances` - How many UAA nodes to deploy.
    Defaults to `2`.

  - `uaa_vm_type` - What type of VM to deploy for the nodes in
    the UAA cluster.  Defaults to `uaa`. Recommend `2 cpu / 4g mem`.

  - `api_instances` - How many Cloud Controller API nodes to
    deploy.  Defaults to `2`.

  - `api_vm_type` - What type of VM to deploy for the nodes in
    the Cloud Controller API cluster.  Defaults to `api`. 
    Recommend `2 cpu / 4g mem`.

  - `doppler_instance` - How many doppler nodes to deploy.
    Defaults to `2`.

  - `doppler_vm_type` - What type of VM to deploy for the doppler
    nodes.  Defaults to `doppler`. Recommend `1 cpu / 2g mem`.

  - `loggregator_instances` - How many loggregator / traffic
    controller nodes to deploy.  Defaults to `2`.

  - `loggregator_vm_type` - What type of VM to deploy for the
    loggregator traffic controller nodes.  Defaults to `loggregator`. 
    Recommend `2 cpu / 4g mem`.

  - `router_instances` - How many gorouter nodes to deploy.
    Defaults to `2`.

  - `router_vm_type` - What type of VM to deploy for the gorouter
    nodes.  Defaults to `router`. Recommend `1 cpu / 2g mem`.

  - `bbs_instances` - How many Diego BBS nodes to deploy.
    Defaults to `2`.

  - `bbs_vm_type` - What type of VM to deploy for the Diego BBS
    nodes.  Defaults to `bbs`. Recommend `1 cpu / 2g mem`.

  - `diego_instances` - How many Diego auctioneers to deploy.
    Defaults to `2`.

  - `diego_vm_type` - What type of VM to deploy for the Diego
    orchestration nodes (not the cells, the auctioneers).
    Defaults to `diego`. Recommend `2 cpu / 4g mem`.

  - `cell_instances` - How many Diego Cells (runtimes) to deploy.
    Defaults to `3`.

  - `cell_vm_type` - What type of VM to deploy for the Diego Cells
    (application runtime).  These are usually very large machines.
    Defaults to `cell`. Recommend `4 cpu / 16g mem`.

  - `errand_vm_type` - What type of VM to deploy for the
    smoke-tests errand.  Defaults to `errand`. Recommend `1 cpu / 2g mem`.

  - `syslogger_instances` - How many scalable syslog VMs to deploy.

  - `syslogger_vm_type` - What type of VM to deploy for the scalable
    syslog. Defaults to `syslogger`. Recommend `1 cpu / 2g mem`.

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

The following secrets will be pulled from the vault:

  - **Access Key** - The Amazon Access Key ID (and its counterpart
    secret key) for use when dealing with the S3 API.
    It is stored in the vault, at `secret/$env/blobstore`.

### Using an Azure Blobstore

The `azure-blobstore` feature will configure Cloud Foundry to use
Microsoft Azure Cloud's object storage offering.

There are currently no parameters defined for this type of
blobstore.

The following secrets will be pulled from the vault:

  - **Storage Account** - The Storage Account Name and Access Key,
    for use when dealing with the Microsoft Azure API.
    These are stored in the vault, at `secret/$env/blobstore`.

### Using Google Cloud Platform's Blobstore

The `gcp-blobstore` feature will configure Cloud Foundry to use
Google Cloud Platform's object storage offering.

There are currently no parameters defined for this type of
blobstore.

The following secrets will be pulled from the vault:

  - **Service Account** - The Google Cloud Storage service account
    to use when dealing with the GCP API.  Three things are
    stored: the project name, the service account email address,
    and the JSON key (the actual credentials) of the account.
    These are stored in the vault, at `secret/$env/blobstore`.

Note: prior versions of the Cloud Foundry kit leveraged legacy
Amazon-like access-key/secret-key credentials.  It now uses
service accounts because Google limits you to 5 legacy keys per
user account.

## Choosing a Database

Cloud Foundry stores its metadata in a set of relational databases,
either MySQL or PostgreSQL.  These database house things like the
orgs and spaces defined, application instance counts, blobstore
pointers (tying an app to its droplet, for instance) and more.

You have a few options in how these databases are deployed, and
can rely on cloud provider RDBMS offerings when appropriate.

### Using a Local Database

There are two feature options that are available, `local-db`, a
single, non-HA PostgreSQL node, and `local-ha-db`, a dual-node
master/replica HA PostgreSQL that uses a VRRP VIP with HAProxy.

Both features are a mostly hands-off change to the deployment, since
the kit will generate all internal passwords, and automatically wire
up to the new node for database DSNs.

This feature brings the [cloudfoundry-community/postgres][1] BOSH
release into play.

[1]: https://github.com/cloudfoundry-community/postgres-boshrelease

#### Local Postgres (non-HA) DB

The following parameters are defined:

  - `postgres_vm_type` - The VM type (per cloud config) to use
    when deploying the standalone database node.
    Defaults to `postgres`. Recommend `2 cpu / 4g mem`.

  - `postgres_disk_pool` - The disk type (per cloud config) to use
    when provisioning the persistent storage for the database.
    Defaults to `postgres`.

  - `postgres_max_connections` - How many connections the internal
    Postgres DB should maintain at once. Only used if internal
    DB is deployed. Defaults to `100`.

#### Local Postgres (HA) DB

The following parameters are defined:

  - `postgres_vm_type` - The VM type (per cloud config) to use
    when deploying the standalone database node.
    Defaults to `postgres`. Recommend `2 cpu / 4g mem`.

  - `postgres_disk_pool` - The disk type (per cloud config) to use
    when provisioning the persistent storage for the database.
    Defaults to `postgres`.

  - `postgres_max_connections` - How many connections the internal
    Postgres DB should maintain at once. Only used if internal
    DB is deployed. Defaults to `100`.

  - `postgres_vip` - What VRRP VIP to use for the HAProxy/keepalived.
    This field has no default, and must be provided.

### Using an External MySQL / MariaDB Database

The `mysql-db` feature configures Cloud Foundry to connect to a
single, external MySQL or MariaDB database server for all of its
RDBMS needs.

The following parameters are defined:

  - `external_db_host` - The hostname (FQDN) or IP address of the
    database server.  This parameter is **required**.

  - `external_db_port` - The TCP port that MySQL / MariaDB is
    listening on.  Defaults to `3306`, the standard MySQL port.

The following secrets are pulled from the vault:

  - **Database User Credentials** - The username and password for
    accessing the UAA database (`uaadb`), Cloud Controller
    database (`ccdb`), and Diego BBS database (`diegodb`).
    These are stored in the vault at `secret/$env/external_db`.

### Using an External PostgreSQL Database

The `postgres-db` feature configures Cloud Foundry to connect to a
single, external PostgreSQL database server for all of its RDBMS
needs.

The following parameters are defined:

  - `external_db_host` - The hostname (FQDN) or IP address of the
    database server.  This parameter is **required**.

  - `external_db_port` - The TCP port that MySQL / MariaDB is
    listening on.  Defaults to `5432`, the standard Postgres port.

The following secrets are pulled from the vault:

  - **Database User Credentials** - The username and password for
    accessing the UAA database (`uaadb`), Cloud Controller
    database (`ccdb`), and Diego BBS database (`diegodb`).
    These are stored in the vault at `secret/$env/external_db`.


## Routing & TLS

The `haproxy` feature activates a pair of software load balancers,
running haproxy, that sit in front of the Cloud Foundry gorouter
layer.

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


## DNS-Based Service Discovery

If you want your Cloud Foundry applications to be able to find one
another via DNS names (on internal routes), and thereby
communicate directly with one another, without having to first
transit the gorouter (and incur a roundtrip _outside_ the runtime),
you can add the `dns-service-discovery` feature to your
environment file.

This enables BOSH-DNS resolution of names inside of CF application
containers, allowing them to find other BOSH-deployed services in
the `*.bosh` DNS zone, as well as other Cloud Foundry components
in the `*.cf.internal` domain -- you may need to review your
application security groups to ensure that applications are only
allowed to the bits and pieces of Cloud Foundry that you want them
to access.  By default, the ASGs deployed by this kit do _not_
allow such communication.

If you want to change the internal domain used for service
discovery, you may set the `internal_domain` property, which
defaults to "apps.internal".  (Note that there should be **no**
trailing `.`).


## Container Routing Integrity

The `container-routing-integrity` feature enables TLS Validation of the cells.
See [HTTP Routing#With TLS Enabled](https://docs.cloudfoundry.org/concepts/http-routing.html#with-tls)

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


## App Autoscaler

If you wish to dynamically scale your instances based on pre-defined
policies via Cloud Foundry's [App
Autoscaler](https://github.com/cloudfoundry-incubator/app-autoscaler),
you can do so via the `autoscaler` feature. It acts as a service
broker, and must be bound to your organization & space. The following
parameters are configurable:

### BOSH-Related Params

  - `autoscaler_network` - Which network to deploy Autoscaler on.
    Defaults to `cf-autoscaler`.

  - `autoscaler_api_instances` - How many instances to deploy of
    the Autoscaler API server. Defaults to `1`.

  - `autoscaler_api_vm_type` - Which VM type to use for the
    Autoscaler API instance. Defaults to `as-api`. 
    Recommend `1 cpu / 2g mem`.

  - `autoscaler_broker_instances` - How many instances to deploy
    of the Autoscaler service broker. Defaults to `1`.

  - `autoscaler_broker_vm_type` - Which VM type to use for the
    Autoscaler API instance. Defaults to `as-broker`. 
    Recommend `1 cpu / 2g mem`.

  - `autoscaler_scheduler_instances` - How many instances to
    deploy of the Autoscaler scheduler. Defaults to `1`.

  - `autoscaler_scheduler_vm_type` - Which VM type to use for the
    Autoscaler scheduler instance. Defaults to `as-scheduler`. 
    Recommend `1 cpu / 2g mem`.

  - `autoscaler_collector_instances` - How many instances to
    deploy of the Autoscaler metrics collector. Defaults to `1`.

  - `autoscaler_collector_vm_type` - Which VM type to use for the
    Autoscaler MetricsCollector instance. Defaults to
    `as-collector`.  Recommend `1 cpu / 2g mem`.

  - `autoscaler_scaler_instances` - How many instances to deploy
    of the Autoscaler event generator. Defaults to `1`.

  - `autoscaler_scaler_vm_type` - Which VM type to use for the
    Autoscaler event generator instance. Defaults to `as-scaler`.  
    Recommend `1 cpu / 2g mem`.

  - `autoscaler_engine_instances` - How many instances to deploy
    of the Autoscaler scaling engine. Defaults to `1`.

  - `autoscaler_engine_vm_type` - Which VM type to use for the
    Autoscaler scaling engine instance. Defaults to `as-engine`.  
    Recommend `1 cpu / 2g mem`.

### Autoscaler-Related Params

  - `autoscaler_broker_url` - URL to register with the Route
    Register. Defaults to
    `autoscalerservicebroker.$system_domain`.

  - `autoscaler_plans` - A YAML list of plans for the service broker. Defaults to:

    ```
    - id: autoscaler-example-plan-id
      name: autoscaler-example-plan
      description: This is the example service plan.
    ```

### Autoscaler DB

App Autoscaler requires a PostgreSQL server. If you've enabled the
`local-db` or `local-db-ha` feature, Autoscaler automatically uses
that information and sets up the proper tables. No extra
configuration is necessary.

If an external PostgreSQL server is used, you will need to create a
database with the name `autoscaler`. No other configuration is
required, as the feature will grab the necessary db information
previously provided.

If an external MySQL server is used, a local non-HA PostgreSQL DB is
deployed alongside Autoscaler. No extra configuration is necessary.
This DB will only be used to store Autoscaler state information.

### Service Binding

An addon called `bind-autoscaler` is available that will automatically
create the service broker within your CF deployment named
`autoscaler`. An operator will still need to enable access and bind
the service to each app manually. More information about App
Autoscaler can be found on [App Autoscaler's Policy
Documentation](https://git.io/fNt3l)

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
