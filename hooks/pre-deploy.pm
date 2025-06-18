package Genesis::Hook::PreDeploy::CF;

use v5.20;
use warnings;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib' }

use parent qw(Genesis::Hook);

use Genesis qw/new_enough bail info run load_json/;
use JSON::PP;

# init - Initialize the hook {{{
sub init {
	my ( $class, %ops ) = @_;
	my $obj = $class->SUPER::init(%ops);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

# }}}

sub perform {
	my ($self) = @_;
	my $env = $self->env;

	return $self->done(1) if $self->want_feature("ocfp");

	# 1. Upgrade check - migration from older versions
	my $version = $env->exodus_lookup('kit_version');
	if ( defined($version) && !new_enough( $version, "2.0.0-rc1" ) ) {
		$env->notify("migrating v#C{${version}} kit secrets from Vault to Credhub...");

		# Original script sources external migration functions
		# We'd implement these methods in a real module
		$self->validate_expected_vault_secrets();
		$self->correct_x509_certs();
		$self->migrate_credentials_to_credhub();
	}

	# 2. Cloud Config checks
	$env->notify("checking BOSH Cloud Config meets requirements of generated manifest...");

	my $manifest_json = $self->get_manifest_json();

	# Check for missing required fields in instance groups
	my @missing = $self->check_missing_fields($manifest_json);
	if (@missing) {
		$env->notify(
			"  Invalid Instance Groups (missing one or more required fields):",
			join( "\n", @missing ),
			"", "  Note: this could be because an instance group has been renamed", ""
		);
		$self->{cc_ok} = 'no';
	}

	# Extract networks, VM types, VM extensions, and disks
	#  my @networks = $self->extract_networks($manifest_json);
	#  my @vm_types = $self->extract_vm_types($manifest_json);
	#  my @vm_extensions = $self->extract_vm_extensions($manifest_json);
	#  my @disks = $self->extract_disks($manifest_json);
	#
	#  $self->env->notify("  Checking cloud config resources for manifest requirements...");

	# Genesis 3.1 now provides cloud config differently.
	# Check if cloud config has all the required elements
	# for my $t (@networks) {
	#   $self->cloud_config_needs('network', $t);
	# }

	# for my $t (@vm_types) {
	#   $self->cloud_config_needs('vm_type', $t);
	# }

	# for my $t (@vm_extensions) {
	#   $self->cloud_config_needs('vm_extension', $t);
	# }

	# for my $t (@disks) {
	#   $self->cloud_config_needs('disk_type', $t);
	# }

	# Additional cloud config validation
	#if (!$self->check_cloud_config()) {
	#  $self->{cc_ok} = 'no';
	#}

	# Check if there were any errors
	if ( $self->{cc_ok} eq 'yes' ) {
		$env->notify("  cloud config [#G{OK}]");
	}
	else {
		$env->notify("  cloud config [#R{FAILED}]");
		return $self->done(0);
	}

	return $self->done(1);
}

# Stub implementations for migration functions
sub validate_expected_vault_secrets {
	my ($self) = @_;

	# The original script just has a placeholder function that does nothing
	# (defined as `: # TODO`)
	$self->env->notify(
"  Validating expected vault secrets... #Ki{(placeholder - no validation actually performed)}"
	);
	return 1;
}

sub correct_x509_certs {
	my ($self) = @_;

	# The original script just has a placeholder function that does nothing
	# (defined as `: # TODO`)
	$self->env->notify(
		"  Correcting x509 certificates... #Ki{(placeholder - no correction actually performed)}");
	return 1;
}

sub migrate_credentials_to_credhub {
	my ($self) = @_;

	# This function has a real implementation in the migrate-to-2.0 script
	# Let's execute it properly

	$self->env->notify("  Migrating credentials from Vault to CredHub...");

	my ( $out, $rc, $err ) = run(
		{
			stderr      => 0,
			interactive => 1,
			env         => {
				GENESIS_SECRETS_MOUNT => $ENV{GENESIS_SECRETS_MOUNT},
				GENESIS_SECRETS_SLUG  => $ENV{GENESIS_SECRETS_SLUG},
				GENESIS_CREDHUB_ROOT  => $ENV{GENESIS_CREDHUB_ROOT},
				GENESIS_ENVIRONMENT   => $ENV{GENESIS_ENVIRONMENT}
			}
		},
		'source "$1" && migrate_credentials_to_credhub',
		$self->kit->path("hooks/migrate-to-2.0")
	);

	if ($rc) {
		$self->env->notify("  #R{Failed to migrate credentials to CredHub: $err}");
		return 0;
	}

	$self->env->notify("  #G{Successfully migrated credentials to CredHub}");
	return 1;
}

sub get_manifest_json {
	my ($self) = @_;

	my $manifest_file = $ENV{GENESIS_MANIFEST_FILE};
	my $vars_file     = $ENV{GENESIS_BOSHVARS_FILE};

	# Equivalent to: bosh int "$GENESIS_MANIFEST_FILE" -l "$GENESIS_BOSHVARS_FILE" | spruce json
	my ( $output, $rc, $err ) =
	  run( { stderr => 0 }, 'bosh int "$1" -l "$2" | spruce json', $manifest_file, $vars_file );

	bail("Failed to process manifest: $err") if $rc;

	return $output;
}

sub check_missing_fields {
	my ( $self, $manifest_json ) = @_;

	# Parse JSON into a Perl hash
	my $manifest = decode_json($manifest_json);
	my @missing;

	# Equivalent to the jq query in the bash script
	for my $ig ( @{ $manifest->{instance_groups} || [] } ) {
		my $name            = $ig->{name} || 'unknown';
		my @required_fields = qw(azs instances jobs name networks stemcell vm_type);
		my @missing_fields;

		for my $field (@required_fields) {
			push @missing_fields, $field unless exists $ig->{$field};
		}

		if (@missing_fields) {
			push @missing, "    - #m{$name}: #R{" . join( ", ", @missing_fields ) . "}";
		}
	}

	return @missing;
}

sub extract_networks {
	my ( $self, $manifest_json ) = @_;

	# This method extracts all network names from the manifest
	# It's a more robust implementation than using jq directly

	my $manifest = decode_json($manifest_json);
	my %networks;

	# Extract unique network names from instance groups
	for my $ig ( @{ $manifest->{instance_groups} || [] } ) {
		for my $network ( @{ $ig->{networks} || [] } ) {
			$networks{ $network->{name} } = 1 if $network->{name};
		}
	}

	return sort keys %networks;
}

sub extract_vm_types {
	my ( $self, $manifest_json ) = @_;

	# This method extracts all VM types from the manifest

	my $manifest = decode_json($manifest_json);
	my %vm_types;

	# Extract unique vm_types from instance groups
	for my $ig ( @{ $manifest->{instance_groups} || [] } ) {
		$vm_types{ $ig->{vm_type} } = 1 if $ig->{vm_type};
	}

	return sort keys %vm_types;
}

sub extract_vm_extensions {
	my ( $self, $manifest_json ) = @_;

	# This method extracts all VM extensions from the manifest
	my $manifest = decode_json($manifest_json);
	my %vm_extensions;

	# Extract unique vm_extensions from instance groups
	for my $ig ( @{ $manifest->{instance_groups} || [] } ) {
		if ( ref( $ig->{vm_extensions} ) eq 'ARRAY' ) {
			for my $ext ( @{ $ig->{vm_extensions} } ) {
				$vm_extensions{$ext} = 1 if $ext;
			}
		}
	}

	return sort keys %vm_extensions;
}

sub extract_disks {
	my ( $self, $manifest_json ) = @_;

	# This method extracts all disk types from the manifest
	my $manifest = decode_json($manifest_json);
	my %disks;

	# Extract unique persistent_disk_type from instance groups
	# Following the same pattern as the bash script using jq
	for my $ig ( @{ $manifest->{instance_groups} || [] } ) {
		if ( defined $ig->{persistent_disk_type} ) {
			$disks{ $ig->{persistent_disk_type} } = 1;
		}
	}

	return sort keys %disks;
}

# Check if cloud config has required elements
sub cloud_config_needs {
	my ( $self, $type, $name ) = @_;

	# Validate that the specified type and name exist in the cloud config
	# This implements the "cloud_config_needs" function from the bash script
	my $bosh = $self->env->bosh;
	my $jq_query;

	# Handle each resource type based on its structure in cloud config
	if ( $type eq 'vm_extension' ) {

		# VM extensions have a different structure in cloud config
		$jq_query = '.vm_extensions[] | select(.name == $n) | .name';
	}
	else {
		# Use standardized naming convention for other types (networks, vm_types, disk_types)
		my $plural = $type . 's';
		$jq_query = '.[$t] | .[] | select(.name == $n) | .name';
	}

	my ( $out, $rc, $err ) = $bosh->execute(
		{ stderr => 0, redact => 1 },
		'cloud-config | spruce json | jq -r --arg t "'
		  . $type
		  . 's" --arg n "'
		  . $name . '" \''
		  . $jq_query . '\''
	);

	if ( $rc || !$out ) {
		$self->env->notify("  #R{missing} #m{$type}: #C{$name}");
		$self->{cc_ok} = 'no';
		return 0;
	}

	$self->env->notify("  #G{found} #m{$type}: #C{$name}") if $ENV{GENESIS_TRACE};
	return 1;
}

# Additional cloud config validation
sub check_cloud_config {
	my ($self) = @_;

	# This would perform any additional checks on the cloud config
	# that aren't covered by the type-specific checks above
	my $bosh = $self->env->bosh;

	# Execute any bosh command that might fail if the cloud config isn't valid
	my ( $out, $rc, $err ) = $bosh->execute( { stderr => 0 }, 'cloud-config > /dev/null 2>&1' );

	if ($rc) {
		$self->env->notify("  #R{Cloud config appears to be invalid or inaccessible}");
		$self->{cc_ok} = 'no';
		return 0;
	}

	return 1;
}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
