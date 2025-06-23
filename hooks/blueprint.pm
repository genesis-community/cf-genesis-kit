package Genesis::Hook::Blueprint::CF;    # Updated version

use v5.20;
use warnings;                            # Genesis min perl version is 5.20

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib'; }
use parent qw(Genesis::Hook::Blueprint);

use Genesis qw/info warning error bail new_enough run/;
use JSON::PP;
use File::Path qw(remove_tree make_path);
use File::Copy qw(copy);
use IO::Socket::INET;
use Socket qw(AF_INET SOCK_STREAM pack_sockaddr_in inet_aton);
use Archive::Tar;

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');

	# Initialize all state variables needed by the hook
	# $obj->{files} is initialized by parent. We'll use add_files directly.
	$obj->{raw_features}         = [];                    # Store raw features from env
	$obj->{processed_features}   = [];                    # Store curated features
	$obj->{opsfiles_for_ocfp}    = [];                    # Specific for OCFP custom ops files
	$obj->{blobstore_selections} = [];                    # To validate only one blobstore
	$obj->{database_selections}  = [];                    # To validate only one database
	$obj->{abort_flag}           = 0;
	$obj->{warn_flag}            = 0;
	$obj->{db_specified_flag}    = 0;
	$obj->{parsed_params}        = $obj->env->{params};
	$obj->{iaas_name}            = $obj->env->iaas;   # aws, gcp, azure, vsphere, openstack, stackit
	$obj->{iaas_name}            = "gcp" if $obj->{iaas_name} eq "google";
	$obj->{custom_ops_dir}       = "ops";

	if ( $ENV{PREVIOUS_ENV} ) {
		$obj->{custom_ops_dir} = ".genesis/cached/$ENV{PREVIOUS_ENV}/ops";
	}

	return $obj;
}

# Utility methods
sub _gopatch_replace {
	my ( $self, $path, $value ) = @_;
	return "  - type: replace\n    path: ${path}\n    value: ${value}\n";
}

sub _gopatch_remove {
	my ( $self, $path ) = @_;
	return "  - type: remove\n    path: ${path}\n";
}

