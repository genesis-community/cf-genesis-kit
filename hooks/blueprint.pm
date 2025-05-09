#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::CF::Blueprint v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

use parent qw(Genesis::Hook::Blueprint);

use Genesis qw/bail bug trace new_enough semver run want_feature lookup lines count_nouns
deep_merge compare_arrays is_valid_uri bosh_cpi in_callback/;
use JSON::PP;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);

  # Initialize all state variables needed by the hook
  $obj->{manifests} = [];
  $obj->{features} = [];
  $obj->{opsfiles} = [];
  $obj->{blobstores} = [];
  $obj->{databases} = [];
  $obj->{abort} = 0;
  $obj->{warn} = 0;
  $obj->{db_specified} = 0;
  $obj->{params} = $obj->env->lookup("params", "{}");

  # Set up IaaS related variables
  $obj->{cpi} = bosh_cpi() || "";
  $obj->{iaas} = $obj->{cpi};
  $obj->{iaas} = "gcp" if $obj->{iaas} eq "google";

  # Set up operations directory
  $obj->{opsdir} = "ops";
  if ($ENV{PREVIOUS_ENV}) {
    $obj->{opsdir} = ".genesis/cached/$ENV{PREVIOUS_ENV}/ops";
  }

  return $obj;
}

# Utility methods to replace bash functions
sub warn_message {
  my ($self, $message) = @_;
  $self->{warn} = 1;
  Genesis::warning({stderr => 1}, "#Y{[WARNING]} %s", $message);
  return;
}

sub abort_message {
  my ($self, $message) = @_;
  $self->{abort} = 1;
  Genesis::error({stderr => 1}, "#R{[ERROR]} %s", $message);
  return;
}

sub switch_cf_version {
  my ($self, $version) = @_;

  Genesis::describe({stderr => 1}, "",
    "- #y{Experimental Feature Enabled:} Custom cf-deployment version: $version");

  my $genesis_root = $self->env->path;
  my $cfd_file = "$genesis_root/.genesis/kits/addons/cf-deployment-${version}.tar.gz";
  my $cfd_url = "https://github.com/cloudfoundry/cf-deployment/archive/v${version}.tar.gz";

  if (! -s $cfd_file) {
    Genesis::describe({stderr => 1},
      "  #i{Fetching cf-deployment-${version} release from cloudfoundry/cf-deployment}",
      "  #i{on github.com}");

    # Ensure directory exists
    system("mkdir -p \"$genesis_root/.genesis/kits/addons/\"");

    # Download the file
    my $curl_cmd = "curl -sSL -o \"$cfd_file\" \"$cfd_url\" > /dev/null";
    system($curl_cmd);

    if (! -s $cfd_file) {
      bail("Failed to download cf-deployment v${version} -- cannot continue");
    }

    # Check if it's a valid release
    my @tar_output = `tar -ztf "$cfd_file" | awk '{print \$NF}' | cut -d'/' -f1 | uniq`;
    my $topdir = $tar_output[0];
    chomp $topdir;

    if ($topdir ne "cf-deployment-${version}") {
      bail("Downloaded cf-deployment v${version} doesn't look like a valid release -- cannot continue");
    }
  } else {
    Genesis::describe({stderr => 1}, "  #i{Using cached copy of cf-deployment-${version} release}");
  }

  # Extract the tar file
  system("rm -rf \"./cf-deployment\"");
  system("mkdir \"./cf-deployment\"");
  system("tar -xz -C \"./cf-deployment/\" --strip-components 1 -f \"$cfd_file\" > /dev/null");

  print STDERR "\n";
  return;
}

# Go-Patch methods
sub gopatch_replace {
  my ($self, $path, $value) = @_;
  return "  - type: replace\n    path: ${path}\n    value: ${value}\n";
}

sub gopatch_remove {
  my ($self, $path) = @_;
  return "  - type: remove\n    path: ${path}\n";
}

