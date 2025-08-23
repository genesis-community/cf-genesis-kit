package Genesis::Hook::Features::CF v3.0.0;

use v5.20;
use warnings;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib' }

use parent qw(Genesis::Hook::Features);

use Genesis qw(new_enough);

# init - Initialize the hook {{{
sub init {
	my ( $class, %ops ) = @_;
	my $obj = $class->SUPER::init(%ops);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

# }}}

# perform - Main hook execution {{{
sub perform {
	my ($self) = @_;

	# Build features list based on requested features
	my @features;

	# Process requested features with transformations
	my $is_ocfp = $self->want_feature('ocfp');
	foreach my $feature ($self->features) {
		if ($feature eq 'cf-deployment/operations/enable-nfs-volume-services') {
			push @features, 'nfs-volume-services';
		} elsif ($feature eq 'cf-deployment/operations/enable-nfs-lambda') {
			push @features, 'nfs-lambda';
		} elsif ($feature eq 'cf-deployment/operations/enable-smb-volume-services') {
			push @features, 'smb-volume-services';
		} elsif ($feature eq 'internal-db') {
			push @features, $is_ocfp ? '+internal-db' : 'internal-db';
		} elsif ($feature eq 'internal-blobstore') {
			push @features, $is_ocfp ? '+internal-blobstore' : 'internal-blobstore';
		} elsif ($feature eq 'split-network') { # Short-lived ocfp feature that is better handled by existing feature name
			push @features, 'partitioned-network';
		} else {
			push @features, $feature;
		}
	}

	# Check for database overrides
	my $params = $self->env->lookup('params', {});
	if ($params && ref($params) eq 'HASH') {
		foreach my $key (keys %$params) {
			if ($key =~ /^(cc|uaa|diego|policyserver|silk|locket|routingapi|credhub)db_(name|user)$/) {
				push @features, '+override-db-names';
				last;
			}
		}
	}

	# Check if migrated from v1
	my $migrated_v1_env = $self->env->exodus_lookup('migrated_v1_env', '');

	if ($migrated_v1_env ne '1') {
		my $version = $self->env->exodus_lookup('kit_version', '');
		if ($version && !new_enough($version, "2.0.0-rc0")) {
			$migrated_v1_env = 1;
		}
	}

	if ($migrated_v1_env) {
		push @features, '+migrated-v1-env';

		# Check for no-v1-vm-types feature
		unless (grep { $_ eq 'no-v1-vm-types' } $self->features) {
			push @features, 'v1-vm-types';
		}
	}

	return $self->done(\@features);
}

# }}}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
