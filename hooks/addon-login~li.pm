package Genesis::Hook::Addon::CF::Login v3.0.0;

use v5.20;
use warnings;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib' }

use parent qw(Genesis::Hook::Addon);

use Genesis     qw/bail info run/;
use Genesis::UI qw/prompt_for_boolean/;

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

sub cmd_details {
	return
	"Log into the Cloud Foundry instance as the admin user account.\n" .
	"This will overwrite local cf CLI configuration!\n" .
	"Supports the following options:\n" .
	"[[  #y{--yes, -y}          >>Skip all confirmations, useful for non-interactive environments like pipelines\n".
	"[[  #y{--validate-ssl}     >>Enforce SSL validation when connecting to the CF API";
}

sub perform {
	my ($self) = @_;
	my $env = $self->env;

	# Parse options
	my %options = $self->parse_options(
		[
			'yes|y',           # Skip confirmation prompts
			'validate-ssl',    # Enforce SSL validation
		]
	);

	my $non_interactive = $options{'yes'}          ? 1 : 0;
	my $validate_ssl    = $options{'validate-ssl'} ? 1 : 0;

	my $use_cf_targets = 1;
	info("#Y{Checking for cf-targets plugin}\n");
	my ( $out, $rc ) = run('cf plugins | grep -q \'^cf-targets\'');
	if ( $rc != 0 ) {
		$use_cf_targets = 0;
		# TODO: Check now in 2025 if the NOTE below is still accurate.
		info(
			"#Y{The cf-targets plugin does not seem to be installed}\n" .
			"It is recommended you install it first, via #G{%s do setup-cli}'\n\n" .
			"[[NOTE: >>It is not currently compatible with Apple M1 (arm) architecture",
			$env->get_call_path_with_env
		);

		# Skip confirmation if in non-interactive mode
		if ( !$non_interactive ) {
			my $continue = prompt_for_boolean( "Continue anyways?", 0 );
			return $self->done(0) unless $continue;
		}
		else {
			info("Running in non-interactive mode, continuing without cf-targets plugin...");
		}
	}

	# Get CF credentials from exodus data
	my $exodus = $self->exodus_data();
	my ( $api_domain, $username, $password ) =
	  $exodus->@{qw/api_domain admin_username admin_password/};
	my $api_url = "https://${api_domain}";

	# Handle SSL validation based on option
	if ($validate_ssl) {
		info("Using SSL validation for CF API connection %s", $api_url);
		my ( $out, $rc ) = run( {interactive => 0}, 'cf', 'api', $api_url);
		info("%s\n", $out);
	}
	else {
		info("#Y{Using skip-ssl-validation for CF API connection} %s\n", $api_url);
		my ( $out, $rc ) = run( {interactive => 0}, 'cf', 'api', '--skip-ssl-validation', $api_url );
		info("%s\n", $out);
	}

	info("#G{Logging in as} %s\n", $username);
	( $out, $rc ) = run( {interactive => 0},'cf', 'auth', $username, $password );
	info("%s\n", $out);

	run( {interactive => 0}, 'cf', 'save-target', '-f', $ENV{GENESIS_ENVIRONMENT} ) if ($use_cf_targets);

	info("\n\n");
	( $out, $rc ) = run('cf target');
	info("%s\n", $out);

	return $self->done();
}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