# Dynamic Isolation Segments methods
sub dynamic_isolation_segments {
  my ($self, $params_json) = @_;
  my @isolation_files = ();

  # Parse JSON params
  my $params = ref($params_json) eq 'HASH' ? $params_json : eval { decode_json($params_json) };
  unless ($params) {
    bail("Failed to parse params: $@");
    return ();
  }

  my @isolation_groups = ();
  my @iso_seg_merges = ();

  # Extract isolation segment names from params
  if (exists $params->{isolation_segments} && ref($params->{isolation_segments}) eq 'ARRAY') {
    foreach my $segment (@{$params->{isolation_segments}}) {
      if (exists $segment->{name}) {
        push @isolation_groups, $segment->{name};
      }
    }
  } else {
    return ();
  }

  # Determine which isolation segment merges to include
  if (!(want_feature("bare")) || want_feature("partitioned-network")) {
    push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-network.yml";
  }

  if (want_feature("cflinuxfs3")) {
    push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-cflinuxfs3.yml";
  }

  if (want_feature("nfs-volume-services")) {
    push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs.yml";

    if (want_feature("nfs-ldap") || want_feature("nfs-ldap-tls")) {
      push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs-ldap.yml";

      if (want_feature("nfs-ldap-tls")) {
        push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs-ldap-tls.yml";
      }

      if (want_feature("ocfp")) {
        push @iso_seg_merges, (
          "overlay/dynamic-templates/isolation-segment-nfs-ldap-ocfp.yml",
          "ocfp/nfs-ldap-data.yml"
        );
      }
    }
  }

  if (want_feature("smb-volume-services")) {
    push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-smb.yml";
  }

  if (want_feature("ocfp")) {
    push @iso_seg_merges, "ocfp/meta.yml";
    if (want_feature("trust-blacksmith-ca")) {
      push @iso_seg_merges, "ocfp/trust-blacksmith-ca.yml";
    }
  }

  # Process each isolation group
  foreach my $group (@isolation_groups) {
    my $additional_trusted_certs = '';

    # Check if we need additional trusted certs
    if (want_feature("ocfp") ||
      system("echo '$params_json' | jq -e --arg v \"$group\" '.isolation_segments[] | select( .name == \$v ) | .additional_trusted_certs//[] | length > 0' >/dev/null 2>&1") == 0) {

      $additional_trusted_certs = $self->dynamic_isolation_template_render("additional-trusted-certs", $group);

      if (want_feature("cflinuxfs3")) {
        $additional_trusted_certs .= " " . $self->dynamic_isolation_template_render("additional-trusted-certs-cflinuxfs3", $group);
      }

      if (want_feature("ocfp")) {
        $additional_trusted_certs .= " " . $self->dynamic_isolation_template_render("ocfp-trusted-certs", $group);
      }
    }

    my $dynamic_segment_fragment_file = "overlay/dynamic/isolation-segments-$group.yml";

    # Prepare the command to generate the segment fragment
    my $cmd = "spruce merge -m --prune meta";
    $cmd .= " \"overlay/dynamic-templates/isolation-segment.yml\"";

    foreach my $merge_file (@iso_seg_merges) {
      $cmd .= " \"$merge_file\"";
    }

    if ($additional_trusted_certs) {
      $cmd .= " $additional_trusted_certs";
    }

    # Replace the (( with (( defer in the params
    my $segment_json = `echo '$params_json' | sed -e 's#"(( *#"(( defer #g' | jq --arg v "$group" '.isolation_segments[] | select(.name == \$v ) | {"meta": }'`;
    my $append_json = '{"instance_groups": [ "((prepend))", "((defer append))" ]}';

    # Create temporary files for JSON input
    my $segment_json_file = $self->env->workpath("segment_$group.json");
    my $append_json_file = $self->env->workpath("append_$group.json");

    open my $fh, '>', $segment_json_file or bail("Cannot write to $segment_json_file: $!");
    print $fh $segment_json;
    close $fh;

    open $fh, '>', $append_json_file or bail("Cannot write to $append_json_file: $!");
    print $fh $append_json;
    close $fh;

    $cmd .= " \"$segment_json_file\" \"$append_json_file\" > \"$dynamic_segment_fragment_file\"";

    system($cmd);

    # Add the fragment file to our list
    push @isolation_files, $dynamic_segment_fragment_file;

    # Render additional templates
    $self->dynamic_isolation_template_render("dns-sd", $group);

    if (want_feature("nfs-volume-services") && want_feature("ocfp")) {
      $self->dynamic_isolation_template_render("nfs-ldap-config", $group);
    }

    # Clean up temp files
    unlink $segment_json_file;
    unlink $append_json_file;
  }

  return @isolation_files;
}

sub dynamic_isolation_template_render {
  my ($self, $tmpl, $name) = @_;

  my $srcdir = 'overlay/dynamic-templates';
  my $dstdir = 'overlay/dynamic';
  my $src = "$srcdir/isolation-segment-${tmpl}.yml";
  my $dst = "$dstdir/isolation-segment-${name}-${tmpl}.yml";

  # Make sure the destination directory exists
  system("mkdir -p \"$dstdir\"");

  # Render the template
  system("sed -e 's/{{segment-name}}/$name/g' < \"$src\" > \"$dst\"");

  return $dst;
}

# Dynamic Instance VM Types
sub dynamic_instance_vm_types {
  my ($self) = @_;
  my $params_ref = ref($self->{params}) eq 'HASH' ? $self->{params} : decode_json($self->{params});

  # Extract instance types from params
  my @instance_types = ();
  foreach my $key (keys %$params_ref) {
    if ($key =~ /^(.*)_vm_type$/) {
      push @instance_types, [$1, $params_ref->{$key}];
    }
  }

  if (@instance_types) {
    my $used = '';
    my $types_op_file = "operations/dynamic/instance_types.yml";

    # Create directory if it doesn't exist
    system("mkdir -p operations/dynamic");

    # Start the op file
    open my $fh, '>', $types_op_file or bail("Cannot write to $types_op_file: $!");
    print $fh "--- # Dynamically created instance type overrides\n";

    foreach my $pair (@instance_types) {
      my ($inst_grp, $type) = @$pair;

      # Handle special cases
      if ($inst_grp eq 'errand' || $inst_grp eq 'haproxy') {
        next; # dealt with elsewhere
      } elsif ($inst_grp eq 'cell') {
        $inst_grp = "diego_cell";
        $self->warn_message("Translated: params.cell_vm_type => params.diego_cell_vm_type");
      } elsif ($inst_grp eq 'diego') {
        $inst_grp = "scheduler";
        $self->warn_message("Translated: params.diego_vm_type => params.scheduler_vm_type");
      } elsif ($inst_grp eq 'bbs') {
        $inst_grp = "diego_api";
        $self->warn_message("Translated: params.bbs_vm_type => params.diego_api_vm_type");
      } elsif ($inst_grp eq 'loggregator') {
        $inst_grp = "log_api";
        $self->warn_message("Translated: params.loggregator_vm_type => params.log_api_vm_type");
      } elsif ($inst_grp eq 'postgres') {
        $inst_grp = "database";
        $self->warn_message("Translated: params.postgres_vm_type => params.database_vm_type");
      } elsif ($inst_grp eq 'blobstore') {
        $inst_grp = "singleton-blobstore";
        $self->warn_message("Translated: params.blobstore_vm_type => params.singleton_blobstore_vm_type");
      } elsif ($inst_grp eq 'windows_diego_cell') {
        $inst_grp = "windows2019-cell";
        $self->warn_message("Translated: params.windows_diego_cell_vm_type => params.windows2019-cell_vm_type");
      }

      # Convert underscores to dashes
      my $dashed_inst_grp = $inst_grp;
      $dashed_inst_grp =~ s/_/-/g;

      # Validate instance group
      if ($dashed_inst_grp !~ /^(api|cc-worker|credhub|database|diego-(api|cell)|doppler|errand|haproxy|windows2019-cell|log-(api|cache)|nats|rotate-cc-database-key|(tcp-)?router|scheduler|singleton-blobstore|smoke-tests|uaa)$/) {
        $inst_grp = $dashed_inst_grp;
        $self->warn_message("Unknown instance group $inst_grp - this may be bug in your environment files.\n\tExpected instance groups are:\n\tapi, cc-worker, credhub, database, diego-api, diego-cell, doppler, errand,\n\thaproxy, log-api, log-cache, nats, rotate-cc-database-key, router, scheduler,\n\tsingleton-blobstore, smoke-tests, tcp-router, uaa, and windows2019-cell\n");
      }

      # Add the vm_type override to the op file
      print $fh $self->gopatch_replace("/instance_groups/name=$dashed_inst_grp/vm_type", $type);

      $used .= "$dashed_inst_grp\n";
    }

    # Handle errand vm_type
    my $errand_vm_type = $params_ref->{errand_vm_type} || "";
    if ($errand_vm_type) {
      foreach my $errand_name (qw(smoke-tests rotate-cc-database-key)) {
        if ($used !~ /^$errand_name$/m) {
          print $fh $self->gopatch_replace("/instance_groups/name=$errand_name/vm_type", $errand_vm_type);
          $used .= "$errand_name\n";
        }
      }
    }

    close $fh;

    # Check for duplicates
    my %seen = ();
    my @dups = ();
    foreach my $line (split /\n/, $used) {
      next unless $line;
      push @dups, $line if $seen{$line}++;
    }

    if (@dups) {
      bail("Instance vm types specified (or translated as) multiple times: " . join(", ", @dups));
    }

    push @{$self->{manifests}}, $types_op_file;
  }
}

