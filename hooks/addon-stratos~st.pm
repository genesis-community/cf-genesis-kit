#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::CF::Stratos v1.0.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/bail info warning run/;
use Genesis::Term qw/terminal_width/;
use Genesis::UI qw/prompt_for_boolean/;
use parent qw(Genesis::Hook::Addon);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');

	# Parse options first before getting info so we can check for version override
	my %options = $obj->parse_options([
		'json',           # Output in JSON format
		'urls-only',      # Only display URLs
		'force',          # Force redeployment
		'skip-cf-check',  # Skip CF CLI availability check
		'file=s',         # Path to Stratos zip file
		'version=s',      # Stratos version to deploy
		'buildpack=s',    # Buildpack to use
		'stack=s',        # Stack to use
		'memory=s',       # Memory allocation
		'disk=s',         # Disk allocation
		'timeout=i',      # Application startup timeout
	]);

	$obj->{options} = \%options;
	$obj->{info} = $obj->_get_stratos_info();
	return $obj;
}

sub cmd_details {
	return
	"Manage and display information about Stratos UI deployments. Supports the following commands:\n".
	"[[  #y{info}                >>Display information about the Stratos deployment\n".
	"[[  #y{deploy}              >>Deploy Stratos as a CF app\n".
	"[[  #y{open}                >>Open the Stratos UI in your browser\n\n".
	"Display Options:\n".
	"[[  #y{--json}              >>Output information in JSON format\n".
	"[[  #y{--urls-only}         >>Only display URLs\n\n".
	"Deploy Options:\n".
	"[[  #y{--buildpack <name>}  >>Buildpack to use (default: binary_buildpack)\n".
	"[[  #y{--disk <size>}       >>Disk allocation (default: 1024M)\n".
	"[[  #y{--file <path>}       >>Path to Stratos zip file (will download from GitHub if not specified)\n".
	"[[  #y{--force}             >>Force redeployment even if already deployed\n".
	"[[  #y{--memory <size>}     >>Memory allocation (default: 1512M)\n".
	"[[  #y{--skip-cf-check}     >>Skip CF CLI availability check\n".
	"[[  #y{--stack <name>}      >>Stack to use (default: cflinuxfs4)\n".
	"[[  #y{--timeout <seconds>} >>Application startup timeout (default: 180)\n".
	"[[  #y{--version <ver>}     >>Stratos version to deploy (overrides configuration and defaults)\n";
}

sub perform {
	my ($self) = @_;
	my $env = $self->env;
	my %options = %{$self->{options}}; # Use options already parsed in init

	# Apply default values for deployment options
	$options{buildpack} //= 'binary_buildpack';
	$options{stack} //= 'cflinuxfs4';
	$options{memory} //= '1512M';
	$options{disk} //= '1024M';
	$options{timeout} //= 180;

	# Get command (default to 'info')
	my $command = $self->{args}->[0] || 'info';

	bail(
		"Unknown command: '$command'. Valid commands are 'info', 'deploy', and 'open'"
	) unless ($command =~ /^(info|deploy|open)$/);

	# Determine the Stratos deployment info
	return $self->display_info(%options) if ($command eq 'info') ;
	return $self->deploy_stratos(%options) if ($command eq 'deploy');
	return $self->open_in_browser() if ($command eq 'open');
}

