#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::CF::Features v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::Features);

use Genesis qw(new_enough);

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;

  $self->add_feature("cflinuxfs4"); # Default runtime.

  # Process requested features
  foreach my $feature (@{$self->{features}}) {
    if ($feature eq 'cf-deployment/operations/enable-nfs-volume-services') {
      $self->add_feature('nfs-volume-services');
    } elsif ($feature eq 'cf-deployment/operations/enable-nfs-lambda') {
      $self->add_feature('nfs-lambda');
    } elsif ($feature eq 'cf-deployment/operations/enable-smb-volume-services') {
      $self->add_feature('smb-volume-services');
    } else {
      $self->add_feature($feature);
    }
  }

  # Check for database overrides
  my $params = $self->env->lookup('params', {});

  if ($params && ref($params) eq 'HASH') {
    foreach my $key (keys %$params) {
      if ($key =~ /^(cc|uaa|diego|policyserver|silk|locket|routingapi|credhub)db_(name|user)$/) {
				$self->add_feature('+override-db-names');
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
    $self->add_feature('+migrated-v1-env');

    # Check for no-v1-vm-types feature
    unless ($self->want_feature('no-v1-vm-types')) {
      $self->add_feature('v1-vm-types');
    }
  }
	return $self->done();
}

1;
