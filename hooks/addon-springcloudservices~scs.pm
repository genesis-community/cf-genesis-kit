package Genesis::Hook::Addon::CF::SCS;

use v5.20;
use warnings;    # Genesis min perl version is 5.20
use Genesis     qw/bail info run pushd popd mkfile_or_fail/;
use Genesis::UI qw/prompt_for_boolean/;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . './.genesis/lib' }

use parent         qw(Genesis::Hook::Addon);
use File::Basename qw/basename/;
use JSON::PP;

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

sub cmd_details {
	return
	"Deploy and register Spring Cloud Services broker to CF. Supports the following options:\n" .
	"[[  #y{deploy}               >>Deploy the SCS broker to the targeted CF environment\n" .
	"[[  #y{register}             >>Register the SCS broker with CF\n" .
	"[[  #y{memory <size>}        >>Memory allocation for the broker app (default: 256M)\n" .
	"[[  #y{disk <size>}          >>Disk allocation for the broker app (default: 1048M)\n" .
	"[[  #y{stack <stack>}        >>Cloud Foundry stack to use (default: cflinuxfs4)\n" .
	"[[  #y{buildpack <name>}     >>Buildpack to use for the broker (default: go_buildpack)\n" .
	"[[  #y{registry_buildpack <name>}  >>Buildpack for registry service (default: java_buildpack)\n".
	"[[  #y{configserver_buildpack <name>} >>Buildpack for config server (default: java_buildpack)\n".
	"[[  #y{release_tag <tag>}    >>Release tag to use (default: 2023.0.1)\n".
	"[[  #y{broker_uri <uri>}     >>URI to download the broker from\n".
	"[[  #y{broker_username <user>} >>Username for broker auth (default: admin)\n".
	"[[  #y{broker_password <pwd>}  >>Password for broker auth (default: admin)\n".
	"[[  #y{configserver_jar_uri <uri>} >>URI to download config server JAR\n".
	"[[  #y{registry_jar_uri <uri>}     >>URI to download registry JAR\n".
	"[[  #y{java_version <version>}     >>Java version to use (default: 17.+)\n".
	"[[  #y{skip_ssl_validation <true|false>} >>Skip SSL validation (default: true)\n";
}