# Dynamic Instance Counts
sub dynamic_instance_counts {
  my ($self) = @_;
  my $params_ref = ref($self->{params}) eq 'HASH' ? $self->{params} : decode_json($self->{params});

  # Extract instance counts from params
  my @instance_counts = ();
  foreach my $key (keys %$params_ref) {
    if ($key =~ /^(.*)_instances$/) {
      push @instance_counts, [$1, $params_ref->{$key}];
    }
  }

  if (@instance_counts) {
    my $used = '';
    my $counts_opsfile = "operations/dynamic/instance_counts.yml";

    # Create directory if it doesn't exist
    system("mkdir -p operations/dynamic");

    # Start the op file
    open my $fh, '>', $counts_opsfile or bail("Cannot write to $counts_opsfile: $!");
    print $fh "--- # Dynamically created instance counts\n";

    foreach my $pair (@instance_counts) {
      my ($inst_grp, $count) = @$pair;

      # Handle special cases
      if ($inst_grp eq 'errand' || $inst_grp eq 'haproxy') {
        next; # dealt with elsewhere
      } elsif ($inst_grp eq 'cell') {
        $inst_grp = "diego_cell";
        $self->warn_message("Translated: params.cell_instances => params.diego_cell_instances");
      } elsif ($inst_grp eq 'diego') {
        $inst_grp = "scheduler";
        $self->warn_message("Translated: params.diego_instances => params.scheduler_instances");
      } elsif ($inst_grp eq 'bbs') {
        $inst_grp = "diego_api";
        $self->warn_message("Translated: params.bbs_instances => params.diego_api_instances");
      } elsif ($inst_grp eq 'loggregator') {
        $inst_grp = "log_api";
        $self->warn_message("Translated: params.loggregator_instances => params.log_api_instances");
      } elsif ($inst_grp eq 'postgres') {
        $inst_grp = "database";
        $self->warn_message("Translated: params.postgres_instances => params.database_instances");
      } elsif ($inst_grp eq 'blobstore') {
        $inst_grp = "singleton-blobstore";
        $self->warn_message("Translated: params.blobstore_instances => params.singleton_blobstore_instances");
      } elsif ($inst_grp eq 'windows_diego_cell') {
        $inst_grp = "windows2019-cell";
        $self->warn_message("Translated: params.windows_diego_cell_instances => params.windows2019-cell_instances");
      }

      # Convert underscores to dashes
      my $dashed_inst_grp = $inst_grp;
      $dashed_inst_grp =~ s/_/-/g;

      # Validate instance group
      if ($dashed_inst_grp !~ /^(api|cc-worker|credhub|database|diego-(api|cell)|doppler|errand|haproxy|log-(api|cache)|nats|windows2019-cell|rotate-cc-database-key|(tcp-)?router|scheduler|singleton-blobstore|smoke-tests|uaa)$/) {
        $inst_grp = $dashed_inst_grp;
        $self->warn_message("Unknown instance group $inst_grp - this may be bug in your environment files.\n\tExpected instance groups are:\n\tapi, cc-worker, credhub, database, diego-api, diego-cell, doppler, errand,\n\thaproxy, log-api, log-cache, nats, rotate-cc-database-key, router, scheduler,\n\tsingleton-blobstore, smoke-tests, tcp-router, uaa, and windows2019-cell");
      }

      # Add the instances override to the op file
      print $fh $self->gopatch_replace("/instance_groups/name=$dashed_inst_grp?/instances", $count);

      $used .= "$dashed_inst_grp\n";
    }

    # Handle errand instances
    my $errand_instances = $params_ref->{errand_instances} || "";
    if ($errand_instances) {
      foreach my $errand_name (qw(smoke-tests rotate-cc-database-key)) {
        if ($used !~ /^$errand_name$/m) {
          print $fh $self->gopatch_replace("/instance_groups/name=$errand_name?/instances", $errand_instances);
          $used .= "$errand_name\n";
        }
      }
    }

    close $fh;

    # Check for duplicates
    my %seen = ();
    my @dups = ();
    foreach my $line (split /\n/, $used) {
      next unless $line;
      push @dups, $line if $seen{$line}++;
    }

    if (@dups) {
      bail("Instance counts specified (or translated as) multiple times: " . join(", ", @dups));
    }

    push @{$self->{manifests}}, $counts_opsfile;
  }
}

