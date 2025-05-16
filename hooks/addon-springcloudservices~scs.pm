#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::CF::SCS v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20
use Genesis qw/bail info run pushd popd mkfile_or_fail/;
use Genesis::UI qw/prompt_for_boolean/;
use parent qw(Genesis::Hook::Addon);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";
use File::Basename qw/basename/;
use JSON::PP;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
  "Deploy and register Spring Cloud Services broker to CF. Supports the following options:\n".
  "[[  #y{deploy}               >>Deploy the SCS broker to the targeted CF environment\n".
  "[[  #y{register}             >>Register the SCS broker with CF\n".
  "[[  #y{memory <size>}        >>Memory allocation for the broker app (default: 256M)\n".
  "[[  #y{disk <size>}          >>Disk allocation for the broker app (default: 1048M)\n".
  "[[  #y{stack <stack>}        >>Cloud Foundry stack to use (default: cflinuxfs4)\n".
  "[[  #y{buildpack <name>}     >>Buildpack to use for the broker (default: go_buildpack)\n".
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

  # Default configuration
  my %config = (
    org => "system",
    space => "scs",
    memory => "256M",
    disk => "1048M",
    stack => "cflinuxfs4",
    buildpack => "go_buildpack",
    release_tag => "2023.0.1",
    broker_uri => "https://github.com/cloudfoundry-community/scs-broker/archive/refs/tags/v1.1.2.tar.gz",
    configserver_buildpack => "java_buildpack",
    configserver_jar_uri => "https://github.com/cloudfoundry-community/cf-spring-cloud-config-server/releases/download/v2.0.0-2023.0.1/spring-cloud-config-server-2.0.0-2023.0.1.jar",
    registry_buildpack => "java_buildpack",
    registry_jar_uri => "https://github.com/cloudfoundry-community/scs-service-registry/releases/download/v2.0.0-3.4.0/service-registry-2.0.0-3.4.0.jar",
    java_version => "17.+",
    broker_name => "scs-broker",
    broker_old_name => "scs-broker",
    broker_auth_username => "admin",
    broker_auth_password => "admin",
    skip_ssl_validation => "true",
    deploy => 0,
    register => 0,
  );

  # Parse arguments - process each arg and its corresponding value if needed
  my @args = @{$self->{args}};

  while (@args) {
    my $arg = shift @args;

    if ($arg eq 'memory') {
      $config{memory} = shift @args || bail("Usage: ... memory <#M>");
    }
    elsif ($arg eq 'disk') {
      $config{disk} = shift @args || bail("Usage: ... disk <#M>");
    }
    elsif ($arg eq 'stack') {
      $config{stack} = shift @args || bail("Usage: ... stack <stack-name>");
    }
    elsif ($arg eq 'buildpack') {
      $config{buildpack} = shift @args || bail("Usage: ... buildpack <go-buildpack-name>");
    }
    elsif ($arg eq 'registry_buildpack') {
      $config{registry_buildpack} = shift @args || bail("Usage: ... registry_buildpack <java-buildpack-name>");
    }
    elsif ($arg eq 'configserver_buildpack') {
      $config{configserver_buildpack} = shift @args || bail("Usage: ... configserver_buildpack <java-buildpack-name>");
    }
    elsif ($arg eq 'release_tag') {
      $config{release_tag} = shift @args || bail("Usage: ... release_tag <tag>");
    }
    elsif ($arg eq 'broker_uri') {
      $config{broker_uri} = shift @args || bail("Usage: ... broker_uri <uri>");
    }
    elsif ($arg eq 'broker_username') {
      $config{broker_auth_username} = shift @args || bail("Usage: ... broker_username <username>");
    }
    elsif ($arg eq 'broker_password') {
      $config{broker_auth_password} = shift @args || bail("Usage: ... broker_password <password>");
    }
    elsif ($arg eq 'configserver_jar_uri') {
      $config{configserver_jar_uri} = shift @args || bail("Usage: ... configserver_jar_uri <uri>");
    }
    elsif ($arg eq 'registry_jar_uri') {
      $config{registry_jar_uri} = shift @args || bail("Usage: ... registry_jar_uri <uri>");
    }
    elsif ($arg eq 'java_version') {
      $config{java_version} = shift @args || bail("Usage: ... java_version <version>");
    }
    elsif ($arg eq 'skip_ssl_validation') {
      $config{skip_ssl_validation} = shift @args || bail("Usage: ... skip_ssl_validation <true|false>");
    }
    elsif ($arg eq 'deploy') {
      $config{deploy} = 1;
    }
    elsif ($arg eq 'register') {
      $config{register} = 1;
    }
    else {
      bail("Unknown argument: $arg");
    }
  }

  # Get data from exodus
  my $exodus_path = $self->env->exodus_base();
  my $system_api_domain = $self->env->exodus_lookup("api_domain");
  my $system_domain = $self->env->exodus_lookup("system_domain");
  my $cf_admin_username = $self->env->exodus_lookup("admin_username");
  my $cf_admin_password = $self->env->exodus_lookup("admin_password");
  my $apps_domain = $self->env->exodus_lookup("apps_domain");

  # Get SCS client data from vault
  my $scs_client = $self->vault->get("$exodus_path:scs_client");
  my $scs_client_secret = $self->vault->get("$exodus_path:scs_secret");

  # Create CF space
  $env->notify("Setting up CF organization and space...");
  run("cf create-space -o \"$config{org}\" \"$config{space}\"");
  run("cf target -o \"$config{org}\" -s \"$config{space}\"");

  # Get space GUID
  my ($scs_space_guid, $rc) = run("cf space $config{space} --guid");
  chomp($scs_space_guid);

  if ($config{deploy}) {
    $env->notify("Deploying SCS Broker...");

    # Create temporary directory
    my $tmp_dir = $env->workpath("scs-deploy");
    run("mkdir -p $tmp_dir");
    pushd($tmp_dir);

    # Download broker archive
    $self->fetch_uri($config{broker_uri});

    # Extract the archive
    my $archive_name = basename($config{broker_uri});
    $self->extract($archive_name);

    # Find the extracted directory and change into it
    my ($broker_dir) = glob("scs-broker-*");
    bail("Failed to find extracted broker directory") unless $broker_dir && -d $broker_dir;
    pushd($broker_dir);

    # Create artifacts directory and download files
    $self->fetch_artifacts($config{configserver_jar_uri}, $config{registry_jar_uri});

    # Create .go-version file
    mkfile_or_fail(".go-version", "1.22\n");

    # Create JSON for broker config
    my $broker_config = {
      broker_id => $config{broker_name},
      broker_name => $config{broker_name},
      description => "Broker to create SCS services",
      long_description => "Broker to create Spring Cloud Services (SCS) Config Servers or Service Registries",
      instance_domain => $apps_domain,
      instance_space_guid => $scs_space_guid,
      artifacts_directory => "/app/artifacts",
      broker_auth => {
        user => $config{broker_auth_username},
        password => $config{broker_auth_password}
      },
      cloud_foundry_config => {
        api_url => "https://$system_api_domain",
        skip_ssl_validation => ($config{skip_ssl_validation} eq 'true' ? JSON::PP::true : JSON::PP::false),
        cf_username => $cf_admin_username,
        cf_password => $cf_admin_password,
        uaa_client_id => $scs_client,
        uaa_client_secret => $scs_client_secret
      },
      services => [
        {
          service_id => "config-server",
          service_name => "config-server",
          service_plan_id => "default-cs",
          service_plan_name => "default",
          service_description => "Broker to create Config Servers",
          service_buildpack => $config{configserver_buildpack},
          service_stack => $config{stack},
          service_download_uri => $config{configserver_jar_uri}
        },
        {
          service_id => "service-registry",
          service_name => "service-registry",
          service_plan_id => "default-sr",
          service_plan_name => "default",
          service_description => "Broker to create Service Registries",
          service_buildpack => $config{registry_buildpack},
          service_stack => $config{stack},
          service_download_uri => $config{registry_jar_uri}
        }
      ],
      java_config => {
        "JBP_CONFIG_OPEN_JDK_JRE" => "{ \"jre\": { \"version\": \"$config{java_version}\" } }"
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

    mkfile_or_fail("manifest.yml", $manifest_content);

    # Push the app to CF
    $env->notify("Pushing SCS Broker to Cloud Foundry...");
    run("cf push -f manifest.yml");

    $env->notify("SCS service broker is now running, you should now be able to create a service, e.g.:");
    info("  \$ cf create-service config-server default test-service -c \"{...whatever json configuration you wish to use for config-server - see config-server docs from Spring.io...}\"");

    # Clean up
    popd(); # from broker dir
    popd(); # from tmp dir
  }

  if ($config{register}) {
    $env->notify("Registering SCS Broker...");

    # Check if broker is already registered
    my ($broker_json, $rc) = run("cf curl \"/v2/service_brokers\"");
    my $json_data = eval { decode_json($broker_json) };
    bail("Failed to parse broker list JSON: $@") if $@;

    my $broker_found = 0;
    foreach my $resource (@{$json_data->{resources}}) {
      if ($resource->{entity}->{name} eq $config{broker_name} ||
        $resource->{entity}->{name} eq $config{broker_old_name}) {
        $broker_found = 1;
        last;
      }
    }

    my $action = $broker_found ? "update" : "create";
    $env->notify(ucfirst($action) . "ing the service broker...");

    run("cf $action-service-broker \"$config{broker_name}\" \"$config{broker_auth_username}\" \"$config{broker_auth_password}\" \"https://scs-broker.$apps_domain\"");
  }

  return 1;
}

# Helper methods
sub fetch_uri {
  my ($self, $url) = @_;
  my $filename = basename($url);

  $self->env->notify("Downloading $filename...");
  my ($out, $rc, $err) = run("curl --fail --silent --show-error --location --remote-name --url \"$url\"");

  bail("Failed to download: $url\n$err") if $rc;
  return $filename;
}

sub fetch_artifacts {
  my ($self, $configserver_jar_uri, $registry_jar_uri) = @_;

  $self->env->notify("Downloading service artifacts...");
  run("mkdir -p artifacts");

  pushd("artifacts");

  $self->fetch_uri($configserver_jar_uri);
  $self->fetch_uri($registry_jar_uri);

  popd();
}

sub extract {
  my ($self, $archive) = @_;

  $self->env->notify("Extracting $archive...");

  if ($archive =~ /\.zip$/) {
    run("unzip -o \"$archive\"");
  }
  elsif ($archive =~ /\.t?gz$/) {
    run("tar zxf \"$archive\"");
  }
  else {
    bail("Unknown file type: $archive");
  }

  # Remove the archive
  run("rm \"$archive\"");
}

1;
