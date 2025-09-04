package Genesis::Hook::Blueprint::CF v3.0.1;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::Blueprint);

use Genesis qw/
	info warning error bail new_enough debug trace
	in_array uniq compare_arrays
	run curl sentence_join struct_lookup
	mkdir_or_fail mkfile_or_fail load_yaml save_to_yaml_file slurp
/;
use Genesis::State qw/envset/;
use Archive::Tar;
use JSON::PP qw/decode_json encode_json/;
use IPv4;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');

	# FIXME: this should not be needed when we move to Genesis 3.2.x and branchified pipelines
	# Set up operations directory path
	# REFACTOR: this should be moved to a common method in Genesis::Hook::Blueprint, so all kits can be updated en masse
	$obj->{custom_ops_dir} = envset('PREVIOUS_ENV')
		? ".genesis/cached/$ENV{PREVIOUS_ENV}/ops"
		: "ops";

	$obj->{upstream_dir} = '.'; # user must specify the cf-deployment dir as part of the feature
	$obj->{upstream_pattern_match} = qr/^cf-deployment\/operations\/(.*)$/;

	return $obj;
}

sub perform {
	my $self = shift;

	# Store raw features
	$self->{raw_features} = [$self->features]; # Get raw features from env
	$self->{params} = $self->env->params->{params} // {}; # Get environment parameters

	# Custom CF Versions
	$self->handle_custom_cf_versions();

	# Add base CF deployment files
	$self->add_files(
		"cf-deployment/cf-deployment.yml",
		"overlay/base.yml",
		"overlay/upstream_version.yml"
	);

	if ($self->want_feature("ocfp")) {
		$self->validate_ocfp_features(); #TODO: make this method
		return $self->process_ocfp_features();
	} else {
		$self->validate_classic_features(); #TODO: make this method
		return $self->process_classic_features();
	}

}

sub process_classic_features {
	my ($self) = @_;
	my $iaas       = $self->iaas; # Get IaaS from environment instead of feature.
	my $blobstore  = $self->requested_blobstore;
	my $env_params = $self->env->params; # Get environment parameters
	my $ops_dir    = $self->ops_dir;

	my @valid_databases = qw{
		+internal-db
		local-postgres-db local-mysql-db
		mysql-db postgres-db
	};
	my ($database, $local_db) = $self->requested_database;

	my $is_bare = $self->want_feature("bare");

	# Setup the base configuration
	if ($is_bare) {
		$self->add_files(
			# Minimal injections for Genesis compliance
			$self->want_feature("partitioned-network")
				? 'operations/rename-network-and-deployment.yml'
				: 'cf-deployment/operations/rename-network-and-deployment.yml'
		);

		my @invalid_bare_features = qw{}; # Not sure we need this...

		# REFACTOR: move this to validation?
		bail(
			"Cannot have #C{bare} feature when migrating from v1 or using external blobstores in v1 migration context."
		) if $self->want_feature('+migrated-v1-env')
			|| $blobstore ne '+internal-blobstore';

		my @invalid_requested_features = grep {
			$self->want_feature($_)
		} @invalid_bare_features;
		bail(
			"Cannot have #C{bare} feature with requested features: "
			. join(", ", @invalid_requested_features)
		) if @invalid_requested_features;

	} else {
		# REFACTOR: this is a common part, should be moved to a common method
		$self->add_files(qw{
			operations/rename-network-and-deployment.yml
			overlay/identity.yml
			overlay/override-app-domains.yml
			overlay/ten-year-ca-expiry.yml
			overlay/uaa-branding.yml
		});

		$self->add_files_if_wants('v1-vm-types' => 'overlay/addons/v1-vm-types.yml');

		# Handle custom AZs and singular AZ - REFACTOR: this is a common part
		$self->add_files(
			'cf-deployment/operations/scale-to-one-az.yml',
			'operations/scale-to-one-az.yml'
		) if $iaas eq 'azure' || $self->want_feature(
			qr{^(small-footprint|cf-deployment/operations/scale-to-one-az)$}
		);
		$self->add_files('operations/custom-azs.yml');

		# FIXME: This should appear near the end
		# REFACTOR: this is a common part, should be moved to a common method
		# Use whatever release overrides are specified in the kit.
		if ($self->want_feature('source-releases')) {
			$self->add_files('overlay/override-releases/source.yml');
		} else {
			$self->add_files('overlay/override-releases/compiled.yml');
		}
	}

	$self->add_files(
		'overlay/blobstore/meta.yml'
	) if $self->want_feature("+migrated-v1-env")
		|| $blobstore ne "+internal-blobstore";

	my @direct_features = qw{
		compiled-releases
		small-footprint cf-deployment/operations/scale-to-one-az
		v1-vm-types v2-nats-credentials
		aws-blobstore-iam gcp-use-access-key blobstore-suffix
		isolation-segments
		nfs-ldap nfs-ldap-tls
		vip
	};

	my ($remaining_features) = compare_arrays(
		[$self->features], \@direct_features
	);

	# Configure each positional feature
	for my $feature (@$remaining_features) {

		# Blobstores
		if ($feature eq "+internal-blobstore") {
			# Internal blobstore is the default, no need to add files
		} elsif ($feature eq $blobstore) {
			$self->enable_external_blobstore($blobstore);

		# Databases
		} elsif ($feature eq "+internal-db" || in_array($feature, @valid_databases)) {
			# We've already validated the database feature, so we can just add it.
			$self->enable_requested_database($database, $local_db);

		# Integrations
		}	elsif ($feature eq "app-autoscaler-integration" ) {
			$self->add_files("overlay/addons/autoscaler.yml");
			$self->_add_app_autoscaler_releases();

		}	elsif ($feature eq "app-scheduler-integration" ) {
			$self->add_files("overlay/addons/app-scheduler.yml");

		} elsif ($feature eq "scs-integration" ) {
			$self->add_files("overlay/addons/scs.yml");

		} elsif ($feature eq "prometheus-integration" ) {
			$self->add_files("overlay/addons/prometheus.yml");

		} elsif ($feature eq "stratos-integration" ) {
			$self->add_files("overlay/addons/stratos.yml");

		} elsif ($feature eq "uaa-admin-client") {
			$self->add_files("overlay/addons/uaa-admin-client.yml");

		# Migration
		} elsif ( $feature eq "+migrated-v1-env" ) {
			$self->add_files("overlay/addons/migration.yml");

		# Other features
		} elsif ($feature eq "nfs-volume-services") {
			$self->enable_nfs_volume_services();

		} elsif ( $feature eq "smb-volume-services" ) {
			$self->add_files("cf-deployment/operations/enable-smb-volume-service.yml");
			$self->add_files("overlay/addons/smb-volume-service.yml") unless $is_bare;

		} elsif ( $feature eq "enable-service-discovery" ) {
			$self->add_files("overlay/enable-service-discovery.yml");

		# TODO: Add windows-diego-cells feature support

		# Custom ops files from environment
		} elsif (-f $self->env->path("$ops_dir/${feature}.yml")) {
			$self->add_files($self->env->path("$ops_dir/${feature}.yml"));

		} else {
			$self->_process_common_positional_features($feature);
		}
	}

	### Post positional features processing

	# Isolation Segments (formerly features_isos)
	if ( $self->want_feature("isolation-segments") ) {
		$self->add_files("operations/diego-cells-networking.yml");
		my @segment_files = $self->_dynamic_isolation_segments();
		$self->add_files(@segment_files) if @segment_files;
	}

	# Automatically include trusted cas if they exist
	$self->_add_trusted_certs();

	# Use compiled releases if requested
	$self->add_files_if_wants('compiled-releases',
		"cf-deployment/operations/use-compiled-releases.yml",
		"overlay/override-releases/compiled.yml"
	);

	if (! $is_bare) {

		# Migration from v1
		if ($self->want_feature('+migrated-v1-env') && !$self->want_feature('v2-nats-credentials')) {
			$self->add_files("overlay/addons/migration-v1-nats-credentials.yml");
		}


		if (! $self->env->lookup('params.skip_ssl_validation')) {
			$self->add_files("cf-deployment/operations/stop-skipping-tls-validation.yml"); # Added .yml
		}

		# IaaS peculiarities
		if ($self->{cpi_name} eq 'azure') {
			$self->add_files("cf-deployment/operations/azure.yml", "overlay/azure_availability_sets.yml");
		} elsif ($self->{cpi_name} eq 'warden') {
			$self->add_files("cf-deployment/operations/bosh-lite.yml");
		}

		# Dynamic instance counts and VM types
		my @vm_type_ops = $self->_dynamic_instance_vm_types();
		$self->add_files(@vm_type_ops) if @vm_type_ops;
		my @count_ops = $self->_dynamic_instance_counts();
		$self->add_files(@count_ops) if @count_ops;

		# VIP network support
		if ($self->want_feature('vip')) {
			my @vip_ops = $self->_dynamic_vip_network_support();
			bail(
				"VIP feature requested but no VIPs configured!"
			) unless @vip_ops;
			$self->add_files(@vip_ops);
		}
	}

	# Exodus migration fragments
	my $exodus_version = $self->env->exodus_lookup("kit_version", ""); # Use $self->env
	if ($exodus_version && !new_enough($exodus_version, "2.0.0-rc0")) {
		$self->add_files("operations/migrate/cells.yml");
		$self->add_files_if_wants("local-postgres-db",
			'operations/migrate/postgres.yml'
		);
	}

	return $self->done();
}

