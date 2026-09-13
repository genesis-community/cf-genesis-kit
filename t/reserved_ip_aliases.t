#!/usr/bin/env perl
# Unit-level coverage for
# Genesis::Hook::CloudConfig::CF::ocfp_reserved_ip_target_aliases.
#
# Nothing else in this repository exercises the sub. Genesis calls the
# cloud-config hook from `genesis deploy` and from the bosh config commands,
# never from `check` or `manifest`, and those two are all the spec/ harness
# runs. No spec environment asks for the ocfp feature either, so the whole
# OCFP cloud-config path is dark there. This calls the sub directly against a
# minimal mock $self instead.
#
# Requires the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib,
# same as hooks/cloud-config.pm itself expects (see its "Only needed for
# development" BEGIN block). `make t` sets GENESIS_LIB for you.
#
# The base class in Genesis declares ocfp_reserved_ip_target_aliases and
# returns nothing, and _get_reserved_allocation treats a defined return as the
# kit taking ownership of the rename. So an undef return here is not a
# throwaway: it is the kit deferring to the Genesis-side alias table, and the
# tests below distinguish undef from an empty list on purpose.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/cloud-config.pm";

# --- minimal mock -----------------------------------------------------------

sub build_self {
	my (@features) = @_;
	my %features = map { ($_ => 1) } @features;
	return bless {feature_flags => \%features}, 'Genesis::Hook::CloudConfig::CF';
}

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*Genesis::Hook::CloudConfig::CF::want_feature
		= sub { $_[0]->{feature_flags}{$_[1]} };
}

# --- the aliases themselves --------------------------------------------------

subtest 'haproxy environments alias ocf onto haproxy' => sub {
	my $self = build_self('haproxy');

	is_deeply($self->ocfp_reserved_ip_target_aliases('ocf'), ['haproxy'],
		"the single-network target aliases onto the carve's haproxy keys");
	is_deeply($self->ocfp_reserved_ip_target_aliases('ocf-edge'), ['haproxy'],
		'the partitioned edge target aliases onto the same keys');
};

subtest 'other targets are left to Genesis' => sub {
	my $self = build_self('haproxy');

	for my $target (qw/ocf-core ocf-runtime ocfp vault bosh/) {
		is($self->ocfp_reserved_ip_target_aliases($target), undef,
			"$target returns undef, so Genesis keeps its own alias table");
	}

	# 'ocf' has to match whole, or an unrelated network beginning with those
	# three letters would be pulled onto the haproxy addresses.
	for my $target (qw/ocf-edge-extra ocfx my-ocf/) {
		is($self->ocfp_reserved_ip_target_aliases($target), undef,
			"$target does not match the ocf pattern");
	}
};

subtest 'no haproxy means no aliasing' => sub {
	my $self = build_self();

	is($self->ocfp_reserved_ip_target_aliases('ocf'), undef,
		'without the haproxy feature the kit expresses no opinion');
	is($self->ocfp_reserved_ip_target_aliases('ocf-edge'), undef,
		'the partitioned edge target is quiet too');

	$self = build_self('no-haproxy');
	is($self->ocfp_reserved_ip_target_aliases('ocf'), undef,
		'an environment fronted by an external load balancer aliases nothing');
};

# --- the Genesis side of the contract ---------------------------------------

subtest 'the base class declares the extension point' => sub {
	# _get_reserved_allocation only consults the kit because Genesis calls this
	# sub, so a Genesis without it renders the whole alias above dead code and
	# the aliasing silently stops happening. Fail here rather than let a run
	# against the wrong Genesis look green.
	my $declared = Genesis::Hook::CloudConfig->can('ocfp_reserved_ip_target_aliases');
	ok($declared,
		'Genesis::Hook::CloudConfig declares ocfp_reserved_ip_target_aliases')
		or diag(
			"The loaded Genesis has no ocfp_reserved_ip_target_aliases, so the ".
			"kit's alias in hooks/cloud-config.pm is never consulted. Check ".
			"which genesis GENESIS_LIB points at."
		);

	SKIP: {
		skip 'base class does not declare the sub', 1 unless $declared;
		is($declared->(undef, 'ocf'), undef,
			'and the base implementation returns undef');
	}
};

done_testing;
