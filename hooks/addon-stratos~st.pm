#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::Addon::CF::Stratos v2.6.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
my $lib;
BEGIN {$lib = $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use lib $lib;

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info count_nouns/;
use Genesis::Term qw/terminal_width/;
use JSON::PP;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
  "Manage and display information about Stratos UI deployments. Supports the following options:\n".
  "[[  #y{--json}         >>Output information in JSON format\n".
  "[[  #y{--urls-only}    >>Only display URLs\n".
  "[[  #y{--open}         >>Open the Stratos UI in your browser (if available)\n";
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Parse options
  my %options = $self->parse_options([
      'json',
      'urls-only',
      'open',
    ],
  );

  # Get BOSH target
  my $bosh;
  eval {
    $bosh = $env->get_target_bosh({self => 0});
  };
  if ($@) {
    bail("Could not connect to BOSH director: $@");
  }

  $env->notify("retrieving information about Stratos UI deployment...");

  # Get deployment name from environment or configuration
  my $deployment_name = $env->lookup('stratos.deployment_name', $env->name . "-stratos");

  # Check if deployment exists
  my @deployments = eval { $bosh->deployments() };
  if ($@) {
    bail("Failed to get deployments: $@");
  }

  my $deployment_exists = grep { $_ eq $deployment_name } @deployments;

  # Get Stratos information from environment
  my $stratos_url = $env->lookup('stratos.url', '');
  if (!$stratos_url) {
    my $system_domain = $env->lookup('cf.system_domain', '');
    $stratos_url = $system_domain ? "https://stratos.$system_domain" : '';
  }

  my $stratos_version = $env->lookup('stratos.version', 'unknown');
  my $stratos_admin = $env->lookup('stratos.admin_user', 'admin');

  # Get credentials from vault
  my $admin_password = "";
  eval {
    $admin_password = $env->vault->get($env->secrets_base . "stratos/admin_password");
  };
  if ($@) {
    info("Could not retrieve admin password from vault: $@");
  }

  # Build info structure
  my $info = {
    name => $deployment_name,
    status => $deployment_exists ? "Deployed" : "Not Deployed",
    url => $stratos_url,
    version => $stratos_version,
    admin_user => $stratos_admin,
    admin_password => $admin_password ? "Available in vault" : "Not found",
  };

  # Handle URLs-only mode
  if ($options{'urls-only'}) {
    if ($stratos_url) {
      info($stratos_url);
    } else {
      info("No Stratos URL configured");
    }
    return 1;
  }

  # Handle open mode
  if ($options{open}) {
    if ($stratos_url) {
      my $cmd = $^O eq 'darwin' ? 'open' :
      ($^O eq 'MSWin32' ? 'start' : 'xdg-open');

      info("Opening Stratos UI in browser: %s", $stratos_url);
      system("$cmd '$stratos_url' >/dev/null 2>&1 &");
    } else {
      bail("Cannot open Stratos UI: No URL configured");
    }
    return 1;
  }

  # Display information
  if ($options{json}) {
    # Output as JSON
    info(JSON::PP->new->pretty->encode($info));
  } else {
    # Print header
    info("\n" . "=" x terminal_width());
    info("Stratos UI Deployment: %s", $info->{name});
    info("=" x terminal_width());

    # Basic information
    info("Status: %s", $info->{status});

    if ($info->{url}) {
      info("URL: %s", $info->{url});
    } else {
      info("URL: Not configured");
    }

    info("Version: %s", $info->{version});

    # Authentication information
    info("\nAuthentication:");
    info("  Admin User: %s", $info->{admin_user});
    info("  Admin Password: %s", $info->{admin_password});

    # Show helpful commands
    info("\nHelpful Commands:");
    info("  Open in browser: %s %s stratos --open",
      $env->get_call_path(), $env->name);

    if ($deployment_exists) {
      info("  View logs: %s %s bosh logs -d %s",
        $env->get_call_path(), $env->name, $deployment_name);
    }
  }

  return $self->done();
}

1;