# Features Validation
sub validate_features {
  my ($self) = @_;
  my @features = ();
  my $db_specified = 0;

  foreach my $want (@{$self->{features}}) {
    # Validate requested features
    if ($want =~ /^cf-deployment-version-(.*)$/) {
      # already dealt with
    } elsif ($want =~ /^(shield-dbs|shield-blobstores)$/) {
      $self->warn_message("The #c{$want} feature has been deprecated, in favor of BOSH add-ons");
    } elsif ($want =~ /^(omit-haproxy|local-blobstore|blobstore-webdav|container-routing-integrity|routing-api|loggregator-forwarder-agent)$/) {
      $self->warn_message("The #c{$want} feature is now the default behaviour and doesn't need\n\tto be specified in the environment file");
    } elsif ($want =~ /^blobstore-(aws|azure|gcp)$/) {
      my $iaas = $1;
      $self->warn_message("The #c{$want} feature has been renamed to #c{$iaas-blobstore}");
      push @features, "$iaas-blobstore";
    } elsif ($want =~ /^db-external-(mysql|postgres)$/) {
      my $db_type = $1;
      $self->warn_message("The #c{$want} flag has been renamed to #c{$db_type-db}");
      push @features, "$db_type-db";
    } elsif ($want =~ /^(db-internal-postgres|local-db)$/) {
      $self->warn_message("The #c{$want} flag has been renamed to #c{local-postgres-db}");
      push @features, "local-postgres-db";
      $db_specified = 1;
    } elsif ($want eq "haproxy-tls") {
      $self->warn_message("The #c{haproxy-tls} feature flag has been deprecated.\n\tPlease replace it with the #c{haproxy} and #c{tls} flags.");
      push @features, "haproxy", "tls";
    } elsif ($want eq "haproxy-self-signed") {
      $self->warn_message("The #c{haproxy-self-signed} feature flag has been deprecated.\n\tPlease replace it with the #c{haproxy} and #c{self-signed} flags.");
      push @features, "haproxy", "self-signed";
    } elsif ($want eq "haproxy-notls") {
      $self->warn_message("The #c{haproxy-notls} feature flag has been deprecated.\n\tPlease replace it with the #c{haproxy} feature flag.\n\tYou are HIGHLY ENCOURAGED to also add the #c{tls} flag.");
      push @features, "haproxy";
    } elsif ($want eq "minimum-vms") {
      $self->warn_message("The 'minimum-vms' feature flag has been renamed to 'small-footprint'");
      push @features, "small-footprint";
    } elsif ($want eq "azure") {
      $self->warn_message("The #c{azure} feature does not have to be specified, as it will automatically be applied when deploying via an Azure CPI");
    } elsif ($want eq "cflinuxfs2") {
      $self->abort_message("The #c{cflinuxfs2} feature is no longer able to be supported.");
    } elsif ($want eq "cflinuxfs3") {
      push @features, $want;
    } elsif ($want eq "no-nats-tls") {
      $self->abort_message("The #c{no-nats-tls} feature is no longer able to be supported.");
    } elsif ($want eq "local-ha-db") {
      $self->abort_message("The #c{local-ha-db} feature is no longer able to be supported.\n\tConsider using external database for high-availability.");
    } elsif ($want =~ /^(autoscaler|autoscaler-postgres)$/) {
      $self->abort_message("The #c{$want} feature is no longer embedded in the #c{cf} kit.\n\tPlease see the cf-app-autoscaler genesis kit.");
    } elsif ($want eq "native-garden-runc") {
      $self->warn_message("The #c{$want} feature is no longer supported; it is replaced by the upstream\n\t#c{cf-deployment/operations/experimental/use-native-garden-runc-runner} feature.");
      push @features, "cf-deployment/operations/experimental/use-native-garden-runc-runner";
    } elsif ($want =~ /^(app-bosh-dns|dns-service-discovery)$/) {
      $self->warn_message("The #c{$want} feature is no longer supported; it has been replaced by the\n\tupstream #c{cf-deployment/operations/enable-service-discovery} feature.");
      push @features, "enable-service-discovery";
    } elsif ($want eq "cf-deployment/operations/enable-service-discovery") {
      if (!want_feature("bare")) {
        push @features, "enable-service-discovery";
      }
    } elsif ($want eq "compiled-releases") {
      if (!want_feature("cf-deployment/operations/use-compiled-releases")) {
        push @features, "compiled-releases";
      }
    } elsif ($want =~ /^(small-footprint|cf-deployment\/operations\/scale-to-one-az)$/) {
      push @features, "small-footprint";
    } elsif ($want =~ /^(nfs-volume-services|cf-deployments\/operations\/enable-nfs-volume-services)$/) {
      push @features, "nfs-volume-services";
    } elsif ($want =~ /^(smb-volume-services|cf-deployments\/operations\/enable-smb-volume-services)$/) {
      push @features, "smb-volume-services";
    } elsif ($want =~ /^(nfs-ldap|nfs-ldap-tls|cf-deployments\/operations\/enable-nfs-ldap)$/) {
      if (!want_feature('nfs-volume-services') && !want_feature("cf-deployments/operations/enable-nfs-volume-services")) {
        $self->abort_message("Feature #c{$want} cannot be specified without feature #c{nfs-volume-services}");
      }
      push @features, $want;
    } elsif ($want =~ /^(local-postgres-db|local-mysql-db|mysql-db|postgres-db)$/) {
      push @features, $want;
      $db_specified = 1;
    } elsif ($want =~ /^(bare|partitioned-network|haproxy|tls|self-signed|isolation-segments)$/) {
      push @features, $want;
    } elsif ($want =~ /^(minio-blobstore|aws-blobstore|aws-blobstore-iam|azure-blobstore|gcp-blobstore)$/) {
      if (want_feature("ocfp")) {
        $self->abort_message("Cannot specify blobstore with ocfp feature. \n\tWith ocfp feature blobstore specifies you.");
      }
      push @features, $want;
    } elsif ($want eq "gcp-use-access-key") {
      push @features, $want;
    } elsif ($want =~ /^(enable-service-discovery|ssh-proxy-on-routers|no-tcp-routers)$/) {
      push @features, $want;
    } elsif ($want =~ /^(blacksmith-integration|trust-blacksmith-ca|app-scheduler-integration|app-autoscaler-integration|prometheus-integration|stratos-integration|v2-nats-credentials|scs-integration)$/) {
      push @features, $want;
    } elsif ($want eq "windows-diego-cells") {
      push @features, $want;
    } elsif ($want =~ /^(\+migrated-v1-env|\+override-db-names)$/) {
      push @features, $want;
    } elsif ($want =~ /^(v1-vm-types|no-v1-vm-types)$/) {
      # no-op, dealt with elsewhere
    } elsif ($want eq "uaa-admin-client") {
      push @features, $want;
    } elsif ($want =~ /^cf-deployment\//) {
      if (-f "$want.yml") {
        push @features, $want;
      } else {
        $self->abort_message("#c{$want} was not found in upstream files.\n\tSee cf-deployment for valid ops files.");
      }
    } elsif ($want eq "ocfp") {
      push @features, (
        "enable-service-discovery",
        $want
      );

      if (!want_feature("uaa-admin-client")) {
        push @features, "uaa-admin-client";
      }
    } else {
      my $env_root = $self->env->path;
      my $opsdir = $self->{opsdir};

      if (-f "$env_root/${opsdir}/$want.yml" || -f "$env_root/ops/$want.yml") {
        push @features, $want;
      } else {
        $self->abort_message("The #c{$want} feature is not supported, see MANUAL.md for valid features.");
      }
    }
  }

  # Handle OCFP blobstore selection
  if (want_feature("ocfp")) {
    my $iaas = $self->{iaas};
    if ($iaas =~ /^(aws|azure|gcp)$/) {
      push @features, "${iaas}-blobstore";
    } elsif ($iaas eq "vsphere") {
      push @features, "minio-blobstore";
    } else {
      $self->abort_message("Blobstores are not supported on #c{${iaas}} yet.");
    }
  }

  # Default to local-postgres-db if no DB is specified
  if (!$db_specified && !want_feature('bare')) {
    push @features, "local-postgres-db";
  }

  # Check for abort/fail conditions
  if ($self->{abort}) {
    bail("#R{Cannot continue} - fix the #C{$ENV{GENESIS_ENVIRONMENT}.yml} file.");
  }

  if ($self->{warn}) {
    $self->warn_message("Adjust your #C{$ENV{GENESIS_ENVIRONMENT}.yml} file to remove warnings.");
  }

  # Update the features list
  $self->{features} = \@features;
  return 1;
}

