#!/usr/bin/env perl
# Coverage for the system_metrics build of hooks/runtime-config.pm.
#
# The runtime config extends the loggr-system-metrics-agent addon to every
# other deployment on the director, and the agent needs the system_metrics
# certificate that upstream's add-system-metrics-agent ops file has the
# director generate in CredHub for the cf deployment. The hook must name
# that variable by its absolute CredHub path, so the director fills it in
# when it deploys each VM, and must never read the certificate or key out
# of exodus data or put the values in the config itself.
#
# Requires the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib,
# and spruce on PATH. `make t` sets GENESIS_LIB for you.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/runtime-config.pm";

package MockCredhub;
sub base { '/lab-bosh/lab-cf/' }

package MockEnv;
sub new { my ($c, %a) = @_; bless {%a}, $c }
sub name { 'lab' }
sub credhub { bless {}, 'MockCredhub' }
sub manifest_lookup {
	my ($s, $key, $default) = @_;
	return exists $s->{manifest}{$key} ? $s->{manifest}{$key} : $default;
}
sub exodus_lookup { push @main::EXODUS_READS, $_[1]; return $_[2] }

package main;

our @EXODUS_READS;
my @warned;
{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*Genesis::Hook::RuntimeConfig::CF::deployed    = sub { 1 };
	*Genesis::Hook::RuntimeConfig::CF::env         = sub { $_[0]->{env_obj} };
	*Genesis::Hook::RuntimeConfig::CF::exodus_data = sub { push @EXODUS_READS, '.'; {} };
	*Genesis::Hook::RuntimeConfig::CF::_get_exodus_secret = sub { push @EXODUS_READS, $_[1]; 'leaked' };
	*Genesis::Hook::RuntimeConfig::CF::warning     = sub { push @warned, sprintf(shift, @_) };
}

my $release = {
	name    => 'system-metrics',
	version => '3.0.35',
	url     => 'https://bosh.io/d/github.com/cloudfoundry/system-metrics-release?v=3.0.35',
	sha1    => 'sha256:b929a91315bfe60586d35f5fc95ec94c8ec3283f510736ac99cd45c254cdcfcb',
};

sub build {
	my (%manifest) = @_;
	return bless {
		env_obj         => MockEnv->new(manifest => \%manifest),
		request_options => { system_metrics => { params => { excluded_deployments => ['blacksmith'] } } },
	}, 'Genesis::Hook::RuntimeConfig::CF';
}

subtest 'the agent certificate comes from the cf deployment CredHub variable' => sub {
	@EXODUS_READS = ();
	my $self = build(
		'variables.system_metrics' => { name => 'system_metrics', type => 'certificate' },
		'releases.system-metrics'  => $release,
	);
	my ($out, $status, $msg) = $self->build_system_metrics_runtime;
	ok(!defined($status) || $status ne 'skipped', 'the build is not skipped')
		or diag($msg);
	like($out // '', qr{ca_cert: \(\(/lab-bosh/lab-cf/system_metrics\.ca\)\)},
		'ca_cert names the CredHub CA');
	like($out // '', qr{cert: \(\(/lab-bosh/lab-cf/system_metrics\.certificate\)\)},
		'cert names the CredHub certificate');
	like($out // '', qr{key: \(\(/lab-bosh/lab-cf/system_metrics\.private_key\)\)},
		'key names the CredHub private key');
	like($out // '', qr{- lab-cf\b}, 'the cf deployment is excluded');
	like($out // '', qr{- lab-blacksmith\b}, 'requested deployments are excluded');
	like($out // '', qr{name: system-metrics\b.*version: 3\.0\.35}s,
		'the release comes from the cf manifest');
	is_deeply(\@EXODUS_READS, [], 'nothing is read from exodus data');
};

subtest 'a cf deployment without the system metrics addon is skipped' => sub {
	@EXODUS_READS = ();
	my $self = build();
	my ($out, $status, $msg) = $self->build_system_metrics_runtime;
	is($status, 'skipped', 'the build is skipped');
	like($msg // '', qr{add-system-metrics-agent}, 'the reason names the upstream ops file');
	is_deeply(\@EXODUS_READS, [], 'nothing is read from exodus data');
};

done_testing;
