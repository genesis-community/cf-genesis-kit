#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker expandtab:
package Genesis::Hook::Addon::Stratos v1.0.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
my $lib;
BEGIN {$lib = $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use lib $lib;

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info warning run/;
use Genesis::Term qw/terminal_width/;

use YAML::PP;
use JSON::PP;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  my $obj->exodus_data = $self->exodus_data();
  return $obj;
}

sub cmd_details {
  return
  "Manage and display information about Stratos UI deployments. Supports the following commands:\n".
  "[[  #y{info}          >>Display information about the Stratos deployment\n".
  "[[  #y{deploy}        >>Deploy Stratos as a CF app\n".
  "[[  #y{open}          >>Open the Stratos UI in your browser\n\n".
  "Display Options:\n".
  "[[  #y{--json}         >>Output information in JSON format\n".
  "[[  #y{--urls-only}    >>Only display URLs\n\n".
  "Deploy Options:\n".
  "[[  #y{--force}        >>Force redeployment even if already deployed\n".
  "[[  #y{--skip-cf-check} >>Skip CF CLI availability check\n".
  "[[  #y{--file <path>}  >>Path to Stratos zip file (will download from GitHub if not specified)\n".
  "[[  #y{--buildpack <name>} >>Buildpack to use (default: binary_buildpack)\n".
  "[[  #y{--stack <name>} >>Stack to use (default: cflinuxfs4)\n".
  "[[  #y{--memory <size>} >>Memory allocation (default: 1512M)\n".
  "[[  #y{--disk <size>}  >>Disk allocation (default: 1024M)\n".
  "[[  #y{--timeout <seconds>} >>Application startup timeout (default: 180)\n".
  "[[  #y{--sgs}          >>Create security groups for VPC access\n";
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Parse options
  my %options = $self->parse_options([
      'json',           # Output in JSON format
      'urls-only',      # Only display URLs
      'force',          # Force redeployment
      'skip-cf-check',  # Skip CF CLI availability check
      'file=s',         # Path to Stratos zip file
      'buildpack=s',    # Buildpack to use
      'stack=s',        # Stack to use
      'memory=s',       # Memory allocation
      'disk=s',         # Disk allocation
      'timeout=i',      # Application startup timeout
      'sgs',            # Create security groups
    ],
  );

  # Apply default values for deployment options
  $options{buildpack} //= 'binary_buildpack';
  $options{stack} //= 'cflinuxfs4';
  $options{memory} //= '1512M';
  $options{disk} //= '1024M';
  $options{timeout} //= 180;

  # Get command (default to 'info')
  my $command = $self->{args}->[0] || 'info';

  bail("Unknown command: '$command'. Valid commands are 'info', 'deploy', and 'open'")
    unless ($command ~ /^(info|deploy|open)$/);

  # Determine the Stratos deployment info
  my $info = $self->_get_stratos_info($env);

  return $self->display_info($info, %options)
    if ($command eq 'info') ;

  return $self->deploy_stratos($env, $info, %options)
    if ($command eq 'deploy');

  return $self->open_in_browser($env, $info)
    if ($command eq 'open');

  return 1;
}

