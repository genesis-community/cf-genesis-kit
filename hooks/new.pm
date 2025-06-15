# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
package Genesis::Hook::New;

use v5.20;
use warnings; # Genesis min perl version is 5.20
use Genesis qw/bail info warning run/;
use Genesis::UI qw/prompt_for/;
# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::New);
use JSON::PP;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->{database} = '';
  $obj->{bucket_prefix} = '';
  $obj->{use_provided_cert} = '';
  $obj->{features} = [];
  $obj->{base_domain} = '';
  $obj->{system_domain} = '';
  $obj->{apps_domain} = '';
  return $obj;
}

sub ask_for_loadbalancer {
  my ($self, $lb_name) = @_;
  $lb_name //= "external Load Balancer";

  my $load_balancer = prompt_for(
    "select",
    "What load balancer would you like to use in front of this Cloud Foundry?",
    -o => "[external] An existing $lb_name",
    -o => '[haproxy] An internal HAProxy Load Balancer',
    --default => 'external'
  );

  if ($load_balancer eq 'external') {
    return;
  }

  push @{$self->{features}}, "haproxy", "tls";

  my $cert = prompt_for(
    "select",
    'Cloud Foundry requires a TLS certificate to support HTTPS traffic.',
    -o => '[provide]  I have a signed X.509 certificate for Cloud Foundry',
    -o => '[generate] Please generate a new, self-signed certificate for Cloud Foundry'
  );

  if ($cert eq "provide") {
    $self->{use_provided_cert} = 'yes';

    my $ok = 0;
    while (!$ok) {
      prompt_for(
        "haproxy/ssl:certificate",
        "secret-block",
        'Please provide the X.509 Certificate (and CA chain, if any), in PEM format'
      );

      prompt_for(
        "haproxy/ssl:key",
        "secret-block",
        'Please provide the private key for that certificate'
      );

      my ($out, $rc) = run('safe x509 validate "${GENESIS_SECRETS_BASE}haproxy/ssl"');
      if ($rc) {
        warning("Certificate validation failed: $out");
        next;
      }

      ($out) = run('safe x509 show "${GENESIS_SECRETS_BASE}haproxy/ssl"');

      $ok = prompt_for("boolean", 'Is this the correct certificate?');
      last if $ok eq 'true';
    }
    print "\n";

    my ($out, $rc) = run(q{
      credhub "set" -n "${GENESIS_CREDHUB_ROOT}/haproxy_ssl" -t certificate -r /dev/null \
      -c <(safe read "${GENESIS_SECRETS_BASE}haproxy/ssl:certificate" | sed -e '/^$/d') \
      -p <(safe read "${GENESIS_SECRETS_BASE}haproxy/ssl:key" | sed -e '/^$/d')
      });

    bail("#R{[ERROR]} Could not write to credhub: $out") if $rc;

    run('safe rm "${GENESIS_SECRETS_BASE}haproxy/ssl"');
  } else {
    push @{$self->{features}}, 'self-signed';
  }
}

# Move a secret from Vault to Credhub
# This function reads a secret from Vault, stores it in Credhub, and removes it from Vault
# Matching the behavior of the original bash script
sub move_secrets_to_credhub {
  my ($self, $vault_path, $credhub_key) = @_;

  # First, read the secret from Vault
  my ($secret_value, $rc_read) = run(qq{safe read "${ENV{GENESIS_SECRETS_BASE}}$vault_path"});
  bail("Failed to read secret from vault: $secret_value") if $rc_read;

  # Store it in Credhub
  my ($out, $rc) = run(qq{
    credhub set -n "/${ENV{GENESIS_CREDHUB_ROOT}}/$credhub_key" -t value -v "$secret_value"
    });

  bail("Failed to move secret from vault to credhub: $out") if $rc;

  # Remove it from Vault
  my ($rm_out, $rm_rc) = run(qq{safe rm "${ENV{GENESIS_SECRETS_BASE}}$vault_path"});
  warning("Failed to remove secret from vault after moving to credhub: $rm_out") if $rm_rc;
}

