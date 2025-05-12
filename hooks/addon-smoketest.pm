#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::Addon::CF::Smoketest v2.7.0;

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
  "Run the smoke tests errand on the first vm in the api instance group.";
}

sub perform {
  my ($self) = @_;
  
  # This assumes $GENESIS_BOSH_COMMAND, $BOSH_ENVIRONMENT, and $BOSH_DEPLOYMENT
  # are set in the environment
  run({interactive => 1},
    '$GENESIS_BOSH_COMMAND -e "$BOSH_ENVIRONMENT" -d "$BOSH_DEPLOYMENT" run-errand smoke_tests'
  );

  return 1;
}

1;
