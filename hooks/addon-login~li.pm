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

use Genesis qw/bail info run exodus_data/;
use Genesis::UI qw/prompt_for_boolean/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
  "Log into the Cloud Foundry instance as the admin user account.\n".
  "This will overwrite local cf CLI configuration!\n".
  "Supports the following options:\n".
  "[[  #y{--yes, -y}          >>Skip all confirmations, useful for non-interactive environments like pipelines\n".
  "[[  #y{--validate-ssl}     >>Enforce SSL validation when connecting to the CF API";
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;
  
  # Parse options
  my %options = $self->parse_options([
    'yes|y',           # Skip confirmation prompts
    'validate-ssl',    # Enforce SSL validation
  ]);
  
  my $non_interactive = $options{'yes'} ? 1 : 0;
  my $validate_ssl = $options{'validate-ssl'} ? 1 : 0;
  
  my $use_cf_targets = 1;
  my ($out, $rc) = run('cf plugins | grep -q \'^cf-targets\'');
  if ($rc != 0) {
    $use_cf_targets = 0;
    info(
      "#Y{The cf-targets plugin does not seem to be installed}\n".
      "It is recommended you install it first, via #G{%s do setup-cli}'\n\n".
      "[[NOTE: >>It is not compatible with Apple M1 (arm) architecture",
      $env->get_call_path_with_environment()
    );

    # Skip confirmation if in non-interactive mode
    if (!$non_interactive) {
      my $continue = prompt_for_boolean("Continue anyways?", 0);
      return $self->done(0) unless $continue;
    } else {
      info("Running in non-interactive mode, continuing without cf-targets plugin...");
    }
  }

  # Get CF credentials from exodus data
  my $exodus = exodus_data($env->path);
  my $api_domain = $exodus->{api_domain};
  my $api_url = "https://${api_domain}";
  my $username = $exodus->{admin_username};
  my $password = $exodus->{admin_password};

  # Handle SSL validation based on option
  if ($validate_ssl) {
    info("Using SSL validation for CF API connection");
    run('cf api "$1"', $api_url);
  } else {
    run('cf api "$1" --skip-ssl-validation', $api_url);
  }
  
  run('cf auth "$1" "$2"', $username, $password);

  if ($use_cf_targets) {
    run('cf save-target -f "$1"', $ENV{GENESIS_ENVIRONMENT});
  }

  info("\n\n");
  run('cf target');

  return $self->done(1);
}

1;