sub process_ocfp_features {
	my ($self) = @_;
	my $iaas      = $self->iaas; # Get IaaS from environment instead of feature.
	my $blobstore = $self->requested_blobstore;
	my $ops_dir   = $self->ops_dir;
	my $trusted_certs_usage = 0;

	my ($database, $local_db) = $self->requested_database;

	# Setup the base configuration that OCFP is placed on top of
	$self->add_files(qw{
		operations/rename-network-and-deployment.yml
		overlay/identity.yml
		overlay/override-app-domains.yml
		overlay/ten-year-ca-expiry.yml
		overlay/uaa-branding.yml
	});

	# Handle custom AZs and singular AZ - REFACTOR: this is a common part
	#   Ensure scale-to-one-az from cf-deployment is added if small-footprint is
	#   active The actual small-footprint feature handling will add its specific
	#   ops files.  This ensures the base cf-d scale-to-one-az is present if azure
	#   or explicitly requested.
	$self->add_files(
		'cf-deployment/operations/scale-to-one-az.yml',
		'operations/scale-to-one-az.yml'
	) if $self->iaas eq 'azure' || $self->want_feature(
		qr{^(small-footprint|cf-deployment/operations/scale-to-one-az)$}
	);
	$self->add_files('operations/custom-azs.yml');

	# Base OCFP configuration
	$self->add_files(qw(
		overlay/addons/autoscaler.yml
		overlay/addons/app-scheduler.yml
		overlay/addons/scs.yml
		overlay/addons/prometheus.yml
		overlay/addons/uaa-admin-client.yml
		overlay/addons/stratos.yml
		overlay/blobstore/meta.yml
		overlay/enable-service-discovery.yml
		ocfp/meta.yml
		ocfp/ocfp.yml
	));

	if ($self->env->ocfp_config_lookup('net.topology', 'v2') eq 'v1') {
		# Wee need to use the greedy ocfp topology for v1
		$self->add_files('ocfp/v1-network.yml');
	}

	$self->_add_app_autoscaler_releases();

	# Add OCFP specific operations
	$self->add_files(
		"ocfp/${iaas}/ocf.yml",
		"ocfp/${iaas}/azs.yml",
		"ocfp/${iaas}/ssh-proxy.yml", # integrated support for ssh-proxy on routers - must come after ocf.yml
	);

	# Need to add compiled releases here, because external db selection
	# deletes a path for pxc and upstream will fail to find it.
	if (!$self->want_feature('source-releases')) {
		$self->add_files(
			"cf-deployment/operations/use-compiled-releases.yml",
		);
	}

	# Blobstores
	if ($blobstore eq '+internal-blobstore') {
		$self->add_files('ocfp/internal-blobstore.yml');
	} else {
		$self->enable_external_blobstore($blobstore);
		$self->add_files('ocfp/external-blobstore.yml');
		$self->add_files_if_exists("ocfp/${iaas}/external-blobstore.yml");
	}

	# Databases
	$self->add_files("cf-deployment/operations/use-postgres.yml") if $database eq 'postgres';
	# FIXME: Postgres is the only supported local database for OCFP
	if ($local_db) {
		$self->add_files_if_exists(
			"ocfp/internal-db.yml",
			"ocfp/internal-${database}-db.yml", # Add specific database ops file
		);
	} else {
		$trusted_certs_usage++;
		$self->add_files_if_exists(
			"ocfp/external-db-prep.yml",
			"ocfp/external-db.yml",
			"ocfp/${iaas}/external-db.yml",
			"ocfp/external-${database}-db.yml", # Add specific database ops file
			"ocfp/${iaas}/external-{$database}-db.yml",
		);
	}

	# Process the remaining requested features in order
	my @handled_features = (
		'ocfp',' self-signed', 'small-footprint',
		'source-releases', 'isolation-segments',
		'cf-deployment/operations/scale-to-one-az',
		$blobstore, '+internal-db', 'local-postgres-db',
		'local-mysql-db', 'mysql-db', 'postgres-db',
		'nfs-ldap', 'nfs-ldap-tls', 'vip'
	);

	my ($remaining_features) = compare_arrays(
		[$self->features], \@handled_features
	);

	my @ops_files = ();
	for my $feature (@$remaining_features) {

		# Integrations - others are automatically included above
		if ($feature eq 'stratos-integration') {
			$self->add_files(
				'ocfp/stratos.yml'
			);

		# Other OCFP features
		} elsif ($feature eq 'nfs-volume-services') {
			$self->enable_nfs_volume_services();
			$self->add_files(
				'overlay/addons/nfs-ldap-config.yml', # Why isn't this under ocfp?
				'ocfp/nfs-ldap.yml',
				'ocfp/nfs-ldap-data.yml'
			);

		} elsif ($feature eq 'smb-volume-services') {
			$self->add_files(
				'cf-deployment/operations/enable-smb-volume-service.yml',
				'overlay/addons/smb-volume-service.yml',
				'ocfp/smb-broker.yml'
			);

		} elsif ($feature eq 'windows-diego-cells') {
			$self->enable_windows_diego_cells(!$self->want_feature('source-releases'));
			$self->add_files(
				"ocfp/$iaas/windows.yml",
				"ocfp/trusted-certs-windows.yml"
			);
			$trusted_certs_usage++;

		# Custom ops files from environment
		} elsif (-f $self->env->path("$ops_dir/${feature}.yml")) {
			push @ops_files, $self->env->path("$ops_dir/${feature}.yml");

		} else {
			$self->_process_common_positional_features($feature, 'ocfp');
		}
	}

	### Post positional features processing

	# Add trusted certs if present
	my $env = $self->env;
	if ($env->vault->has($env->secrets_mount."/certs/org","ca")) {
		$self->add_files("ocfp/trust-org-ca.yml");
		$trusted_certs_usage++
	}
	if ($env->vault->has($env->exodus_mount.$env->name."/blacksmith","blacksmith_ca")) {
		$self->add_files("ocfp/trust-blacksmith-ca.yml");
		$trusted_certs_usage++
	}
	if ($trusted_certs_usage) {
		$self->add_files(
			"ocfp/trusted-certs.yml",
			"ocfp/trusted-certs-cflinuxfs4.yml"
		);
		if ($self->want_feature('cflinuxfs3')) {
			$self->add_files("ocfp/trusted-certs-cflinuxfs3.yml");
		}
	}

	# Isolation Segments (formerly features_isos)
	if ( $self->want_feature("isolation-segments") ) {
		$self->add_files("operations/diego-cells-networking.yml");
		my @segment_files = $self->_dynamic_isolation_segments();    # Uses $self->{parsed_params}
		$self->add_files(@segment_files) if @segment_files;
	}

	# Dynamic instance counts and VM types
	my @vm_type_ops = $self->_dynamic_instance_vm_types();
	$self->add_files(@vm_type_ops) if @vm_type_ops;
	my @count_ops = $self->_dynamic_instance_counts();
	$self->add_files(@count_ops) if @count_ops;

	# VIP network support
	if ($self->want_feature('vip')) {
		my @vip_ops = $self->_dynamic_vip_network_support();
		bail(
			"VIP feature requested but no VIPs configured!"
		) unless @vip_ops;
		$self->add_files(@vip_ops);
	}

	if (! $self->env->lookup('params.skip_ssl_validation')) { # Should this always be on in OCFP?
		$self->add_files("cf-deployment/operations/stop-skipping-tls-validation.yml");
	}

	# IaaS peculiarities
	if ($iaas eq 'azure') {
		$self->add_files("cf-deployment/operations/azure.yml", "overlay/azure_availability_sets.yml");
	} elsif ($iaas eq 'warden') {
		$self->add_files("cf-deployment/operations/bosh-lite.yml");
	}

	# Use whatever release overrides are specified in the kit.
	if ($self->want_feature('source-releases')) {
		$self->add_files('overlay/override-releases/source.yml');
	} else {
		$self->add_files('overlay/override-releases/compiled.yml');
	}

	# Add custom ops files collected for OCFP
	$self->add_files(@ops_files) if @ops_files;

	return $self->done();
}