# Features Processing Setup
sub features_setup {
  my ($self) = @_;

  # Minimal injections required for Genesis compliance
  if (!want_feature("bare") || want_feature("partitioned-network")) {
    push @{$self->{manifests}}, "operations/rename-network-and-deployment.yml";
  } else {
    push @{$self->{manifests}}, "cf-deployment/operations/rename-network-and-deployment.yml";
  }

  # Set up some best practices if not bare
  if (!want_feature("bare")) {
    push @{$self->{manifests}}, (
      "overlay/identity.yml",
      "overlay/override-app-domains.yml",
      "overlay/ten-year-ca-expiry.yml",
      "overlay/uaa-branding.yml"
    );

    # Change vm types - must be done before operations delete unused instance_types
    if (want_feature("v1-vm-types")) {
      push @{$self->{manifests}}, "overlay/addons/v1-vm-types.yml";
    }

    # Deal with availability zones - has to be done to core instance groups
    # before they potentially get removed by further features
    if ($self->{cpi} eq 'azure' || want_feature("small-footprint") ||
      want_feature("cf-deployment/operations/scale-to-one-az")) {
      push @{$self->{manifests}}, (
        "cf-deployment/operations/scale-to-one-az.yml",
        "operations/scale-to-one-az.yml"
      );
    }
    push @{$self->{manifests}}, "operations/custom-azs.yml";

    # Temporary override of specific releases - keep but leave empty when upstream catches up
    push @{$self->{manifests}}, "overlay/override-releases/static.yml";
  }
}

# Version 1 features check
sub features_v1_check {
  my ($self) = @_;

  if (want_feature("+migrated-v1-env") || want_feature("azure-blobstore") ||
    want_feature('minio-blobstore') || want_feature('aws-blobstore') ||
    want_feature('gcp-blobstore')) {

    if (want_feature('bare')) {
      bail("Cannot have #C{bare} feature when migrating from v1");
    }

    push @{$self->{manifests}}, "overlay/blobstore/meta.yml";
  }
}

