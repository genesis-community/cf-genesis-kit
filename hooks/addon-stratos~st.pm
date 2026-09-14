package Genesis::Hook::Addon::CF::Stratos v3.1.0;

use v5.20;
use warnings;    # Genesis min perl version is 5.20

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib'; }

use Genesis       qw/bail info warning run/;
use Genesis::Term qw/terminal_width/;
use Genesis::UI   qw/prompt_for_boolean/;
use Socket        qw/inet_ntoa/;

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

# Resolve the CF API URL and the two domains the console needs.
#
# This addon is the only hook in the kit that reads a top-level `cf:` key, and
# no OCFP environment file defines one -- those set `params.system_domain` and
# `params.apps_domain`, which is the convention the rest of the kit follows. Read
# `cf.*` first so an environment that does define it keeps working, then fall
# back to `params.*`, and finally to the exodus data a successful CF deploy
# writes. The api_domain exodus key already carries the full hostname, so the
# system domain comes from stripping its leading `api.` label.
sub _cf_endpoints {
	my ($self) = @_;
	my $env = $self->env;
	my $data = eval { $self->exodus_data } || {};

	my $system_domain =
	     $env->lookup( 'cf.system_domain',     '' )
	  || $env->lookup( 'params.system_domain', '' );
	my $apps_domain =
	     $env->lookup( 'cf.apps_domain',     '' )
	  || $env->lookup( 'params.apps_domain', '' )
	  || $data->{apps_domain}
	  || '';

	my $api_domain = $data->{api_domain} || '';
	unless ($system_domain) {
		( $system_domain = $api_domain ) =~ s/^api\.//;
	}

	my $api_url =
	     $env->lookup( 'cf.api_url', '' )
	  || ( $api_domain    ? "https://$api_domain"        : '' )
	  || ( $system_domain ? "https://api.$system_domain" : '' );

	return {
		api_url       => $api_url,
		system_domain => $system_domain,
		apps_domain   => $apps_domain,
	};
}

# Read a secret from the vault, generating and storing one the first time.
#
# The generator is Perl's Bytes::Random::Secure where it is available and
# /dev/urandom otherwise. The previous implementation hashed rand(10000), which
# yields at most about fourteen bits of entropy however long the hex string it
# produces happens to look.
sub _persistent_secret {
	my ( $self, $path, $description ) = @_;
	my $env = $self->env;

	my $existing = $env->vault->get( $env->secrets_base . $path );
	return $existing if defined($existing) && $existing ne '';

	my $bytes;
	if ( open my $urandom, '<:raw', '/dev/urandom' ) {
		read $urandom, $bytes, 32;
		close $urandom;
	}
	bail( "Could not read /dev/urandom to generate the Stratos %s", $description )
	  unless defined($bytes) && length($bytes) == 32;

	my $secret = unpack( 'H*', $bytes );
	info( "Generating a new Stratos %s and storing it in the vault.", $description );
	$env->vault->set( $env->secrets_base . $path, $secret )
	  or bail( "Failed to store the Stratos %s in the vault", $description );

	return $secret;
}