sub _get_stratos_info {
  my ($self, $env) = @_;

  # Get BOSH target if possible
  my $deployment_exists = 0;

  # Get deployment name from environment or configuration
  my $deployment_name = $env->lookup('stratos.deployment_name', $self->env->name . "-stratos");

  # Currently we don't support stratos via bosh deployment
  #my @deployments = $self->bosh->deployments();
  #$deployment_exists = grep { $_ eq $deployment_name } @deployments;

  # Get Stratos information from environment
  my $system_domain = $env->lookup('cf.system_domain', '');
  my $apps_domain = $env->lookup('cf.apps_domain', '');
  my $stratos_domain = "console.${apps_domain}";
  my $stratos_url = "https://${stratos_domain}";

  # Get CF configuration
  my $cf_api = $env->lookup('cf.api_url', '');
  my $cf_org = $env->lookup('stratos.cf_org', 'system');
  my $cf_space = $env->lookup('stratos.cf_space', 'stratos');
  my $cf_app_name = $env->lookup('stratos.cf_app_name', 'apps');

  # Get Stratos specific configuration
  my $stratos_version = $env->lookup('stratos.version', '4.4.1');
  my $stratos_admin = $env->lookup('stratos.admin_user', 'admin');

  # Get database connection information
  my $stratos_db_scheme = $env->lookup('stratos.db.scheme', 'postgres');
  my $stratos_db_hostname = $env->lookup('stratos.db.hostname', '');
  my $stratos_db_username = $env->lookup('stratos.db.username', 'stratos');
  my $stratos_db_port = $env->lookup('stratos.db.port', 5432);
  my $stratos_db_database = $env->lookup('stratos.db.database', 'stratos');
  my $stratos_db_sslmode = $env->lookup('stratos.db.sslmode', 'disabled');

  # Determine if Stratos is deployed as a CF app
  my $is_cf_app_deployed = 0;
  my $cf_app_status = "unknown";
  eval {
    my ($out, $rc) = run('cf app "$1" >/dev/null 2>&1', $cf_app_name);
    $is_cf_app_deployed = ($rc == 0);
    if ($is_cf_app_deployed) {
      ($out, $rc) = run('cf app "$1" | grep -E "^#?status:" | awk \'{print $2}\'', $cf_app_name);
      $cf_app_status = $out if $rc == 0;
      chomp($cf_app_status);
    }
  };

  # Get credentials from vault
  my $admin_password = "";
  my $session_secret = "";
  my $stratos_client = "";
  my $stratos_client_secret = "";

  eval {
    $admin_password = $env->vault->get($env->secrets_base . "stratos/admin_password");
  };

  eval {
    $session_secret = $env->vault->get($env->secrets_base . "stratos/session_secret");
  };

  # Try to get client credentials from exodus
  my $exodus_path = $env->lookup_genesis('exodus_base');
  eval {
    $stratos_client = $env->vault->get($exodus_path . ":stratos_client");
    $stratos_client_secret = $env->vault->get($exodus_path . ":stratos_secret");
  };

  # Build info structure
  return {
    name => $env->lookup('stratos.deployment_name', $env->name . "-stratos"),
    #status => $deployment_exists ? "Deployed via BOSH" :
    status => $is_cf_app_deployed ? "Deployed as CF app ($cf_app_status)" : "Not Deployed",
    url => $stratos_url,
    version => $stratos_version,
    admin_user => $stratos_admin,
    admin_password => $admin_password ? $admin_password : "",
    has_admin_password => $admin_password ? 1 : 0,
    session_secret => $session_secret ? $session_secret : "",
    cf_api => $cf_api,
    cf_org => $cf_org,
    cf_space => $cf_space,
    cf_app_name => $cf_app_name,
    is_cf_app_deployed => $is_cf_app_deployed,
    system_domain => $system_domain,
    apps_domain => $apps_domain,
    stratos_domain => $stratos_domain,

    # Database configuration
    db => {
      scheme => $stratos_db_scheme,
      hostname => $stratos_db_hostname,
      username => $stratos_db_username,
      port => $stratos_db_port,
      database => $stratos_db_database,
      sslmode => $stratos_db_sslmode,
    },

    # UAA client information
    client => {
      id => $stratos_client ? $stratos_client : "stratos_client",
      secret => $stratos_client_secret ? $stratos_client_secret : "stratos_secret",
    },
  };
}

