#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::CF::SetupCLI v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/bail info run/;
use Genesis::UI qw/prompt_for_boolean/;
use parent qw(Genesis::Hook::Addon);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";
use File::Basename qw/basename/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
  "Installs cf CLI plugins like 'Targets', which helps to manage multiple Cloud Foundries from a single jumpbox.\n".
  "Supports the following options:\n".
  "[[  #y{--f}                 >>Force installation of plugins, overwriting existing versions";
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Parse options according to the proper pattern
  my %options = $self->parse_options([
    'f',   # Force installation of plugins
  ]);

  # Check for unexpected arguments
  if (scalar(@{$self->{args}}) > 0) {
    bail("#R{[ERROR]} setup-cli does not take any arguments");
  }

  my $force = $options{f} ? 1 : 0;

  my ($out, $rc) = run('cf list-plugin-repos | grep -q CF-Community');
  if ($rc != 0) {
    info('Adding #G{Cloud Foundry Community} plugins repository...');
    run('cf add-plugin-repo CF-Community http://plugins.cloudfoundry.org');
  }

  ($out, $rc) = run('cf plugins | grep -q \'^cf-targets\'');
  bail("#R{[ERROR]} cf plugins listing failed with rc=$rc") unless ( $rc == 0 );

  info('Installing the #C{cf-targets} plugin...');
  cmd = 'cf install-plugin -r CF-Community Targets';
  cmd += ' -f' if ($force);
  run(cmd)

  run('cf plugins');

  return $self->done();
}

1;
