#!/usr/bin/env perl
# Coverage for the classic 'source-releases' feature.
#
# The classic dispatch in hooks/blueprint.pm reads source-releases to pick
# overlay/override-releases/source.yml over compiled.yml, and to build the
# Windows cells from source, so validate_classic_features has to accept it.
# validate_features comes from the real genesis library; everything it
# touches is mocked here.
#
# Requires the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib.
# `make t` sets GENESIS_LIB for you.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/blueprint.pm";

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*Genesis::Hook::Blueprint::CF::features     = sub { @{ $_[0]->{features} } };
	*Genesis::Hook::Blueprint::CF::set_features = sub { my $s = shift; $s->{features} = [@_] };
	*Genesis::Hook::Blueprint::CF::ops_dir      = sub { 'ops' };
	*Genesis::Hook::Blueprint::CF::upstream_dir = sub { undef };
	*Genesis::Hook::Blueprint::CF::iaas         = sub { 'vsphere' };
	*Genesis::Hook::Blueprint::CF::want_feature = sub { my ($s, $f) = @_; scalar grep { $_ eq $f } @{ $s->{features} } };
	*Genesis::Hook::Blueprint::CF::env          = sub { $_[0] };
	*Genesis::Hook::Blueprint::CF::path         = sub { '/nonexistent/' . $_[1] };
	*Genesis::Hook::Blueprint::warning          = sub {};
	*Genesis::Hook::Blueprint::CF::warning      = sub {};
}

# The blueprint keeps the env's own feature list in raw_features before it
# validates, the way handle_custom_cf_versions leaves it.
my @requested = qw/haproxy source-releases/;
my $self = bless {
	features     => [@requested],
	raw_features => [@requested],
}, 'Genesis::Hook::Blueprint::CF';
my $ok = eval { $self->validate_classic_features; 1 };
ok($ok, 'source-releases passes classic feature validation') or diag $@;
ok($self->want_feature('source-releases'),
	'source-releases stays in the curated feature list');

done_testing;
