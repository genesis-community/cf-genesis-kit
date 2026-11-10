#!/usr/bin/env perl
# Coverage for the classic 'cflinuxfs4' feature, which is now a warning no-op.
#
# cflinuxfs5 is the default stack and cflinuxfs4 stays installed beside it, so
# the old feature has nothing left to apply. It must still pass feature
# validation, warn the operator, and then fall through the dispatch without
# the "Unknown feature" bail. validate_features comes from the real genesis
# library; everything it touches is mocked here.
#
# Requires the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib.
# `make t` sets GENESIS_LIB for you.

use v5.20;
use warnings;
use FindBin;
use Test::More;

require "$FindBin::Bin/../hooks/blueprint.pm";

my @warned;
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
	*Genesis::Hook::Blueprint::warning          = sub { push @warned, sprintf(shift, @_) };
	*Genesis::Hook::Blueprint::CF::warning      = sub { push @warned, sprintf(shift, @_) };
}

sub build { bless { features => [@_] }, 'Genesis::Hook::Blueprint::CF' }

my $self = build(qw/haproxy cflinuxfs4/);
my $ok = eval { $self->validate_classic_features; 1 };
ok($ok, 'cflinuxfs4 passes classic feature validation') or diag $@;

my $text = join "\n", @warned;
like($text, qr/cflinuxfs4.*still installed alongside cflinuxfs5/s,
	'warns that cflinuxfs4 is still installed alongside cflinuxfs5');
like($text, qr/cflinuxfs4-default/, 'points to cflinuxfs4-default');

@warned = ();
$self = build(qw/haproxy/);
$self->validate_classic_features;
unlike(join("\n", @warned), qr/cflinuxfs4 feature no longer/, 'no warning when not requested');

done_testing;
