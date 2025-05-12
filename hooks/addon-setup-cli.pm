#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::Addon::CF::SetupCLI v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
my $lib;
BEGIN {$lib = $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use lib $lib;

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info run/;
use Genesis::UI qw/describe/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0');
  return $obj;
}

sub cmd_details {
  return
  "Installs cf CLI plugins like 'Targets', which helps to manage multiple Cloud Foundries from a single jumpbox.\n".
  "Supports the following options:\n".
  "[[  #y{-f}                  >>Force installation of plugins, overwriting existing versions";
}

sub perform {
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

1;