# Resolve the console's database coordinates.
#
# The info path used to read these from the vault while the deploy path read
# them from an exodus key that nothing in the kit ever writes, so the service
# the deploy actually created was always built from the fallback defaults and
# pointed at an empty hostname. Resolve them once, here, and let both paths
# call it.
#
# Note that sslmode must be a value libpq accepts. The old deploy-path default
# was "disabled", which Postgres rejects; the correct spelling is "disable".
sub _stratos_db {
	my ($self) = @_;
	my $env = $self->env;

	my %db = (
		scheme   => $env->params->{db_scheme}   || 'postgres',
		hostname => $env->params->{db_hostname} || '',
		username => $env->params->{db_username} || 'stratos',
		password => $env->params->{db_password} || 'stratos',
		port     => $env->params->{db_port}     || 5432,
		database => $env->params->{db_database} || 'stratos',
		sslmode  => $env->params->{db_sslmode}  || 'disable',
	);

	return \%db unless $env->has_feature('ocfp');

	my $base = $env->secrets_base . "stratos/db/stratos";
	for my $field (qw/scheme hostname username password port database sslmode/) {
		my $value = $env->vault->get("$base:$field");
		$db{$field} = $value if defined($value) && $value ne '';
	}

	return \%db;
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

	# Get Stratos information from environment
	my $endpoints      = $self->_cf_endpoints;
	my $system_domain  = $endpoints->{system_domain};
	my $apps_domain    = $endpoints->{apps_domain};
	my $stratos_domain = '';
	my $stratos_url    = '';

	# Get CF configuration
	my $cf_api      = $endpoints->{api_url};
	my $cf_org      = $env->lookup( 'stratos.cf_org',      'system' );
	my $cf_space    = $env->lookup( 'stratos.cf_space',    'stratos' );
	my $cf_app_name = $env->lookup( 'stratos.cf_app_name', 'apps' );

	# Get Stratos specific configuration
	# Command line version takes precedence over environment config
	my $stratos_version = $self->{options}->{version} // $env->lookup( 'stratos.version', '5.5.3' );
	my $stratos_admin   = $env->lookup( 'stratos.admin_user', 'admin' );

	# Get database connection information

	# Default configuration
	$stratos_domain = "console.${apps_domain}";
	$stratos_url    = "https://${stratos_domain}";
	my $db = $self->_stratos_db;

	# Check for OCFP requested feature
	if ( $self->env->has_feature('ocfp') ) {

		# Get Stratos configuration from vault.
		# FIXME: Should we bail if not set?
		$stratos_domain = $env->ocfp_config_lookup("fqdns")->{stratos} || '';
		$stratos_url    = "https://${stratos_domain}";
	}

	# Determine if Stratos is deployed as a CF app
	my $is_cf_app_deployed = 0;
	my $cf_app_status      = "unknown";

	# Check if CF app is deployed
	if ( !run( {interactive => 0, passfail => 1 }, 'cf', 'app', $cf_app_name ) ) {
		$is_cf_app_deployed = 0;
	}
	else {
		$is_cf_app_deployed = 1;

		# Get the app status
		my ( $app_info, $app_rc ) = run( {interactive => 0, stderr => 0 }, 'cf', 'app', $cf_app_name );
		if ( $app_rc == 0 ) {

			# Parse the status from the output
			if ( $app_info =~ /^#?status:\s+(\S+)/m ) {
				$cf_app_status = $1;
			}
		}
	}

	# FIXME: Should we bail or generate instead of "" if not set?
	my $admin_password = $env->vault->get( $env->secrets_base . "stratos:admin_password" ) || "";
	my $session_secret = $env->vault->get( $env->secrets_base . "stratos:session_secret" ) || "";
	my $data           = $self->exodus_data;

	# FIXME: Should we bail if not set?
	my $stratos_client        = $data->{stratos_client} || "";
	my $stratos_client_secret = $data->{stratos_secret} || "";

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
		admin_password     => $admin_password ? $admin_password : "",
		has_admin_password => $admin_password ? 1               : 0,
		session_secret     => $session_secret ? $session_secret : "",
		cf_api             => $cf_api,
		cf_org             => $cf_org,
		cf_space           => $cf_space,
		cf_app_name        => $cf_app_name,
		is_cf_app_deployed => $is_cf_app_deployed,
		system_domain      => $system_domain,
		apps_domain        => $apps_domain,
		stratos_domain     => $stratos_domain,

		# Database configuration
		db => $db,

		# UAA client information
		client => {
			id     => $stratos_client ? $stratos_client : "stratos_client",
			secret => $stratos_client_secret
			? $stratos_client_secret
			: "stratos_secret",
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
		$info->{url} ? $info->{url} : "Not configured",
		$info->{version},
		$info->{admin_user},
		$info->{has_admin_password}
		? $info->{admin_password}
		: "Not found in vault",
		$info->{client}->{id},
		$info->{client}->{secret}
	);

	if ( $info->{cf_api} ) {
		info(
			"\n" .
			  "=" x terminal_width() .
			  "\nCloud Foundry Details:" . "\n" .
			  "=" x terminal_width() .
			  "\n  API: %s" .
			  "\n  System Domain: %s" .
			  "\n  Apps Domain: %s" .
			  "\n  Organization: %s" .
			  "\n  Space: %s" .
			  "\n  App Name: %s",
			$info->{cf_api}, $info->{system_domain}, $info->{apps_domain},
			$info->{cf_org}, $info->{cf_space},      $info->{cf_app_name}
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
		info( "  View CF app logs: cf logs %s --recent", $info->{cf_app_name} );
		info( "  Restart CF app: cf restart %s",         $info->{cf_app_name} );
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
		if ( !run( {interactive => 0, passfail => 1 }, 'cf', '--version' )
		) {
			bail(
"CF CLI not found. Please install it or use --skip-cf-check if you're sure it's available."
			);
		}
	}

	# Check CF API is configured
	bail("No CF API URL configured. Set cf.api_url in your environment.")
	  unless $info->{cf_api};

	# Check if we're logged in to CF
	if ( !run( {interactive => 0, passfail => 1 }, 'cf', 'target' ) ) {
		warning("Not logged in to CF. Please log in first with 'cf login'");
		bail("CF authentication required before deployment");
	}

	# Create a temporary directory for the deployment
	my $tmp_dir = $self->tempdir('stratos-deploy');
	info("Preparing Stratos deployment...");

	# Get environment config and exodus data
	my $data              = $self->exodus_data;
	my $endpoints = $self->_cf_endpoints;
	my $system_api_domain = $endpoints->{api_url};
	$system_api_domain =~ s/^https?:\/\///;    # Remove protocol

	# Get database connection information
	my $db                  = $self->_stratos_db;
	my $stratos_db_scheme   = $db->{scheme};
	my $stratos_db_hostname = $db->{hostname};
	my $stratos_db_username = $db->{username};
	my $stratos_db_password = $db->{password};
	my $stratos_db_port     = $db->{port};
	my $stratos_db_database = $db->{database};
	my $stratos_db_sslmode  = $db->{sslmode};

	bail(
		    "No database hostname configured for Stratos. Write the console's "
		  . "database coordinates to %sstratos/db/stratos before deploying.",
		$env->secrets_base
	) unless $stratos_db_hostname;

	# Get or generate session store secret
	my $stratos_session_store_sekret =
	  $self->_persistent_secret( "stratos/session_secret", 'session store secret' );

	# Jetstream encrypts the OAuth tokens it stores for each registered
	# endpoint, and since 5.x the binary buildpack no longer defaults the key
	# the way the old source buildpack did. It has to be stable across pushes:
	# a new key makes every token already in the database undecryptable, which
	# presents to the operator as a console that has silently forgotten its
	# endpoints.
	my $stratos_encryption_key =
	  $self->_persistent_secret( "stratos/encryption_key", 'encryption key' );

	# FIXME: Should we bail if not set?
	my $stratos_client        = $data->{"stratos_client"} || "";
	my $stratos_client_secret = $data->{stratos_secret}   || "";

	unless ( $stratos_client && $stratos_client_secret ) {
		warning("Stratos client credentials not found in vault. Using defaults.");
		$stratos_client        = "stratos_client";
		$stratos_client_secret = "stratos_secret";
	}

	# Get Stratos version - command line takes precedence over environment config
	my $stratos_version = $options{version} // $info->{version};
	info( "Using Stratos version: %s%s",
		$stratos_version, $options{version} ? " (from command line)" : "" );
	# Stratos renamed its CF bundle at v5.0.0, from stratos-ui- to stratos-cf-,
	# so the asset name depends on the major version we are asking for.
	my ($stratos_major) = $stratos_version =~ /^(\d+)/;
	$stratos_major //= 0;
	my $stratos_asset =
	  ( $stratos_major >= 5 )
	  ? "stratos-cf-v${stratos_version}.zip"
	  : "stratos-ui-v${stratos_version}.zip";
	my $stratos_releases_url =
	  "https://github.com/cloudfoundry/stratos/releases/download/v${stratos_version}/${stratos_asset}";
	my $stratos_sso_options = $env->lookup( 'stratos.sso_options', 'nosplash, logout' );

	# Domain setup
	my $apps_domain    = $endpoints->{apps_domain};
	my $stratos_domain = "console.${apps_domain}";

	# On an OCFP environment the console hostname comes from the bloc's FQDN
	# map in the vault, and ocfp/stratos.yml has already registered that exact
	# hostname as the UAA client's redirect URI. The info path honours the map
	# and this path did not, so a bloc whose map differs from console.<apps
	# domain> would push a route that SSO refuses to redirect back to.
	if ( $env->has_feature('ocfp') ) {
		my $mapped = $env->ocfp_config_lookup("fqdns")->{stratos};
		$stratos_domain = $mapped if $mapped;
	}

	# Get file or download Stratos release
	my $chdir = $tmp_dir;
	chdir $chdir or bail("Could not change to temporary directory: $!");

	if ( $options{file} && -f $options{file} ) {
		info( "Using provided Stratos file: %s", $options{file} );
		run(
			{ interactive => 0, onfailure => "Failed to unzip Stratos file" },
			'unzip', '-o', $options{file}
		);
	}
	else {
		info( "Downloading Stratos %s...", $stratos_version );

		# Download to a name we choose rather than the one wget derives from the
		# URL. The two used to disagree over the version's leading "v", so the
		# unzip that followed asked for a file that was never written.
		run(
			{ interactive => 0, onfailure => "Failed to download Stratos" },
			'wget', '-O', 'stratos.zip', $stratos_releases_url
		);
		run(
			{ interactive => 0, onfailure => "Failed to unzip Stratos" },
			'unzip', '-o', 'stratos.zip'
		);
		unlink('stratos.zip');
	}

	# Target the correct CF organization and space
	info("Targeting CF organization 'system' and space 'stratos'...");
	run(
		{ interactive => 0, onfailure => "Failed to create space" },
		'cf', 'create-space', '-o', 'system', 'stratos'
	);
	run(
		{ interactive => 0, onfailure => "Failed to target space" },
		'cf', 'target', '-o', 'system', '-s', 'stratos'
	);

	# The console's SSH terminal dials the platform's app SSH proxy from inside
	# its own container, so the space needs an egress rule allowing it.
	$self->_ensure_app_ssh_security_group($tmp_dir);
	$self->_ensure_db_security_group( $tmp_dir, $db );

	# Configure database via CUPS
	info("Configuring Stratos Database Connection via CUPS Services");
	my $svc_name = "console_db_tls_verify_ca";

	# Check if service already exists
	my ( $org_guid, $org_rc ) =
	  run(
			{ interactive => 0, stderr => 0 },
			'cf', 'org', 'system', '--guid'
		);
	bail("Failed to get organization GUID") if $org_rc != 0;
	chomp($org_guid);

	my ( $space_guid, $space_rc ) =
	  run(
			{ interactive => 0, stderr => 0 },
			'cf', 'space', 'stratos', '--guid'
		);
	bail("Failed to get space GUID") if $space_rc != 0;
	chomp($space_guid);

	# Check if service exists using CF API
	my ( $svc_list, $svc_rc ) = run(
		{ interactive => 0, stderr => 0 },
		'cf', 'curl',
		"/v3/service_instances?organization_guids=${org_guid}&space_guids=${space_guid}"
	);
	bail("Failed to query service instances") if $svc_rc != 0;

	# Parse the JSON to check if our service exists
	my $svc_exists = '';
	my ( $jq_out, $jq_rc ) =
	  run(
			{ interactive => 0, stderr => 0 },
			'jq', '-r', ".resources[]|select(.name|test(\"${svc_name}\"))|.name"
		);
	if ( $jq_rc == 0 ) {

		# Write the service list to a temp file for jq processing
		my $temp_svc_file = "$tmp_dir/services.json";
		open my $svc_fh, '>', $temp_svc_file
		  or bail("Cannot write to $temp_svc_file: $!");
		print $svc_fh $svc_list;
		close $svc_fh;

		( $svc_exists, $jq_rc ) = run(
			{ interactive => 0, stderr => 0 },
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
uri: "$stratos_db_scheme://$stratos_db_username:$stratos_db_password\@$stratos_db_hostname:$stratos_db_port/$stratos_db_database?sslmode=$stratos_db_sslmode"
username: "$stratos_db_username"
password: "$stratos_db_password"
hostname: "$stratos_db_hostname"
port: $stratos_db_port
dbname: "$stratos_db_database"
sslmode: "$stratos_db_sslmode"
EOF
	close $db_fh;

	my ( $db_json, $rc_db ) =
	  run(
			{ interactive => 0, stderr => 0 },
			'spruce', 'json', "$tmp_dir/db.yml"
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
			{ interactive => 0, onfailure => "Failed to update service" },
			'cf', 'uups', $svc_name, '-p', $db_json_file
		);
	}
	else {
		info( "Service %s was not found, creating cups service definition.", $svc_name );
		run(
			{ interactive => 0, onfailure => "Failed to create service" },
			'cf', 'cups', $svc_name, '-p', $db_json_file
		);
	}

	unlink $db_json_file;

	# Create application manifest
	info("Creating application manifest...");
	open my $manifest, '>', "$tmp_dir/manifest.yml"
	  or bail("Could not create manifest file: $!");
	print $manifest <<EOF;
---
applications:
- name: apps
  health-check-type: port
  memory: $options{memory}
  disk_quota: $options{disk}
  timeout: $options{timeout}
  buildpacks:
  - $options{buildpack}
  stack: $options{stack}
  routes:
  - route: $stratos_domain
  env:
    CF_API_URL: https://$system_api_domain
    CF_CLIENT: $stratos_client
    CF_CLIENT_SECRET: $stratos_client_secret
    SESSION_STORE_SECRET: $stratos_session_store_sekret
    SSO_OPTIONS: $stratos_sso_options
    SSO_WHITELIST: https://$stratos_domain/*
    SSO_LOGIN: "true"
    DATABASE_PROVIDER: pgsql
    ENCRYPTION_KEY: $stratos_encryption_key
    DB_SSL_MODE: $stratos_db_sslmode
  services:
  - console_db_tls_verify_ca
EOF
	close $manifest;

	# Deploy the application
	info("Deploying Stratos application...");
	my ( $out, $rc, $err ) =
	  run( { stderr => 0 }, 'cf', 'push', '-f', "$tmp_dir/manifest.yml" );
	bail( "Failed to deploy Stratos: %s", $err || $out ) unless $rc == 0;

	# Update the status in the info object
	$info->{is_cf_app_deployed} = 1;
	$info->{status}             = "Deployed as CF app (running)";
	$info->{url}                = "https://$stratos_domain";

	info("\nStratos deployment completed successfully!");

	chdir('/');    # Go back to root directory

	$self->display_info(%options);

	return $self->done();
}

sub _ensure_app_ssh_security_group {
	my ( $self, $tmp_dir ) = @_;

	my $sg_name = 'stratos-app-ssh';

	my ( $info_json, $rc ) =
	  run( {interactive => 0, stderr => 0 }, 'cf', 'curl', '/v2/info' );
	if ( $rc != 0 ) {
		warning("Could not read /v2/info; skipping %s security group setup", $sg_name);
		return;
	}

	my ($endpoint) = $info_json =~ /"app_ssh_endpoint":\s*"([^"]+)"/;
	unless ($endpoint) {
		warning("No app_ssh_endpoint advertised; skipping %s security group setup", $sg_name);
		return;
	}

	my ( $host, $port ) = $endpoint =~ /^(.*?):(\d+)$/;
	( $host, $port ) = ( $endpoint, 2222 ) unless $host;

	my @addrs = gethostbyname($host);
	@addrs = map { inet_ntoa($_) } @addrs[ 4 .. $#addrs ];
	unless (@addrs) {
		warning( "Could not resolve app SSH host '%s'; skipping %s security group setup",
			$host, $sg_name );
		return;
	}

	my $rules = '[' . join(
		',',
		map {
			sprintf(
				'{"protocol":"tcp","destination":"%s","ports":"%s",'
				  . '"description":"console access to the app SSH proxy"}',
				$_, $port
			)
		} @addrs
	) . ']';

	my $sg_file = "$tmp_dir/$sg_name.json";
	open my $sg_fh, '>', $sg_file
	  or bail("Cannot write to $sg_file: $!");
	print $sg_fh $rules;
	close $sg_fh;

	if ( run( {interactive => 0, passfail => 1, stderr => 0 }, 'cf', 'security-group', $sg_name ) ) {
		run(
			{ interactive => 0, onfailure => "Failed to update security group $sg_name" },
			'cf', 'update-security-group', $sg_name, $sg_file
		);
	}
	else {
		run(
			{ interactive => 0, onfailure => "Failed to create security group $sg_name" },
			'cf', 'create-security-group', $sg_name, $sg_file
		);
	}

	run(
		{ interactive => 0, onfailure => "Failed to bind security group $sg_name" },
		'cf', 'bind-security-group', $sg_name, 'system',
		'--space', 'stratos', '--lifecycle', 'running'
	);
	unlink $sg_file;

	info( "Security group %s bound to system/stratos for app SSH proxy %s",
		$sg_name, $endpoint );
}

# Open egress from the console's space to its database.
#
# An app container gets no egress to the BOSH network under the default
# security groups, so jetstream's connection to a colocated Postgres is
# refused outright. The rule is needed during staging as well as at runtime,
# because the buildpack's own start-up check dials the database.
sub _ensure_db_security_group {
	my ( $self, $tmp_dir, $db ) = @_;

	my $sg_name = 'stratos-db';
	my $host    = $db->{hostname};
	my $port    = $db->{port};

	unless ( $host && $port ) {
		warning( "No database host or port known; skipping %s security group setup", $sg_name );
		return;
	}

	my @addrs;
	if ( $host =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
		@addrs = ($host);
	}
	else {
		my @entry = gethostbyname($host);
		@addrs = map { inet_ntoa($_) } @entry[ 4 .. $#entry ];
	}
	unless (@addrs) {
		warning( "Could not resolve database host '%s'; skipping %s security group setup",
			$host, $sg_name );
		return;
	}

	my $rules = '[' . join(
		',',
		map {
			sprintf(
				'{"protocol":"tcp","destination":"%s","ports":"%s",'
				  . '"description":"console access to its database"}',
				$_, $port
			)
		} @addrs
	) . ']';

	my $sg_file = "$tmp_dir/$sg_name.json";
	open my $sg_fh, '>', $sg_file
	  or bail("Cannot write to $sg_file: $!");
	print $sg_fh $rules;
	close $sg_fh;

	if ( run( { interactive => 0, passfail => 1, stderr => 0 }, 'cf', 'security-group', $sg_name ) )
	{
		run(
			{ interactive => 0, onfailure => "Failed to update security group $sg_name" },
			'cf', 'update-security-group', $sg_name, $sg_file
		);
	}
	else {
		run(
			{ interactive => 0, onfailure => "Failed to create security group $sg_name" },
			'cf', 'create-security-group', $sg_name, $sg_file
		);
	}

	for my $lifecycle (qw/running staging/) {
		run(
			{ interactive => 0, onfailure => "Failed to bind security group $sg_name" },
			'cf', 'bind-security-group', $sg_name, 'system',
			'--space', 'stratos', '--lifecycle', $lifecycle
		);
	}
	unlink $sg_file;

	info( "Security group %s bound to system/stratos for database %s:%s",
		$sg_name, $host, $port );
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

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
