package Genesis::Hook::Addon::CF::Stratos v3.0.1;

use v5.20;
use warnings;    # Genesis min perl version is 5.20
use Genesis       qw/bail info warning run curl mkdir_or_fail mkfile_or_fail/;
use Genesis::Term qw/terminal_width/;
use Genesis::UI   qw/prompt_for_boolean/;
use File::Basename;


# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . './.genesis/lib'; }

use parent qw(Genesis::Hook::Addon);

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');

	# Parse options first before getting info so we can check for version override
	my %options = $obj->parse_options(
		[
			'json',             # Output in JSON format
			'urls-only',        # Only display URLs
			'force',            # Force redeployment
			'skip-cf-check',    # Skip CF CLI availability check
			'file=s',           # Path to Stratos zip file
			'version=s',        # Stratos version to deploy
			'buildpack=s',      # Buildpack to use
			'stack=s',          # Stack to use
			'memory=s',         # Memory allocation
			'disk=s',           # Disk allocation
			'timeout=i',        # Application startup timeout
		]
	);

	$obj->{options} = \%options;
	$obj->{info}    = $obj->_get_stratos_info();
	return $obj;
}

sub cmd_details {
	return
	"Manage and display information about Stratos UI deployments. Supports the following commands:\n".
	"[[  #y{info}                >>Display information about the Stratos deployment\n".
	"[[  #y{deploy}              >>Deploy Stratos as a CF app\n".
	"[[  #y{open}                >>Open the Stratos UI in your br.owser\n\n".
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
	my ($self)  = @_;
	my $env     = $self->env;
	my %options = %{ $self->{options} };    # Use options already parsed in init

	# Apply default values for deployment options
	$options{buildpack} //= 'binary_buildpack';
	$options{stack}     //= 'cflinuxfs4';
	$options{memory}    //= '1512M';
	$options{disk}      //= '1024M';
	$options{timeout}   //= 180;

	# Get command (default to 'info')
	my $command = $self->{args}->[0] || 'info';

	bail("Unknown command: '$command'. Valid commands are 'info', 'deploy', and 'open'")
	  unless ( $command =~ /^(info|deploy|open)$/ );

	# Determine the Stratos deployment info
	return $self->display_info(%options)   if ( $command eq 'info' );
	return $self->deploy_stratos(%options) if ( $command eq 'deploy' );
	return $self->open_in_browser()        if ( $command eq 'open' );
}

