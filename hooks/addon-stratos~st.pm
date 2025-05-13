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
  "[[  #y{--skip-cf-check} >>Skip CF CLI availability check\n";
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Parse options
  my %options = $self->parse_options([
      'json',
      'urls-only',
      'force',
      'skip-cf-check',
    ],
  );

  # Get command (default to 'info')
  my $command = $self->{args}->[0] || 'info';

  # Check for valid command
  if ($command !~ /^(info|deploy|open)$/) {
    bail("Unknown command: $command. Valid commands are 'info', 'deploy', and 'open'");
  }

  # Determine the Stratos deployment info
  my $info = $self->_get_stratos_info($env);

  # Handle commands
  if ($command eq 'info') {
    return $self->display_info($info, %options);
  }
  elsif ($command eq 'deploy') {
    $self->deploy_stratos($env, $info, %options);
    # Display info after deployment
    return $self->display_info($info, %options);
  }
  elsif ($command eq 'open') {
    return $self->open_in_browser($env, $info);
  }

  return 1;
}

sub _get_stratos_info {
  my ($self, $env) = @_;

  # Get BOSH target if possible
  my $deployment_exists = 0;
  eval {
    # Get deployment name from environment or configuration
    #TODO: Should we: my $exodus = $self->exodus_data()
    my $deployment_name = $env->lookup('stratos.deployment_name', $self->env->name . "-stratos");

    # Check if deployment exists
    my @deployments = $self->bosh->deployments();
    $deployment_exists = grep { $_ eq $deployment_name } @deployments;
  };

  # Get Stratos information from environment
  my $stratos_url = $env->lookup('stratos.url', '');
  if (!$stratos_url) {
    my $system_domain = $env->lookup('cf.system_domain', '');
    $stratos_url = $system_domain ? "https://stratos.$system_domain" : '';
  }

    # Get CF configuration
    my $cf_api = $env->lookup('cf.api_url', '');
    my $cf_org = $env->lookup('stratos.cf_org', 'stratos');
    my $cf_space = $env->lookup('stratos.cf_space', 'stratos');
    my $cf_app_name = $env->lookup('stratos.cf_app_name', 'stratos');

    # Determine if Stratos is deployed as a CF app
    my $is_cf_app_deployed = 0;
    my $cf_app_status = "unknown";
    eval {
        my ($out, $rc) = run('cf app "$1" >/dev/null 2>&1', $cf_app_name);
        $is_cf_app_deployed = ($rc == 0);
        if ($is_cf_app_deployed) {
            ($out, $rc) = run('cf app "$1" | grep -E "^#?status:" | awk \'{print $2}\'', $cf_app_name);
            $cf_app_status = $out if $rc == 0;
        }
    };

    my $stratos_version = $env->lookup('stratos.version', 'unknown');
    my $stratos_admin = $env->lookup('stratos.admin_user', 'admin');

    # Get credentials from vault
    my $admin_password = "";
    eval {
        $admin_password = $env->vault->get($env->secrets_base . "stratos/admin_password");
    };

    # Build info structure
    return {
        name => $env->lookup('stratos.deployment_name', $env->name . "-stratos"),
        status => $deployment_exists ? "Deployed via BOSH" :
                  $is_cf_app_deployed ? "Deployed as CF app ($cf_app_status)" : "Not Deployed",
        url => $stratos_url,
        version => $stratos_version,
        admin_user => $stratos_admin,
        admin_password => $admin_password ? $admin_password : "",
        has_admin_password => $admin_password ? 1 : 0,
        cf_api => $cf_api,
        cf_org => $cf_org,
        cf_space => $cf_space,
        cf_app_name => $cf_app_name,
        is_cf_app_deployed => $is_cf_app_deployed,
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

        # CF Information
        if ($info->{cf_api}) {
            info("\nCloud Foundry Details:");
            info("  API: %s", $info->{cf_api});
            info("  Organization: %s", $info->{cf_org});
            info("  Space: %s", $info->{cf_space});
            info("  App Name: %s", $info->{cf_app_name});
        }

        # Show helpful commands
        info("\nHelpful Commands:");
        info("  Open in browser: %s %s stratos open",
            $env->get_call_path(), $env->name);
        info("  Deploy Stratos: %s %s stratos deploy",
            $env->get_call_path(), $env->name);

        if ($info->{is_cf_app_deployed}) {
            info("  View CF app logs: cf logs %s --recent", $info->{cf_app_name});
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
    my $tmp_dir = $self->tempdir('stratos-deploy')
    eval {
        info("Preparing Stratos deployment...");

        # Target the correct CF organization and space
        info("Targeting CF organization '%s' and space '%s'...", $info->{cf_org}, $info->{cf_space});

        # Create org if it doesn't exist
        run('cf org "$1" >/dev/null 2>&1 || cf create-org "$1"', $info->{cf_org});

        # Target org and create space if it doesn't exist
        run('cf target -o "$1"', $info->{cf_org});
        run('cf space "$1" >/dev/null 2>&1 || cf create-space "$1"', $info->{cf_space});
        run('cf target -o "$1" -s "$2"', $info->{cf_org}, $info->{cf_space});

        # Create manifest file
        my $manifest_path = "$tmp_dir/manifest.yml";
        $self->_create_manifest($manifest_path, $info);

        # Deploy or update the app
        info("Deploying Stratos application...");
        run('cf push -f "$1"', $manifest_path);

        # Generate and store admin password if not already set
        if (!$info->{has_admin_password}) {
            my $password = $self->_generate_password(16);
            $env->vault->set($env->secrets_base . "stratos/admin_password", $password);
            info("Generated and stored admin password in vault");
            $info->{admin_password} = $password;
            $info->{has_admin_password} = 1;
        }

        # Update app environment variables with admin credentials
        info("Configuring Stratos admin credentials...");
        run('cf set-env "$1" CONSOLE_ADMIN_SCOPE stratos.admin', $info->{cf_app_name});
        run('cf set-env "$1" CONSOLE_ADMIN "$2"', $info->{cf_app_name}, $info->{admin_user});
        run('cf set-env "$1" CONSOLE_ADMIN_PASSWORD "$2"', $info->{cf_app_name}, $info->{admin_password});

        # Restart the app to apply new environment variables
        info("Restarting Stratos to apply configuration...");
        run('cf restart "$1"', $info->{cf_app_name});

        # Update the status in the info object
        $info->{is_cf_app_deployed} = 1;
        $info->{status} = "Deployed as CF app";

        info("\nStratos deployment completed successfully!");
    };

    if ($@) {
        bail("Failed to deploy Stratos: $@");
    }

    return 1;
}

sub _create_manifest {
    my ($self, $manifest_path, $info) = @_;

    my $yaml = YAML::PP->new;
    my $manifest = {
        applications => [
            {
                name => $info->{cf_app_name},
                memory => '1G',
                disk_quota => '1G',
                docker => {
                    image => 'splatform/stratos:latest'
                },
                env => {
                    'SSO_LOGIN' => 'false',
                    'CONSOLE_CLIENT' => 'cf',
                    'CONSOLE_CLIENT_SECRET' => '',
                    'CONSOLE_ADMIN_SCOPE' => 'stratos.admin',
                    'CONSOLE_ADMIN' => $info->{admin_user},
                    'CONSOLE_ADMIN_PASSWORD' => $info->{admin_password},
                }
            }
        ]
    };

    # Add custom routes if system domain is defined
    if ($info->{url} && $info->{url} =~ /^https?:\/\/([^\/]+)/) {
        my $route = $1;
        $manifest->{applications}->[0]->{routes} = [
            { route => $route }
        ];
    }

    # Write the manifest to file
    open my $fh, '>', $manifest_path or bail("Could not write manifest file: $!");
    print $fh $yaml->dump($manifest);
    close $fh;

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
