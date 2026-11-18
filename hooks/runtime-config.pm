package Genesis::Hook::RuntimeConfig::CF v3.1.0;

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

	return ("", "skipped", "CF deployment has not been deployed yet") unless $self->deployed;

	# The agent authenticates with the system_metrics certificate, which
	# upstream's add-system-metrics-agent ops file has the director generate
	# in CredHub for this deployment, alongside the scraper that reads the
	# agents.  Without that ops file there is no certificate to hand out.
	return (
		"", "skipped",
		"The CF manifest defines no system_metrics certificate.  Add the " .
		"cf-deployment/operations/addons/add-system-metrics-agent feature " .
		"to build this runtime config."
	) unless $self->env->manifest_lookup('variables.system_metrics', undef);

	# Name the variable by its absolute CredHub path, so the director fills
	# in the certificate when it deploys each VM.  No certificate or key is
	# read here, and none is written into the runtime config.
	my $variable = $self->env->credhub->base . 'system_metrics';
	my $system_metrics_tls = {
		ca_cert => "((${variable}.ca))",
		cert    => "((${variable}.certificate))",
		key     => "((${variable}.private_key))",
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