sub _get_stratos_info {
	my ($self) = @_;
	my $env = $self->env;

	# Get BOSH target if possible
	my $deployment_exists = 0;

	# Get deployment name from environment or configuration
	my $deployment_name = $env->lookup( 'stratos.deployment_name', $self->env->name . "-stratos" );

	# Currently we don't support stratos via bosh deployment
	#my @deployments = $self->bosh->deployments();
	#$deployment_exists = grep { $_ eq $deployment_name } @deployments;

	# Get CF configuration
	my $cf_api      = $self->exodus_data('api_domain');
	my $cf_org      = $env->lookup('params.stratos.cf_org',   'system');
	my $cf_space    = $env->lookup('params.stratos.cf_space', 'stratos');
	my $apps_domain = $env->lookup('cf.apps_domain',          '');

	# Get Stratos information from environment
	my $app_name       =  $env->lookup('params.stratos_app_name', 'console');
	my $stratos_domain = "${app_name}.${apps_domain}";
	my $stratos_url    = "https://${stratos_domain}";

	# Get Stratos specific configuration
	# Command line version takes precedence over environment config
	my $stratos_version = $self->{options}->{version} // $env->lookup('params.stratos.version', '4.9.4' );
	my $stratos_admin   = $env->lookup('params.stratos.admin_user', 'admin' );

	# Get database connection information

	# Default configuration
	# TODO: Capture the source key and warn if using outdated non-stratos prefix
	my $stratos_db_scheme   = $env->lookup(['params.stratos_db_scheme',   'params.db_scheme'],   'postgres');
	my $stratos_db_hostname = $env->lookup(['params.stratos_db_hostname', 'params.db_hostname'], '');
	my $stratos_db_username = $env->lookup(['params.stratos_db_username', 'params.db_username'], 'stratos');
	my $stratos_db_password = $env->lookup(['params.stratos_db_password', 'params.db_password'], 'stratos');
	my $stratos_db_port     = $env->lookup(['params.stratos_db_port',     'params.db_port'],     5432);
	my $stratos_db_database = $env->lookup(['params.stratos_db_database', 'params.db_database'], 'stratos');
	my $stratos_db_sslmode  = $env->lookup(['params.stratos_db_sslmode',  'params.db_sslmode'],  'disabled');    # verify-ca

	# Check for OCFP requested feature
	# FIXME: Params should override OCFP if provided
	if ( $self->env->has_feature('ocfp') ) {

		# Get Stratos configuration from vault.
		# FIXME: Should we bail if not set?
		$stratos_domain    = $env->ocfp_config_lookup("fqdns")->{stratos} || '';
		$stratos_url       = "https://${stratos_domain}";
		$stratos_db_scheme = $env->vault->get($env->secrets_base . "stratos/db/stratos:scheme" )
		  || 'postgres';
		$stratos_db_hostname =
		  $env->vault->get( $env->secrets_base . "stratos/db/stratos:hostname" )
		  || '';
		$stratos_db_username =
		  $env->vault->get( $env->secrets_base . "stratos/db/stratos:username" )
		  || 'stratos';
		$stratos_db_password =
		  $env->vault->get( $env->secrets_base . "stratos/db/stratos:password" )
		  || 'stratos';
		$stratos_db_port = $env->vault->get( $env->secrets_base . "stratos/db/stratos:port" )
		  || 5432;
		$stratos_db_database =
		  $env->vault->get( $env->secrets_base . "stratos/db/stratos:database" )
		  || 'stratos';
		$stratos_db_sslmode = "disable";    # or "verify-ca"
	}

	# Determine if Stratos is deployed as a CF app
	my $is_cf_app_deployed = 0;
	my $cf_app_status      = "unknown";

	# Check if stratos app is deployed to CF
	if ( !run( {interactive => 0, passfail => 1 }, 'cf', 'app', $app_name ) ) {
		$is_cf_app_deployed = 0;
	}
	else {
		$is_cf_app_deployed = 1;

		# Get the app status
		my ( $app_info, $app_rc ) = run( {interactive => 0, stderr => 0 }, 'cf', 'app', $app_name );
		if ( $app_rc == 0 ) {

			# Parse the status from the output
			if ( $app_info =~ /^#?status:\s+(\S+)/m ) {
				$cf_app_status = $1;
			}
		}
	}

	# FIXME: Should we bail or generate instead of "" if not set?
	my $session_secret = $env->vault->get( $env->secrets_base . "stratos:session_secret" ) || "";

	my $admin_password        = $self->exodus_data('admin_password') // '';
	my $stratos_client        = $self->exodus_data('stratos_client') // bail('Stratos client missing');
	my $stratos_client_secret = $self->exodus_data('stratos_secret') // bail('Stratos client secret missing');

	# Build info structure
	return {
		name => scalar $env->lookup( 'stratos.deployment_name', $env->name . "-stratos" ),

		#status => $deployment_exists ? "Deployed via BOSH" :
		status => $is_cf_app_deployed
		? "Deployed as CF app ($cf_app_status)"
		: "Not Deployed",
		url                => $stratos_url,
		version            => $stratos_version,
		admin_user         => $stratos_admin,
		admin_password     => $admin_password,
		session_secret     => $session_secret,
		cf_api             => $cf_api,
		cf_org             => $cf_org,
		cf_space           => $cf_space,
		app_name           => $app_name,
		is_cf_app_deployed => $is_cf_app_deployed,
		apps_domain        => $apps_domain,
		stratos_domain     => $stratos_domain,

		# Database configuration
		db => {
			scheme   => $stratos_db_scheme,
			hostname => $stratos_db_hostname,
			username => $stratos_db_username,
			password => $stratos_db_password,
			port     => $stratos_db_port,
			database => $stratos_db_database,
			sslmode  => $stratos_db_sslmode,
		},

		# UAA client information
		client => {
			id     => $stratos_client,
			secret => $stratos_client_secret,
		},
	};
}