sub _switch_cf_version {
	my ( $self, $version ) = @_;

	info( { stderr => 1 },
		"", "- #y{Experimental Feature Enabled:} Custom cf-deployment version: $version" );

	my $genesis_root = $self->env->path;
	my $cfd_file     = "$genesis_root/.genesis/kits/addons/cf-deployment-${version}.tar.gz";
	my $cfd_url      = "https://github.com/cloudfoundry/cf-deployment/archive/v${version}.tar.gz";

	if ( !-s $cfd_file ) {
		info(
			{ stderr => 1 },
			"  #i{Fetching cf-deployment-${version} release from cloudfoundry/cf-deployment}",
			"  #i{on github.com}"
		);

		make_path("$genesis_root/.genesis/kits/addons/");

		# Download the file using only core Perl modules
		my $response_code = 0;
		eval {
			# Parse the URL - GitHub URLs are HTTPS
			$cfd_url =~ m{^https://([^/:]+)(?::(\d+))?(.*)$}
			  or die "Invalid URL format";
			my $host = $1;
			my $port = $2 || 443;    # Default HTTPS port
			my $path = $3;

			# Create a temporary file for the download content
			my $tmp_file = "$cfd_file.tmp";

			# Use curl to download the file
			my ( $curl_out, $curl_rc ) =
			  run( { stderr => 0 }, 'curl', '-s', '-o', $tmp_file, '-L', $cfd_url );
			if ( $curl_rc == 0 && -s $tmp_file ) {

				# If successful, move the temp file to the final location
				rename( $tmp_file, $cfd_file ) or die "Cannot rename file: $!";
				$response_code = 200;    # Indicate success
			}
			else {
				die "Failed to download file using curl: $curl_out";
			}
		};

		if ($@) {
			warning("Error downloading file: $@");
			$response_code = 500;
		}

		bail("Failed to download cf-deployment v${version} -- cannot continue")
		  unless $response_code == 200;

		bail("Failed to download cf-deployment v${version} -- cannot continue")
		  unless -s $cfd_file;

		# List the contents of the tar file to verify it's valid
		my ( $tar_output, $tar_rc ) =
		  run( { stderr => 0 }, 'tar', '-ztf', $cfd_file );

		if ( $tar_rc != 0 ) {
			bail("Failed to list contents of cf-deployment v${version} tarball: $tar_output");
		}

		# Extract the top directory name
		my @lines = split( /\n/, $tar_output );
		my %top_dirs;
		foreach my $line (@lines) {
			if ( $line =~ m{^([^/]+)/} ) {
				$top_dirs{$1} = 1;
			}
		}

		my @unique_dirs = keys %top_dirs;
		if ( scalar(@unique_dirs) != 1
			|| $unique_dirs[0] ne "cf-deployment-${version}" )
		{
			bail(
"Downloaded cf-deployment v${version} doesn't look like a valid release -- cannot continue"
			);
		}

		my $topdir = $unique_dirs[0];
	}
	else {
		info( { stderr => 1 }, "  #i{Using cached copy of cf-deployment-${version} release}" );
	}

	# Remove the existing cf-deployment directory
	remove_tree( "./cf-deployment", { error => \my $remove_err } );
	bail( "Failed to remove ./cf-deployment: " . join( ", ", map { $_->{message} } @$remove_err ) )
	  if @$remove_err;

	# Create a new cf-deployment directory
	make_path( "./cf-deployment", { error => \my $create_err } );
	bail( "Failed to create ./cf-deployment: " . join( ", ", map { $_->{message} } @$create_err ) )
	  if @$create_err;

	# Extract the tar.gz file into the cf-deployment directory
	my $tar = Archive::Tar->new;
	$tar->read( $cfd_file, 1 );    # 1 indicates gzip compression
	$tar->extract( { filter => sub { $_[0] =~ s{^[^/]+/}{} } }, "./cf-deployment" );
	print STDERR "\n";
	return;
}

sub _dynamic_isolation_template_render {
	my ( $self, $tmpl, $name ) = @_;
	my $srcdir = 'overlay/dynamic-templates';
	my $dstdir = 'overlay/dynamic';
	my $src    = "$srcdir/isolation-segment-${tmpl}.yml";
	my $dst    = "$dstdir/isolation-segment-${name}-${tmpl}.yml";

	# Ensure the destination directory exists
	make_path($dstdir);

	# Read the source file, replace the placeholder, and write to the destination file
	open my $src_fh, '<', $src or bail("Cannot open source file $src: $!");
	open my $dst_fh, '>', $dst or bail("Cannot open destination file $dst: $!");

	while ( my $line = <$src_fh> ) {
		$line =~ s/\{\{segment-name\}\}/$name/g;
		print $dst_fh $line;
	}

	close $src_fh;
	close $dst_fh;
	return $dst;
}

sub _dynamic_isolation_segments {
	my ($self)          = @_;                       # params_json is $self->{parsed_params}
	my @isolation_files = ();
	my $params_ref      = $self->{parsed_params};

	my @isolation_groups = ();
	if ( exists $params_ref->{isolation_segments}
		&& ref( $params_ref->{isolation_segments} ) eq 'ARRAY' )
	{
		foreach my $segment ( @{ $params_ref->{isolation_segments} } ) {
			if ( exists $segment->{name} ) {
				push @isolation_groups, $segment->{name};
			}
		}
	}
	else {
		return ();
	}

	return () unless @isolation_groups;

	my @iso_seg_merges = ();
	if ( !( $self->want_feature("bare") )
		|| $self->want_feature("partitioned-network") )
	{
		push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-network.yml";
	}
	if ( $self->want_feature("cflinuxfs3") ) {
		push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-cflinuxfs3.yml";
	}
	if ( $self->want_feature("nfs-volume-services") ) {
		push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs.yml";
		if (   $self->want_feature("nfs-ldap")
			|| $self->want_feature("nfs-ldap-tls") )
		{
			push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-nfs-ldap.yml";
			if ( $self->want_feature("nfs-ldap-tls") ) {
				push @iso_seg_merges,
				  "overlay/dynamic-templates/isolation-segment-nfs-ldap-tls.yml";
			}
			if ( $self->want_feature("ocfp") ) {
				push @iso_seg_merges,
				  "overlay/dynamic-templates/isolation-segment-nfs-ldap-ocfp.yml",
				  "ocfp/nfs-ldap-data.yml";
			}
		}
	}
	if ( $self->want_feature("smb-volume-services") ) {
		push @iso_seg_merges, "overlay/dynamic-templates/isolation-segment-smb.yml";
	}
	if ( $self->want_feature("ocfp") ) {
		push @iso_seg_merges, "ocfp/meta.yml";
		if ( $self->want_feature("trust-blacksmith-ca") ) {
			push @iso_seg_merges, "ocfp/trust-blacksmith-ca.yml";
		}
	}

	my $params_json_str = encode_json($params_ref);

	foreach my $group (@isolation_groups) {
		my $additional_trusted_certs_str   = '';
		my @additional_trusted_certs_files = ();
		my $isolation_segments             = decode_json($params_json_str)->{isolation_segments};
		my $has_additional_trusted_certs   = 0;

		foreach my $segment (@$isolation_segments) {
			if ( $segment->{name} eq $group ) {
				$has_additional_trusted_certs =
				  scalar( @{ $segment->{additional_trusted_certs} // [] } ) > 0;
				last;
			}
		}

		if ( $self->want_feature("ocfp") || $has_additional_trusted_certs ) {
			push @additional_trusted_certs_files,
			  $self->_dynamic_isolation_template_render( "additional-trusted-certs", $group );
			if ( $self->want_feature("cflinuxfs3") ) {
				push @additional_trusted_certs_files,
				  $self->_dynamic_isolation_template_render( "additional-trusted-certs-cflinuxfs3",
					$group );
			}
			if ( $self->want_feature("ocfp") ) {
				push @additional_trusted_certs_files,
				  $self->_dynamic_isolation_template_render( "trusted-certs", $group );
			}
		}
		$additional_trusted_certs_str = join( " ", @additional_trusted_certs_files );

		my $dynamic_segment_fragment_file = "overlay/dynamic/isolation-segments-$group.yml";
		my $cmd                           = "spruce merge -m --prune meta";
		$cmd .= " \"overlay/dynamic-templates/isolation-segment.yml\"";
		foreach my $merge_file (@iso_seg_merges) {
			$cmd .= " \"$merge_file\"";
		}
		$cmd .= " $additional_trusted_certs_str"
		  if $additional_trusted_certs_str;

		# Process the JSON to extract segment data
		# First apply sed transformation
		my $sed_transformed = $params_json_str;
		$sed_transformed =~ s/"\(\( */"\(\( defer /g;

		# Then use jq to extract the segment
		my ( $segment_json, $jq_rc, $jq_err ) = run( { stderr => 0 },
			'jq', '--arg', 'v', $group,
			'.isolation_segments[] | select(.name == $v ) | {"meta": .}' );

		if ( $jq_rc != 0 ) {
			bail("Failed to process isolation segment '$group' with jq: $jq_err");
		}

		# Write the transformed JSON to a temp file for jq processing
		my $temp_json_file = $self->env->workpath("temp_segment_$group.json");
		open my $temp_fh, '>', $temp_json_file
		  or bail("Cannot write to $temp_json_file: $!");
		print $temp_fh $sed_transformed;
		close $temp_fh;

		# Re-run jq on the transformed file
		( $segment_json, $jq_rc, $jq_err ) = run(
			{ stderr => 0 },
			'jq', '--arg', 'v', $group,
			'.isolation_segments[] | select(.name == $v ) | {"meta": .}',
			$temp_json_file
		);

		unlink $temp_json_file;

		if ( $jq_rc != 0 ) {
			bail("Failed to process isolation segment '$group' with jq: $jq_err");
		}
		my $append_json = '{"instance_groups": [ "((prepend))", "((defer append))" ]}';

		my $segment_json_file = $self->env->workpath("segment_$group.json");
		my $append_json_file  = $self->env->workpath("append_$group.json");

		open my $fh_seg, '>', $segment_json_file
		  or bail("Cannot write to $segment_json_file: $!");
		print $fh_seg $segment_json;
		close $fh_seg;

		open my $fh_app, '>', $append_json_file
		  or bail("Cannot write to $append_json_file: $!");
		print $fh_app $append_json;
		close $fh_app;

		# Build the command arguments as an array
		my @cmd_parts = (
			'spruce', 'merge', '-m', '--prune', 'meta',
			'overlay/dynamic-templates/isolation-segment.yml'
		);

		foreach my $merge_file (@iso_seg_merges) {
			push @cmd_parts, $merge_file;
		}

		if ($additional_trusted_certs_str) {
			push @cmd_parts, split( ' ', $additional_trusted_certs_str );
		}

		push @cmd_parts, $segment_json_file, $append_json_file;

		# Run spruce merge and capture output
		my ( $spruce_output, $spruce_rc, $spruce_err ) =
		  run( { stderr => 0 }, @cmd_parts );

		if ( $spruce_rc != 0 ) {
			bail("Failed to merge isolation segment '$group' with spruce: $spruce_err");
		}

		# Write the output to the dynamic segment fragment file
		open my $fh_out, '>', $dynamic_segment_fragment_file
		  or bail("Cannot write to $dynamic_segment_fragment_file: $!");
		print $fh_out $spruce_output;
		close $fh_out;

		push @isolation_files, $dynamic_segment_fragment_file;

		$self->_dynamic_isolation_template_render( "dns-sd", $group );
		if (   $self->want_feature("nfs-volume-services")
			&& $self->want_feature("ocfp") )
		{
			$self->_dynamic_isolation_template_render( "nfs-ldap-config", $group );
		}
		unlink $segment_json_file;
		unlink $append_json_file;
	}
	return @isolation_files;
}

sub _dynamic_instance_vm_types {
	my ($self)                   = @_;
	my $params_ref               = $self->{parsed_params};
	my @instance_types_ops       = ();
	my $used_groups_for_vm_types = '';                       # To track for duplicates
	my $types_op_file_content    = "--- # Dynamically created instance type overrides\n";
	my $found_vm_types           = 0;

	foreach my $key ( keys %$params_ref ) {
		if ( $key =~ /^(.*)_vm_type$/ ) {
			$found_vm_types = 1;
			my ( $inst_grp_orig, $type ) = ( $1, $params_ref->{$key} );
			my $inst_grp = $inst_grp_orig;

			if    ( $inst_grp eq 'errand' || $inst_grp eq 'haproxy' ) { next; }
			elsif ( $inst_grp eq 'cell' ) {
				$inst_grp = "diego_cell";
				warning("Translated: params.cell_vm_type => params.diego_cell_vm_type");
			}
			elsif ( $inst_grp eq 'diego' ) {
				$inst_grp = "scheduler";
				warning("Translated: params.diego_vm_type => params.scheduler_vm_type");
			}
			elsif ( $inst_grp eq 'bbs' ) {
				$inst_grp = "diego_api";
				warning("Translated: params.bbs_vm_type => params.diego_api_vm_type");
			}
			elsif ( $inst_grp eq 'loggregator' ) {
				$inst_grp = "log_api";
				warning("Translated: params.loggregator_vm_type => params.log_api_vm_type");
			}
			elsif ( $inst_grp eq 'postgres' ) {
				$inst_grp = "database";
				warning("Translated: params.postgres_vm_type => params.database_vm_type");
			}
			elsif ( $inst_grp eq 'blobstore' ) {
				$inst_grp = "singleton-blobstore";
				warning(
					"Translated: params.blobstore_vm_type => params.singleton_blobstore_vm_type");
			}
			elsif ( $inst_grp eq 'windows_diego_cell' ) {
				$inst_grp = "windows2019-cell";
				warning(
"Translated: params.windows_diego_cell_vm_type => params.windows2019-cell_vm_type"
				);
			}

			my $dashed_inst_grp = $inst_grp;
			$dashed_inst_grp =~ s/_/-/g;

			if ( $dashed_inst_grp !~
/^(api|cc-worker|credhub|database|diego-(api|cell)|doppler|errand|haproxy|windows2019-cell|log-(api|cache)|nats|rotate-cc-database-key|(tcp-)?router|scheduler|singleton-blobstore|smoke-tests|uaa)$/
			  )
			{
				warning(
"Unknown instance group $dashed_inst_grp (from $inst_grp_orig) - this may be bug in your environment files."
				);
			}
			$types_op_file_content .=
			  $self->_gopatch_replace( "/instance_groups/name=$dashed_inst_grp/vm_type", $type );
			$used_groups_for_vm_types .= "$dashed_inst_grp\n";
		}
	}

	my $errand_vm_type = $params_ref->{errand_vm_type} || "";
	if ($errand_vm_type) {
		$found_vm_types = 1;
		foreach my $errand_name (qw(smoke-tests rotate-cc-database-key)) {
			if ( $used_groups_for_vm_types !~ /^$errand_name$/m ) {
				$types_op_file_content .=
				  $self->_gopatch_replace( "/instance_groups/name=$errand_name/vm_type",
					$errand_vm_type );
				$used_groups_for_vm_types .= "$errand_name\n";
			}
		}
	}

	if ($found_vm_types) {
		my %seen = ();
		my @dups = ();
		foreach my $line ( split /\n/, $used_groups_for_vm_types ) {
			next unless $line;
			push @dups, $line if $seen{$line}++;
		}
		if (@dups) {
			bail( "Instance vm types specified (or translated as) multiple times: " .
				  join( ", ", @dups ) );
		}
		my $types_op_file_path = "operations/dynamic/instance_types.yml";
		make_path( "operations/dynamic", { error => \my $err } );
		bail( "Failed to create operations/dynamic directory: " .
			  join( ", ", map { $_->{message} } @$err ) )
		  if @$err;
		open my $fh, '>', $types_op_file_path
		  or bail("Cannot write to $types_op_file_path: $!");
		print $fh $types_op_file_content;
		close $fh;
		push @instance_types_ops, $types_op_file_path;
	}
	return @instance_types_ops;
}

sub _dynamic_instance_counts {
	my ($self)                 = @_;
	my $params_ref             = $self->{parsed_params};
	my @instance_counts_ops    = ();
	my $used_groups_for_counts = '';                       # To track for duplicates

	my $counts_opsfile_content = "--- # Dynamically created instance counts\n";
	my $found_counts           = 0;

	foreach my $key ( keys %$params_ref ) {
		if ( $key =~ /^(.*)_instances$/ ) {
			$found_counts = 1;
			my ( $inst_grp_orig, $count ) = ( $1, $params_ref->{$key} );
			my $inst_grp = $inst_grp_orig;

			# Handle translations
			if ( $inst_grp eq 'errand' || $inst_grp eq 'haproxy' ) {
				next;
			}    # dealt with elsewhere
			elsif ( $inst_grp eq 'cell' ) {
				$inst_grp = "diego_cell";
				warning("Translated: params.cell_instances => params.diego_cell_instances");
			}
			elsif ( $inst_grp eq 'diego' ) {
				$inst_grp = "scheduler";
				warning("Translated: params.diego_instances => params.scheduler_instances");
			}
			elsif ( $inst_grp eq 'bbs' ) {
				$inst_grp = "diego_api";
				warning("Translated: params.bbs_instances => params.diego_api_instances");
			}
			elsif ( $inst_grp eq 'loggregator' ) {
				$inst_grp = "log_api";
				warning("Translated: params.loggregator_instances => params.log_api_instances");
			}
			elsif ( $inst_grp eq 'postgres' ) {
				$inst_grp = "database";
				warning("Translated: params.postgres_instances => params.database_instances");
			}
			elsif ( $inst_grp eq 'blobstore' ) {
				$inst_grp = "singleton-blobstore";
				warning(
					"Translated: params.blobstore_instances => params.singleton_blobstore_instances"
				);
			}
			elsif ( $inst_grp eq 'windows_diego_cell' ) {
				$inst_grp = "windows2019-cell";
				warning(
"Translated: params.windows_diego_cell_instances => params.windows2019-cell_instances"
				);
			}

			my $dashed_inst_grp = $inst_grp;
			$dashed_inst_grp =~ s/_/-/g;

			if ( $dashed_inst_grp !~
/^(api|cc-worker|credhub|database|diego-(api|cell)|doppler|errand|haproxy|log-(api|cache)|nats|windows2019-cell|rotate-cc-database-key|(tcp-)?router|scheduler|singleton-blobstore|smoke-tests|uaa)$/
			  )
			{
				warning(
"Unknown instance group $dashed_inst_grp (from $inst_grp_orig) - this may be bug in your environment files."
				);
			}
			$counts_opsfile_content .=
			  $self->_gopatch_replace( "/instance_groups/name=$dashed_inst_grp?/instances",
				$count );
			$used_groups_for_counts .= "$dashed_inst_grp\n";
		}
	}

	my $errand_instances = $params_ref->{errand_instances} || "";
	if ($errand_instances) {
		$found_counts = 1;
		foreach my $errand_name (qw(smoke-tests rotate-cc-database-key)) {
			if ( $used_groups_for_counts !~ /^$errand_name$/m ) {
				$counts_opsfile_content .=
				  $self->_gopatch_replace( "/instance_groups/name=$errand_name?/instances",
					$errand_instances );
				$used_groups_for_counts .= "$errand_name\n";
			}
		}
	}

	if ($found_counts) {
		my %seen = ();
		my @dups = ();
		foreach my $line ( split /\n/, $used_groups_for_counts ) {
			next unless $line;
			push @dups, $line if $seen{$line}++;
		}
		if (@dups) {
			bail( "Instance counts specified (or translated as) multiple times: " .
				  join( ", ", @dups ) );
		}

		my $counts_opsfile_path = "operations/dynamic/instance_counts.yml";
		make_path( "operations/dynamic", { error => \my $err } );
		bail( "Failed to create operations/dynamic directory: " .
			  join( ", ", map { $_->{message} } @$err ) )
		  if @$err;
		open my $fh, '>', $counts_opsfile_path
		  or bail("Cannot write to $counts_opsfile_path: $!");
		print $fh $counts_opsfile_content;
		close $fh;
		push @instance_counts_ops, $counts_opsfile_path;
	}
	return @instance_counts_ops;
}

sub _perform_feature_pre_validation {
	my ($self) = @_;
	my @curated_features = ();

	for my $want ( @{ $self->{raw_features} } ) {

		# Validate requested features (taken from original validate_features)
		if ( $want =~ /^cf-deployment-version-(.*)$/ ) {

			# already dealt with, but keep it in list for reference if needed
			push @curated_features, $want;
		}
		elsif ( $want =~ /^(shield-dbs|shield-blobstores)$/ ) {
			warning("The #c{$want} feature has been deprecated, in favor of BOSH add-ons");
		}
		elsif ( $want =~
/^(omit-haproxy|local-blobstore|blobstore-webdav|container-routing-integrity|routing-api|loggregator-forwarder-agent)$/
		  )
		{
			warning(
"The #c{$want} feature is now the default behaviour and doesn't need\n\tto be specified in the environment file"
			);
		}
		elsif ( $want =~ /^internal-blobstore$/ ) {
			push @curated_features, "+internal-blobstore"
			  unless $self->want_feature_in_list( "+internal-blobstore", \@curated_features );
		}
		elsif ( $want =~ /^blobstore-(aws|azure|gcp)$/ ) {
			my $iaas = $1;
			warning("The #c{$want} feature has been renamed to #c{$iaas-blobstore}");
			push @curated_features, "$iaas-blobstore";
		}
		elsif ( $want =~ /^db-external-(mysql|postgres)$/ ) {
			my $db_type = $1;
			warning("The #c{$want} flag has been renamed to #c{$db_type-db}");
			push @curated_features, "$db_type-db";
		}
		elsif ( $want =~ /^(internal-db|db-internal-postgres|local-db|\+internal-db)$/ ) {
			push @curated_features, "+internal-db"
			  unless $self->want_feature_in_list( "+internal-db", \@curated_features );
			warning("The #c{$want} flag has been renamed to #c{local-postgres-db}");
			push @curated_features, "local-postgres-db";
			$self->{db_specified_flag} = 1;
		}
		elsif ( $want eq "haproxy-tls" ) {
			warning(
"The #c{haproxy-tls} feature flag has been deprecated.\n\tPlease replace it with the #c{haproxy} and #c{tls} flags."
			);
			push @curated_features, "haproxy", "tls";
		}
		elsif ( $want eq "haproxy-self-signed" ) {
			warning(
"The #c{haproxy-self-signed} feature flag has been deprecated.\n\tPlease replace it with the #c{haproxy} and #c{self-signed} flags."
			);
			push @curated_features, "haproxy", "self-signed";
		}
		elsif ( $want eq "haproxy-notls" ) {
			warning(
"The #c{haproxy-notls} feature flag has been deprecated.\n\tPlease replace it with the #c{haproxy} feature flag.\n\tYou are HIGHLY ENCOURAGED to also add the #c{tls} flag."
			);
			push @curated_features, "haproxy";
		}
		elsif ( $want eq "minimum-vms" ) {
			warning("The 'minimum-vms' feature flag has been renamed to 'small-footprint'");
			push @curated_features, "small-footprint";
		}
		elsif ( $want eq "azure" && $self->{iaas_name} eq "azure" ) {  # only warn if it's redundant
			warning(
"The #c{azure} feature does not have to be specified, as it will automatically be applied when deploying via an Azure CPI"
			);
		}
		elsif ( $want eq "cflinuxfs2" ) {
			bail("The #c{cflinuxfs2} feature is no longer able to be supported.");
		}
		elsif ( $want eq "cflinuxfs3" ) {
			push @curated_features, $want;
		}
		elsif ( $want eq "cflinuxfs4" ) {
			push @curated_features, $want;
		}
		elsif ( $want eq "no-nats-tls" ) {
			bail("The #c{no-nats-tls} feature is no longer able to be supported.");
		}
		elsif ( $want eq "local-ha-db" ) {
			bail(
"The #c{local-ha-db} feature is no longer able to be supported.\n\tConsider using external database for high-availability."
			);
		}
		elsif ( $want =~ /^(autoscaler|autoscaler-postgres)$/ ) {
			bail(
"The #c{$want} feature is no longer embedded in the #c{cf} kit.\n\tPlease see the cf-app-autoscaler genesis kit."
			);
		}
		elsif ( $want eq "native-garden-runc" ) {
			warning(
"The #c{$want} feature is no longer supported; it is replaced by the upstream\n\t#c{cf-deployment/operations/experimental/use-native-garden-runc-runner} feature."
			);
			push @curated_features,
			  "cf-deployment/operations/experimental/use-native-garden-runc-runner";
		}
		elsif ( $want =~ /^(app-bosh-dns|dns-service-discovery)$/ ) {
			warning(
"The #c{$want} feature is no longer supported; it has been replaced by the\n\tupstream #c{cf-deployment/operations/enable-service-discovery} feature."
			);
			push @curated_features, "enable-service-discovery";    # this will be handled below
		}
		elsif ( $want eq "cf-deployment/operations/enable-service-discovery" ) {

			# handled by 'enable-service-discovery' alias
			push @curated_features, "enable-service-discovery"
			  unless $self->want_feature_in_list( "bare", \@curated_features );
		}
		elsif ( $want eq "compiled-releases" ) {
			push @curated_features,
			  "compiled-releases"
			  unless $self->want_feature_in_list( "cf-deployment/operations/use-compiled-releases",
				\@curated_features );
		}
		elsif ( $want =~ /^(small-footprint|cf-deployment\/operations\/scale-to-one-az)$/ ) {
			push @curated_features, "small-footprint"
			  unless $self->want_feature_in_list( "small-footprint", \@curated_features );
		}
		elsif ( $want =~
			/^(nfs-volume-services|cf-deployment\/operations\/enable-nfs-volume-service)$/ )
		{    # Corrected regex
			push @curated_features, "nfs-volume-services"
			  unless $self->want_feature_in_list( "nfs-volume-services", \@curated_features );
		}
		elsif ( $want =~
			/^(smb-volume-services|cf-deployment\/operations\/enable-smb-volume-service)$/ )
		{    # Corrected regex
			push @curated_features, "smb-volume-services"
			  unless $self->want_feature_in_list( "smb-volume-services", \@curated_features );
		}
		elsif ( $want =~ /^(nfs-ldap|nfs-ldap-tls|cf-deployment\/operations\/enable-nfs-ldap)$/ )
		{    # Corrected regex
			if (
				!$self->want_feature_in_list( 'nfs-volume-services', \@curated_features )
				&& !$self->want_feature_in_list(
					"cf-deployment/operations/enable-nfs-volume-service",
					\@curated_features
				)
			  )
			{
				bail(
					"Feature #c{$want} cannot be specified without feature #c{nfs-volume-services}"
				);
			}
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want =~ /^(local-postgres-db|local-mysql-db|mysql-db|postgres-db)$/ ) {
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
			$self->{db_specified_flag} = 1;
		}
		elsif ( $want =~ /^(bare|partitioned-network|haproxy|tls|self-signed|isolation-segments)$/ )
		{
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want =~
			/^(minio-blobstore|aws-blobstore|aws-blobstore-iam|azure-blobstore|gcp-blobstore|stackit-blobstore)$/ )
		{
			if ( $self->want_feature_in_list( "ocfp", \@curated_features ) )
			{    # check against already curated ocfp
				bail(
"Cannot specify blobstore with ocfp feature. \n\tWith ocfp feature blobstore specifies you."
				);
			}
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want eq "gcp-use-access-key" ) {
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want =~ /^(enable-service-discovery|ssh-proxy-on-routers|no-tcp-routers)$/ ) {

	# 'enable-service-discovery' is special, ensure it's added if not bare (handled above via alias)
			if (   $want eq "enable-service-discovery"
				&& $self->want_feature_in_list( "bare", \@curated_features ) )
			{
				# do nothing if bare
			}
			else {
				push @curated_features, $want
				  unless $self->want_feature_in_list( $want, \@curated_features );
			}
		}
		elsif ( $want =~
/^(blacksmith-integration|trust-blacksmith-ca|app-scheduler-integration|app-autoscaler-integration|prometheus-integration|stratos-integration|v2-nats-credentials|scs-integration)$/
		  )
		{
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want eq "windows-diego-cells" ) {
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want =~ /^(\+migrated-v1-env|\+override-db-names)$/ ) {
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want =~ /^(v1-vm-types|no-v1-vm-types)$/ ) {

			# no-op, dealt with elsewhere, but can keep for reference
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want eq "uaa-admin-client" ) {
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want =~ /^(blobstore-suffix|no-blobstore-suffix)$/ ) {
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		elsif ( $want =~ /^cf-deployment\// ) {
			if ( -f "$want.yml" ) {
				push @curated_features, $want
				  unless $self->want_feature_in_list( $want, \@curated_features );
			}
			else {
				bail(
"#c{$want} was not found in upstream files.\n\tSee cf-deployment for valid ops files."
				);
			}
		}
		elsif ( $want eq "ocfp" ) {
			push @curated_features, "enable-service-discovery"
			  unless $self->want_feature_in_list( "enable-service-discovery", \@curated_features )
			  || $self->want_feature_in_list( "bare", \@curated_features );
			push @curated_features, "uaa-admin-client"
			  unless $self->want_feature_in_list( "uaa-admin-client", \@curated_features );
			push @curated_features, $want
			  unless $self->want_feature_in_list( $want, \@curated_features );
		}
		else {
			my $env_root = $self->env->path;
			my $opsdir   = $self->{custom_ops_dir};
			if (   -f "$env_root/${opsdir}/$want.yml"
				|| -f "$env_root/ops/$want.yml" )
			{
				push @curated_features, $want;    # Custom ops file
			}
			else {
				bail("The #c{$want} feature is not supported, see MANUAL.md for valid features.");
			}
		}
	}

	# Handle OCFP blobstore selection (needs curated_features for want_feature("ocfp"))
	if ( $self->want_feature_in_list( "ocfp", \@curated_features ) ) {
		my $iaas                       = $self->{iaas_name};
		my $blobstore_feature_for_ocfp = "";
		if ($self->want_feature_in_list('internal-blobstore', \@curated_features)) {
			# If internal-blobstore is specified, use it for OCFP
			$blobstore_feature_for_ocfp = "internal-blobstore";
		} elsif ( $iaas =~ /^(aws|azure|gcp|stackit)$/ ) {
			$blobstore_feature_for_ocfp = "${iaas}-blobstore";
		} elsif ( $iaas eq "vsphere" ) {
			$blobstore_feature_for_ocfp = "minio-blobstore";
		} elsif ( $iaas =~ /^(openstack)$/ ) {
			$blobstore_feature_for_ocfp = "internal-blobstore";
		} else {
			bail("Blobstores are not supported on #c{${iaas}} yet for OCFP.");
		}
		if ( $blobstore_feature_for_ocfp
			&& !$self->want_feature_in_list( $blobstore_feature_for_ocfp, \@curated_features ) )
		{
			# Check if any other blobstore is specified, which is an error with OCFP.
			# The earlier check for general blobstore with ocfp handles this.
			# Here, we just add the required blobstore if not present.
			my $conflicting_blobstore = 0;
			for my $f (@curated_features) {
				if ( $f =~
/^(minio-blobstore|aws-blobstore|aws-blobstore-iam|azure-blobstore|gcp-blobstore|stackit-blobstore)$/
					&& $f ne $blobstore_feature_for_ocfp )
				{
					$conflicting_blobstore = 1;
					last;
				}
			}
			unless ($conflicting_blobstore) {
				push @curated_features, $blobstore_feature_for_ocfp;
			}
		}
	}

	# Default to local-postgres-db if no DB is specified and not bare
	if (   !$self->{db_specified_flag}
		&& !$self->want_feature_in_list( 'bare', \@curated_features ) )
	{
		my $has_db = 0;
		foreach my $f (@curated_features) {
			if ( $f =~ /^(local-postgres-db|local-mysql-db|mysql-db|postgres-db)$/ ) {
				$has_db = 1;
				last;
			}
		}
		unless ($has_db) {
			push @curated_features, "local-postgres-db";
		}
	}

	$self->{processed_features} = \@curated_features;

	# Check for abort/fail conditions from pre-validation
	if ( $self->{abort_flag} ) {
		bail("#R{Cannot continue} - fix the #C{$ENV{GENESIS_ENVIRONMENT}.yml} file.");
	}

	# Warnings will be displayed at the end.
}

# Helper to check feature in a given list, useful during curation
sub want_feature_in_list {
	my ( $self, $feature_name, $list_ref ) = @_;
	foreach my $f (@$list_ref) {
		return 1 if $f eq $feature_name;
	}
	return 0;
}

sub perform {
	my $self = shift;

	# Store raw features
	$self->{raw_features} = [ $self->features ];    # Get features from env

	# Process CF deployment version early
	my $custom_cf_version = "";
	foreach my $want ( @{ $self->{raw_features} } ) {
		if ( $want =~ /^cf-deployment-version-(.*)$/ ) {
			if ($custom_cf_version) {
				bail("You cannot specify more than one cf-deployment-version-* feature");
			}
			$custom_cf_version = $1;
		}
	}
	if ($custom_cf_version) {
		$self->_switch_cf_version($custom_cf_version);
	}

	# Perform feature pre-validation and curation
	$self->_perform_feature_pre_validation();    # Populates $self->{processed_features}

	# Add base CF deployment files
	$self->add_files( "cf-deployment/cf-deployment.yml",
		"overlay/base.yml", "overlay/upstream_version.yml" );

# ==== Begin Main Feature Processing ====
# (Combines logic from original features_setup, features_v1_check, features_process, features_isos, features_ocfp)

	# --- Minimal injections for Genesis compliance (formerly features_setup part 1) ---
	if (  !$self->want_feature("bare")
		|| $self->want_feature("partitioned-network") )
	{
		$self->add_files("operations/rename-network-and-deployment.yml");
	}
	else {
		$self->add_files("cf-deployment/operations/rename-network-and-deployment.yml");
	}

	# --- Best practices if not bare (formerly features_setup part 2) ---
	if ( !$self->want_feature("bare") ) {
		$self->add_files(
			"overlay/identity.yml",           "overlay/override-app-domains.yml",
			"overlay/ten-year-ca-expiry.yml", "overlay/uaa-branding.yml"
		);

		if ( $self->want_feature("v1-vm-types") ) {
			$self->add_files("overlay/addons/v1-vm-types.yml");
		}

		# AZ handling (formerly features_setup part 3)
		# Note: small-footprint feature also adds scale-to-one-az.yml later
		if (   $self->{iaas_name} eq 'azure'
			|| $self->want_feature("small-footprint")
			|| $self->want_feature("cf-deployment/operations/scale-to-one-az") )
		{
		   # Ensure scale-to-one-az from cf-deployment is added if small-footprint is active
		   # The actual small-footprint feature handling will add its specific ops files.
		   # This ensures the base cf-d scale-to-one-az is present if azure or explicitly requested.
			unless ( $self->want_feature("small-footprint") )
			{    # Avoid double-adding if small-footprint adds it
				$self->add_files("cf-deployment/operations/scale-to-one-az.yml");
			}
			$self->add_files("operations/scale-to-one-az.yml");    # Our overlay for scale-to-one-az
		}
		$self->add_files("operations/custom-azs.yml");

		$self->add_files("overlay/override-releases/static.yml");
	}

	# --- V1 migration checks (formerly features_v1_check) ---
	if (   $self->want_feature("+migrated-v1-env")
		|| $self->want_feature("azure-blobstore")
		|| $self->want_feature('minio-blobstore')
		|| $self->want_feature('aws-blobstore')
		|| $self->want_feature('gcp-blobstore') )
	{
		if ( $self->want_feature('bare') ) {
			bail(
"Cannot have #C{bare} feature when migrating from v1 or using these blobstores in v1 migration context."
			);
		}
		$self->add_files("overlay/blobstore/meta.yml");
	}

	# --- Process each curated feature ---
	my $params_ref = $self->{parsed_params};    # Already parsed in init

	for my $feature ( @{ $self->{processed_features} } ) {

		# Blobstores
		if ( $feature eq "azure-blobstore" ) {
			push @{ $self->{blobstore_selections} }, $feature;
			$self->add_files(
				"overlay/blobstore/external.yml",
				"overlay/blobstore/azure.yml",
				"cf-deployment/operations/use-external-blobstore.yml",
				"cf-deployment/operations/use-azure-storage-blobstore.yml"
			);
		}
		elsif ( $feature =~ /^(aws-blobstore|aws-blobstore-iam)$/ ) {
			push @{ $self->{blobstore_selections} }, $feature;
			$self->add_files(
				"overlay/blobstore/external.yml",
				"overlay/blobstore/aws.yml",
				"cf-deployment/operations/use-external-blobstore.yml"
			);
			if (   $feature eq "aws-blobstore-iam"
				|| $self->want_feature("aws-blobstore-iam") )
			{    # check both original and potentially curated
				$self->add_files("overlay/blobstore/aws-iam.yml");
			}
		}
		elsif ( $feature eq "minio-blobstore" ) {
			push @{ $self->{blobstore_selections} }, $feature;
			$self->add_files(
				"overlay/blobstore/external.yml",
				"overlay/blobstore/minio.yml",
				"cf-deployment/operations/use-external-blobstore.yml"
			);
		}
		elsif ( $feature eq "gcp-blobstore" ) {
			push @{ $self->{blobstore_selections} }, $feature;
			if ( $self->want_feature("gcp-use-access-key") ) {
				$self->add_files(
					"overlay/blobstore/external.yml",
					"cf-deployment/operations/use-external-blobstore.yml",
					"cf-deployment/operations/use-gcs-blobstore-access-key.yml"
				);
			}
			else {
				$self->add_files(
					"overlay/blobstore/external.yml",
					"cf-deployment/operations/use-external-blobstore.yml",
					"cf-deployment/operations/use-gcs-blobstore-service-account.yml"
				);
			}
		}

		# Databases
		elsif ( $feature =~ /^(mysql-db|postgres-db)$/ ) {
			push @{ $self->{database_selections} }, $feature;
			my $db_type = ( $feature =~ s/-db//r );
			$self->add_files(
				"cf-deployment/operations/use-external-dbs.yml",
				"operations/use-external-dbs-ports.yml",
				"overlay/db/external.yml",
				"overlay/db/external-${db_type}.yml"
			);
		}
		elsif ( $feature =~ /^(internal-db|local-postgres-db)$/ ) {
			push @{ $self->{database_selections} }, $feature;
			$self->add_files("cf-deployment/operations/use-postgres.yml");
			if ( $self->want_feature('+override-db-names') ) {
				$self->add_files(
					"operations/db-override-names.yml",
					"operations/db-override-postgres-names.yml",
					"overlay/db/internal-overrides.yml"
				);
				if ( $self->want_feature('+migrated-v1-env') ) {
					$self->add_files("overlay/addons/migration-db-override-names.yml");
				}
			}
		}
		elsif ( $feature eq "local-mysql-db" ) {
			push @{ $self->{database_selections} }, $feature;
			$self->add_files("overlay/db/local-mysql-db.yml");
			if ( $self->want_feature('+override-db-names') ) {
				$self->add_files(
					"operations/db-override-names.yml",
					"operations/db-override-mysql-names.yml",
					"overlay/db/internal-overrides.yml"
				);
				if ( $self->want_feature('+migrated-v1-env') ) {
					$self->add_files("overlay/addons/migration-db-override-names.yml");
				}
			}
		}

		# Other features
		elsif ( $feature eq "compiled-releases" ) {
			$self->add_files( "cf-deployment/operations/use-compiled-releases.yml",
				"overlay/override-releases/compiled.yml" );
		}
		elsif ( $feature eq "small-footprint" ) {

# scale-to-one-az.yml from cf-deployment is added if this feature is present (or azure CPI) by earlier logic
# No specific files to add here beyond what was handled in AZ setup,
# but its presence in want_feature checks is important.
# The operations/scale-to-one-az.yml is already added.
# If there are other ops files specific to small-footprint beyond AZ scaling they would go here.
# Based on original script, scale-to-one-az seems to be the primary effect handled in features_setup.
		}
		elsif ( $feature eq "nfs-volume-services" ) {
			$self->add_files("cf-deployment/operations/enable-nfs-volume-service.yml");
			$self->add_files("overlay/addons/nfs-volume-service.yml")
			  unless $self->want_feature("bare");
			if (   $self->want_feature("nfs-ldap")
				|| $self->want_feature("nfs-ldap-tls") )
			{
				$self->add_files( "cf-deployment/operations/enable-nfs-ldap.yml",
					"overlay/addons/nfs-ldap.yml" );
				if ( $self->want_feature("ocfp") ) {
					$self->add_files("overlay/addons/nfs-ldap-config.yml");
				}
				if ( $self->want_feature("nfs-ldap-tls") ) {
					$self->add_files("overlay/addons/nfs-ldap-tls.yml");
					if ( exists $params_ref->{"nfs-ldap-ca-cert-ca"} ) {
						my $remove_ops_file =
						  "operations/dynamic/remove-unused-nfs-ldap-ca-cert.yml";
						make_path( "operations/dynamic", { error => \my $err } );
						bail( "Failed to create operations/dynamic directory: " .
							  join( ", ", map { $_->{message} } @$err ) )
						  if @$err;
						open my $fh_rem, '>', $remove_ops_file
						  or bail("Cannot write to $remove_ops_file: $!");
						print $fh_rem "--- # Remove unused variables\n";    # Corrected typo
						print $fh_rem $self->_gopatch_remove("/variables/name=nfs-ldap-ca-cert");
						close $fh_rem;
						$self->add_files($remove_ops_file);
					}
				}
			}
		}
		elsif ( $feature eq "smb-volume-services" ) {
			$self->add_files("cf-deployment/operations/enable-smb-volume-service.yml");
			$self->add_files("overlay/addons/smb-volume-service.yml")
			  unless $self->want_feature("bare");
		}
		elsif ( $feature eq "enable-service-discovery" ) {

			# This was potentially added during pre-validation if not bare.
			# If it's in processed_features and not bare, add overlay.
			$self->add_files("overlay/enable-service-discovery.yml")
			  unless $self->want_feature("bare");
		}
		elsif ( $feature eq "trust-blacksmith-ca" ) {
			$self->add_files("overlay/addons/trust-blacksmith-ca.yml");
			if ( $self->want_feature("cflinuxfs3") ) {
				$self->add_files("overlay/addons/trust-blacksmith-ca-cflinuxfs3.yml");
			}

			# ocfp specific part handled in ocfp block
		}
		elsif ( $feature eq "app-autoscaler-integration" ) {
			$self->add_files("overlay/addons/autoscaler.yml");    # ocfp adds this too
		}
		elsif ( $feature eq "app-scheduler-integration" ) {
			$self->add_files("overlay/addons/app-scheduler.yml");    # ocfp adds this too
		}
		elsif ( $feature eq "scs-integration" ) {
			$self->add_files("overlay/addons/scs.yml");              # ocfp adds this too
		}
		elsif ( $feature eq "prometheus-integration" ) {
			$self->add_files("overlay/addons/prometheus.yml");       # ocfp adds this too
		}
		elsif ( $feature eq "stratos-integration" ) {
			$self->add_files("overlay/addons/stratos.yml")
			  ;    # ocfp specific part handled in ocfp block
		}
		elsif ( $feature eq "ssh-proxy-on-routers" ) {
			$self->add_files("overlay/addons/ssh-proxy-on-routers.yml");
		}
		elsif ( $feature eq "no-tcp-routers" ) {
			$self->add_files("overlay/addons/no-tcp-routers.yml");
		}
		elsif ( $feature eq "windows-diego-cells" ) {
			$self->add_files(
				"cf-deployment/operations/windows2019-cell.yml",
				"cf-deployment/operations/use-online-windows2019fs.yml",
				"cf-deployment/operations/use-latest-windows2019-stemcell.yml",
				"overlay/override-releases/static-windows.yml"
			);
			if ( $self->want_feature("compiled-releases") ) {
				$self->add_files(
					"cf-deployment/operations/experimental/use-compiled-releases-windows.yml",
					"overlay/override-releases/compiled-windows.yml" );
			}
			$self->add_files("overlay/windows.yml")
			  unless $self->want_feature("bare");

			# ocfp specific part handled in ocfp block
		}
		elsif ( $feature eq "cflinuxfs3" ) {
			$self->add_files("operations/use-cflinuxfs3.yml");
		}
		elsif ( $feature eq "uaa-admin-client" ) {
			$self->add_files("overlay/addons/uaa-admin-client.yml")
			  ;    # ocfp adds this too if not present
		}
		elsif ( $feature eq "+migrated-v1-env" ) {
			$self->add_files("overlay/addons/migration.yml");
		}
		elsif ( $feature =~ /^cf-deployment\// && -f "$feature.yml" ) {    # Upstream ops files
			$self->add_files("$feature.yml");
		}
		elsif ( $feature eq "haproxy" ) {
			$self->add_files("overlay/routing/haproxy.yml");
			if ( exists $params_ref->{cf_lb_network}
				&& $params_ref->{cf_lb_network} ne "" )
			{
				$self->add_files("overlay/routing/haproxy-public-network.yml");
			}
			if ( $self->want_feature("tls") ) {
				$self->add_files("overlay/routing/haproxy-tls.yml");
				unless ( $self->want_feature("self-signed") ) {
					$self->add_files("overlay/routing/haproxy-provided-cert.yml");
				}
			}
			if ( $self->want_feature("small-footprint") ) {
				$self->add_files("overlay/routing/haproxy-small-footprint.yml");
			}
		}

		# Custom ops files from environment (not OCFP specific yet)
		elsif (-f $self->env->path( $self->{custom_ops_dir} . "/${feature}.yml" )
			|| -f $self->env->path("ops/${feature}.yml") )
		{
			my $ops_file_path =
			  -f $self->env->path( $self->{custom_ops_dir} . "/${feature}.yml" )
			  ? $self->env->path( $self->{custom_ops_dir} . "/${feature}.yml" )
			  : $self->env->path("ops/${feature}.yml");
			if ( $self->want_feature("ocfp") ) {
				push @{ $self->{opsfiles_for_ocfp} }, $ops_file_path;    # Collect for OCFP block
			}
			else {
				$self->add_files($ops_file_path);
			}
		}

		# NOTE: isolation-segments and ocfp are major features often with their own blocks
	}

	# --- Handle blobstore suffix overlays ---
	# Apply blobstore suffix handling if any external blobstore is configured
	my $has_external_blobstore = scalar( @{ $self->{blobstore_selections} } ) > 0;
	my $has_ocfp_external_blobstore = $self->want_feature("ocfp") && !$self->want_feature("internal-blobstore");

	if ( $has_external_blobstore || $has_ocfp_external_blobstore ) {
		# Default is no suffix for new deployments, but can be overridden with features
		if ( $self->want_feature("blobstore-suffix") ) {
			$self->add_files("overlay/blobstore-suffix.yml");
		} else { # Default to no-blobstore-suffix for new behavior
			$self->add_files("overlay/no-blobstore-suffix.yml");
		}
	}

	# --- Isolation Segments (formerly features_isos) ---
	if ( $self->want_feature("isolation-segments") ) {
		$self->add_files("operations/diego-cells-networking.yml");
		my @segment_files = $self->_dynamic_isolation_segments();    # Uses $self->{parsed_params}
		$self->add_files(@segment_files) if @segment_files;
	}

	# --- OCFP Features (formerly features_ocfp) ---
	if ( $self->want_feature("ocfp") ) {
		my $env_scale = $params_ref->{ocfp_env_scale} || "dev";
		$self->add_files(    # These are common additions for OCFP
			"overlay/addons/autoscaler.yml", "overlay/addons/app-scheduler.yml",
			"overlay/addons/scs.yml",        "overlay/addons/prometheus.yml",
		);

		# TODO: Do we need to adjust this for internal (builtin) blobstore?
		#unless ($self->want_feature("internal-blobstore")) {
		$self->add_files("overlay/blobstore/meta.yml");    # For OCFP controlled blobstore
														   #}

		$self->add_files( "ocfp/meta.yml", "ocfp/ocfp.yml" );
		if ( $self->want_feature('trusted-certs') ) {
			$self->add_files("ocfp/trusted-certs-meta.yml", "ocfp/trusted-certs.yml");
			$self->add_files("ocfp/trusted-certs-cflinuxfs3.yml")
			  if ( $self->want_feature('cflinuxfs3') );
			$self->add_files("ocfp/trusted-certs-cflinuxfs4.yml")
			  if ( $self->want_feature('cflinuxfs4') );
		}

		if ( $self->want_feature("local-postgres-db|internal-db|\+internal-db") ) {
			$self->add_files('ocfp/internal-db.yml');
		} else {
			$self->add_files("ocfp/external-db-prep.yml", "ocfp/external-db.yml");
		}

		if ( $self->want_feature("internal-blobstore") ) {
			$self->add_files("ocfp/internal-blobstore.yml");
		} else {
			$self->add_files("ocfp/external-blobstore.yml");
			$self->add_files("ocfp/$self->{iaas_name}/external-blobstore.yml")
				if -f $self->kit->path("ocfp/$self->{iaas_name}/external-blobstore.yml");
		}

		$self->add_files(
			"ocfp/$self->{iaas_name}/ocf.yml",
			"ocfp/$self->{iaas_name}/azs.yml",
		);
		if ( $self->want_feature("windows-diego-cells") ) {
			$self->add_files( "ocfp/$self->{iaas_name}/windows.yml" );
			$self->add_files( "ocfp/trusted-certs-windows.yml" )
			  if ( $self->want_feature('trusted-certs') );
		}
		$self->add_files("ocfp/scale/${env_scale}.yml");

		# OCFP specific feature integrations
		if ( $self->want_feature("stratos-integration") ) {
			$self->add_files("ocfp/stratos.yml");
		}
		if ( $self->want_feature("nfs-volume-services") ) {  # Assumes nfs-ldap implied for ocfp nfs
			$self->add_files( "ocfp/nfs-ldap.yml", "ocfp/nfs-ldap-data.yml" );
		}
		if ( $self->want_feature("smb-volume-services") ) {
			$self->add_files("ocfp/smb-broker.yml");
		}
		if ( $self->want_feature("trust-blacksmith-ca") ) {
			$self->add_files("ocfp/trust-blacksmith-ca.yml");
		}

		# Add custom ops files collected for OCFP
		$self->add_files( @{ $self->{opsfiles_for_ocfp} } )
		  if @{ $self->{opsfiles_for_ocfp} };
	}

	# --- Final Validations and non-bare specific additions ---
	if ( scalar( @{ $self->{blobstore_selections} } ) > 1 ) {
		bail( "Too many blobstores selected; pick only one of: " .
			  join( ", ", @{ $self->{blobstore_selections} } ) );
	}
	if ( scalar( @{ $self->{database_selections} } ) > 1 ) {
		bail( "Too many databases selected; pick only one of: " .
			  join( ", ", @{ $self->{database_selections} } ) );
	}
	if ( $self->want_feature("blobstore-suffix") && $self->want_feature("no-blobstore-suffix") ) {
		bail( "Cannot specify both 'blobstore-suffix' and 'no-blobstore-suffix' features; pick only one." );
	}

	my $has_availability_zones = exists( $params_ref->{availability_zones} );
	my $randomize_az_placement =
	  $params_ref->{randomize_az_placement}
	  ? lc( $params_ref->{randomize_az_placement} )
	  : 'false';    # lc for true/false
	if ( ( $has_availability_zones || $randomize_az_placement eq 'true' )
		&& $self->want_feature("bare") )
	{
		bail(
"#M{params.availability_zones} and #M{params.randomize_az_placement}\n\tare not compatible with feature '#C{bare}'."
		);
	}

	if ( !$self->want_feature("bare") ) {
		if ( $self->want_feature('+migrated-v1-env')
			&& !$self->want_feature('v2-nats-credentials') )
		{
			$self->add_files("overlay/addons/migration-v1-nats-credentials.yml");
		}
		my $skip_ssl_validation =
		  $params_ref->{skip_ssl_validation}
		  ? lc( $params_ref->{skip_ssl_validation} )
		  : '';
		if ( $skip_ssl_validation eq 'false' ) {

			# Ensure this is added if not already by another feature
			unless ( $self->has_file("cf-deployment/operations/stop-skipping-tls-validation.yml") )
			{    # Assuming has_file check
				$self->add_files("cf-deployment/operations/stop-skipping-tls-validation.yml")
				  ;    # Added .yml
			}
		}
		if ( scalar( @{ $self->{database_selections} } ) == 0 )
		{              # If still no DB after defaults in pre-val
				# This case should be covered by default DB logic in pre-validation if not bare.
				# Re-affirming use-postgres if somehow no DB was selected and not bare.
			$self->add_files("cf-deployment/operations/use-postgres.yml");
		}

		# IaaS peculiarities
		if ( $self->{iaas_name} eq 'azure' ) {
			if ( ( $has_availability_zones || $randomize_az_placement eq 'true' ) )
			{    # Stricter check for azure
				bail(
"#M{params.availability_zones} and #M{params.randomize_az_placement} are\n\tnot compatible with deployments to Azure infrastructure."
				);
			}
			$self->add_files( "cf-deployment/operations/azure.yml",
				"overlay/azure_availability_sets.yml" );
		}
		elsif ( $self->{iaas_name} eq 'warden' ) {
			$self->add_files("cf-deployment/operations/bosh-lite.yml");
		}

		# Dynamic instance counts and VM types
		my @vm_type_ops = $self->_dynamic_instance_vm_types();
		$self->add_files(@vm_type_ops) if @vm_type_ops;
		my @count_ops = $self->_dynamic_instance_counts();
		$self->add_files(@count_ops) if @count_ops;
	}

	# Exodus migration fragments
	my $exodus_version = $self->env->exodus_lookup( "kit_version", "" );    # Use $self->env
	if ( $exodus_version && !new_enough( $exodus_version, "2.0.0-rc0" ) ) {
		$self->add_files("operations/migrate/cells.yml");
		if ( $self->want_feature("local-postgres-db") ) {
			$self->add_files("operations/migrate/postgres.yml");
		}
	}

	# Display warnings if any occurred
	if ( $self->{warn_flag} ) {
		warning( { stderr => 1 },
			"\n#Y{[INFO]} Adjust your #C{$ENV{GENESIS_ENVIRONMENT}.yml} file to remove warnings." );
	}

	return $self->done();
}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