# Utility methods
sub _gopatch_replace {
	my ($self, $path, $value) = @_;
	return "  - type: replace\n    path: ${path}\n    value: ${value}\n";
}

sub _gopatch_remove {
	my ($self, $path) = @_;
	return "  - type: remove\n    path: ${path}\n";
}

# handle_custom_cf_versions - Handle custom cf-deployment versions if present
sub handle_custom_cf_versions {
	my ($self) = @_;

	# Check if we have one or more custom cf-deployment versions specified
	my ($custom_cf_version, @extra_cf_versions) = map {
		$_ =~ /^cf-deployment-version-(.*)$/ ? $1 : ()
	} @{$self->{raw_features}};

	# Only one custom cf-deployment version allowed
	bail(
		"Cannot specify more than one cf-deployment-version-* feature"
	) if scalar(@extra_cf_versions) > 0;
	return unless $custom_cf_version;

	warning(
		"#Y{Experimental Feature Enabled:} Custom cf-deployment version: $custom_cf_version"
	);

	# Fetch and cache the specified cf-deployment version
	my $custom_cf_file = "cf-deployment-${custom_cf_version}.tar.gz";
	my $addon_path = $self->env->path(".genesis/kits/addons/");
	mkdir_or_fail($addon_path) unless -d $addon_path;
	my $cfd_file = "$addon_path/$custom_cf_file";

	if (!-f $cfd_file) {
		my $source_url = "https://github.com/cloudfoundry/cf-deployment/archive/v${custom_cf_version}.tar.gz";
		info({stderr => 1},
			"  #i{Fetching custom cf-deployment version $custom_cf_version}",
			"  #i{from cloudfoundry/cf-deployment on github.com}");

		my ($out, $code, $err) = curl({file => $cfd_file}, $source_url);
		bail(
			"Failed to download cf-deployment v%s -- cannot continue!  Error:\n%s\n",
			$custom_cf_version, $err
		) if $code >= 300 && -f $cfd_file;

		# Validate the download
		my @tar_output = `tar -ztf "$cfd_file" | awk '{print \$NF}' | cut -d'/' -f1 | uniq`;
		my $topdir = $tar_output[0];
		chomp $topdir;

		bail("Downloaded cf-deployment v${custom_cf_version} doesn't look like a valid release -- cannot continue")
			unless $topdir eq "cf-deployment-${custom_cf_version}";
	} else {
		info({stderr => 1}, "  #i{Using cached copy of cf-deployment-${custom_cf_version} release}");
	}

  # Remove the existing cf-deployment directory
	my $cf_dir = $self->kit->path("cf-deployment");
	require File::Path;
	File::Path::remove_tree($cf_dir, {error => \my $err});
	bail("Failed to remove ./cf-deployment: " . join(", ", map { $_->{message} } @$err))
		if @$err;

	# Create a new cf-deployment directory
	mkdir_or_fail($cf_dir);

	# Extract the tar.gz file into the cf-deployment directory
	my $tar = Archive::Tar->new;
	$tar->read($cfd_file, 1); # 1 indicates gzip compression

	# Get all files and process them to remove the top-level directory
	my @files = $tar->get_files();
	for my $file (@files) {
		my $path = $file->full_path;
		# Remove the top-level directory (cf-deployment-v1.2.3/)
		$path =~ s|^[^/]+/||;
		next unless $path; # Skip if path becomes empty (was the top directory itself)

		my $dest_path = $self->kit->path("cf-deployment/$path");
		$file->extract($dest_path);
	}
	return 1;
}

sub _dynamic_isolation_template_render {
	my ($self, $tmpl, $name) = @_;
	my $srcdir = 'overlay/dynamic-templates';
	my $dstdir = 'overlay/dynamic';
	my $src = "$srcdir/isolation-segment-${tmpl}.yml";
	my $dst = "$dstdir/isolation-segment-${name}-${tmpl}.yml";

  # Ensure the destination directory exists with full kit path
  my $kit_dynamic_dir = $self->kit->path($dstdir);
  mkdir_or_fail($kit_dynamic_dir) unless -d $kit_dynamic_dir;

	mkfile_or_fail(
		$self->kit->path($dst), slurp(
			$self->kit->path($src)
		) =~ s/\{\{segment-name\}\}/$name/mgr
	);
	return $dst;
}

