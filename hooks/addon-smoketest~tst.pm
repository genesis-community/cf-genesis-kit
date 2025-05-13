#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::CF::Smoketest v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/bail info run/;
use Genesis::UI qw/prompt_for_boolean/;
use parent qw(Genesis::Hook::Addon);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
  "Run the smoke tests errand on the first vm in the api instance group.";
}

sub perform {
  my ($self) = @_;

  $self->bosh->execute(
    'run-errand',
    'smoke_tests',
    {interactive => 1}, # Run in interactive mode means seeing output as it happens
  )

  return $self->done();
}

1;