sub display_info {
	my ( $self, %options ) = @_;
	my $info = $self->{info};

	# If version was specified on command line, update the info object
	if ( $options{version} && $options{version} ne $info->{version} ) {
		$info->{version} = $options{version};
		info( "Note: Using Stratos version %s from command line", $options{version} );
	}

	# Handle URLs-only mode
	if ( $options{'urls-only'} ) {
		if ( $info->{url} ) {
			info( $info->{url} );
		}
		else {
			info("No Stratos URL configured");
		}
		return 1;
	}

	# Display information
	if ( $options{json} ) {

		# Output as JSON using spruce
		my $tmp = $self->tempdir('stratos-info-json');
		open my $fh, '>', "$tmp/info.yml"
		  or bail("Could not create temporary file: $!");
		print $fh _to_yaml($info);
		close $fh;

		my ( $json_out, $rc ) =
		  run( {interactive => 0, stderr => 0 }, 'spruce', 'json', "$tmp/info.yml" );
		bail("Failed to convert to JSON") if $rc != 0;
		info($json_out);
		return 1;
	}

	# Otherwise, display in a human-readable format
	# TODO: Discuss if we want to simply dump as YAML?
	info(
		"\n" .
		  "=" x terminal_width() .
		  "\nStratos UI Deployment: %s" . "\n" .
		  "=" x terminal_width() .
		  "\nStatus: %s" .
		  "\nURL: %s" .
		  "\nVersion: %s" .
		  "\n\nAuthentication:" .
		  "\n  Admin User: %s" .
		  "\n  Admin Password: %s" .
		  "\nUAA Client Details:" .
		  "\n  Client ID: %s" .
		  "\n  Client Secret: %s",
		$info->{name},
		$info->{status},
		$info->{url} || "Not configured",
		$info->{version},
		$info->{admin_user},
		$info->{admin_password} || "Not found in vault",
		$info->{client}{id},
		$info->{client}{secret}
	);

	if ( $info->{cf_api} ) {
		info(
			"\n" .
			  "=" x terminal_width() .
			  "\nCloud Foundry Details:" . "\n" .
			  "=" x terminal_width() .
			  "\n  API: %s" .
			  "\n  Apps Domain: %s" .
			  "\n  Organization: %s" .
			  "\n  Space: %s" .
			  "\n  App Name: %s",
			$info->{cf_api}, $info->{apps_domain},
			$info->{cf_org}, $info->{cf_space},      $info->{app_name}
		);
	}

	# Database information if available
	if ( $info->{db}->{hostname} ) {
		info(
			"\nDatabase Configuration:\n" .
			  "  Scheme: %s\n" .
			  "  Hostname: %s\n" .
			  "  Port: %s\n" .
			  "  Database: %s\n" .
			  "  Username: %s\n" .
			  "  SSL Mode: %s",
			$info->{db}->{scheme},   $info->{db}->{hostname}, $info->{db}->{port},
			$info->{db}->{database}, $info->{db}->{username}, $info->{db}->{sslmode}
		);
	}

	# Show helpful commands
	info("\nHelpful Commands:");
	info( "  Open in browser: %s %s stratos open", $self->env->get_call_path_with_env() )
	  ;    # returns two strings
	info( "  Deploy Stratos: %s %s stratos deploy", $self->env->get_call_path_with_env() )
	  ;    # returns two strings

	if ( $info->{is_cf_app_deployed} ) {
		info( "  View CF app logs: cf logs %s --recent", $info->{app_name} );
		info( "  Restart CF app: cf restart %s",         $info->{app_name} );
	}

	return $self->done();
}

