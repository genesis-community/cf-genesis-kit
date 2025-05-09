#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::CF::PostDeploy v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
my $lib;
BEGIN {$lib = $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use lib $lib;

use parent qw(Genesis::Hook::PostDeploy);

use Genesis qw/bail info/;

# Initialize the hook
sub init {
  my ($class, %ops) = @_;
  my $self = $class->SUPER::init(%ops);

  # Nothing additional needed for initialization
  return $self;
}

# Main hook execution
sub perform {
  my ($self) = @_;

  # Base class has deploy_successful method to check if GENESIS_DEPLOY_RC == 0
  if ($self->deploy_successful) {
    # Display messages to the user about available commands
    # This emulates the 'describe' function in the bash script
    info(
      "\n".
      "#M{$ENV{GENESIS_ENVIRONMENT}} Cloud Foundry deployed!\n".
      "\n".
      "For details about the deployment, run\n".
      "\n".
      "  #G{$ENV{GENESIS_CALL_ENV} info}\n".
      "\n".
      "To see a list of available addons, run\n".
      "\n".
      "  #G{$ENV{GENESIS_CALL_ENV} do -- list}\n".
      "\n".
      "To set up your local cf CLI installation with useful plugins:\n".
      "\n".
      "  #G{$ENV{GENESIS_CALL_ENV} do -- setup-cli}\n".
      "\n".
      "To log into Cloud Foundry, run\n".
      "\n".
      "  #G{$ENV{GENESIS_CALL_ENV} do -- login}\n".
      "\n"
    );
  }

  # Call parent class methods if needed
  $self->SUPER::perform() if $self->can('SUPER::perform');

  # Mark the hook as completed successfully
  return $self->done(1);
}

1; # End of module

=head1 NAME

Genesis::Hook::PostDeploy::CloudFoundry - Post-deployment hook for Cloud Foundry Genesis Kit

=head1 DESCRIPTION

This module implements the post-deployment hook for the Cloud Foundry Genesis Kit.
It displays helpful information to the user after a successful deployment.

=head1 METHODS

=head2 init(%options)

Initializes the hook with the given options.

=head2 perform()

Executes the post-deploy hook, displaying helpful information if the deployment was successful.

=head1 AUTHOR

Genesis Framework

=cut