sub _get_stratos_info {
  my ($self) = @_;
	my $env = $self->env;

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
	my $stratos_domain = '';
	my $stratos_url = '';

	# Get CF configuration
	my $cf_api = $env->lookup('cf.api_url', '');
	my $cf_org = $env->lookup('stratos.cf_org', 'system');
	my $cf_space = $env->lookup('stratos.cf_space', 'stratos');
	my $cf_app_name = $env->lookup('stratos.cf_app_name', 'apps');

	# Get Stratos specific configuration
	# Command line version takes precedence over environment config
	my $stratos_version = $self->{options}->{version} // $env->lookup('stratos.version', '4.8.1');
	my $stratos_admin = $env->lookup('stratos.admin_user', 'admin');

	# Get database connection information

  # Default configuration
  $stratos_domain = "console.${apps_domain}";
  $stratos_url = "https://${stratos_domain}";
  my $stratos_db_scheme = $env->params->{db_scheme} || 'postgres';
  my $stratos_db_hostname = $env->params->{db_hostname} || '';
  my $stratos_db_username = $env->params->{db_username} || 'stratos';
  my $stratos_db_password = $env->params->{db_password} || 'stratos';
  my $stratos_db_port = $env->params->{db_port} || 5432;
  my $stratos_db_database = $env->params->{db_database} || 'stratos';
  my $stratos_db_sslmode = $env->params->{db_sslmode} || 'disabled'; # verify-ca

	# Check for OCFP requested feature
  if ($self->env->has_feature('ocfp')) {
		# Get Stratos configuration from vault.
    # FIXME: Should we bail if not set?
    $stratos_domain = $env->vault->get($env->secrets_base . "fqdns:stratos") || '';
		$stratos_url = "https://${stratos_domain}";
    $stratos_db_scheme = $env->vault->get($env->secrets_base . "stratos/db/stratos:scheme") || 'postgres';
    $stratos_db_hostname = $env->vault->get($env->secrets_base . "stratos/db/stratos:hostname") || '';
    $stratos_db_username = $env->vault->get($env->secrets_base . "stratos/db/stratos:username") || 'stratos';
    $stratos_db_password = $env->vault->get($env->secrets_base . "stratos/db/stratos:password") || 'stratos';
    $stratos_db_port = $env->vault->get($env->secrets_base . "stratos/db/stratos:port") || 5432;
    $stratos_db_database = $env->vault->get($env->secrets_base . "stratos/db/stratos:database")|| 'stratos';
    $stratos_db_sslmode = "disable"; # or "verify-ca"
	}

	# Determine if Stratos is deployed as a CF app
	my $is_cf_app_deployed = 0;
	my $cf_app_status = "unknown";
  my ($out, $rc) = run('cf app "$1" >/dev/null 2>&1', $cf_app_name);
  $is_cf_app_deployed = ($rc == 0);
  if ($is_cf_app_deployed) {
    ($out, $rc) = run('cf app "$1" | grep -E "^#?status:" | awk \'{print $2}\'', $cf_app_name);
    $cf_app_status = $out if $rc == 0;
    chomp($cf_app_status);
  }
  # FIXME: Should we bail or generate instead of "" if not set?
  my $admin_password = $env->vault->get($env->secrets_base . "stratos/admin_password") || "";
  my $session_secret = $env->vault->get($env->secrets_base . "stratos/session_secret") || "";
  my $data = $self->exodus_data;
  # FIXME: Should we bail if not set?
  my $stratos_client = $data->{stratos_client} || "";
  my $stratos_client_secret = $data->{stratos_secret} || "";

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
			password => $stratos_db_password,
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
	my ($self, %options) = @_;
	my $info = $self->{info};

	# If version was specified on command line, update the info object
	if ($options{version} && $options{version} ne $info->{version}) {
		$info->{version} = $options{version};
		info("Note: Using Stratos version %s from command line", $options{version});
	}

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
		# Output as JSON using spruce
		my $tmp = $self->tempdir('stratos-info-json');
		open my $fh, '>', "$tmp/info.yml" or bail("Could not create temporary file: $!");
		print $fh _to_yaml($info);
		close $fh;
		
		my ($json_out, $rc) = run('spruce json "$1"', "$tmp/info.yml");
		bail("Failed to convert to JSON: $!") if $rc != 0;
		info($json_out);
		return 1;
	}
  # Otherwise, display in a human-readable format
  # TODO: Discuss if we want to simply dump as YAML?
  info(
    "\n" . "=" x terminal_width() .
    "\nStratos UI Deployment: %s" .
    "\n" . "=" x terminal_width() .
    "\nStatus: %s".
    "\nURL: %s".
    "\nVersion: %s" .
    "\n\nAuthentication:" .
    "\n  Admin User: %s".
    "\n  Admin Password: %s" .
    "\nUAA Client Details:" .
    "\n  Client ID: %s" .
    "\n  Client Secret: %s",
    $info->{name},
    $info->{status},
    $info->{url} ? $info->{url} : "Not configured",
    $info->{version},
    $info->{admin_user},
    $info->{has_admin_password} ? $info->{admin_password} : "Not found in vault",
    $info->{client}->{id},
    $info->{client}->{secret}
  );

  if ($info->{cf_api}) {
    info(
      "\n" . "=" x terminal_width() .
      "\nCloud Foundry Details:" .
      "\n" . "=" x terminal_width() .
      "\n  API: %s" .
      "\n  System Domain: %s" .
      "\n  Apps Domain: %s" .
      "\n  Organization: %s" .
      "\n  Space: %s" .
      "\n  App Name: %s",
      $info->{cf_api},
      $info->{system_domain},
      $info->{apps_domain},
      $info->{cf_org},
      $info->{cf_space},
      $info->{cf_app_name}
    );
  }

  # Database information if available
  if ($info->{db}->{hostname}) {
    info("\nDatabase Configuration:\n" .
      "  Scheme: %s\n" .
      "  Hostname: %s\n" .
      "  Port: %s\n" .
      "  Database: %s\n" .
      "  Username: %s\n" .
      "  SSL Mode: %s",
      $info->{db}->{scheme},
      $info->{db}->{hostname},
      $info->{db}->{port},
      $info->{db}->{database},
      $info->{db}->{username},
      $info->{db}->{sslmode}
    );
  }

		# Show helpful commands
		info("\nHelpful Commands:");
		info("  Open in browser: %s %s stratos open",
			$self->env->get_call_path_with_env()); # returns two strings
		info("  Deploy Stratos: %s %s stratos deploy",
			$self->env->get_call_path_with_env()); # returns two strings

  if ($info->{is_cf_app_deployed}) {
    info("  View CF app logs: cf logs %s --recent", $info->{cf_app_name});
    info("  Restart CF app: cf restart %s", $info->{cf_app_name});
  }

  return $self->done();
}

