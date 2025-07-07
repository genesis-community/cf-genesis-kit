package Genesis::Hook::CF::Check;

use v5.20;
use warnings;    # Genesis min perl version is 5.20
use Genesis qw/info error bail new_enough/;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . './.genesis/lib' }

use parent qw(Genesis::Hook::Check);

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

sub perform {
	my ($self) = @_;

	my $ok = 1;

	# Run all component checks
	$ok = 0 unless $self->check_version_compatibility();
	$ok = 0 unless $self->check_cloud_config();
	$ok = 0 unless $self->check_runtime_config();
	$ok = 0 unless $self->check_environment();

	return $self->done($ok);
}

sub check_cloud_config {
	my ($self) = @_;

	# For now, we're just going to check that there is a cloud config, but
	# ideally we should check that the cloud config contains all the required
	# properties for this deployment.
	#
	# DISCUSS: Since we now generate the cloud config from the kit, and genesis
	# is responsible for uploading it at deployment time, do we even need to
	# check for the cloud config or validate its contents?

	$self->start_check('cloud-config');
	return $self->check_result( 'cloud-config', 'skipped', 'OCFP env manages its own cloud-config' )
	  if $self->is_ocfp;
	return $self->check_result( 'cloud-config', 'failed', 'no cloud config found' )
	  unless $self->env->has_config('cloud');
	return $self->check_result('cloud-config');
}

sub check_runtime_config {
	my ($self) = @_;

	$self->start_check('runtime-config');

	return $self->check_result( 'runtime-config', 'failed', 'no runtime config found' )
	  unless $self->env->has_config('runtime');

	$self->has_entry( 'runtime-config', 'job', 'bosh-dns' );
	$self->has_entry( 'runtime-config', 'job', 'toolbelt' );

	#FIXME: Need to ensure the job is for the target stemcell os
	return $self->check_result('runtime-config');
}

# TODO: How to handle not yet deployed?
sub check_version_compatibility {
	my ($self) = @_;
	return 1 unless keys $self->exodus_data->%*;
	my $last_version = $self->exodus_data->{kit_id};
	if ($last_version) {
		$last_version = $self->exodus_data->{kit_id} =~ m{ / (\d+\.\d+\.\d+(?:-rc\.?\d+))};
	}
	elsif ( $last_version = $self->exodus_data->{kit_version} ) {
		if ( $last_version =~ m{(\d+\.\d+\.\d+(?:-rc\.?\d+)?)} ) {
			$last_version = $1;
		}
		else {
			return 1;    # probably a dev version or `latest`
		}
	}
	else {
		bail(
'Previous deploy detected, but cannot determine version - please deploy with v1.10.5 or manually confirm the kit version in exodus'
		);
	}

	if ( !new_enough( $last_version, "2.0.0-rc0" ) ) {
		$self->start_check('version upgrade compatibility');
		if ( !new_enough( $last_version, "1.10.1" ) ) {
			return $self->check_result( 'version upgrade compatibility',
				'failed', 'please upgrade to at least cf kit 1.10.1 before upgrading to v2.x.x' );
		}
	}
	return 1;
}

sub check_environment {
	my ($self) = @_;

	$self->start_check('environment');
	my $retired_params = [
		'api_domain',                'default_app_memory',
		'default_app_disk_in_mb',    'default_stack',
		'uaa_lockout_failure_count', 'uaa_lockout_window',
		'uaa_lockout_time',          'uaa_refresh_token_validity',
		'grootfs_reserved_space',    'vm_strategy',
		'max_log_lines_per_second'
	];

	# Check for retired parameters
	my @retired_params_found = ();
	foreach my $param (@$retired_params) {
		$self->has_entry( 'environment', 'params', $param, retired => 1 )
			if ( $self->env->defines("params.$param") );
	}

	# Can't use params availability_zones or randomize_az_placement if using bare feature
	if ($self->want_feature('bare')) {
		$self->has_entry('environment', 'params', 'availability_zones',
			retired => 1, msg => 'availability_zones is not supported with bare feature'
		);
		$self->has_entry('environment', 'params', 'randomize_az_placement',
			retired => 1, msg => 'randomize_az_placement is not supported with bare feature'
		);
	}

	return $self->check_result('environment');
}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