sub perform {
	my ($self) = @_;
	my $env = $self->env;

	# Argument to config key mapping, default values, and usage patterns
	my $scs_url = 'https://github.com/cloudfoundry-community/scs-service-registry';
	my $uri_regexp = qr{^https?://[-\w\@:%._+~#=]{1,256}\.[-\w\@:%\._+~#=]{1,256}(?:\:\d{1,5})?(?:/[-\w\@:%\._\+~#\?&/=]*)?$};
	my $uri_err_msg = "must be a valid URI in the format 'http(s)://example.com/path'";
	my $size_err_msg = 'must be in format "###M" (e.g., 256M, 1024M)';
	my %config_desc = (
		# Boolean flags (no value required)
		deploy   => { type => 'flag', default => 0 },
		register => { type => 'flag', default => 0 },

		# Direct mappings (arg name matches config key)
		memory                   => { type => 'value', usage => '<size>M', default => "256M", validate => qr/^\d+M$/, err_msg => $size_err_msg },
		disk                     => { type => 'value', usage => '<size>M', default => "256M", validate => qr/^\d+M$/, err_msg => $size_err_msg },
		stack                    => { type => 'value', usage => '<stack-name>', default => "cflinuxfs4" },
		buildpack                => { type => 'value', usage => '<go-buildpack-name>', default => "go_buildpack" },
		registry_buildpack       => { type => 'value', usage => '<java-buildpack-name>', default => "java_buildpack" },
		configserver_buildpack   => { type => 'value', usage => '<java-buildpack-name>', default => "java_buildpack" },
		release_tag              => { type => 'value', usage => '<tag>', default => "2023.0.1" },
		broker_uri               => { type => 'value', usage => '<uri>', validate => $uri_regexp, err_msg => $uri_err_msg,
		                              default => $scs_url . "/archive/refs/tags/v1.1.2.tar.gz" },
		configserver_jar_uri     => { type => 'value', usage => '<uri>', validate => $uri_regexp, err_msg => $uri_err_msg,
		                              default => $scs_url . "/releases/download/v2.0.0-2023.0.1/spring-cloud-config-server-2.0.0-2023.0.1.jar" },
		registry_jar_uri         => { type => 'value', usage => '<uri>', validate => $uri_regexp, err_msg => $uri_err_msg,
		                              default => $scs_url . "/releases/download/v2.0.0-3.4.0/service-registry-2.0.0-3.4.0.jar" },
		java_version             => { type => 'value', usage => '<version>', default => "17.+" },
		skip_ssl_validation      => { type => 'value', usage => '<true|false>', default => "true", validate => qr/^(true|false)$/,
		                              err_msg => "must be 'true' or 'false'" },

		# Mapped arguments (arg name differs from config key)
		broker_username          => { key => 'broker_auth_username', type => 'value', usage => '<username>', default => "admin" },
		broker_password          => { key => 'broker_auth_password', type => 'value', usage => '<password>', default => "admin" },
	);

	# Initialize config with defaults and immutable values
	my %config = (
		# Immutable configuration (not configurable via arguments)
		org             => "system",
		space           => "scs",
		broker_name     => "scs-broker",
		broker_old_name => "scs-broker",
	);

	# Parse arguments - process each arg and its corresponding value if needed
	my @args = @{ $self->{args} };
	my @errors;

	while (@args) {
		my $arg = shift @args;

		if ( my $arg_info = $config_desc{$arg} ) {
			my $key = $arg_info->{key} // $arg;
			if ( $arg_info->{type} eq 'flag' ) {
				$config{$key} = 1;
				next;
			}

			# If next arg is another config key, treat as no value
			my $value = in_array($args[0], keys %config_desc) ? undef : shift @args;
			if (!$value) {
				push @errors, sprintf('%s expects %s argument', $key, $arg_info->{usage});
				next;
			}

			# Validate value if a validation pattern is provided
			if ($arg_info->{validate} && $value !~ $arg_info->{validate}) {
				push @errors, sprintf(
					"%s %s",
					$key, $arg_info->{err_msg} // "must match pattern $arg_info->{validate}"
				);
			}
			$config{$key} = $value;
		} else {
			push @errors, "Unknown argument: $arg";
		}
	}

	# Check for errors and bail if any found
	bail(
		"Invalid arguments: \n%s",
		join( "\n", map { "  - $_" } @errors )
	) if @errors;

	# Set defaults from arg_config
	for my $arg (keys %config_desc) {
		my $key = $config_desc{$arg}{key} // $arg;
		$config{$key} //= $config_desc{$arg}{default} if exists $config_desc{$arg}{default};
	}


	# Get data from exodus
	my $exodus_path       = $self->env->exodus_base();
	my $system_api_domain = $self->env->exodus_lookup("api_domain");
	my $system_domain     = $self->env->exodus_lookup("system_domain");
	my $cf_admin_username = $self->env->exodus_lookup("admin_username");
	my $cf_admin_password = $self->env->exodus_lookup("admin_password");
	my $apps_domain       = $self->env->exodus_lookup("apps_domain");

	# Get SCS client data from vault
	my $scs_client        = $self->vault->get("$exodus_path:scs_client");
	my $scs_client_secret = $self->vault->get("$exodus_path:scs_secret");

	# Create CF space
	info("Setting up CF organization and space...");
	run('cf', 'create-space', '-o', $config{org}, $config{space});
	run('cf', 'target', '-o', $config{org}, '-s', $config{space});

	# Get space GUID
	my ( $scs_space_guid, $rc ) = run('cf', 'space', $config{space}, '--guid');
	chomp($scs_space_guid);

	if ( $config{deploy} ) {
		info("Deploying SCS Broker...");

		# Create temporary directory
		my $tmp_dir = $env->workpath("scs-deploy");
		mkdir_or_fail($tmp_dir);
		pushd($tmp_dir);

		# Download broker archive
		$self->fetch_uri( $config{broker_uri} );

		# Extract the archive
		my $archive_name = basename( $config{broker_uri} );
		$self->extract($archive_name);

		# Find the extracted directory and change into it
		my ($broker_dir) = glob("scs-broker-*");
		bail("Failed to find extracted broker directory") unless $broker_dir && -d $broker_dir;
		pushd($broker_dir);

		# Create artifacts directory and download files
		$self->fetch_artifacts( $config{configserver_jar_uri}, $config{registry_jar_uri} );

		# Create .go-version file
		mkfile_or_fail( ".go-version", "1.22\n" );

		# Create JSON for broker config
		my $broker_config = {
			broker_id        => $config{broker_name},
			broker_name      => $config{broker_name},
			description      => "Broker to create SCS services",
			long_description =>
			  "Broker to create Spring Cloud Services (SCS) Config Servers or Service Registries",
			instance_domain     => $apps_domain,
			instance_space_guid => $scs_space_guid,
			artifacts_directory => "/app/artifacts",
			broker_auth         => {
				user     => $config{broker_auth_username},
				password => $config{broker_auth_password}
			},
			cloud_foundry_config => {
				api_url             => "https://$system_api_domain",
				skip_ssl_validation =>
				  ( $config{skip_ssl_validation} eq 'true' ? JSON::PP::true : JSON::PP::false ),
				cf_username       => $cf_admin_username,
				cf_password       => $cf_admin_password,
				uaa_client_id     => $scs_client,
				uaa_client_secret => $scs_client_secret
			},
			services => [
				{
					service_id           => "config-server",
					service_name         => "config-server",
					service_plan_id      => "default-cs",
					service_plan_name    => "default",
					service_description  => "Broker to create Config Servers",
					service_buildpack    => $config{configserver_buildpack},
					service_stack        => $config{stack},
					service_download_uri => $config{configserver_jar_uri}
				},
				{
					service_id           => "service-registry",
					service_name         => "service-registry",
					service_plan_id      => "default-sr",
					service_plan_name    => "default",
					service_description  => "Broker to create Service Registries",
					service_buildpack    => $config{registry_buildpack},
					service_stack        => $config{stack},
					service_download_uri => $config{registry_jar_uri}
				}
			],
			java_config => {
				"JBP_CONFIG_OPEN_JDK_JRE" =>
				  "{ \"jre\": { \"version\": \"$config{java_version}\" } }"
			}
		};

		my $broker_config_json = JSON::PP->new->utf8->pretty->encode($broker_config);

		# Create manifest.yml
		my $manifest_content = <<"MANIFEST";
---
applications:
  - name: scs-broker
    stack: $config{stack}
    buildpack: $config{buildpack}
    memory: $config{memory}
    disk_quota: $config{disk}
    host: console
    timeout: 180
    health-check-type: port
    env:
      GOPACKAGENAME: scs-broker
      GO_VERSION: 1.22
      SCS_BROKER_CONFIG: |-
      $broker_config_json
MANIFEST

		mkfile_or_fail( "manifest.yml", $manifest_content );

		# Push the app to CF
		info("Pushing SCS Broker to Cloud Foundry...");
		run({interactive => 0}, 'cf', 'push', '-f', 'manifest.yml');

		info(
			"SCS service broker is now running, you should now be able to create a service, e.g.:\n".
			"  \$ cf create-service config-server default test-service -c \"{...whatever json configuration you wish to use for config-server - see config-server docs from Spring.io...}\""
		);

		# Clean up
		popd();    # from broker dir
		popd();    # from tmp dir
	}

	if ( $config{register} ) {
		info("Registering SCS Broker...");

		info("Checking if broker is already registered...");
		# TODO: Switch to read_json_from($self->env->bosh->execute())
		my ($broker_json, $rc ) = run('cf', 'curl', '/v2/service_brokers');
		my $json_data = eval { decode_json($broker_json) };
		bail("Failed to parse broker list JSON: $@") if $@;

		my $broker_found = 0;
		foreach my $resource ( @{ $json_data->{resources} } ) {
			if (   $resource->{entity}->{name} eq $config{broker_name}
				|| $resource->{entity}->{name} eq $config{broker_old_name} )
			{
				$broker_found = 1;
				last;
			}
		}

		my $action = $broker_found ? "update" : "create";
		info( (ucfirst($action) =~ s/e$//r) . "ing the service broker..." );

		run(
			'cf', "$action-service-broker",
			$config{broker_name},
			$config{broker_auth_username},
			$config{broker_auth_password},
			"https://scs-broker.$apps_domain",
		);
	}

	return $self->done();
}

# Helper methods
sub fetch_uri {
	my ( $self, $url ) = @_;
	my $filename = basename($url);

	info("Downloading $filename...");
	my ( $out, $rc, $err ) = run('curl', '--fail', '--silent', '--show-error', '--location', '--remote-name', '--url', $url);

	bail("Failed to download: $url\n$err") if $rc;
	return $filename;
}

sub fetch_artifacts {
	my ( $self, $configserver_jar_uri, $registry_jar_uri ) = @_;

	info("Downloading service artifacts...");
	mkdir_or_fail('artifacts');

	pushd('artifacts');

	$self->fetch_uri($configserver_jar_uri);
	$self->fetch_uri($registry_jar_uri);

	popd();
}

sub extract {
	my ( $self, $archive ) = @_;

	info("Extracting $archive...");

	if ( $archive =~ /\.zip$/ ) {
		run('unzip', '-o', $archive);
	}
	elsif ( $archive =~ /\.t?gz$/ ) {
		run('tar', 'zxf', $archive);
	}
	else {
		bail("Unknown file type: $archive");
	}
	unlink($archive) or warn "Failed to remove archive $archive: $!";
}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