sub deploy_stratos {
	my ($self, %options) = @_;
	my $env = $self->env;
	my $info = $self->{info};

	$env->notify("deploying Stratos as a CF application...");

	# Check if already deployed
	if ($info->{is_cf_app_deployed} && !$options{force}) {
		info("Stratos is already deployed. Use --force to redeploy.");
		return 1;
	}

	# Check CF CLI is available
	unless ($options{'skip-cf-check'}) {
		my ($out, $rc) = run('cf --version >/dev/null 2>&1');
		bail(
			"CF CLI not found. Please install it or use --skip-cf-check if you're sure it's available."
		) if $rc != 0;
	}

	# Check CF API is configured
	bail(
		"No CF API URL configured. Set cf.api_url in your environment."
	) unless $info->{cf_api};

	# Check if we're logged in to CF
	my ($out, $rc) = run('cf target >/dev/null 2>&1');
	if ($rc != 0) {
		warning("Not logged in to CF. Please log in first with 'cf login'");
		bail(
			"CF authentication required before deployment"
		);
	}

	# Create a temporary directory for the deployment
	my $tmp_dir = $self->tempdir('stratos-deploy');
  info("Preparing Stratos deployment...");

  # Get environment config and exodus data
  my $data = $self->exodus_data;
  my $system_api_domain = $data->{cf}{api_url} || '';
  $system_api_domain =~ s/^https?:\/\///; # Remove protocol

  # Get database connection information
  my $stratos_db_scheme = $data->{stratos}{db}{scheme} || 'postgres';
  my $stratos_db_hostname = $data->{stratos}{db}{hostname} || '';
  my $stratos_db_username = $data->{stratos}{db}{username} || 'stratos';
  my $stratos_db_password = $data->{stratos}{db}{password} || 'stratos';
  my $stratos_db_port = $data->{stratos}{db}{port} || 5432;
  my $stratos_db_database = $data->{stratos}{db}{database} || 'stratos';
  my $stratos_db_sslmode = $data->{stratos}{db}{sslmode} || 'disabled';

  # Get or generate session store secret
  my $stratos_session_store_sekret = $env->vault->get($env->secrets_base . "stratos/session_secret");
  unless ($stratos_session_store_sekret) {
    # Generate session secret
    my $random = rand(10000);
    $stratos_session_store_sekret = `echo $random | sha256sum | awk '{print \$1}'`;
    chomp($stratos_session_store_sekret);
    # FIXME: Should we bail if set fails?
    $env->vault->set($env->secrets_base . "stratos/session_secret", $stratos_session_store_sekret);
  }

  # FIXME: Should we bail if not set?
  my $stratos_client = $data->{"stratos_client"} || "";
  my $stratos_client_secret = $data->{stratos_secret} || "";

  unless ($stratos_client && $stratos_client_secret) {
    warning("Stratos client credentials not found in vault. Using defaults.");
    $stratos_client = "stratos_client";
    $stratos_client_secret = "stratos_secret";
  }

  # Get Stratos version - command line takes precedence over environment config
  my $stratos_version = $options{version} // $info->{version};
  info("Using Stratos version: %s%s", $stratos_version, $options{version} ? " (from command line)" : "");
  my $stratos_releases_url = "https://github.com/cloudfoundry/stratos/releases/download/v${stratos_version}/stratos-ui-${stratos_version}.zip";
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
    run('wget "$1" && unzip -o stratos-ui-$2.zip && rm stratos-ui-$2.zip',
      $stratos_releases_url, $stratos_version);
  }

  # Target the correct CF organization and space
  info("Targeting CF organization 'system' and space 'stratos'...");
  run('cf create-space -o system stratos');
  run('cf target -o system -s stratos');

  # Configure database via CUPS
  info("Configuring Stratos Database Connection via CUPS Services");
  my $svc_name = "console_db_tls_verify_ca";

  # Check if service already exists
  my $org_guid = `cf org system --guid`; chomp($org_guid);
  my $space_guid = `cf space stratos --guid`; chomp($space_guid);
  my $svc_exists = `cf curl "/v3/service_instances?organization_guids=${org_guid}&space_guids=${space_guid}" | jq -r '.resources[]|select(.name|test("${svc_name}"))|.name'`; chomp($svc_exists);

  # Prepare database connection JSON using spruce
  open my $db_fh, '>', "$tmp_dir/db.yml" or bail("Could not create database config file: $!");
  print $db_fh <<EOF;
