#!/usr/bin/env perl
# Unit-level coverage for Genesis::Hook::Blueprint::CF::_refuse_fog_external_blobstore.
#
# The guard reads whichever use-external-blobstore.yml is on disk at render
# time, so each case writes a fixture into a throwaway kit root and calls the
# sub directly against a minimal mock $self, the same way service_routes.t
# exercises _generate_service_routes_ops.
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

# --- minimal mocks -----------------------------------------------------------

package MockEnv;
sub new { my ($c, %a) = @_; bless {%a}, $c }
sub name { $_[0]->{name} }

package main;

{
	no strict 'refs';
	no warnings 'redefine', 'once';
	*Genesis::Hook::Blueprint::CF::env = sub { $_[0]->{env_obj} };
	*Genesis::Hook::Blueprint::CF::kit = sub { $_[0] }; # kit() and path() combined below
	*Genesis::Hook::Blueprint::CF::path = sub { my ($s, $p) = @_; return defined($p) ? "$s->{kit_root}/$p" : $s->{kit_root} };
}

# The pre-v59 shape, trimmed from cf-deployment v56.5.0: a YAML anchor carries
# ((fog_connection)) onto each bucket.
my $fog_ops = <<'EOF';
- type: remove
  path: /instance_groups/name=singleton-blobstore

- type: replace
  path: /instance_groups/name=api/jobs/name=cloud_controller_ng/properties/cc/buildpacks?/fog_connection
  value: &blobstore-properties ((fog_connection))

- type: replace
  path: /instance_groups/name=api/jobs/name=cloud_controller_ng/properties/cc/droplets?/fog_connection
  value: *blobstore-properties
EOF

# The v59+ shape: directory keys only, no fog wiring.
my $storage_cli_ops = <<'EOF';
- type: remove
  path: /instance_groups/name=singleton-blobstore

- type: replace
  path: /instance_groups/name=api/jobs/name=cloud_controller_ng/properties/cc/buildpacks?/buildpack_directory_key
  value: ((blobstore_buildpacks_directory))
EOF

sub build_self {
	my (%opts) = @_;
	my $kit_root = tempdir(CLEANUP => 1);
	if (defined $opts{ops}) {
		make_path("$kit_root/cf-deployment/operations");
		open(my $fh, '>', "$kit_root/cf-deployment/operations/use-external-blobstore.yml") or die $!;
		print $fh $opts{ops};
		close $fh;
	}
	return bless {
		env_obj      => MockEnv->new(name => 'ocfp-cf1-lab-ocf'),
		kit_root     => $kit_root,
		raw_features => $opts{raw_features} // ['ocfp', 'pve-blobstore'],
	}, 'Genesis::Hook::Blueprint::CF';
}

subtest 'fog-wired tree selected by a custom version bails' => sub {
	my $self = build_self(
		ops          => $fog_ops,
		raw_features => ['ocfp', 'pve-blobstore', 'cf-deployment-version-56.5.0'],
	);
	eval { $self->_refuse_fog_external_blobstore('pve-blobstore') };
	my $err = $@;
	ok($err, 'bails');
	like($err, qr/ocfp-cf1-lab-ocf/, 'names the environment');
	like($err, qr/pve-blobstore/, 'names the blobstore feature');
	like($err, qr/cf-deployment-version-56\.5\.0/, 'names the version feature to remove');
	like($err, qr/fog_connection/, 'names the unresolvable variable');
	like($err, qr/v59\.0\.0/, 'names the first storage-cli cf-deployment');
};

subtest 'fog-wired vendored tree bails without a version feature' => sub {
	my $self = build_self(ops => $fog_ops);
	eval { $self->_refuse_fog_external_blobstore('pve-blobstore') };
	my $err = $@;
	ok($err, 'bails');
	like($err, qr/vendored in this kit/, 'blames the vendored tree');
	unlike($err, qr/cf-deployment-version-\d/, 'does not invent a version feature');
};

subtest 'storage-cli tree passes' => sub {
	my $self = build_self(
		ops          => $storage_cli_ops,
		raw_features => ['ocfp', 'pve-blobstore', 'cf-deployment-version-60.5.0'],
	);
	ok(eval { $self->_refuse_fog_external_blobstore('pve-blobstore'); 1 }, 'does not bail')
		or diag $@;
};

subtest 'a comment that mentions fog_connection passes' => sub {
	my $self = build_self(ops => "# fog_connection was removed in v59.0.0\n$storage_cli_ops");
	ok(eval { $self->_refuse_fog_external_blobstore('pve-blobstore'); 1 }, 'does not bail')
		or diag $@;
};

subtest 'a tree without the ops file passes' => sub {
	my $self = build_self();
	ok(eval { $self->_refuse_fog_external_blobstore('pve-blobstore'); 1 }, 'does not bail')
		or diag $@;
};

done_testing;
