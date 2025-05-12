#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::Addon::CF::Login v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
my $lib;
BEGIN {$lib = $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use lib $lib;

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info run/;
use Genesis::UI qw/prompt_for_boolean describe/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0');
  return $obj;
}

sub cmd_details {
  return
  "Log into the Cloud Foundry instance as the admin user account.\n".
  "This will overwrite local cf CLI configuration!";
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  my $use_cf_targets = 1;
  my ($out, $rc) = run('cf plugins | grep -q \'^cf-targets\'');
  if ($rc != 0) {
    $use_cf_targets = 0;
    describe("#Y{The cf-targets plugin does not seem to be installed}");
    info("It is recommended you install it first, via 'genesis do $ENV{GENESIS_ENVIRONMENT} -- setup-cli'");
    info("NOTE:  It is not compatible with Apple M1 (arm) architecture");

    my $continue = prompt_for_boolean("Continue anyways?", 0);
    return 0 unless $continue;
  }

  my $api_domain = $env->exodus_lookup('api_domain');
  my $api_url = "https://${api_domain}";
  my $username = $env->exodus_lookup('admin_username');
  my $password = $env->exodus_lookup('admin_password');

  # TODO: enforce ssl validation
  run('cf api "$1" --skip-ssl-validation', $api_url);
  run('cf auth "$1" "$2"', $username, $password);

  if ($use_cf_targets) {
    run('cf save-target -f "$1"', $ENV{GENESIS_ENVIRONMENT});
  }

  info("\n\n");
  run('cf target');

  return 1;
}

1;