sub ask_for_database {
  my ($self, $db_type) = @_;

  my $inst = "database";
  my @options;

  if (defined $db_type && $db_type eq 'rds') {
    @options = (
      -o => '[postgres-db]       PostgreSQL Amazon RDS',
      -o => '[mysql-db]          MySQL Amazon RDS',
      -o => '[local-postgres-db] an internal PostgreSQL database node',
      -o => '[local-mysql-db]    internal MySQL database node'
    );
  } elsif (defined $db_type && $db_type eq 'gcp') {
    @options = (
      -o => '[postgres-db]       PostgreSQL Google Cloud SQL',
      -o => '[mysql-db]          MySQL Google Cloud SQL',
      -o => '[local-postgres-db] an internal PostgreSQL database node',
      -o => '[local-mysql-db]    internal MySQL database node'
    );
  } else {
    @options = (
      -o => '[postgres-db]       Existing external PostgreSQL Database',
      -o => '[mysql-db]          Existing external MySQL Database',
      -o => '[local-postgres-db] Internal PostgreSQL database node',
      -o => '[local-mysql-db]    Internal MySQL database node'
    );
  }

  $self->{database} = prompt_for(
    "select",
    'Where would you like to house Cloud Foundry configuration and metadata?',
    @options
  );

  if ($self->{database} eq 'postgres-db') {
    if (defined $db_type && $db_type eq 'rds') {
      $inst = "Amazon RDS PostgreSQL instance";
    } elsif (defined $db_type && $db_type eq 'gcp') {
      $inst = "Google Cloud SQL PostgreSQL instance";
    } else {
      $inst = "external PostgreSQL instance";
    }
  } elsif ($self->{database} eq 'mysql-db') {
    if (defined $db_type && $db_type eq 'rds') {
      $inst = "Amazon RDS MySQL instance";
    } elsif (defined $db_type && $db_type eq 'gcp') {
      $inst = "Google Cloud SQL MySQL instance";
    } else {
      $inst = "external MySQL instance";
    }
  }

  if ($self->{database} eq 'mysql-db' || $self->{database} eq 'postgres-db') {
    my $db_host = prompt_for("line", "What is the hostname or IP of your $inst?");
    my $db_user = prompt_for("line", "What is your $inst database username?");

    run(qq{credhub set -n "/$ENV{GENESIS_CREDHUB_ROOT}/external_db_user" -t value -v "$db_user"});

    prompt_for(
      "external_db:password",
      "secret-line",
      "What is the password for the $inst $db_user user?"
    );

    $self->move_secrets_to_credhub("external_db:password", "external_db_password");
    $self->{db_host} = $db_host;
    $self->{db_user} = $db_user;
  }

  push @{$self->{features}}, $self->{database};
}

# Get Cloud Foundry version from cf-deployment manifest
# This extracts the manifest_version field from the cf-deployment.yml file
sub get_cf_version {
  my ($self) = @_;

  # Using the same command as the bash script for consistent behavior
  my ($out) = run('spruce json cf-deployment/cf-deployment.yml | jq -r \'.manifest_version\'');

  # Strip any trailing whitespace
  chomp($out);
  return $out;
}

