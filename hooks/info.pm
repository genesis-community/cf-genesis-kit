# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
package Genesis::Hook::CF::Info;

use v5.20;
use warnings; # Genesis min perl version is 5.20
use Genesis qw/info error bail/;
# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook);
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
  my $upstream_version = $exodus_data->{'cf-deployment-version'} || 'unknown';
  my $upstream_hotfixes = $exodus_data->{'cf-deployment-hotfixes'} || 'false';
  my $upstream_url = $exodus_data->{'cf-deployment-releases'} || 'unknown';

  # Format hotfixes info
  my $hotfixes = "";
  if ($upstream_hotfixes eq 'true') {
    $hotfixes = " #Y{(+ hot-fixes)}";
  }

  # Display information
  # Note: The original used 'describe' which appears to be a helper function
  # that formats multi-line output with proper indentation and styling
  info(
    "Based on #M{cf-deployment %s}%s\n".
    "[cf-deployment-releases url: #c{%s}]\n".
    "\n".
    "Access to Cloud Foundry API:\n".
    "       url: #C{%s}\n".
    "  username: #M{%s}\n".
    "  password: #G{%s}\n",
    $upstream_version, $hotfixes, $upstream_url, $api_url, $admin, $password
  );

  # If the Load Balancer isn't availabe this will fail
  # Also fails if "cf" command is missing
  my $cf_api_outout = qx(cf api $api_url --skip-ssl-validation 2>&1);
  my $cf_curl_output = qx(cf curl /info 2>&1);
  my $curl_rc = $? >> 8; # Get the exit code

  bail(
    "  Error executing 'cf curl /info': $cf_curl_output\n"
  ) unless $curl_rc == 0;

  # Parse and format JSON for better display
  my $data = eval { JSON::PP::decode_json($cf_curl_output) };
  if ($@) {
    # JSON parsing error
    error "  Error parsing output: $@\n";
    error "  Raw output: $cf_curl_output\n";
  } else {
    # Pretty-print the JSON with 2-space indentation
    my $formatted = JSON::PP->new->pretty->canonical->encode($data);
    # Add two spaces prefix to each line
    my $curl_output = join("\n", map { "  $_" } split(/\n/, $formatted));
    info $curl_output;
  }

  return $self->done();
}

sub results {
  my $self = shift;
  return $self->completed ? 1 : 0;
}

1;
