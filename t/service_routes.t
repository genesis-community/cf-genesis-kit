#!/usr/bin/env perl
# Unit-level coverage for Genesis::Hook::Blueprint::CF::_generate_service_routes_ops.
#
# This bypasses the spec/ testkit (full-env rendering, currently broken at
# HEAD by an unrelated genesis v3.2.0 haproxy_ips validation issue -- see
# .superpowers/sdd/final-review-cfkit-report.md triage item 5) and instead
# calls the sub directly against a minimal mock $self, so it can validate
# hook logic without a working end-to-end blueprint render.
#
# Requires the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib,
# same as hooks/blueprint.pm itself expects (see its "Only needed for
# development" BEGIN block).

use v5.20;
use warnings;
use FindBin;
use Test::More;
use File::Temp qw/tempdir/;

require "$FindBin::Bin/../hooks/blueprint.pm";

# --- minimal mocks -----------------------------------------------------------

package MockEnv;
sub new { my ($c, %a) = @_; bless {%a}, $c }
sub lookup { my ($s, $k, $d) = @_; return $s->{lookups}{$k} // $d }

package main;

my $kit_root = tempdir(CLEANUP => 1);

sub build_self {
	my (%opts) = @_;
	my $routes = $opts{routes} // [];
	my %features = map { ($_ => 1) } @{ $opts{features} // ['haproxy', 'self-signed'] };

	my $env = MockEnv->new(lookups => {
		'params.ocfp_haproxy_service_routes' => $routes,
	});

	return bless {
		env_obj      => $env,
		kit_root     => $kit_root,
		feature_flags => \%features,
	}, 'Genesis::Hook::Blueprint::CF';
}

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*Genesis::Hook::Blueprint::CF::env = sub { $_[0]->{env_obj} };
	*Genesis::Hook::Blueprint::CF::want_feature = sub { $_[0]->{feature_flags}{$_[1]} };
	*Genesis::Hook::Blueprint::CF::kit = sub { $_[0] }; # kit() and path() combined below
	*Genesis::Hook::Blueprint::CF::path = sub { my ($s, $p) = @_; return "$s->{kit_root}/$p" };
}

sub generated_content {
	my ($self, $relpath) = @_;
	open(my $fh, '<', "$kit_root/$relpath") or die "read $relpath: $!";
	local $/;
	return <$fh>;
}

# --- port validation (Important finding 1) -----------------------------------

subtest 'port validation' => sub {
	for my $bad_port (qw/443x -1 65536 999999/) {
		my $self = build_self(routes => [
			{ hostname => 'svc.example.com', backend => '10.0.0.5', port => $bad_port },
		]);
		my $result = eval { $self->_generate_service_routes_ops };
		like($@, qr/\Qparams.ocfp_haproxy_service_routes[0].port\E/,
			"bails on invalid port '$bad_port'");
		like($@, qr/\Q$bad_port\E/, "error names the bad port value '$bad_port'");
	}

	# A port value containing a newline must not survive into the generated
	# YAML block scalar (see report Important-1: this is how a bad port
	# smuggles extra lines into the haproxy backend block).
	my $injected = "443\nrogue: line";
	my $self = build_self(routes => [
		{ hostname => 'svc.example.com', backend => '10.0.0.5', port => $injected },
	]);
	eval { $self->_generate_service_routes_ops };
	like($@, qr/\Qparams.ocfp_haproxy_service_routes[0].port\E/,
		"bails on newline-injected port value");

	for my $good_port (1, 443, 8080, 65535) {
		my $self = build_self(routes => [
			{ hostname => 'svc.example.com', backend => '10.0.0.5', port => $good_port },
		]);
		my $result = eval { $self->_generate_service_routes_ops };
		is($@, '', "accepts valid port $good_port");
		like(generated_content($self, $result), qr/:\Q$good_port\E\b/,
			"generated backend targets port $good_port");
	}

	$self = build_self(routes => [
		{ hostname => 'svc.example.com', backend => '10.0.0.5' },
	]);
	my $result = eval { $self->_generate_service_routes_ops };
	is($@, '', 'omitted port does not error');
	like(generated_content($self, $result), qr/:443\b/, 'omitted port defaults to 443');
};

done_testing;