# Process Requested Features
sub features_process {
  my ($self) = @_;

  foreach my $want (@{$self->{features}}) {
    if ($want eq "azure-blobstore") {
      push @{$self->{blobstores}}, $want;
      push @{$self->{manifests}}, (
        "overlay/blobstore/external.yml",
        "overlay/blobstore/azure.yml",
        "cf-deployment/operations/use-external-blobstore.yml",
        "cf-deployment/operations/use-azure-storage-blobstore.yml"
      );
    } elsif ($want =~ /^(aws-blobstore|aws-blobstore-iam)$/) {
      push @{$self->{blobstores}}, $want;
      push @{$self->{manifests}}, (
        "overlay/blobstore/external.yml",
        "overlay/blobstore/aws.yml",
        "cf-deployment/operations/use-external-blobstore.yml"
      );

      if (want_feature("aws-blobstore-iam")) {
        push @{$self->{manifests}}, "overlay/blobstore/aws-iam.yml";
      }
    } elsif ($want eq "minio-blobstore") {
      push @{$self->{blobstores}}, $want;
      push @{$self->{manifests}}, (
        "overlay/blobstore/external.yml",
        "overlay/blobstore/minio.yml",
        "cf-deployment/operations/use-external-blobstore.yml"
      );
    } elsif ($want eq "gcp-blobstore") {
      push @{$self->{blobstores}}, $want;

      if (want_feature("gcp-use-access-key")) {
        push @{$self->{manifests}}, (
          "overlay/blobstore/external.yml",
          "cf-deployment/operations/use-external-blobstore.yml",
          "cf-deployment/operations/use-gcs-blobstore-access-key.yml"
        );
      } else {
        push @{$self->{manifests}}, (
          "overlay/blobstore/external.yml",
          "cf-deployment/operations/use-external-blobstore.yml",
          "cf-deployment/operations/use-gcs-blobstore-service-account.yml"
        );
      }
    } elsif ($want =~ /^(mysql-db|postgres-db)$/) {
      push @{$self->{databases}}, $want;
      push @{$self->{manifests}}, (
        "cf-deployment/operations/use-external-dbs.yml",
        "operations/use-external-dbs-ports.yml",
        "overlay/db/external.yml",
        "overlay/db/external-".($want =~ s/-db//r).".yml"
      );
    } elsif ($want eq "local-postgres-db") {
      push @{$self->{databases}}, $want;
      push @{$self->{manifests}}, "cf-deployment/operations/use-postgres.yml";

      if (want_feature('+override-db-names')) {
        push @{$self->{manifests}}, (
          "operations/db-override-names.yml",
          "operations/db-override-postgres-names.yml",
          "overlay/db/internal-overrides.yml"
        );

        if (want_feature('+migrated-v1-env')) {
          push @{$self->{manifests}}, "overlay/addons/migration-db-override-names.yml";
        }
      }
    } elsif ($want eq "local-mysql-db") {
      push @{$self->{databases}}, $want;
      push @{$self->{manifests}}, "overlay/db/local-mysql-db.yml";

      if (want_feature('+override-db-names')) {
        push @{$self->{manifests}}, (
          "operations/db-override-names.yml",
          "operations/db-override-mysql-names.yml",
          "overlay/db/internal-overrides.yml"
        );

        if (want_feature('+migrated-v1-env')) {
          push @{$self->{manifests}}, "overlay/addons/migration-db-override-names.yml";
        }
      }
    } elsif ($want eq "compiled-releases") {
      push @{$self->{manifests}}, (
        "cf-deployment/operations/use-compiled-releases.yml",
        "overlay/override-releases/compiled.yml"
      );
    } elsif ($want eq "small-footprint") {
      # already dealt with
    } elsif ($want eq "nfs-volume-services") {
      push @{$self->{manifests}}, "cf-deployment/operations/enable-nfs-volume-service.yml";

      if (!want_feature("bare")) {
        push @{$self->{manifests}}, "overlay/addons/nfs-volume-service.yml";
      }

      if (want_feature("nfs-ldap") || want_feature("nfs-ldap-tls")) {
        push @{$self->{manifests}}, (
          "cf-deployment/operations/enable-nfs-ldap.yml",
          "overlay/addons/nfs-ldap.yml"
        );

        if (want_feature("ocfp")) {
          push @{$self->{manifests}}, "overlay/addons/nfs-ldap-config.yml";
        }

        if (want_feature("nfs-ldap-tls")) {
          push @{$self->{manifests}}, "overlay/addons/nfs-ldap-tls.yml";

          # If user provided their own nfs-ldap-ca path, delete the default
          my $params_ref = ref($self->{params}) eq 'HASH' ? $self->{params} : decode_json($self->{params});
          if (exists $params_ref->{"nfs-ldap-ca-cert-ca"}) {
            my $remove_unused_variables_opsfile = "operations/dynamic/remove-unused-nfs-ldap-ca-cert.yml";

            # Create directory if it doesn't exist
            system("mkdir -p operations/dynamic");

            # Create the ops file
            open my $fh, '>', $remove_unused_variables_opsfile or bail("Cannot write to $remove_unused_variables_opsfile: $!");
            print $fh "--- # Remove unused variabels\n";
            print $fh $self->gopatch_remove("/variables/name=nfs-ldap-ca-cert");
            close $fh;

            push @{$self->{manifests}}, $remove_unused_variables_opsfile;
          }
        }
      }
    } elsif ($want eq "smb-volume-services") {
      push @{$self->{manifests}}, "cf-deployment/operations/enable-smb-volume-service.yml";

      if (!want_feature("bare")) {
        push @{$self->{manifests}}, "overlay/addons/smb-volume-service.yml";
      }
    } elsif ($want eq "enable-service-discovery") {
      push @{$self->{manifests}}, "overlay/enable-service-discovery.yml";
    } elsif ($want eq "trust-blacksmith-ca") {
      push @{$self->{manifests}}, "overlay/addons/trust-blacksmith-ca.yml";

      if (want_feature("cflinuxfs3")) {
        push @{$self->{manifests}}, "overlay/addons/trust-blacksmith-ca-cflinuxfs3.yml";
      }

      if (want_feature("ocfp")) {
        push @{$self->{manifests}}, "ocfp/trust-blacksmith-ca.yml";
      }
    } elsif ($want eq "app-autoscaler-integration") {
      push @{$self->{manifests}}, "overlay/addons/autoscaler.yml";
    } elsif ($want eq "app-scheduler-integration") {
      push @{$self->{manifests}}, "overlay/addons/app-scheduler.yml";
    } elsif ($want eq "scs-integration") {
      push @{$self->{manifests}}, "overlay/addons/scs.yml";
    } elsif ($want eq "prometheus-integration") {
      push @{$self->{manifests}}, "overlay/addons/prometheus.yml";
    } elsif ($want eq "stratos-integration") {
      push @{$self->{manifests}}, "overlay/addons/stratos.yml";
    } elsif ($want eq "ssh-proxy-on-routers") {
      push @{$self->{manifests}}, "overlay/addons/ssh-proxy-on-routers.yml";
    } elsif ($want eq "no-tcp-routers") {
      push @{$self->{manifests}}, "overlay/addons/no-tcp-routers.yml";
    } elsif ($want eq "windows-diego-cells") {
      push @{$self->{manifests}}, (
        "cf-deployment/operations/windows2019-cell.yml",
        "cf-deployment/operations/use-online-windows2019fs.yml",
        "cf-deployment/operations/use-latest-windows2019-stemcell.yml",
        "overlay/override-releases/static-windows.yml"
      );

      if (want_feature("compiled-releases")) {
        push @{$self->{manifests}}, (
          "cf-deployment/operations/experimental/use-compiled-releases-windows.yml",
          "overlay/override-releases/compiled-windows.yml"
        );
      }

      if (!want_feature("bare")) {
        push @{$self->{manifests}}, "overlay/windows.yml";
      }
    } elsif ($want eq "cflinuxfs3") {
      push @{$self->{manifests}}, "operations/use-cflinuxfs3.yml";
    } elsif ($want eq "isolation-segments") {
      # process outside of base features
    } elsif ($want eq "uaa-admin-client") {
      push @{$self->{manifests}}, "overlay/addons/uaa-admin-client.yml";
    } elsif ($want eq "+migrated-v1-env") {
      push @{$self->{manifests}}, "overlay/addons/migration.yml";
    } elsif ($want =~ /cf-deployment\//) {
      if (-f "$want.yml") {
        push @{$self->{manifests}}, "$want.yml";
      } else {
        bail("Kit $ENV{GENESIS_KIT_NAME}/$ENV{GENESIS_KIT_VERSION} does not support the '$want' feature.");
      }
    } elsif ($want eq "haproxy") {
      push @{$self->{manifests}}, "overlay/routing/haproxy.yml";

      my $params_ref = ref($self->{params}) eq 'HASH' ? $self->{params} : decode_json($self->{params});
      if (exists $params_ref->{cf_lb_network} && $params_ref->{cf_lb_network} ne "") {
        push @{$self->{manifests}}, "overlay/routing/haproxy-public-network.yml";
      }

      if (want_feature("tls")) {
        push @{$self->{manifests}}, "overlay/routing/haproxy-tls.yml";

        if (!want_feature("self-signed")) {
          push @{$self->{manifests}}, "overlay/routing/haproxy-provided-cert.yml";
        }
      }

      if (want_feature("small-footprint")) {
        push @{$self->{manifests}}, "overlay/routing/haproxy-small-footprint.yml";
      }
    } else {
      my $env_root = $self->env->path;
      my $opsdir = $self->{opsdir};

      if (-f "$env_root/${opsdir}/$want.yml") {
        if (want_feature("ocfp")) {
          push @{$self->{opsfiles}}, "$env_root/${opsdir}/$want.yml";
        } else {
          push @{$self->{manifests}}, "$env_root/${opsdir}/$want.yml";
        }
      } elsif (-f "$env_root/ops/$want.yml") {
        if (want_feature("ocfp")) {
          push @{$self->{opsfiles}}, "$env_root/ops/$want.yml";
        } else {
          push @{$self->{manifests}}, "$env_root/ops/$want.yml";
        }
      }
    }
  }

  # Validate blobstores
  if (scalar(@{$self->{blobstores}}) > 1) {
    bail("Too many blobstores selected; pick only one of: " . join(", ", @{$self->{blobstores}}));
  }

  # Validate databases
  if (scalar(@{$self->{databases}}) > 1) {
    bail("Too many databases selected; pick only one of: " . join(", ", @{$self->{databases}}));
  }

  # Validate availability zones
  my $params_ref = ref($self->{params}) eq 'HASH' ? $self->{params} : decode_json($self->{params});
  my $has_availability_zones = exists($params_ref->{availability_zones});
  my $randomize_az_placement = exists($params_ref->{randomize_az_placement}) ? $params_ref->{randomize_az_placement} : 'false';

  if (($has_availability_zones || $randomize_az_placement eq 'true') && want_feature("bare")) {
    bail("#M{params.availibility_zones} and #M{params.randomize_az_placement}\n\tare not compatible with feature '#C{bare}'.");
  }

  # Additional manifests for non-bare deployments
  if (!want_feature("bare")) {
    if (want_feature('+migrated-v1-env') && !want_feature('v2-nats-credentials')) {
      push @{$self->{manifests}}, "overlay/addons/migration-v1-nats-credentials.yml";
    }

    my $skip_ssl_validation = $params_ref->{skip_ssl_validation} || '';
    if ($skip_ssl_validation eq 'false') {
      if (!want_feature("cf-deployment/operations/stop-skipping-tls-validation")) {
        push @{$self->{manifests}}, "cf-deployment/operations/stop-skipping-tls-validation";
      }
    }

    if (scalar(@{$self->{databases}}) == 0) {
      push @{$self->{manifests}}, "cf-deployment/operations/use-postgres.yml";
    }

    # Handle IaaS peculiarities
    if ($self->{cpi} eq 'azure') {
      if ($has_availability_zones || $randomize_az_placement eq 'true') {
        bail("#M{params.availibility_zones} and #M{params.randomize_az_placement} are\n\tnot compatible with deployments to Azure infrastructure.");
      }

      push @{$self->{manifests}}, (
        "cf-deployment/operations/azure.yml",
        "overlay/azure_availability_sets.yml"
      );
    } elsif ($self->{cpi} eq 'warden') {
      push @{$self->{manifests}}, "cf-deployment/operations/bosh-lite.yml";
    }

    # Dynamic instance counts and VM types
    $self->dynamic_instance_counts();
    $self->dynamic_instance_vm_types();
  }

  # Include migration manifest fragments
  my $version = lookup("exodus.kit_version", "");
  if ($version && !new_enough($version, "2.0.0-rc0")) {
    push @{$self->{manifests}}, "operations/migrate/cells.yml";

    if (want_feature("local-postgres-db")) {
      push @{$self->{manifests}}, "operations/migrate/postgres.yml";
    }
  }
}

# Isolation Segments
sub features_isos {
  my ($self) = @_;

  return unless want_feature("isolation-segments");

  push @{$self->{manifests}}, "operations/diego-cells-networking.yml";

  my @segments = $self->dynamic_isolation_segments($self->{params});
  push @{$self->{manifests}}, @segments;
}

# OCFP Features
sub features_ocfp {
  my ($self) = @_;

  return unless want_feature("ocfp");

  my $params_ref = ref($self->{params}) eq 'HASH' ? $self->{params} : decode_json($self->{params});
  my $env_scale = $params_ref->{ocfp_env_scale} || "dev";

  push @{$self->{manifests}}, (
    "overlay/addons/autoscaler.yml",
    "overlay/addons/app-scheduler.yml",
    "overlay/addons/scs.yml",
        "overlay/addons/prometheus.yml",
        "overlay/blobstore/meta.yml"
    );

    # OCFP Overrides
    push @{$self->{manifests}}, (
        "ocfp/meta.yml",
        "ocfp/ocfp.yml",
        "ocfp/external-db-prep.yml",
        "ocfp/external-db.yml",
        "ocfp/external-blobstore.yml",
        "ocfp/trusted-certs.yml"
    );

    push @{$self->{manifests}}, (
        "ocfp/$self->{iaas}/ocf.yml",
        "ocfp/$self->{iaas}/azs.yml",
        "ocfp/$self->{iaas}/blobstore.yml"
    );

    if (want_feature("windows-diego-cells")) {
        push @{$self->{manifests}}, (
            "ocfp/$self->{iaas}/windows.yml",
            "ocfp/trusted-certs-windows.yml"
        );
    }

    push @{$self->{manifests}}, "ocfp/scale/${env_scale}.yml";

    foreach my $want (@{$self->{features}}) {
        if ($want eq "stratos-integration") {
            push @{$self->{manifests}}, "ocfp/stratos.yml";
        } elsif ($want eq "nfs-volume-services") {
            push @{$self->{manifests}}, "ocfp/nfs-ldap.yml";
            push @{$self->{manifests}}, "ocfp/nfs-ldap-data.yml";
        } elsif ($want eq "smb-volume-services") {
            push @{$self->{manifests}}, "ocfp/smb-broker.yml";
        }
    }
}

# Main perform method that executes all the logic
sub perform {
    my $self = shift;

    # Genesis version check
    my $genesis_min_version = "2.8.6";
    my $genesis_version = `genesis -v 2>&1 | awk '{gsub("v",""); print \$2}'`;
    chomp $genesis_version;

    if ($genesis_version !~ /-dev$/ && !new_enough($genesis_version, $genesis_min_version)) {
        bail("This kit needs at least Genesis '${genesis_min_version}'.\n\tPlease upgrade and try again.");
    }

    # Process CF deployment version
    my $version = "";
    foreach my $want (@{$self->{features}}) {
        if ($want =~ /^cf-deployment-version-(.*)$/) {
            if ($version) {
                bail("You cannot specify more than one cf-deployment-version-* feature");
            }
            $version = $1;
        }
    }

    if ($version) {
        $self->switch_cf_version($version);
    }

    # Base configuration with minimal injections
    $self->{manifests} = [
        "cf-deployment/cf-deployment.yml",
        "overlay/base.yml",
        "overlay/upstream_version.yml"
    ];

    # Parse params
    my $params_ref = ref($self->{params}) eq 'HASH' ? $self->{params} : decode_json($self->{params});
    my $has_availability_zones = exists($params_ref->{availability_zones});
    my $randomize_az_placement = exists($params_ref->{randomize_az_placement}) ? $params_ref->{randomize_az_placement} : 'false';

    # Process features
    $self->validate_features();
    $self->features_setup();
    $self->features_v1_check();
    $self->features_process();
    $self->features_isos();
    $self->features_ocfp();

    # Add opsfiles for OCFP
    if (want_feature("ocfp")) {
        push @{$self->{manifests}}, @{$self->{opsfiles}};
    }

    # Add all manifests to the blueprint files
    $self->add_files(@{$self->{manifests}});

    # Mark as completed and return
    return $self->done();
}

1;