sub display_info {
  my ($self, $info, %options) = @_;

  # Handle URLs-only mode
  if ($options{'urls-only'}) {
    if ($info->{url}) {
      info($info->{url});
    } else {
      info("No Stratos URL configured");
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
    if ($info->{has_admin_password}) {
      info("  Admin Password: %s", $info->{admin_password});
    } else {
      info("  Admin Password: Not found in vault");
    }

    # Client information
    info("\nUAA Client Details:");
    info("  Client ID: %s", $info->{client}->{id});
    info("  Client Secret: %s", $info->{client}->{secret});

    # CF Information
    if ($info->{cf_api}) {
      info("\nCloud Foundry Details:");
      info("  API: %s", $info->{cf_api});
      info("  System Domain: %s", $info->{system_domain});
      info("  Apps Domain: %s", $info->{apps_domain});
      info("  Organization: %s", $info->{cf_org});
      info("  Space: %s", $info->{cf_space});
      info("  App Name: %s", $info->{cf_app_name});
    }

    # Database information if available
    if ($info->{db}->{hostname}) {
      info("\nDatabase Configuration:");
      info("  Scheme: %s", $info->{db}->{scheme});
      info("  Hostname: %s", $info->{db}->{hostname});
      info("  Port: %s", $info->{db}->{port});
      info("  Database: %s", $info->{db}->{database});
      info("  Username: %s", $info->{db}->{username});
      info("  SSL Mode: %s", $info->{db}->{sslmode});
    }

    # Show helpful commands
    info("\nHelpful Commands:");
    info("  Open in browser: %s %s stratos open",
      $env->get_call_path(), $env->name);
    info("  Deploy Stratos: %s %s stratos deploy",
      $env->get_call_path(), $env->name);

    if ($info->{is_cf_app_deployed}) {
      info("  View CF app logs: cf logs %s --recent", $info->{cf_app_name});
      info("  Restart CF app: cf restart %s", $info->{cf_app_name});
    }
  }

  return 1;
}

sub deploy_stratos {
  my ($self, $env, $info, %options) = @_;

  $env->notify("deploying Stratos as a CF application...");

  # Check if already deployed
  if ($info->{is_cf_app_deployed} && !$options{force}) {
    info("Stratos is already deployed. Use --force to redeploy.");
    return 1;
  }

  # Check CF CLI is available
  unless ($options{'skip-cf-check'}) {
    my ($out, $rc) = run('cf --version >/dev/null 2>&1');
    bail("CF CLI not found. Please install it or use --skip-cf-check if you're sure it's available.")
    if $rc != 0;
  }

  # Check CF API is configured
  bail("No CF API URL configured. Set cf.api_url in your environment.")
  unless $info->{cf_api};

  # Check if we're logged in to CF
  my ($out, $rc) = run('cf target >/dev/null 2>&1');
  if ($rc != 0) {
    warning("Not logged in to CF. Please log in first with 'cf login'");
    bail("CF authentication required before deployment");
  }

  # Create a temporary directory for the deployment
  my $tmp_dir = $self->tempdir('stratos-deploy');
  eval {
    info("Preparing Stratos deployment...");

    # Get environment config and exodus data
    my $exodus_path = $env->lookup_genesis('exodus_base');
    my $system_api_domain = $env->lookup('cf.api_url', '');
    $system_api_domain =~ s/^https?:\/\///; # Remove protocol

    # Get database connection information
    my $stratos_db_scheme = $env->lookup('stratos.db.scheme', 'postgres');
    my $stratos_db_hostname = $env->lookup('stratos.db.hostname', '');
    my $stratos_db_username = $env->lookup('stratos.db.username', 'stratos');
    my $stratos_db_password = $env->lookup('stratos.db.password', 'stratos');
    my $stratos_db_port = $env->lookup('stratos.db.port', 5432);
    my $stratos_db_database = $env->lookup('stratos.db.database', 'stratos');
    my $stratos_db_sslmode = $env->lookup('stratos.db.sslmode', 'disabled');

    # Get or generate session store secret
    my $stratos_session_store_sekret = "";
    eval {
      $stratos_session_store_sekret = $env->vault->get($env->secrets_base . "stratos/session_secret");
    };
    unless ($stratos_session_store_sekret) {
      # Generate session secret
      my $random = rand(10000);
      $stratos_session_store_sekret = `echo $random | sha256sum | awk '{print \$1}'`;
      chomp($stratos_session_store_sekret);
      eval {
        $env->vault->set($env->secrets_base . "stratos/session_secret", $stratos_session_store_sekret);
      };
    }

    # Get client credentials from vault/exodus
    my $stratos_client = "";
    my $stratos_client_secret = "";
    eval {
      $stratos_client = $env->vault->get($exodus_path . ":stratos_client");
      $stratos_client_secret = $env->vault->get($exodus_path . ":stratos_secret");
    };
    unless ($stratos_client && $stratos_client_secret) {
      warning("Stratos client credentials not found in vault. Using defaults.");
      $stratos_client = "stratos_client";
      $stratos_client_secret = "stratos_secret";
    }

    # Get Stratos version
    my $stratos_version = $env->lookup('stratos.version', '4.4.1');
    my $stratos_releases_url = "https://github.com/cloudfoundry-community/stratos/releases/download/${stratos_version}/stratos-ui-packaged.zip";
    my $stratos_sso_options = $env->lookup('stratos.sso_options', 'nosplash, logout');

    # Domain setup
    my $apps_domain = $env->lookup('cf.apps_domain', '');
    my $stratos_domain = "console.${apps_domain}";

    # Get file or download Stratos release
    my $chdir = $tmp_dir;
    chdir $chdir or bail("Could not change to temporary directory: $!");

    if ($options{file} && -f $options{file}) {
      info("Using provided Stratos file: %s", $options{file});
      run('unzip -o "$1"', $options{file});
    } else {
      info("Downloading Stratos %s...", $stratos_version);
      run('wget "$1" && unzip -o stratos-ui-packaged.zip && rm stratos-ui-packaged.zip',
        $stratos_releases_url);
    }

    # Target the correct CF organization and space
    info("Targeting CF organization 'system' and space 'stratos'...");
    run('cf create-space -o system stratos');
    run('cf target -o system -s stratos');

    # Configure database via CUPS
    info("Configuring Stratos Database Connection via CUPS Services");
    my $svc_name = "console_db_tls_verify_ca";

    # Check if service already exists
    my $org_guid = `cf org system --guid`;
    chomp($org_guid);
    my $space_guid = `cf space stratos --guid`;
    chomp($space_guid);

    my $svc_exists = `cf curl "/v3/service_instances?organization_guids=${org_guid}&space_guids=${space_guid}" | jq -r '.resources[]|select(.name|test("${svc_name}"))|.name'`;
    chomp($svc_exists);

    # Prepare database connection JSON
    my $db_json = '{ "uri": "' . $stratos_db_scheme . '://", ' .
    '"username":"' . $stratos_db_username . '", ' .
    '"password":"' . $stratos_db_password . '", ' .
    '"hostname":"' . $stratos_db_hostname . '", ' .
    '"port":"' . $stratos_db_port . '", ' .
    '"dbname":"' . $stratos_db_database . '", ' .
    '"sslmode":"' . $stratos_db_sslmode . '" }';

    # Create or update the service
    if ($svc_exists eq $svc_name) {
      info("Service %s was found, updating existing cups service definition.", $svc_name);
      run('cf uups "$1" -p \'$2\'', $svc_name, $db_json);
    } else {
      info("Service %s was not found, creating cups service definition.", $svc_name);
      run('cf cups "$1" -p \'$2\'', $svc_name, $db_json);
    }

    # Create security groups if requested
    if ($options{sgs}) {
      info("Creating security groups for VPC access...");
      open my $sg_file, '>', "$tmp_dir/vpc-sg.json" or bail("Could not create security group file: $!");
      print $sg_file qq|[
      {
      "protocol": "all",
      "destination": "10.0.0.0-10.255.255.255"
      }
      ]|;
      close $sg_file;

      run('cf create-security-group vpc "$1" || true', "$tmp_dir/vpc-sg.json");
      run('cf bind-staging-security-group vpc || true');
      run('cf bind-running-security-group vpc || true');
    }

    # Create application manifest
    info("Creating application manifest...");
    open my $manifest, '>', "$tmp_dir/manifest.yml" or bail("Could not create manifest file: $!");
    print $manifest qq|---
    applications:
    - name: apps
      host: console
      health-check-type: port
      memory: $options{memory}
      disk_quota: $options{disk}
      timeout: $options{timeout}
      buildpack: $options{buildpack}
      stack: $options{stack}
      env:
      CF_API_URL: https://$system_api_domain
      CF_CLIENT: $stratos_client
      CF_CLIENT_SECRET: $stratos_client_secret
      SESSION_STORE_SECRET: $stratos_session_store_sekret
      SSO_OPTIONS: "$stratos_sso_options"
      SSO_WHITELIST: "https://$stratos_domain/*"
      SSO_LOGIN: "true"
      DB_SSL_MODE: "$stratos_db_sslmode"
      services:
      - console_db_tls_verify_ca
    |;
    close $manifest;

    # Deploy the application
    info("Deploying Stratos application...");
    run('cf push -f "$1"', "$tmp_dir/manifest.yml");

    # Update the status in the info object
    $info->{is_cf_app_deployed} = 1;
    $info->{status} = "Deployed as CF app (running)";
    $info->{url} = "https://$stratos_domain";

    info("\nStratos deployment completed successfully!");
  };

  if ($@) {
    bail("Failed to deploy Stratos: $@");
  }

  chdir('/');  # Go back to root directory

  $self->display_info($info, %options);

  return 1;
}

sub _generate_password {
  my ($self, $length) = @_;
  $length ||= 16;

  my @chars = ('a'..'z', 'A'..'Z', '0'..'9', '_', '-', '!', '@', '#', '$', '%', '^', '&', '*');
  my $password = '';
  $password .= $chars[int(rand(scalar @chars))] for (1..$length);

  return $password;
}

sub open_in_browser {
  my ($self, $env, $info) = @_;

  if ($info->{url}) {
    my $cmd = $^O eq 'darwin' ? 'open' :
    ($^O eq 'MSWin32' ? 'start' : 'xdg-open');

    info("Opening Stratos UI in browser: %s", $info->{url});
    system("$cmd '$info->{url}' >/dev/null 2>&1 &");
  } else {
    bail("Cannot open Stratos UI: No URL configured");
  }

  return 1;
}

1;
