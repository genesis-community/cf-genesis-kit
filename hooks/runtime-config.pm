package Genesis::Hook::RuntimeConfig::CF v3.0.2;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::RuntimeConfig);

use Genesis qw/bail info warning run/;
use JSON::PP;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');

	# Define valid builds - only system-metrics for CF
	$obj->register_runtime_config_builds(
		[system_metrics => "System Metrics Agent"],
	);
	$obj->validate_runtime_config_requests();

	return $obj;
}

sub build_system_metrics_runtime {
	my ($self) = @_;

	# Check if CF deployment exists and has the required secrets
	return ("", "skipped", "CF deployment has not been deployed yet") unless $self->deployed;

	# Get exodus data directly from this CF deployment
	my $exodus = $self->exodus_data;

	# Check for required system metrics secrets
	my $required_secrets = [qw/system_metrics_ca_cert system_metrics_cert system_metrics_key/];
	my @missing_secrets;
	for my $secret (@$required_secrets) {
		if (!$exodus->{$secret}) {
			push @missing_secrets, $secret;
		}
	}

	if (@missing_secrets) {
		return (
			"", "skipped",
			"Missing required system metrics secrets in exodus data: " . join(", ", @missing_secrets)
		);
	}

	# Get system metrics TLS configuration from exodus data with entombment
	my $system_metrics_tls = {
		ca_cert => $self->_get_exodus_secret('system_metrics_ca_cert'),
		cert => $self->_get_exodus_secret('system_metrics_cert'),
		key => $self->_get_exodus_secret('system_metrics_key')
	};

	# Get user-provided excluded deployments with validation
	my $user_excluded_deployments = [];
	eval {
		my $excluded = $self->{request_options}{system_metrics}{params}{excluded_deployments};
		$user_excluded_deployments = $excluded if ref($excluded) eq 'ARRAY';
	};
	bail("Invalid excluded_deployments parameter for system-metrics: %s", $@) if $@;

	# Build list of deployments to exclude - CF is always excluded, plus user-specified ones
	my $env_name = $self->env->name;
	my @excluded_deployments = (
		$env_name . "-cf",  # CF deployment is always excluded
		map {
			# Add environment prefix if not already present
			$_ =~ /^$env_name-/ ? $_ : $env_name . "-" . $_
		} @$user_excluded_deployments
	);

	# Create the system metrics runtime config structure
	my $runtime = {
		addons => [
			{
				name => 'system-metrics',
				exclude => {
					deployments => [
						@excluded_deployments
					]
				},
				jobs => [
					{
						name => 'loggr-system-metrics-agent',
						release => 'system-metrics',
						properties => {
							metrics_port => 53035,
							system_metrics => {
								tls => $system_metrics_tls
							}
						}
					}
				]
			}
		]
	};

	# Look up the system-metrics release information
	my $release = $self->env->manifest_lookup('releases.system-metrics', undef);
	if ($release && $release->{name}) {
		$runtime->{releases} = [$release];
	} else {
		# If no release is defined in the manifest, we'll let BOSH handle it
		# but warn about it
		warning("No system-metrics release defined in CF manifest - BOSH will need the release uploaded");
	}

	# Convert to YAML and return
	my ($out, $rc, $err) = run(
		'spruce merge <(echo "$1")',
		JSON::PP::encode_json($runtime)
	);
	bail("Failed to merge system-metrics runtime: %s", $err) if $rc;

	return $out;
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