sub perform {
  my ($self) = @_;
  my $cfversion = $self->get_cf_version();

  info(
    "",
    "#Gku{Cloud Foundry Genesis Kit $ENV{GENESIS_KIT_VERSION}}",
    "",
    "This kit is based on #c{cf-deployment $cfversion}, but contains best-practice",
    "enhancements derived from the v1.x version of the kit."
  );

  # Get domain info
  my $ok = 'false';
  while ($ok ne 'true') {
    info(
      "",
      "Your Cloud Foundry instance needs a base domain, from which all the",
      "other endpoint URLs and domains will be fashioned."
    );

    $self->{base_domain} = prompt_for("line", "What is the base domain of your Cloud Foundry?");

    my $default_system = "system.$self->{base_domain}";
    $self->{system_domain} = prompt_for(
      "line",
      "What is the system domain of your Cloud Foundry? (press enter for default: system.{base_domain})",
      --default => $default_system
    );

    my $default_apps = "run.$self->{base_domain}";
    $self->{apps_domain} = prompt_for(
      "line",
      "What is the apps domain of your Cloud Foundry? (press enter for default: run.{base_domain})",
      --default => $default_apps
    );

    # Fix for the logic error in the bash version where system_domain and apps_domain
    # could remain empty - properly set defaults if empty strings are provided
    if ($self->{system_domain} eq "") {
      $self->{system_domain} = "system.$self->{base_domain}";
    }

    if ($self->{apps_domain} eq "") {
      $self->{apps_domain} = "run.$self->{base_domain}";
    }

    info(
      "",
      "Using the base domain of #C{$self->{base_domain}},",
      "you will get the following domains and endpoints:",
      "",
      "    apps: https://#yi{<APP-NAME>}.#C{$self->{apps_domain}}",
      "  cf api: https://#M{api}.#C{$self->{system_domain}}",
     info"     uaa: https://#M{uaa}.#C{$self->{system_domain}}",
      "          https://#M{login}.#C{$self->{system_domain}}",
    );

    $ok = prompt_for("boolean", "Is this acceptable [y|n]?", --default => "y");
  }

  # Feature selection
  info(
    "",
    "This new environment can be configured as a bare cf-deployment deployment with",
    "just enough modifications to allow it to work with Genesis, or it can be",
    "configured with enhanced best-practice features that were present in the",
    "v1.x kit versions."
  );

  my $use_bare = prompt_for(
    "boolean",
    "Would you like to use the enhanced Genesis kit features [y|n]?",
    --invert => 1,
    --default => "y"
  );

  if ($use_bare eq 'true') {
    push @{$self->{features}}, 'bare';

    my $network_topography = prompt_for(
      "select",
      "What network topography would you like to use?",
      -o => "[] Single 'default' network",
      -o => "[partitioned-network] Partitioned network that separates core, edge and runtime vms",
      --default => "partitioned-network"
    );

    push @{$self->{features}}, $network_topography if $network_topography;

    my $load_balancer = prompt_for(
      "select",
      'What load balancer would you like to use in front of this Cloud Foundry?',
      -o => "[external] An existing external Load Balancer",
      -o => '[haproxy] An internal HAProxy Load Balancer',
      --default => 'external'
    );

    if ($load_balancer eq 'haproxy') {
      push @{$self->{features}}, "cf-deployment/operations/use-haproxy";
    }
  } else {
    # IaaS selection
    info("", "#gu{Iaas Selection}");
    my $iaas = prompt_for(
      "select",
      'What IaaS are you deploying to?',
      -o => '[aws]       Amazon Web Services',
      -o => '[azure]     Microsoft Azure',
      -o => '[google]    Google Cloud Platform',
      -o => '[stackit]   STACKIT Cloud Platform',
      -o => '[other]     Other (OpenStack, vSphere, etc.)'
    );

    if ($iaas eq 'azure') {
      $self->ask_for_loadbalancer("Azure Load Balancer");
      $self->ask_for_database();

      info("#gu{Blobstore}");
      my $use_azure_storage = prompt_for(
        "boolean",
        'Would you like to use Azure Storage to store droplets and application bits?'
      );

      if ($use_azure_storage eq 'true') {
        push @{$self->{features}}, 'azure-blobstore';

        prompt_for(
          "$ENV{GENESIS_SECRETS_BASE}blobstore:storage_account_name",
          "secret-line",
          'What is your Azure Storage Account Name?'
        );

        prompt_for(
          "$ENV{GENESIS_SECRETS_BASE}blobstore:storage_access_key",
          "secret-line",
          'What is your Azure Storage Account Key?'
        );

        $self->move_secrets_to_credhub(
          "blobstore:storage_account_name",
          "blobstore_storage_account_name"
        );

        $self->move_secrets_to_credhub(
          "blobstore:storage_access_key",
          "blobstore_storage_access_key"
        );
      }
    } elsif ($iaas eq 'aws') {
      $self->ask_for_loadbalancer("Elastic Load Balancer");
      $self->ask_for_database('rds');

      my $use_aws_stuff = prompt_for(
        "boolean",
        'Would you like to use Amazon S3 to store droplets and application bits?'
      );

      if ($use_aws_stuff eq 'true') {
        push @{$self->{features}}, 'aws-blobstore';

        prompt_for(
          "blobstore:aws_access_key",
          "secret-line",
          'What is your Amazon S3 Access Key ID?'
        );

        prompt_for(
          "blobstore:aws_access_secret",
          "secret-line",
          'What is your Amazon S3 Secret Access Key?'
        );

        $self->{aws_blobstore_region} = prompt_for(
          "line",
          'What region contains the your Amazon S3 blobstore?'
        );

        $self->move_secrets_to_credhub(
          "blobstore:aws_access_key",
          "blobstore_access_key_id"
        );

        $self->move_secrets_to_credhub(
          "blobstore:aws_access_secret",
          "blobstore_secret_access_key"
        );

        # Generate bucket prefix from environment name
        # Following exact transformation from the bash script:
        # 1. Convert to lowercase
        # 2. Convert periods and underscores to hyphens
        # 3. Remove characters that aren't alphanumeric, periods, or hyphens
        my $env_name = lc($ENV{GENESIS_ENVIRONMENT});
        $env_name =~ tr/./_/--; # Convert periods and underscores to hyphens
        $env_name =~ s/[^a-z0-9\.-]//g;

        $self->{bucket_prefix} = ($env_name eq lc($ENV{GENESIS_ENVIRONMENT})) ? '' : $env_name;
      }
    } elsif ($iaas eq 'google') {
      $self->ask_for_loadbalancer("Google Cloud Load Balancer");
      $self->ask_for_database('gcp');

      my $use_gcp_blobstore = prompt_for(
        "select",
        'What would you like to use to store droplets, buildpacks and application bits?',
        -o => '[gcp] Existing Google Cloud Storage accessed via project and json key',
        -o => '[gcpaccess] Existing Google Cloud Storage accessed via access and secret keys',
        -o => '[builtin] Local singleton blobstore that will be deployed in this deployment',
        --default => 'gcp'
      );

      if ($use_gcp_blobstore eq 'gcp') {
        push @{$self->{features}}, 'gcp-blobstore';

        prompt_for(
          "blobstore:gcp_project_name",
          "secret-line",
          'What is your Google Cloud Project Name?'
        );

        prompt_for(
          "blobstore:gcp_client_email",
          "secret-line",
          'What is the Cloud Storage Service Account ID (@<project>.iam.gserviceaccount.com)?'
        );

        prompt_for(
          "blobstore:gcp_json_key",
          "secret-block",
          'What is the Cloud Storage Service Account (JSON) Key?'
        );

        $self->move_secrets_to_credhub(
          "blobstore:gcp_project_name",
          "gcs_project"
        );

        $self->move_secrets_to_credhub(
          "blobstore:gcp_client_email",
          "gcs_service_account_email"
        );

        $self->move_secrets_to_credhub(
          "blobstore:gcp_json_key",
          "gcs_service_account_json_key"
        );
      } elsif ($use_gcp_blobstore eq 'gcpaccess') {
        push @{$self->{features}}, 'gcp-blobstore', 'gcp-use-access-key';

        prompt_for(
          "blobstore:gcp_access_key",
          "secret-line",
          'What is your Google Cloud Storage access key?'
        );

        prompt_for(
          "blobstore:gcp_secret_key",
          "secret-line",
          'What is your Google Cloud Storage secret access key?'
        );

        $self->move_secrets_to_credhub(
          "blobstore:gcp_access_key",
          "blobstore_access_key_id"
        );

        $self->move_secrets_to_credhub(
          "blobstore:gcp_secret_key",
          "blobstore_secret_access_key"
        );
      }
    } elsif ($iaas eq 'stackit') {
      $self->ask_for_loadbalancer("Stackit Load Balancer");
      $self->ask_for_database();

      # Use internal blobstore by default for Stackit
      push @{$self->{features}}, 'internal-blobstore';

      # Generate bucket prefix from environment name
      # Following exact transformation from the bash script:
      # 1. Convert to lowercase
      # 2. Convert periods and underscores to hyphens
      # 3. Remove characters that aren't alphanumeric, periods, or hyphens
      my $env_name = lc($ENV{GENESIS_ENVIRONMENT});
      $env_name =~ tr/./_/--; # Convert periods and underscores to hyphens
      $env_name =~ s/[^a-z0-9\.-]//g;

      $self->{bucket_prefix} = ($env_name eq lc($ENV{GENESIS_ENVIRONMENT})) ? '' : $env_name;
    } else {
      $self->ask_for_loadbalancer();
      $self->ask_for_database();
    }

    # Extra features
    info("", "#gu{Extra Features}");

    my $compiled_releases = prompt_for(
      "boolean",
      'Would you like to use pre-compiled releases [y|n]?',
      --default => 'n'
    );

    push @{$self->{features}}, 'compiled-releases' if $compiled_releases eq 'true';

    my $small_footprint = prompt_for(
      "boolean",
      'Would you like to use a small footprint (minimal VMs on one AZ) [y|n]?',
      --default => 'n'
    );

    push @{$self->{features}}, 'small-footprint' if $small_footprint eq 'true';

    my $use_nsf = prompt_for(
      "boolean",
      'Would you like to enable NFS Volume Services [y|n]?',
      --default => 'n'
    );

    push @{$self->{features}}, 'nfs-volume-services' if $use_nsf eq 'true';

    my $service_discovery = prompt_for(
      "boolean",
      'Would you like to enable service discovery [y|n]?',
      --default => 'y'
    );

    push @{$self->{features}}, 'enable-service-discovery' if $service_discovery eq 'true';

    my $use_autoscaler = prompt_for(
      "boolean",
      'Would you like to set up integration for the CF App Autocaler Genesis Kit [y|n]?'
    );

    push @{$self->{features}}, 'app-autoscaler-integration' if $use_autoscaler eq 'true';

    my $use_prometheus = prompt_for(
      "boolean",
      'Would you like to set up integration for the Prometheus Genesis Kit [y|n]?'
    );

    push @{$self->{features}}, 'prometheus-integration' if $use_prometheus eq 'true';
  }

  info(
    "",
    "Further cf-deployment operations can be added as features manually. Just",
    "specify them as #m{cf-deployment/operations/<subpath-to-ops-file-without-.yml>}",
    "in the #c{features} list -- they will be applied in the order that they appear."
  );

  # Generate the environment YAML
  $self->generate_env_file();

  return $self->done();
}

