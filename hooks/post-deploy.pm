#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::CF::PostDeploy v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/info/;
use parent qw(Genesis::Hook);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";
use JSON::PP;

# Only needed for development
my $lib;
BEGIN {$lib = $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use lib $lib;

use parent qw(Genesis::Hook::PostDeploy);


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

  $self->create_cf_vpcs();

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

# TODO: In the future we can refactor this to be a specific override restricted configurable CIDR range(s) instead of the privbate ip address space.
sub create_cf_vpcs {
  info("Creating security groups for CF private networks VPC access.");

  open my $sg_file, '>', "$tmp_dir/vpc-sg.json" or bail("Could not create security group file: $!");
  # Create a Perl data structure for the security groups
  my $security_groups = [
    { "protocol" => "all", "destination" => "10.0.0.0-10.255.255.255" },
    { "protocol" => "all", "destination" => "172.16.0.0-172.31.255.255" },
    { "protocol" => "all", "destination" => "192.168.0.0-192.168.255.255" }
  ];
  # Use JSON::PP to encode the data structure with tab indentation
  my $json = JSON::PP->new->indent(1)->tab(1)->pretty->encode($security_groups);
  print $sg_file $json; # Write the JSON to the file
  close $sg_file;

  run('cf create-security-group vpc "$1" || true', "$tmp_dir/vpc-sg.json");
  run('cf bind-staging-security-group vpc || true');
  run('cf bind-running-security-group vpc || true');
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