sub deploy_stratos {
	my ( $self, %options ) = @_;
	my $env  = $self->env;
	my $info = $self->{info};

	info("deploying Stratos as a CF application...");

	# Check if already deployed
	if ( $info->{is_cf_app_deployed} && !$options{force} ) {
		info("Stratos is already deployed. Use --force to redeploy.");
		return 1;
	}

	# Check CF CLI is available
	unless ( $options{'skip-cf-check'} ) {
		bail(
      "CF CLI not found. Please install it or use --skip-cf-check if you're sure it's available."
		) unless run({interactive => 0, passfail => 1 }, 'cf', '--version');
	}

	#	# Check CF API is configured
	info("API: %s\n", $info->{cf_api} // 'missing!');
	bail(
		"No CF API URL configured. Set cf.api_domain in your environment."
	) unless $info->{cf_api};


	# Check if we're logged in to CF
	bail(
		"CF authentication required before deployment.  Please log in first with 'cf login'"
	) unless run({interactive => 0, passfail => 1 }, 'cf', 'target');

	# Create a temporary directory for the deployment
	my $tmp_dir = mkdir_or_fail($self->tempdir('stratos-deploy'));
	info("Preparing Stratos deployment... %s", $tmp_dir);

	# Get environment config and exodus data
	my $system_api_domain = $info->{cf_api};
	$system_api_domain =~ s{^https?://}{};    # Remove protocol

	# Get Stratos version - command line takes precedence over environment config
	my $stratos_version = $options{version} // $info->{version};
	info( "Using Stratos version: %s%s",
		$stratos_version, $options{version} ? " (from command line)" : "" );
	my $stratos_release_url =
"https://github.com/cloudfoundry/stratos/releases/download/v${stratos_version}/stratos-ui-v${stratos_version}.zip";
	my $stratos_sso_options = $env->lookup( 'stratos.sso_options', 'nosplash, logout' );

	# Get file or download Stratos release
	
	my $zipfile;
	if ($options{file}) {
		info( "Using provided Stratos file: %s", $options{file} );
		bail(
			"Specified Stratos install file not found!"
		) unless -f $options{file};
		$zipfile= $options{file};

	} else {
		info( "Downloading Stratos %s...", $stratos_version );
		my ($status, $line, $file) = curl({file => $tmp_dir.'/stratos.zip'}, $stratos_release_url);
		if ($status >=  300) {
			if ($status eq '404') {
				$line = 'File not found';
				$file = '';
			}
			bail(
   			"Failed to download Stratos installation file: %s (%s)\n\n%s\n",
				$line, $status, $file
			);
		}
		$zipfile = $file;
	}

	# Target the correct CF organization and space
	info("Targeting CF organization 'system' and space 'stratos'...");
	run(
		{interactive => 0, onfailure => "Failed to create space" },
		'cf', 'create-space', '-o', 'system', 'stratos'
	);
	run(
		{interactive => 0, onfailure => "Failed to target space" },
		'cf', 'target', '-o', 'system', '-s', 'stratos'
	);

	$self->configure_cups($info) if $info->{statos_db_hostname};

	# Create application manifest
	info("Creating application manifest...");
	mkfile_or_fail( "$tmp_dir/manifest.yml", <<EOF);
---
applications:
- name: $info->{app_name}
  buildpacks:
  - $options{buildpack}
  stack: $options{stack}
  env:
    CF_API_URL: https://$system_api_domain
    CF_CLIENT: $info->{client}{id}
    CF_CLIENT_SECRET: $info->{client}{secret}
    SESSION_STORE_SECRET: $info->{session_secret}
    SSO_OPTIONS: $stratos_sso_options
    SSO_WHITELIST: https://$info->{stratos_domain}/*
    SSO_LOGIN: "true"
    DB_SSL_MODE: $info->{db}{sslmode}
#  services:
#  - console_db_tls_verify_ca
  routes:
  - route: $info->{stratos_domain}
    protocol: http1
  processes:
  - type: web
    instances: 1
    memory: $options{memory}
    disk_quota: $options{disk}
    timeout: $options{timeout}
    log-rate-limit-per-second: -1
    health-check-type: port
    readiness-health-check-type: process
EOF

	# Deploy the application
	info("Deploying Stratos application...");
	run({
		interactive => 1,
		onfailure => "Failed to deploy Stratos"
	}, 'cf', 'push', '-f', "$tmp_dir/manifest.yml", '-p', $zipfile);

	# Update the status in the info object
	$info->{is_cf_app_deployed} = 1;
	$info->{status}             = "Deployed as CF app (running)";
	$info->{url}                = "https://$info->{stratos_domain}";

	info("\nStratos deployment completed successfully!");

	$self->display_info(%options);

	return $self->done();
}

sub _generate_password {
	my ( $self, $length ) = @_;
	$length ||= 16;

	my @chars =
	  ( 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-', '!', '@', '#', '$', '%', '^', '&', '*' );
	my $password = '';
	$password .= $chars[ int( rand( scalar @chars ) ) ] for ( 1 .. $length );

	return $password;
}

sub _to_yaml {
	my ( $data, $indent ) = @_;
	$indent //= 0;
	my $prefix = "  " x $indent;
	my $result = "";

	if ( ref($data) eq 'HASH' ) {
		for my $key ( sort keys %$data ) {
			$result .= "${prefix}$key: ";
			my $value = $data->{$key};
			if ( ref($value) ) {
				$result .= "\n" . _to_yaml( $value, $indent + 1 );
			}
			else {
				$value //= '';
				if ( $value =~ /[\n:]/ || $value eq '' ) {
					$value =~ s/"/\\"/g;
					$result .= "\"$value\"\n";
				}
				else {
					$result .= "$value\n";
				}
			}
		}
	}
	elsif ( ref($data) eq 'ARRAY' ) {
		for my $item (@$data) {
			$result .= "${prefix}- ";
			if ( ref($item) ) {
				$result .= "\n" . _to_yaml( $item, $indent + 1 );
			}
			else {
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

	bail("Cannot open Stratos UI: No URL configured") unless $info->{url};

	my $cmd = $^O eq 'darwin' ? 'open' : ( $^O eq 'MSWin32' ? 'start' : 'xdg-open' );
	info( "Opening Stratos UI in browser: %s", $info->{url} );
	system("$cmd '$info->{url}' >/dev/null 2>&1 &");

	return $self->done();
}

sub  configure_cups {
	my ($self, $info) = @_;

	my $tmp_dir = $self->tempdir('cups-config');

	# Configure database via CUPS
	info("Configuring Stratos Database Connection via CUPS Services");
	my $svc_name = "console_db_tls_verify_ca";

	# Check if service already exists
	my ( $org_guid, $org_rc ) =
		run(
			{interactive => 0},
			{ stderr => 0 }, 'cf', 'org', 'system', '--guid'
		);
	bail("Failed to get organization GUID") if $org_rc != 0;
	chomp($org_guid);

	my ( $space_guid, $space_rc ) =
		run(
			{interactive => 0},
			{ stderr => 0 }, 'cf', 'space', 'stratos', '--guid'
		);
	bail("Failed to get space GUID") if $space_rc != 0;
	chomp($space_guid);

	# Check if service exists using CF API
	my ( $svc_list, $svc_rc ) = run(
		{interactive => 0},
		{ stderr => 0 },
		'cf', 'curl',
		"/v3/service_instances?organization_guids=${org_guid}&space_guids=${space_guid}"
	);
	bail("Failed to query service instances") if $svc_rc != 0;

	# Parse the JSON to check if our service exists
	my $svc_exists = '';
	my ( $jq_out, $jq_rc ) =
		run(
			{interactive => 0},
			{ stderr => 0 }, 'jq', '-r', ".resources[]|select(.name|test(\"${svc_name}\"))|.name"
		);
	if ( $jq_rc == 0 ) {

		# Write the service list to a temp file for jq processing
		my $temp_svc_file = "$tmp_dir/services.json";
		open my $svc_fh, '>', $temp_svc_file
			or bail("Cannot write to $temp_svc_file: $!");
		print $svc_fh $svc_list;
		close $svc_fh;

		( $svc_exists, $jq_rc ) = run(
			{interactive => 0},
			{ stderr => 0 },
			'jq', '-r', ".resources[]|select(.name|test(\"${svc_name}\"))|.name",
			$temp_svc_file
		);
		chomp($svc_exists) if $jq_rc == 0;
		unlink $temp_svc_file;
	}

	# Prepare database connection JSON using spruce
	open my $db_fh, '>', "$tmp_dir/db.yml"
		or bail("Could not create database config file: $!");
	print $db_fh <<EOF;
	uri: "$info->{stratos_db_scheme}://"
	username: "$info->{tratos_db_username}"
	password: "$info->{stratos_db_password}"
	hostname: "$info->{stratos_db_hostname}"
	port: $info->{stratos_db_port}
	dbname: "$info->{stratos_db_database}"
	sslmode: "$info->{stratos_db_sslmode}"
EOF
	close $db_fh;

	my ( $db_json, $rc_db ) =
		run(
			{interactive => 0},
			{ stderr => 0 }, 'spruce', 'json', "$tmp_dir/db.yml"
		);
	bail("Failed to convert database config to JSON") if $rc_db != 0;
	chomp($db_json);

	# Write JSON to file to avoid shell escaping issues
	my $db_json_file = "$tmp_dir/db.json";
	open my $json_fh, '>', $db_json_file
		or bail("Cannot write to $db_json_file: $!");
	print $json_fh $db_json;
	close $json_fh;

	# Create or update the service
	if ( $svc_exists eq $svc_name ) {
		info( "Service %s was found, updating existing cups service definition.", $svc_name );
		run(
			{interactive => 0},
			{ onfailure => "Failed to update service" },
			'cf', 'uups', $svc_name, '-p', $db_json_file
		);
	}
	else {
		info( "Service %s was not found, creating cups service definition.", $svc_name );
		run(
			{interactive => 0},
			{ onfailure => "Failed to create service" },
			'cf', 'cups', $svc_name, '-p', $db_json_file
		);
	}

	unlink $db_json_file;
}
1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