uri: "$stratos_db_scheme://"
username: "$stratos_db_username"
password: "$stratos_db_password"
hostname: "$stratos_db_hostname"
port: $stratos_db_port
dbname: "$stratos_db_database"
sslmode: "$stratos_db_sslmode"
EOF
  close $db_fh;
  
  my ($db_json, $rc_db) = run('spruce json "$1"', "$tmp_dir/db.yml");
  bail("Failed to convert database config to JSON") if $rc_db != 0;
  chomp($db_json);

  # Create or update the service
  if ($svc_exists eq $svc_name) {
    info("Service %s was found, updating existing cups service definition.", $svc_name);
    run('cf uups "$1" -p \'$2\'', $svc_name, $db_json);
  } else {
    info("Service %s was not found, creating cups service definition.", $svc_name);
    run('cf cups "$1" -p \'$2\'', $svc_name, $db_json);
  }

  # Create application manifest
  info("Creating application manifest...");
  open my $manifest, '>', "$tmp_dir/manifest.yml" or bail("Could not create manifest file: $!");
  print $manifest <<EOF;
---
applications:
- name: apps
  host: console
  health-check-type: port
  memory: $options{memory}
  disk_quota: $options{disk}
  timeout: $options{timeout}
  buildpacks:
  - $options{buildpack}
  stack: $options{stack}
  env:
    CF_API_URL: https://$system_api_domain
    CF_CLIENT: $stratos_client
    CF_CLIENT_SECRET: $stratos_client_secret
    SESSION_STORE_SECRET: $stratos_session_store_sekret
    SSO_OPTIONS: $stratos_sso_options
    SSO_WHITELIST: https://$stratos_domain/*
    SSO_LOGIN: "true"
    DB_SSL_MODE: $stratos_db_sslmode
  services:
  - console_db_tls_verify_ca
EOF
  close $manifest;

  # Deploy the application
  info("Deploying Stratos application...");
  my ($out,$rc,$err) = run('cf push -f "$1"', "$tmp_dir/manifest.yml");
  bail(
    "Failed to deploy Stratos: %s", $err
  ) unless $rc == 0;

  # Update the status in the info object
  $info->{is_cf_app_deployed} = 1;
  $info->{status} = "Deployed as CF app (running)";
  $info->{url} = "https://$stratos_domain";

  info("\nStratos deployment completed successfully!");

  chdir('/');  # Go back to root directory

  $self->display_info(%options);

  return $self->done();
}

sub _generate_password {
  my ($self, $length) = @_;
  $length ||= 16;

  my @chars = ('a'..'z', 'A'..'Z', '0'..'9', '_', '-', '!', '@', '#', '$', '%', '^', '&', '*');
  my $password = '';
  $password .= $chars[int(rand(scalar @chars))] for (1..$length);

  return $password;
}

sub _to_yaml {
  my ($data, $indent) = @_;
  $indent //= 0;
  my $prefix = "  " x $indent;
  my $result = "";
  
  if (ref($data) eq 'HASH') {
    for my $key (sort keys %$data) {
      $result .= "${prefix}$key: ";
      my $value = $data->{$key};
      if (ref($value)) {
        $result .= "\n" . _to_yaml($value, $indent + 1);
      } else {
        $value //= '';
        if ($value =~ /[\n:]/ || $value eq '') {
          $value =~ s/"/\\"/g;
          $result .= "\"$value\"\n";
        } else {
          $result .= "$value\n";
        }
      }
    }
  } elsif (ref($data) eq 'ARRAY') {
    for my $item (@$data) {
      $result .= "${prefix}- ";
      if (ref($item)) {
        $result .= "\n" . _to_yaml($item, $indent + 1);
      } else {
        $item //= '';
        $result .= "$item\n";
      }
    }
  }
  
  return $result;
}

sub open_in_browser {
  my ($self) = @_;
  my $info = $self->{info};

  bail(
    "Cannot open Stratos UI: No URL configured"
  ) unless $info->{url};

  my $cmd = $^O eq 'darwin' ? 'open' : ($^O eq 'MSWin32' ? 'start' : 'xdg-open');
  info(
    "Opening Stratos UI in browser: %s",
    $info->{url}
  );
  system("$cmd '$info->{url}' >/dev/null 2>&1 &");

  return $self->done();
}

1;
