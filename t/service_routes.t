#!/usr/bin/env perl
# Unit-level coverage for Genesis::Hook::Blueprint::CF::_generate_service_routes_ops.
#
# The spec/ suite renders whole environments and compares them against the
# golden manifests, which pins the shape of the generated ops file but says
# nothing about the argument validation in front of it. This calls the sub
# directly against a minimal mock $self so the bad-input paths get exercised
# without a full render.
#
# Requires the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib,
# same as hooks/blueprint.pm itself expects (see its "Only needed for
# development" BEGIN block). `make t` sets GENESIS_LIB for you.

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

# --- self-signed / provided-cert interaction (Important finding 2) ----------
#
# Routing and certificate naming are separate concerns. When the operator
# brings their own certificate, overlay/routing/haproxy-provided-cert.yml has
# deleted the haproxy_ssl variable, so there is no SAN list to append to, but
# the frontend and backend ops still have to be emitted or haproxy routes
# nothing at all. The kit therefore skips only the SAN ops and warns with the
# hostnames the operator's certificate has to cover.

subtest 'provided-cert path' => sub {
	my @warnings;
	{
		no warnings 'redefine';
		*Genesis::Hook::Blueprint::CF::warning = sub {
			my ($fmt, @args) = @_;
			push @warnings, sprintf($fmt, @args);
		};
	}

	my $self = build_self(
		routes   => [{ hostname => 'svc.example.com', backend => '10.0.0.5' }],
		features => ['haproxy'], # self-signed NOT active -> provided-cert path
	);
	my $result = eval { $self->_generate_service_routes_ops };
	is($@, '', 'provided-cert path emits ops instead of bailing');
	ok($result, 'provided-cert path returns an ops file path');

	my $content = generated_content($self, $result);
	like($content, qr/acl host_ocfp_route_0 .*\Qsvc.example.com\E/,
		'provided-cert path still emits the frontend ACL');
	like($content, qr/use_backend ocfp_route_0 if host_ocfp_route_0/,
		'provided-cert path still emits the use_backend line');
	like($content, qr{raw_blocks\?/backend/ocfp_route_0},
		'provided-cert path still emits the backend block');
	unlike($content, qr{path: /variables/name=haproxy_ssl},
		'provided-cert path emits no SAN op, since haproxy_ssl no longer exists');

	is(scalar(@warnings), 1, 'provided-cert path warns exactly once');
	like($warnings[0], qr/\Qsvc.example.com\E/,
		'warning names the hostname the operator certificate must cover');
	like($warnings[0], qr/routing 1 hostname through/,
		'warning is singular for a single hostname');

	# Two routes: the warning pluralises and lists both hostnames.
	@warnings = ();
	$self = build_self(
		routes => [
			{ hostname => 'svc.example.com',   backend => '10.0.0.5' },
			{ hostname => 'other.example.com', backend => '10.0.0.6' },
		],
		features => ['haproxy'],
	);
	$result = eval { $self->_generate_service_routes_ops };
	is($@, '', 'provided-cert path handles multiple routes');
	is(scalar(@warnings), 1, 'multiple routes still warn exactly once');
	like($warnings[0], qr/routing 2 hostnames through/,
		'warning pluralises for multiple hostnames');
	like($warnings[0], qr/\Qother.example.com\E/,
		'warning lists every hostname');

	# The self-signed path (as used on the lab) must be unaffected.
	@warnings = ();
	$self = build_self(
		routes   => [{ hostname => 'svc.example.com', backend => '10.0.0.5' }],
		features => ['haproxy', 'self-signed'],
	);
	$result = eval { $self->_generate_service_routes_ops };
	is($@, '', 'self-signed path is unaffected');
	like(generated_content($self, $result), qr{path: /variables/name=haproxy_ssl},
		'self-signed path still emits the SAN op');
	is(scalar(@warnings), 0, 'self-signed path does not warn about certificate coverage');
};

# --- haproxy feature gate ----------------------------------------------------

subtest 'haproxy feature gate' => sub {
	my $self = build_self(
		routes   => [{ hostname => 'svc.example.com', backend => '10.0.0.5' }],
		features => ['self-signed'], # no haproxy
	);
	eval { $self->_generate_service_routes_ops };
	like($@, qr/haproxy/,
		'bails when routes are configured without the haproxy feature');

	$self = build_self(routes => []);
	my $result = eval { $self->_generate_service_routes_ops };
	is($@, '', 'no routes configured is not an error');
	is($result, undef, 'no routes configured emits no ops file');
};

done_testing;
