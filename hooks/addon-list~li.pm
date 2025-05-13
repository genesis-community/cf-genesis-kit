#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::Addon::CF v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
my $lib;
BEGIN {$lib = $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use lib $lib;

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info run/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
  "Lists all available Cloud Foundry addons and their descriptions.";
}

sub perform {
  my ($self) = @_;

  info("The following addons are defined:\n".
    "  login             Log into the Cloud Foundry instance as the".
    "                    admin user account.  This will overwrite local".
    "                    cf CLI configuration!\n".
    "  logout            Log out of the Cloud Foundry instance.\n".
    "  setup-cli         Installs cf CLI plugins like 'Targets', which".
    "                    helps to manage multiple Cloud Foundries from a".
    "                    single jumpbox.\n".
    "  smoketest         Run the smoke tests errand on the first vm in the".
    "                    api instance group.\n".
    "  stratos           Deploy Stratos, the Cloud Foundry web console.\n".
    "  scs               Deploy and register Spring Cloud Services broker to CF.\n"
  );

  return $self->done();
}

1;
