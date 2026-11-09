#!/usr/bin/env perl
# Unit-level coverage for Genesis::Hook::Blueprint::CF::_refuse_unpatched_garden_runc.
#
# The guard reads whichever cf-deployment.yml is on disk at render time, so
# each case writes a fixture into a throwaway kit root and calls the sub
# directly against a minimal mock $self, the same way fog_blobstore_guard.t
# exercises _refuse_fog_external_blobstore.
#
# Requires the real genesis Perl library on GENESIS_LIB or ~/.genesis/lib,
# same as hooks/blueprint.pm itself expects. `make t` sets GENESIS_LIB for you.

use v5.20;
use warnings;
use FindBin;
use Test::More;
use File::Path qw/make_path/;
use File::Temp qw/tempdir/;

require "$FindBin::Bin/../hooks/blueprint.pm";

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*Genesis::Hook::Blueprint::CF::kit = sub { $_[0] }; # kit() and path() combined below
	*Genesis::Hook::Blueprint::CF::path = sub { my ($s, $p) = @_; return defined($p) ? "$s->{kit_root}/$p" : $s->{kit_root} };
}

# The releases block around garden-runc, in cf-deployment's own key order.
sub releases_with_garden {
	my ($version) = @_;
	return <<"YAML";
releases:
- name: dotnet-core-buildpack
  url: https://bosh.io/d/github.com/cloudfoundry/dotnet-core-buildpack-release?v=2.4.52
  version: 2.4.52
- name: garden-runc
  url: https://bosh.io/d/github.com/cloudfoundry/garden-runc-release?v=$version
  version: $version
  sha1: sha256:c883276ee3f00316f4b73aa85ddcff4abb5ffe315d515dde6a1cb883cae4a5b1
- name: go-buildpack
  url: https://bosh.io/d/github.com/cloudfoundry/go-buildpack-release?v=1.11.0
  version: 1.11.0
YAML
}

sub build_self {
	my (%opts) = @_;
	my $kit_root = tempdir(CLEANUP => 1);
	if (defined $opts{manifest}) {
		make_path("$kit_root/cf-deployment");
		open(my $fh, '>', "$kit_root/cf-deployment/cf-deployment.yml") or die $!;
		print $fh $opts{manifest};
		close $fh;
	}
	return bless { kit_root => $kit_root }, 'Genesis::Hook::Blueprint::CF';
}

subtest 'a tree on the patched version passes' => sub {
	my $self = build_self(manifest => releases_with_garden('1.105.0'));
	ok(eval { $self->_refuse_unpatched_garden_runc(); 1 }, 'does not bail')
		or diag $@;
};

subtest 'a tree on another version bails' => sub {
	my $self = build_self(manifest => releases_with_garden('1.101.0'));
	eval { $self->_refuse_unpatched_garden_runc() };
	my $err = $@;
	ok($err, 'bails');
	like($err, qr/1\.101\.0/, 'names the version the tree pins');
	like($err, qr/1\.105\.0/, 'names the patched version');
};

subtest 'a quoted version is read' => sub {
	(my $manifest = releases_with_garden('1.105.0')) =~ s/version: 1\.105\.0/version: "1.105.0"/;
	my $self = build_self(manifest => $manifest);
	ok(eval { $self->_refuse_unpatched_garden_runc(); 1 }, 'does not bail')
		or diag $@;
};

subtest 'the next release entry is not read as garden-runc' => sub {
	(my $manifest = releases_with_garden('1.105.0')) =~ s/^  version: 1\.105\.0\n//m;
	my $self = build_self(manifest => $manifest);
	eval { $self->_refuse_unpatched_garden_runc() };
	like($@, qr/nothing/, 'bails without borrowing go-buildpack 1.11.0');
};

subtest 'a tree without cf-deployment.yml bails' => sub {
	my $self = build_self();
	eval { $self->_refuse_unpatched_garden_runc() };
	like($@, qr/nothing/, 'bails and says nothing was found');
};

done_testing;
