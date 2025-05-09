#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::CF::Features v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

use parent qw(Genesis::Hook);

use Genesis;
sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;

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
  my $has_db_overrides = 0;

  if ($params && ref($params) eq 'HASH') {
    foreach my $key (keys %$params) {
      if ($key =~ /^(cc|uaa|diego|policyserver|silk|locket|routingapi|credhub)db_(name|user)$/) {
        $has_db_overrides = 1;
        last;
      }
    }
  }

  $self->add_feature('+override-db-names') if $has_db_overrides;

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

  # Build the features list and return it
  my @results = $self->build_features_list();
  return \@results;
}

1;