# Generate the environment YAML file with all settings
# This creates the environment configuration file with all the options selected during the hook execution
sub generate_env_file {
  my ($self) = @_;
  my $env_file = "$ENV{GENESIS_ROOT}/$ENV{GENESIS_ENVIRONMENT}.yml";

  # Open file for writing
  open my $fh, '>', $env_file or bail("Could not open $env_file for writing: $!");

  # Write basic kit information
  print $fh "---\n";
  print $fh "kit:\n";
  print $fh "  name:    $ENV{GENESIS_KIT_NAME}\n";
  print $fh "  version: $ENV{GENESIS_KIT_VERSION}\n";

  # Write selected features
  if (@{$self->{features}}) {
    print $fh "  features:\n";
    foreach my $feature (@{$self->{features}}) {
      print $fh "    - $feature\n";
    }
  }

  # Include Genesis config block (provided by Genesis)
  my ($out) = run('genesis_config_block');
  print $fh $out;

  # Write domain configuration
  print $fh "params:\n";
  print $fh "  # Cloud Foundry base domain\n";
  print $fh "  base_domain: $self->{base_domain}\n";
  print $fh "  system_domain: $self->{system_domain}\n";
  print $fh "  apps_domains:\n";
  print $fh "  - $self->{apps_domain}\n";

  # Write database configuration if using external database
  if ($self->{database} eq 'mysql-db') {
    print $fh "\n";
    print $fh "  # External MySQL configuration\n";
    print $fh "  external_db_host: $self->{db_host}\n";
  } elsif ($self->{database} eq 'postgres-db') {
    print $fh "\n";
    print $fh "  # External PostgreSQL configuration\n";
    print $fh "  external_db_host: $self->{db_host}\n";
  }

  # Write blobstore configuration
  if ($self->{aws_blobstore_region}) {
    print $fh "  blobstore_s3_region: $self->{aws_blobstore_region}\n";
  }

  if ($self->{bucket_prefix}) {
    print $fh "  blobstore_bucket_prefix: $self->{bucket_prefix}\n";
  }

  # Set SSL validation settings
  if (!$self->{use_provided_cert}) {
    print $fh "  # Skip SSL validation since we use self-signed certs\n";
    print $fh "  skip_ssl_validation: true\n";
  }

  close $fh;

  # Offer environment editor to the user
  run('offer_environment_editor');

  return 1;
}

1;
