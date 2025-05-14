#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::CF::Check v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/info bail new_enough/;
use parent qw(Genesis::Hook);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	$obj->{min_version} = "2.7.0";
	$obj->{checks} = {
		cloud_config => 'yes',
		runtime_config => 'yes',
		environment => 'yes'
	};
	$obj->{retired_params} = [
		'api_domain', 'default_app_memory', 'default_app_disk_in_mb',
		'default_stack', 'uaa_lockout_failure_count',
		'uaa_lockout_window', 'uaa_lockout_time', 'uaa_refresh_token_validity',
		'grootfs_reserved_space', 'vm_strategy', 'max_log_lines_per_second'
	];
	return $obj;
}

sub perform {
	my ($self) = @_;

	# Genesis version check
	my $genesis_version = $Genesis::VERSION;
	if ($genesis_version !~ /-dev$/ && !new_enough($genesis_version, $self->{min_version})) {
		error(
			"\n#R{[ERROR]} This kit needs Genesis %s. Please upgrade before continuing\n",
			$self->{min_version}
		);
		return $self->done(0);
	}

	# Run all component checks
	$self->check_cloud_config();
	$self->check_runtime_config();
	$self->check_environment();

	# Return overall status
	my $success = !($self->{checks}{cloud_config} eq 'no' ||
		$self->{checks}{runtime_config} eq 'no' ||
		$self->{checks}{environment} eq 'no');

	return $self->done($success);
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

	if ($self->env->has_config('cloud')) {
		info("  cloud config [#G{OK}]");
	} else {
		info("  cloud config [#R{MISSING}]");
		$self->{checks}{cloud_config} = 'no';
	}
}

sub check_runtime_config {
	my ($self) = @_;
	my $runtime_ok = 'yes';

	my $file = $self->env->config_file('runtime');
	if (!$file) {
		info("  runtime config [#R{MISSING}]");
		$self->{checks}{runtime_config} = 'no';
		return;
	}
	# TODO? wrap in an eval block to catch errors
	my $rtc = $self->env->config_contents('object', 'runtime');

	my ($bosh_dns_job, @more_bosh_dns_jobs) = map {
		my @jobs = $_->{jobs}->@*;
		grep {$_->{name} eq 'bosh-dns'} @jobs
	} $rtc->{addons}->@*;

	my @errors = ();
	if (@more_bosh_dns_jobs) {
		push @errors, 
			"There are multiple BOSH DNS jobs in the runtime-config, which is not ".
			"allowed.  Please remove all but one of them.";
		$runtime_ok = 'no';
	} elsif (!defined($bosh_dns_job)) {
		push @errors,
			"There is no BOSH DNS job in the runtime-config, which is required.  ".
			"Please add one.  Refer to #G{". $self->env->get_call_path_with_env.
			" man} for more info.";
		$runtime_ok = 'no';
	}

	if ($runtime_ok eq 'yes') {
		info("  runtime config [#G{OK}]");
	} else {
		error(
			"\n  Errors were found in the runtime config(s):%s\n\n",
			join("\n[[    - >>", ''.@errors)
		);
		info("  runtime config [#R{FAILED}]");
	}

	$self->{checks}{runtime_config} = $runtime_ok;
}

sub check_environment {
	my ($self) = @_;
	my $env_ok = 'yes';

	# Check kit version for upgrades
	my $version = '';
	eval { $version = $self->env->exodus_lookup('kit_version'); };

	if ($version) {
		if (!new_enough($version, "2.0.0-rc0")) {
			info("\n  #C{[Checking Upgrade from %s]}", $version);

			if (!new_enough($version, "1.10.1")) {
				info("    #R{[ERROR]} Please upgrade to at least cf kit 1.10.1 before upgrading to v2.x.x");
				$env_ok = 'no';
			} else {
				# TODO: Check if safe secrets are present to be imported by migration hook
			}
		}
	}

	# Check for retired parameters
	my @retired_params_found = ();
	foreach my $param (@{$self->{retired_params}}) {
		if ($self->env->defines("params.$param")) {
			push @retired_params_found, "  - #R{params.$param}";
			unless ($ENV{GENESIS_IGNORE_RETIRED_PARAMS} =~ /^(y|yes|1|true)$/i) {
				$env_ok = 'no';
			}
		}
	}

	if (@retired_params_found) {
		info(
			"Using the following retired parameters -- see #g{genesis man %s} to resolve:\n%s",
			$ENV{GENESIS_ENVIRONMENT},
			join("\n", @retired_params_found)
		);
	}

	if ($env_ok eq 'yes') {
		info("  environment files [#G{OK}]");
	} else {
		info("  environment files [#R{FAILED}]");
	}

	$self->{checks}{environment} = $env_ok;
}

1;