sub _dynamic_isolation_segments {
	my ($self) = @_;
	my $env = $self->env;
	my @isolation_files = ();
	my $params_ref = $self->{params}; # Get environment parameters

	info("Processing isolation segments...") if $ENV{GENESIS_DEBUG};

	my @isolation_groups = ();
	if (exists $params_ref->{isolation_segments} && ref($params_ref->{isolation_segments}) eq 'ARRAY') {
		foreach my $segment (@{$params_ref->{isolation_segments}}) {
			if (exists $segment->{name}) {
				push @isolation_groups, $segment->{name};
				info("  Found isolation segment: %s", $segment->{name}) if $ENV{GENESIS_DEBUG};
			}
		}
	} else {
		info("  No isolation segments found in params") if $ENV{GENESIS_DEBUG};
		return ();
	}

	return () unless @isolation_groups;

	my @iso_seg_merges = ();
	push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-network.yml"
		if (!($self->want_feature("bare")) || $self->want_feature("partitioned-network"));

	push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-cflinuxfs3.yml"
		if ($self->want_feature("cflinuxfs3"));

	if ($self->want_feature("nfs-volume-services")) {
		push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs.yml";
		if ($self->want_feature("nfs-ldap") || $self->want_feature("nfs-ldap-tls")) {
			push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs-ldap.yml";
			push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs-ldap-tls.yml"
				if ($self->want_feature("nfs-ldap-tls"));
			push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs-ldap-ocfp.yml", "ocfp/nfs-ldap-data.yml"
				if ($self->want_feature("ocfp"));
		}
	}

	push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-smb.yml"
		if ($self->want_feature("smb-volume-services"));

	if ($self->want_feature("ocfp")) {
		push @iso_seg_merges, "ocfp/meta.yml";
	}

	foreach my $group (@isolation_groups) {
		info("  Processing isolation segment: %s", $group) if $ENV{GENESIS_DEBUG};

		my @additional_trusted_certs_files = ();
    my $isolation_segments = $params_ref->{isolation_segments};
    my $has_additional_trusted_certs = 0;

    foreach my $segment (@$isolation_segments) {
      if ($segment->{name} eq $group) {
        $has_additional_trusted_certs = scalar(@{$segment->{additional_trusted_certs} // []}) > 0;
        last;
      }
    }

		if ($self->want_feature("ocfp") || $has_additional_trusted_certs) {
			push @additional_trusted_certs_files, $self->_dynamic_isolation_template_render("additional-trusted-certs", $group);
			if ($self->want_feature("cflinuxfs3")) {
				push @additional_trusted_certs_files, $self->_dynamic_isolation_template_render("additional-trusted-certs-cflinuxfs3", $group);
			}
		}

		# Handle VM type override for isolation segment diego-cell instances
		my $diego_cell_vm_type_name = "diego-cell-$group";
		if ($self->env->lookup("bosh-configs.cloud.vm_types.$diego_cell_vm_type_name")) {
			my $vm_type_actual = $self->want_feature('ocfp')
				? $self->env->name . '.' . $self->env->type . '.vm-diego-cell-' . $group
				: $diego_cell_vm_type_name;

			my $vm_override_content = <<"EOF";
---
meta:
  vm_type: $vm_type_actual
EOF

			my $dstdir = 'overlay/dynamic';
			my $vm_override_file = "$dstdir/isolation-segment-$group-vm-type-override.yml";
			my $kit_dynamic_dir = $self->kit->path($dstdir);
			mkdir_or_fail($kit_dynamic_dir) unless -d $kit_dynamic_dir;
			mkfile_or_fail($self->kit->path($vm_override_file), 0644, $vm_override_content);
			push @iso_seg_merges, $vm_override_file;
		}

		my $dynamic_segment_fragment_file = "overlay/dynamic/isolation-segments-$group.yml";
		my $dynamic_segment_fragment_path = $self->kit->path($dynamic_segment_fragment_file);
		unshift @iso_seg_merges, "overlay/dynamic-templates/isolation-segment.yml";
		my @spruce_cmd = (
			'spruce', 'merge', '-m', '--prune', 'meta',
			(map {$self->kit->path($_)} @iso_seg_merges)
		);

		push @spruce_cmd, (map { $self->kit->path($_) } @additional_trusted_certs_files);

		# Add the user-provided isolation segment data
		my $segment_data = {meta => scalar struct_lookup($params_ref, "isolation_segments.${group}", {})};
		my $segment_json = encode_json($segment_data) =~ s/\(\( /(( defer /gr;
		my $fin_data = {
			"instance_groups" => [
				"(( prepend ))",
				"(( defer append ))"
			],
			genesis => {
				"env" => $env->name,
				"type" => $env->type,
				"secrets_mount" => $env->secrets_mount,
				"secrets_slug" => $env->secrets_slug,
				"secrets_base" => $env->secrets_base,
				"exodus_mount" => $env->exodus_mount,
				"exodus_slug" => $env->exodus_slug,
				"exodus_base" => $env->exodus_base,
				"ci_mount" => $env->ci_mount,
				"bosh_env" => scalar $env->bosh_env,
			}
		};
		if ($self->want_feature("ocfp")) {
			$fin_data->{genesis}{is_ocfp} = 1;
			$fin_data->{genesis}{ocfp_env} = $env->ocfp_env;
			$fin_data->{genesis}{ocfp_type} = $env->ocfp_type;
			$fin_data->{genesis}{ocfp_config_mount} = $env->ocfp_config_mount;
			$fin_data->{genesis}{ocfp_config_base} = $env->ocfp_config_base;
		};
		my $fin_json = encode_json($fin_data);

		my $segment_json_file = $self->env->workpath("segment_$group.json");
		my $append_json_file = $self->env->workpath("fin_$group.json");

		push @spruce_cmd,
			mkfile_or_fail($segment_json_file, $segment_json),
			mkfile_or_fail($append_json_file, $fin_json);

		my ($out, $rc, $err) = run(@spruce_cmd);
		bail(
			"Failed to generate isolation segment file for %s:\n%s",
			$group, $err||$out
		) if $rc;
		mkfile_or_fail( $dynamic_segment_fragment_path, 0644, $out);

		push @isolation_files, $dynamic_segment_fragment_file;
		push @isolation_files, $self->_dynamic_isolation_template_render("dns-sd", $group);
		push @isolation_files, $self->_dynamic_isolation_template_render("nfs-ldap-config", $group)
			if ($self->want_feature("nfs-volume-services") && $self->want_feature("ocfp"));
	}
	return @isolation_files;
}

sub _dynamic_instance_vm_types {

	# FIXME: These use the old vm_types, not the generated ones by the cloud-cloud hook.
	# They should be predictable, but if we want different segments to have different vm types,
	# we need to handle that here and in the cloud-cloud hook.
	my ($self) = @_;
	my $params_ref = $self->{params}; # Get environment parameters
	my @instance_types_ops = ();
	my @used_groups_for_vm_types = (); # To track for duplicates
	my $types_op_file_content = "--- # Dynamically created instance type overrides\n";
	my $found_vm_types = 0;

	my $trans_map = _instance_group_translations();

	my @warnings = ();
	foreach my $key (keys %$params_ref) {
		if ($key =~ /^(.*)_vm_type$/) {
			$found_vm_types = 1;
			my ($inst_grp_orig, $type) = ($1, $params_ref->{$key});
			my $inst_grp = $inst_grp_orig;

			# Handle translations
			if (exists $trans_map->{$inst_grp}) {
				push @warnings, "Translated: params.$inst_grp_orig => params.$trans_map->{$inst_grp}";
				$inst_grp = $trans_map->{$inst_grp};
			}

			next if ($inst_grp eq 'errand' || $inst_grp eq 'haproxy'); # dealt with elsewhere

			my $dashed_inst_grp = $inst_grp;
			$dashed_inst_grp =~ s/_/-/g;
			push @warnings, "Unknown instance group $dashed_inst_grp (from $inst_grp_orig) - this may be bug in your environment files."
				unless exists _is_instance_group()->{$dashed_inst_grp};

			if ($self->want_feature('ocfp')) {
				# OCFP uses a different naming convention for vms
				# FIXME: Need to support different vm types for different segments
				$type = $self->env->name . '.' . $self->env->type . '.vm-' . $dashed_inst_grp;
			}
			$types_op_file_content .= $self->_gopatch_replace("/instance_groups/name=$dashed_inst_grp/vm_type", $type);
			push @used_groups_for_vm_types, $dashed_inst_grp;
		}
	}

	# Handle warning messages
	warning(
		"Found the following warnings while processing instance vm types:\n%s",
		join("\n", map {"[[  - >>$_\n"} @warnings)
	) if @warnings;

	my $errand_vm_type = $params_ref->{errand_vm_type} || "";
	if ($errand_vm_type) {
		$found_vm_types = 1;
		foreach my $errand_name (qw(smoke-tests rotate-cc-database-key)) {
			if (! in_array($errand_name, @used_groups_for_vm_types)) {
				$types_op_file_content .= $self->_gopatch_replace("/instance_groups/name=$errand_name/vm_type", $errand_vm_type);
				push @used_groups_for_vm_types, $errand_name;
			}
		}
	}

	if ($found_vm_types) {
		my @uniq_groups = uniq(@used_groups_for_vm_types);
		my ($dups) = compare_arrays(\@used_groups_for_vm_types, \@uniq_groups);
		bail(
			"Instance vm types specified (or translated as) multiple times: " . join(", ", @$dups)
		) if scalar(@$dups) > 0;

		my $types_op_file_path = "operations/dynamic/instance_types.yml";
		mkfile_or_fail($self->kit->path($types_op_file_path), 0644, $types_op_file_content);
		push @instance_types_ops, $types_op_file_path;
	}
	return @instance_types_ops;
}

sub _instance_count_overrides {
	my ($self) = @_;
	# This is a helper method to get the instance counts overrides from the environment parameters.
	return $self->{_memoized_instance_counts} if exists $self->{_memoized_instance_counts};

	my $params_ref = $self->{params}; # Get environment parameters
	my $trans_map = _instance_group_translations();
	my $counts = {};
	my @warnings = ();
	my @used_groups_for_counts = (); # To track for duplicates
	foreach my $key (grep {/^(.*)_instances$/} keys %$params_ref) {
		my ($inst_grp_orig, $count) = ($key =~ s/^(.*)_instances$/$1/r, $params_ref->{$key});
		my $inst_grp = $inst_grp_orig;

		# Handle translations
		next if ($inst_grp eq 'errand' || $inst_grp eq 'haproxy'); # dealt with elsewhere

		if (exists $trans_map->{$inst_grp}) {
			push @warnings, "Translated: params.$inst_grp_orig => params.$trans_map->{$inst_grp}";
			$inst_grp = $trans_map->{$inst_grp};
		}

		my $dashed_inst_grp = $inst_grp;
		$dashed_inst_grp =~ s/_/-/g;
		push @warnings, "Unknown instance group $dashed_inst_grp (from $inst_grp_orig) - this may be bug in your environment files."
			unless exists _is_instance_group()->{$dashed_inst_grp};

		$counts->{$dashed_inst_grp} = $count;
		push @used_groups_for_counts, $dashed_inst_grp;
	}

	my $errand_instances = $params_ref->{errand_instances};
	if (defined $errand_instances) { # 0 is a valid value
		my @unconfigured_errands = grep { !exists $counts->{$_} } qw(smoke-tests rotate-cc-database-key);
		$counts->{$_} = $errand_instances for @unconfigured_errands;
	}

	# Check for duplicate instance group counts
	if (@used_groups_for_counts) {
		my @uniq_groups = uniq(@used_groups_for_counts);
		my ($dups) = compare_arrays(\@used_groups_for_counts, \@uniq_groups);
		bail(
			"Instance counts specified (or translated as) multiple times: " . join(", ", @$dups)
		) if scalar(@$dups) > 0;
	}

	# Handle warning messages
	warning(
		"Found the following warnings while processing instance vm types:\n%s",
		join("\n", map {"[[  - >>$_\n"} @warnings)
	) if @warnings;
	return $self->{_memoized_instance_counts} = $counts;
}


sub _dynamic_instance_counts {
	my ($self) = @_;
	my @instance_counts_ops = ();

	my $counts_opsfile_content = "--- # Dynamically created instance counts\n";
	my $count_overrides = $self->_instance_count_overrides();

	for my $dashed_inst_grp (keys %$count_overrides) {
		my $count = $count_overrides->{$dashed_inst_grp};
		$counts_opsfile_content .= $self->_gopatch_replace("/instance_groups/name=$dashed_inst_grp?/instances", $count);
	}


	if (keys %$count_overrides) {
		my $counts_opsfile_path = "operations/dynamic/instance_counts.yml";
		mkfile_or_fail($self->kit->path($counts_opsfile_path), 0644, $counts_opsfile_content);
		push @instance_counts_ops, $counts_opsfile_path;
	}

	return @instance_counts_ops;
}

sub _dynamic_vip_network_support {
	my ($self) = @_;
	debug("Processing VIP network support...");

	my $env = $self->env;
	my $param_vips = $env->lookup('params.vip') || {};
	my $vault_vips = $env->ocfp_config_lookup("public-ips") || {};
	my $vault_path = $env->ocfp_config_base . "public-ips";
	my @vip_ops = ();

	my @supported_types = ('router');
	push @supported_types, 'tcp-router' unless $self->want_feature('no-tcp-routers');
	push @supported_types, 'scheduler' unless $self->want_feature('ssh-proxy-on-routers') || $self->want_feature('ocfp');

	# Check for invalid VIP types
	my $msg = '';
	my @invalid_param_vips = grep {!in_array($_, @supported_types)} keys %$param_vips;
	$msg .= sprintf(
		"Invalid VIP types specified in params.vip: %s\n\n",
		join(", ", @invalid_param_vips)
	) if @invalid_param_vips;

	if ($self->want_feature('ocfp')) {
		# Need to remap vault keys to supported types due to historical reasons
		my %remap = (
			'cf_router' => 'router',
			'cf_tcp_router' => 'tcp-router',
			'cf_scheduler' => 'scheduler',
		);
		for my $key (keys %remap) {
			my $i = 0;
			my $idx_key;
			my @ips = ();
			while (exists $vault_vips->{$idx_key = "${key}_".$i++}) {
				push @ips, delete($vault_vips->{$idx_key});
			}
			$vault_vips->{$remap{$key}} = join(',', @ips) if @ips;
		}
		my @invalid_vault_vips = grep {!in_array($_, @supported_types)} keys %$vault_vips;
		$msg .= sprintf(
			"Invalid VIP types specified in vault: %s\n\n",
			join(", ", @invalid_vault_vips)
		) if @invalid_vault_vips;
	}

	warning(
		"${msg}Supported VIP targets are: %s\n\nThe invalid VIP types will be ignored.",
		join(", ", @supported_types)
	) if $msg;

	foreach my $type (@supported_types) {
		my $public_ips = undef;
		my $source = "";

		if ($self->want_feature("ocfp")) {
			if (exists $vault_vips->{$type}) {
				debug("Found VIP config for $type in vault");
				$public_ips = $vault_vips->{$type};
				$source = $env->vault->has("$vault_path:$type") ? "$vault_path:$type" : "$vault_path:cf_" . ($type =~ s/-/_/gr) . "_[0..n]";
			}
		}

		# Check for params override
		if ($param_vips->{$type}) {
			debug("%s", $self->want_feature('ocfp') && $public_ips
				? "OCFP mode: VIP config for $type overridden by params"
				: "Found VIP config for $type in params"
			);
			$public_ips = $param_vips->{$type};
			$source = "params.vip.$type";
		}

		if ($public_ips) {
			# 		Generate the dynamic overlay fragment
			my $vip_file = $self->_generate_vip_overlay($type, $public_ips, $source);
			push @vip_ops, $vip_file if $vip_file; # Only add if a file was generated

			debug("Generated VIP support for $type: $vip_file");
		}
	}
	return @vip_ops;
}

sub _generate_vip_overlay {
	my ($self, $type, $public_ips, $source) = @_;

	my $instance_count = $self->get_instance_count_for($type);
	return undef unless $instance_count;

	my $available_ips = IPv4->new($public_ips);
	if ($available_ips < $instance_count) {
		bail("Not enough VIPs available for %s (need %d, have %d) from %s -- cannot continue",
			$type, $instance_count, $available_ips->size, $source
		);
	}
	$available_ips = $available_ips->slice($instance_count);

	my $dstdir = 'overlay/dynamic';
	my $vip_file = "$dstdir/vip-for-${type}.yml";
	my $kit_dynamic_dir = $self->kit->path($dstdir);
	mkdir_or_fail($kit_dynamic_dir) unless -d $kit_dynamic_dir;

	my $basename = join('.', $self->env->name, $self->env->type); # FIXME: extract from CloudConfig, move to Hooks

	# Generate YAML content for VIP support
	my $content = <<"YAML";
---
instance_groups:
- name: $type
  networks:
  - default: [gateway, dns]
  - (( append ))
  - name: $basename.net-vip
    static_ips:
YAML
	$content .= sprintf("    - %s\n", $_) for $available_ips->spans;

	mkfile_or_fail($self->kit->path($vip_file), 0644, $content);
	return $vip_file;
}

# }}}
# get_instance_count_for - Get the instance count for a given instance group
sub get_instance_count_for {
	my ($self, $instance_group) = @_;

	# The instance count is determined by the features chosen, but can be
	# overridden by params.  # Not sure if `ocfp` feature should also be able to
	# specify instance counts, but it currently does not.

	# We're going to hardcode the default instance counts for each supported VIP
	# type.  This is a bit of a hack, but it works for now.  We can improve this
	# later if needed.
	my %default_instance_counts = (
		'router'     => 2, # Default instance counts for routers
		'tcp-router' => 2, # Default instance counts for TCP routers
		'scheduler'  => 2, # Default instance counts for schedulers
	);
	my $instance_count_overrides = $self->_instance_count_overrides();
	return $instance_count_overrides->{$instance_group}//$default_instance_counts{$instance_group}//0;
}

# validate_classic_features - Validate and process classic features
sub validate_classic_features {
	my ($self) = @_;

	# This will go through the raw features, validate them, and "mutate" them to accomplish the
	# desired processing flow.  It also checks params for dymnamic features.

	my @valid_features = (
		'bare',
		'partitioned-network',
		'haproxy',
		'tls',
		'self-signed',
		'cflinuxfs3', 'cflinuxfs4',
		'isolation-segments',
		'ssh-proxy-on-routers',
		'no-tcp-routers',
		'blacksmith-integration',
		'trust-blacksmith-ca',
		'app-scheduler-integration',
		'app-autoscaler-integration',
		'prometheus-integration',
		'stratos-integration',
		'scs-integration',
		'uaa-admin-client',
		'windows-diego-cells',
		'vip',

		'nfs-volume-services', 'nfs-ldap', 'nfs-ldap-tls',
		'smb-volume-services',

		# Migration from v1
		'+migrated-v1-env',
		'+override-db-names',
		'v1-vm-types',
		'no-v1-vm-types',
		'v2-nats-credentials',

		# Blobstores:
		'aws-blobstore',   'azure-blobstore',   'gcp-blobstore',
		'minio-blobstore', 'stackit-blobstore',

		# Blobstore support:
		'blobstore-suffix',

		# Databases:
		'local-postgres-db', 'local-mysql-db', 'postgres-db', 'mysql-db',
	);
	push @valid_features, 'aws-blobstore-iam' if $self->iaas eq 'aws';
	push @valid_features, 'gcp-use-access-key' if $self->iaas eq 'gcp';

	# This has already been validated, but we need to account for it # in the valid features list.
	if (my ($upgrade_feature) = grep { m{^cf-deployment-version-(?:.*)$} } @{$self->{raw_features}}) {
		push @valid_features, $upgrade_feature;
	}

	my $enable_service_discovery_resolution = {
		msg => "- automatically enabled in upstream cf-deployment now",
		replace => []
	};

	my %deprecated_features = ( # values: undef - not valid, [] - not needed, [feature,...] - replacement, {params => [xxx]} - moved to params
		'shield-dbs' => {msg => "in favour of BOSH add-ons", replace => []},
		'shield-blobstores' => {msg => "in favour of BOSH add-ons", replace => []},
		'omit-haproxy' => [],
		'local-blobstore' => [],
		'blobstore-webdav' => [],
		'container-routing-integrity' => [],
		'routing-api' => [],
		'loggregator-forwarder-agent' => [],
		'internal-blobstore' => [],
		'blobstore-aws' => ['aws-blobstore'],
		'blobstore-azure' => ['aws-blobstore'],
		'blobstore-gcp' => ['gcp-blobstore'],
		'db-external-mysql' => ['mysql-db'],
		'db-external-postgres' => ['postgres-db'],
		'internal-db' => ['local-postgres-db'],
		'db-internal-postgres' => ['local-postgres-db'],
		'db-internal-mysql' => ['local-mysql-db'],
		'local-db' => ['local-postgres-db'],
		'haproxy-tls' => ['haproxy', 'tls'],
		'haproxy-self-signed' => ['haproxy', 'self-signed'],
		'haproxy-notls' => ['haproxy'],
		'minimum-vms' => 'small-footprint',
		'blacksmith-integration' => ['trust-blacksmith-ca'],

		# Special Case:
		'azure' => {
			msg => "- it will automatically be applied when deploying via an Azure CPI",
			replace => []
		},
		'trust-blacksmith-ca' => {
			msg => "- it will automatically be applied if detected in secrets store",
			replace => []
		},

		'cflinuxfs2' => undef,
		'no-nats-tls' => undef,
		'local-ha-db' => {msg => "Consider using external High Availability databases instead"},
		'autoscaler' => {msg => "Use the 'cf-app-autoscaler' genesis kit"},
		'autoscaler-postgres' => {msg => "Use the 'cf-app-autoscaler' genesis kit"},
		'native-garden-runc' => ['cf-deployment/operations/native-garden-runc-runner'],

		# Service Discovery redundant features
		'app-bosh-dns' => $enable_service_discovery_resolution,
		'dns-service-discovery' => $enable_service_discovery_resolution,
		'enable-service-discovery' => $enable_service_discovery_resolution,
		'cf-deployment/operations/enable-service-discovery' => $enable_service_discovery_resolution,

		# cf-deployment features as named features
		'cf-deployment/operations/enable-smb-volume-service' => ['smb-volume-services'],
		'cf-deployment/operations/enable-nfs-volume-service' => ['nfs-volume-services'],
		'cf-deployment/operations/scale-to-one-az' => ['partitioned-network'],
		'cf-deployment/operations/enable-nfs-ldap' => ['nfs-ldap'],
		'cf-deployment/operations/enable-nfs-ldap-tls' => ['nfs-ldap-tls'],
	);

	$self->validate_features(
		valid_features      => \@valid_features,
		deprecated_features => \%deprecated_features
	);
}

# }}}

# validate_ocfp_features - Validate OCFP features {{{
sub validate_ocfp_features {
	my ($self) = @_;
	# This will go through the raw features, validate them, and "mutate" them to accomplish the
	# desired processing flow.  It also checks params for dymnamic features.
	my @valid_features = (
		'ocfp', # OCFP is the only feature that is always enabled in OCFP environments
		'partitioned-network',
		'small-footprint',
		'source-releases',
		'haproxy',
		'self-signed',
		'cflinuxfs3',
		'isolation-segments',
		'no-tcp-routers',
		'stratos-integration',
		'windows-diego-cells',
		'vip',

		'nfs-volume-services', 'nfs-ldap', 'nfs-ldap-tls',
		'smb-volume-services',

		# Blobstores:
		'+internal-blobstore',

		# Blobstore support:
		'blobstore-suffix',

		# Databases:
		'+internal-db', # FIXME: Maybe allow mysql-db in the future?
	);
	push @valid_features, 'aws-blobstore-iam' if $self->iaas eq 'aws';
	push @valid_features, 'gcp-use-access-key' if $self->iaas eq 'gcp';

	# This has already been validated, but we need to account for it # in the valid features list.
	if (my ($upgrade_feature) = grep { m{^cf-deployment-version-(?:.*)$} } @{$self->{raw_features}}) {
		push @valid_features, $upgrade_feature;
	}

	my $ocfp_included_resolution = {
		msg => "- included as part of OCFP feature",
		replace => []
	};
	my $enable_service_discovery_resolution = {
		msg => "- automatically enabled in upstream cf-deployment now",
		replace => []
	};

	my %deprecated_features = ( # values: undef - not valid, [] - not needed, [feature,...] - replacement, {params => [xxx]} - moved to params
		'tls' => $ocfp_included_resolution,
		'app-scheduler-integration' => $ocfp_included_resolution,
		'app-autoscaler-integration' => $ocfp_included_resolution,
		'prometheus-integration' => $ocfp_included_resolution,
		'scs-integration' => $ocfp_included_resolution,
		'uaa-admin-client' => $ocfp_included_resolution,
		'ssh-proxy-on-routers' => $ocfp_included_resolution,
		'cflinuxfs4' => $ocfp_included_resolution,

		'blacksmith-integration' => {
			msg => "- was never implemented, and Blacksmith CA is now automatically trusted if detected in secrets store",
			replace => []
		},
		'trust-blacksmith-ca' => {
			msg => "- it will be automatically applied if detected in secrets store",
			replace => []
		},
		'compiled-releases' => {
			msg => "- it is the default behaviour in OCFP; to turn it off, use the ".
			"'source-releases' feature",
			replace => []
		},

		'cflinuxfs2' => undef,

		# Service Discovery redundant features
		'enable-service-discovery' => $enable_service_discovery_resolution,
		'cf-deployment/operations/enable-service-discovery' => $enable_service_discovery_resolution,

		# cf-deployment features as named features
		'cf-deployment/operations/enable-smb-volume-service' => ['smb-volume-services'],
		'cf-deployment/operations/enable-nfs-volume-service' => ['nfs-volume-services'],
		'cf-deployment/operations/scale-to-one-az' => ['partitioned-network'],
		'cf-deployment/operations/enable-nfs-ldap' => ['nfs-ldap'],
		'cf-deployment/operations/enable-nfs-ldap-tls' => ['nfs-ldap-tls'],
	);

	$self->validate_features(
		valid_features      => \@valid_features,
		deprecated_features => \%deprecated_features
	);

	# Handle OCFP blobstore selection
	if (!$self->want_feature('+internal-blobstore')) {
		# Add the iaas-specific blobstore feature
		my $type = $self->iaas;
		$type = "minio" if $type eq "vsphere"; # vsphere uses minio blobstore
		if (-f $self->kit->path("overlay/blobstore/${type}.yml")) {
			$self->set_features($self->features, "${type}-blobstore");
		} else {
			bail("OCFP blobstores are not supported on #c{$type} IaaS.");
		}
	}
	# Handle OCFP database selection
	if (!$self->want_feature('+internal-db')) {
		# Add the iaas-specific database feature
		$self->set_features(
			$self->features, 'postgres-db' # FIXME: Postgres is currently the only supported database for OCFP
		);
	}
}

# }}}

sub requested_blobstore {
	my ($self) = @_;

	my @valid_blobstores = qw(
		+internal-blobstore  aws-blobstore  azure-blobstore
		stackit-blobstore    gcp-blobstore  minio-blobstore
	);

	my @requested_blobstores = grep {in_array($_, @valid_blobstores)} $self->features;
	bail(
		"Conflicting blobstore features specified: %s",
		join(", ", @requested_blobstores)
	) if scalar(@requested_blobstores) > 1;
	return $requested_blobstores[0] // '+internal-blobstore';
}
sub requested_database {
	my ($self) = @_;

	my @valid_databases = qw(
		local-postgres-db local-mysql-db mysql-db  postgres-db
	);

	my @requested_databases = grep {in_array($_, @valid_databases)} $self->features;
	bail(
		"Conflicting database features specified: %s",
		join(", ", @requested_databases)
	) if scalar(@requested_databases) > 1;

	push(@requested_databases, 'local-postgres-db') unless scalar(@requested_databases);

	my $is_local = $self->wants_feature('+internal-db') // scalar(grep {$_ =~ /^local-/} @requested_databases);
	return ($requested_databases[0] =~ s/^(?:local-)?(.*?)-db$/$1/r, $is_local);
}

sub enable_external_blobstore {
	my ($self, $feature) = @_;

	my $type = $feature =~ s/-blobstore//r;

	$self->add_files(
		'overlay/blobstore/meta.yml',
		'overlay/blobstore/external.yml'
	);
	$self->add_files_if_exists("overlay/blobstore/${type}.yml");
	$self->add_files('cf-deployment/operations/use-external-blobstore.yml');

	# Add specific operations for each blobstore type
	if ($type eq 'azure') {
		$self->add_files('cf-deployment/operations/use-azure-storage-blobstore.yml');

	} elsif ($type eq 'aws' && $self->want_feature('aws-blobstore-iam')) {
		$self->add_files('overlay/blobstore/aws-iam.yml')

	} elsif ($type eq 'gcp') {
		$self->add_files($self->want_feature('gcp-use-access-key')
			? 'cf-deployment/operations/use-gcs-blobstore-access-key.yml'
			: 'cf-deployment/operations/use-gcs-blobstore-service-account.yml'
		);
	}

	$self->add_files_if_wants('blobstore-suffix',
		"overlay/blobstore-suffix.yml"
	);
	return 1;
}

sub enable_requested_database {
	my ($self, $type, $local) = @_;

	if ($local) {
		# Local database setup
		# RISK: need to fix if we support more than postgress & mysql
		$self->add_files(
			$type eq 'postgres'
				? "cf-deployment/operations/use-postgres.yml"
				: "overlay/db/local-mysql-db.yml"
		);

		if ($self->want_feature('+override-db-names')) {
			$self->add_files_if_exists(
				"operations/db-override-names.yml",
				"operations/db-override-${type}-names.yml",
				"overlay/db/internal-overrides.yml"
			);
			$self->add_files_if_wants('+migrated-v1-env',
				"overlay/addons/migration-db-override-names.yml"
			);
		}
	} else {
		# External database setup
		$self->add_files(
			'cf-deployment/operations/use-external-dbs.yml',
			'operations/use-external-dbs-ports.yml',
			'overlay/db/external.yml',
			"overlay/db/external-${type}.yml"
		);
	}
	return 1;
}

sub enable_nfs_volume_services {
	my ($self) = @_;
	$self->add_files(
		"cf-deployment/operations/enable-nfs-volume-service.yml"
	);
	$self->add_files(
		"overlay/addons/nfs-volume-service.yml"
	) unless $self->want_feature("bare");

	$self->add_files_if_wants(qr/^nfs-ldap(-tls)?$/,
		"cf-deployment/operations/enable-nfs-ldap.yml",
		"overlay/addons/nfs-ldap.yml"
	);

	if ($self->want_feature("nfs-ldap-tls")) {
		$self->add_files("overlay/addons/nfs-ldap-tls.yml");

		# Remove generative variable if user provided custom CA cert
		if ( exists $self->env->params->{"nfs-ldap-ca-cert-ca"} ) {
			my $remove_ops_file = "operations/dynamic/remove-unused-nfs-ldap-ca-cert.yml";
			mkfile_or_fail( $self->kit->path($remove_ops_file), 0644,
				"--- # Remove unused variables\n" .
				$self->_gopatch_remove("/variables/name=nfs-ldap-ca-cert")
			);
			$self->add_files($remove_ops_file);
		}
	}
	return 1;
}

sub enable_windows_diego_cells {
	my ($self, $compiled_releases) = @_;

	$self->add_files(
		"cf-deployment/operations/windows2019-cell.yml",
		"cf-deployment/operations/use-online-windows2019fs.yml",
		"cf-deployment/operations/use-latest-windows2019-stemcell.yml",
	);
	if ($compiled_releases) {
		$self->add_files_if_exists(
			"cf-deployment/operations/use-compiled-releases-windows.yml",
			"overlay/override-releases/compiled-windows.yml"
		);
	} else {
		$self->add_files(
			"overlay/override-releases/source-windows.yml"
		);
	}
	$self->add_files("overlay/windows.yml") unless $self->want_feature("bare");
	return 1;
}

sub _process_common_positional_features {
	my ($self, $feature) = @_;

	# HAProxy and related features
	if ( $feature eq "haproxy" ) {
		$self->add_files("overlay/routing/haproxy.yml");
		$self->add_files(
			'overlay/routing/haproxy-public-network.yml'
		) if $self->env->params->{cf_lb_network};

		if ($self->want_feature("tls") || $self->want_feature('ocfp')) {
			$self->add_files("overlay/routing/haproxy-tls.yml");
			$self->add_files(
				'overlay/routing/haproxy-provided-cert.yml'
			) unless $self->want_feature("self-signed");
		}
		$self->add_files_if_wants('small-footprint',
			"overlay/routing/haproxy-small-footprint.yml"
		);

	} elsif ($feature eq "ssh-proxy-on-routers") {
		$self->add_files("overlay/addons/ssh-proxy-on-routers.yml");

	} elsif ($feature eq "no-tcp-routers") {
		$self->add_files("overlay/addons/no-tcp-routers.yml");

	} elsif ($feature eq "cflinuxfs3") {
		$self->add_files("operations/use-cflinuxfs3.yml");

	# Handle cf-deployment ops files
	} elsif ($feature =~ /^cf-deployment\/operations\//) {
		bail(
			"Invalid cf-deployment operation requested: #c{$feature}"
		) unless -f $self->kit->path("$feature.yml");
		$self->add_files("$feature.yml");

	} else {
		bail("Unknown feature: $feature. Please check your environment file.");
	}

	return 1;
}

sub _add_app_autoscaler_releases {
	my ($self) = @_;
	# If cf-app-autoscaler integration is enabled, we need to dynamically
	# generate a stringified JSON block containing the release versions
	# that the autoscaler needs to be able to work with.
	if ($self->want_feature('app-autoscaler-integration') || $self->want_feature('ocfp')) {
		# Using our list of files, we need to merge them without evaluation,
		# then cherry-pick the releases block.
		my @autoscaler_releases = qw/bosh-dns-aliases routing loggregator-agent bpm/;
		my @spruce_opts = qw/--skip-eval -m --go-patch --fallback-append --cherry-pick releases/;
		my ($out, $rc, $err) = $self->spruce_merge(@spruce_opts,$self->{files}->@*);
		bail(
			"Failed to merge spruce files to determine releases for app-autoscaler integration: %s", $err//$out
		) if $rc;

		# Get the array of releases, and select only the ones we care about
		# for the app-autoscaler integration.
		my $releases = load_yaml($out);
		my @releases = grep {
			my $name = $_->{name};
			in_array($name, @autoscaler_releases);
		} $releases->{releases}->@*;

		# Create a dynamic file containing the array of releases to stuff into exodus data.
		my $file = $self->kit->path("overlay/dynamic/autoscaler-releases.yml");
		save_to_yaml_file({exodus => {app_autoscaler_releases => \@releases}}, $file);
		$self->add_files("overlay/dynamic/autoscaler-releases.yml");
	}
}


sub _instance_group_translations {
	return {
		'cell' => 'diego_cell',
		'diego' => 'scheduler',
		'bbs' => 'diego_api',
		'loggregator' => 'log_api',
		'postgres' => 'database',
		'blobstore' => 'singleton_blobstore',
		'windows_diego_cell' => 'windows2019_cell'
	};
}

sub _is_instance_group {
	return {map {($_,1)} qw{
		api cc-worker credhub database diego-api diego-cell doppler errand haproxy
		log-api log-cache nats rotate-cc-database-key tcp-router scheduler
		singleton-blobstore smoke-tests uaa windows2019-cell
	}};
}

1;
# vim: set ts=2 sw=2 sts=2 noet foldmethod=marker foldlevel=1 nu
