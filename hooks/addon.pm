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
use Genesis::UI qw/prompt_for_boolean describe/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0');
  return $obj;
}

sub cmd_details {
  return
  "The following Cloud Foundry addons are available:\n\n".
  "[[  #G{login}         >>Log into the Cloud Foundry instance as the ".
  "admin user account.  This will overwrite local ".
  "cf CLI configuration!\n\n".
  "[[  #G{setup-cli}     >>Installs cf CLI plugins like 'Targets', which ".
  "helps to manage multiple Cloud Foundries from a ".
  "single jumpbox.\n\n".
  "[[  #G{smoketest}     >>Run the smoke tests errand on the first vm in the ".
  "api instance group.\n\n".
  "[[  #G{stratos}       >>Deploy Stratos, the Cloud Foundry web console.\n";
}

sub perform {
  my ($self) = @_;
  my $script = $self->{script};

  if ($script eq 'list') {
    return $self->do_list();
  } elsif ($script eq 'login') {
    return $self->do_login();
  } elsif ($script eq 'remigrate') {
    return $self->do_remigrate();
  } elsif ($script eq 'setup-cli') {
    return $self->do_setup_cli();
  } elsif ($script eq 'smoketest') {
    return $self->do_smoketest();
  } elsif ($script eq 'stratos') {
    # Stratos is implemented as an extended addon in hooks/addon-stratos.pm
    # This delegates to the extended addon mechanism
    return $self->run_extended_addon();
  } else {
    # Handle other extended addons
    return $self->run_extended_addon();
  }
}

sub do_list {
  my ($self) = @_;
  info("The following addons are defined:");
  info("");
  info("  login             Log into the Cloud Foundry instance as the");
  info("                    admin user account.  This will overwrite local");
  info("                    cf CLI configuration!");
  info("");
  info("  setup-cli         Installs cf CLI plugins like 'Targets', which");
  info("                    helps to manage multiple Cloud Foundries from a");
  info("                    single jumpbox.");
  info("");
  info("  smoketest         Run the smoke tests errand on the first vm in the");
  info("                    api instance group.");
  info("");
  info("  stratos           Deploy Stratos, the Cloud Foundry web console.");
  info("");
  return 1;
}

sub do_login {
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

sub do_remigrate {
  my ($self) = @_;

  # Migrate the secrets by sourcing the migration script and calling its functions
  run({interactive => 1},
    'cd "$1"; source ./hooks/migrate-to-2.0; '.
    'validate_expected_vault_secrets; '.
    'correct_x509_certs; '.
    'migrate_credentials_to_credhub',
    $self->env->path
  );

  return 1;
}

sub do_setup_cli {
  my ($self) = @_;

  # Check for unexpected arguments
  if (scalar(@{$self->{args}}) > 0) {
    foreach my $arg (@{$self->{args}}) {
      if ($arg =~ /^-/ && $arg ne '-f') {
        bail("#R{[ERROR]} Bad option $arg: expecting -f");
      } elsif ($arg !~ /^-/) {
        bail("#R{[ERROR]} setup-cli does not take any arguments");
      }
    }
  }
  
  # Parse -f option
  my %options = $self->parse_options(['f']);
  my $force = $options{f} ? 1 : 0;

  my ($out, $rc) = run('cf list-plugin-repos | grep -q CF-Community');
  if ($rc != 0) {
    describe('Adding #G{Cloud Foundry Community} plugins repository...');
    run('cf add-plugin-repo CF-Community http://plugins.cloudfoundry.org');
  }

  ($out, $rc) = run('cf plugins | grep -q \'^cf-targets\'');
  if ($rc != 0) {
    describe('Installing the #C{cf-targets} plugin...');
    if ($force) {
      run('cf install-plugin -r CF-Community Targets -f');
    } else {
      run('cf install-plugin -r CF-Community Targets');
    }
  }

  run('cf plugins');

  return 1;
}

sub do_smoketest {
  my ($self) = @_;

  # This assumes $GENESIS_BOSH_COMMAND, $BOSH_ENVIRONMENT, and $BOSH_DEPLOYMENT
  # are set in the environment
  run({interactive => 1},
    '$GENESIS_BOSH_COMMAND -e "$BOSH_ENVIRONMENT" -d "$BOSH_DEPLOYMENT" run-errand smoke_tests'
  );

  return 1;
}

sub run_extended_addon {
  my ($self) = @_;

  # This will run the addon script in the $GENESIS_ADDON_SCRIPT file, if it exists.
  # Ex: hooks/addon-stratos for the stratos addon.
  # Pass all arguments to the extended addon handler
  run({interactive => 1}, 'run_extended_addon "$@"', @{$self->{args}});

  return 1;
}

1;
