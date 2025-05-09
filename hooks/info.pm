#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::CF::Info v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

use parent qw(Genesis::Hook);

use Genesis;
use JSON::PP;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  return $obj;
}

sub perform {
  my $self = shift;
  my $env = $self->env;

  # Get exodus data
  my $exodus_data = $env->exodus_lookup('.');

  # Extract domain information
  my $system_domain = $exodus_data->{system_domain} || "system.".$exodus_data->{base_domain};
  my $api_domain = $exodus_data->{api_domain} || "api.$system_domain";
  my $api_url = "https://$api_domain";

  # Extract credentials
  my $admin = $exodus_data->{admin_username};
  my $password = $exodus_data->{admin_password};

  # Get CF deployment information
  my $upstream_version = $exodus_data->{'cf-deployment-version'};
  my $upstream_hotfixes = $exodus_data->{'cf-deployment-hotfixes'} || 'false';
  my $upstream_url = $exodus_data->{'cf-deployment-releases'};

  # Format hotfixes info
  my $hotfixes = "";
  if ($upstream_hotfixes eq 'true') {
    $hotfixes = " #Y{(+ hot-fixes)}";
  }

  # Display information
  # Note: The original used 'describe' which appears to be a helper function
  # that formats multi-line output with proper indentation and styling
  $env->notify(
    "Based on #M{cf-deployment %s}%s\n".
    "[url: #c{%s}]\n".
    "\n".
    "Access to Cloud Foundry API:\n".
    "       url: #C{%s}\n".
    "  username: #M{%s}\n".
    "  password: #G{%s}",
    $upstream_version, $hotfixes, $upstream_url,
    $api_url, $admin, $password
  );

  # Make API request using curl (similar to the bash script)
  print "\n";
  my ($curl_output, $curl_rc, $curl_err) = run(
    'curl -m5 -Lsk "$1/v2/info" | jq -Cr . | sed -e \'s/^/  /\'',
    $api_url
  );

  if ($curl_rc == 0) {
    print $curl_output;
  }

  $self->done(1);
  return 1;
}

sub results {
  my $self = shift;
  return $self->completed ? 1 : 0;
}

1;
