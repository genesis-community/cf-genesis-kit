package Genesis::Hook::CF::Info;

use v5.20;
use warnings;    # Genesis min perl version is 5.20
use Genesis qw/info error bail run/;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . './.genesis/lib'; }

use parent qw(Genesis::Hook);
use JSON::PP;

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	return $obj;
}

sub perform {
	my $self = shift;
	my $env  = $self->env;

	# Get exodus data
	my $exodus_data = $env->exodus_lookup('.');

	# Extract domain information
	my $system_domain = $exodus_data->{system_domain} || "system." . $exodus_data->{base_domain};
	my $api_domain    = $exodus_data->{api_domain}    || "api.$system_domain";

	# Validate that we have an API domain
	unless ($api_domain) {
		bail(
"No API domain found in exodus data. Please ensure the deployment has completed successfully."
		);
	}

	# Sanitize the API domain to prevent shell injection
	# Remove any shell metacharacters except dots, hyphens and alphanumerics
	$api_domain =~ s/[^\w\.-]//g;

	# Validate domain format
	unless ( $api_domain =~ /^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$/ ) {
		bail("Invalid API domain format: $api_domain");
	}

	my $api_url = "https://$api_domain";

	# Extract credentials
	my $admin    = $exodus_data->{admin_username};
	my $password = $exodus_data->{admin_password};

	# Get CF deployment information
	my $upstream_version  = $exodus_data->{'cf-deployment-version'}  || 'unknown';
	my $upstream_hotfixes = $exodus_data->{'cf-deployment-hotfixes'} || 'false';
	my $upstream_url      = $exodus_data->{'cf-deployment-releases'} || 'unknown';

	# Format hotfixes info
	my $hotfixes = "";
	if ( $upstream_hotfixes eq 'true' ) {
		$hotfixes = " #Y{(+ hot-fixes)}";
	}

	# Display information
	# Note: The original used 'describe' which appears to be a helper function
	# that formats multi-line output with proper indentation and styling
	info( "Based on #M{cf-deployment %s}%s\n"
		  . "[cf-deployment-releases url: #c{%s}]\n" . "\n"
		  . "Access to Cloud Foundry API:\n"
		  . "       url: #C{%s}\n"
		  . "  username: #M{%s}\n"
		  . "  password: #G{%s}\n",
		$upstream_version, $hotfixes, $upstream_url, $api_url, $admin, $password );

	# Check DNS resolution and connectivity before attempting CF commands
	info("\nChecking API connectivity...\n");

	# First check if we can resolve the domain
	my ( $nslookup_output, $nslookup_rc ) =
	  run( { stderr => 0 }, 'nslookup', $api_domain );

	if ( $nslookup_rc != 0 ) {
		error(
			"\n#R{DNS Resolution Failed:}\n"
			  . "Unable to resolve API domain: #Y{%s}\n" . "\n"
			  . "This typically means:\n"
			  . "  • The DNS is not configured or propagated yet\n"
			  . "  • There's a typo in the domain name\n"
			  . "  • The load balancer hasn't been set up yet\n" . "\n"
			  . "Please ensure the Cloud Foundry deployment has completed successfully\n"
			  . "and that DNS records have been properly configured.\n",
			$api_domain
		);
		return $self->done();
	}

	# Check if we can reach the API endpoint
	my ( $curl_test, $curl_rc ) = run( { stderr => 0 },
		'curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', '--connect-timeout', '5', $api_url );

	if ( $curl_rc != 0
		|| ( $curl_test !~ /^[23]\d\d$/ && $curl_test ne "000" ) )
	{
		error(
			"\n#R{API Endpoint Unreachable:}\n"
			  . "Unable to connect to API at: #Y{%s}\n" . "\n"
			  . "This typically means:\n"
			  . "  • The load balancer is not yet available\n"
			  . "  • Firewall rules are blocking access\n"
			  . "  • The CF deployment hasn't fully started\n" . "\n"
			  . "HTTP Status: %s\n",
			$api_url, $curl_test
		);
		return $self->done();
	}

	# Check if cf command is available
	if ( !run( { passfail => 1 }, 'which', 'cf' ) ) {
		error(  "\n#R{CF CLI Not Found:}\n"
			  . "The 'cf' command line tool is not installed or not in PATH.\n"
			  . "Please install the CF CLI to interact with Cloud Foundry.\n" );
		return $self->done();
	}

	# If the Load Balancer isn't availabe this will fail
	# Also fails if "cf" command is missing
	my ( $cf_api_output, $cf_api_rc ) =
	  run( { stderr => 0 }, 'cf', 'api', $api_url, '--skip-ssl-validation' );

	if ( $cf_api_rc != 0 ) {
		error(
			"\n#R{CF API Connection Failed:}\n"
			  . "Unable to set CF API endpoint.\n"
			  . "Error: %s\n",
			$cf_api_output
		);
		return $self->done();
	}

	my $cf_curl_output =
	  run( { onfailure => "Error executing 'cf curl /info'", stderr => 0 }, 'cf', 'curl', '/info' );

	# Parse and format JSON for better display
	my $data = eval { JSON::PP::decode_json($cf_curl_output) };
	if ($@) {

		# JSON parsing error
		error "  Error parsing output: $@\n";
		error "  Raw output: $cf_curl_output\n";
	}
	else {
		# Pretty-print the JSON with 2-space indentation
		my $formatted = JSON::PP->new->pretty->canonical->encode($data);

		# Add two spaces prefix to each line
		my $curl_output =
		  join( "\n", map { "  $_" } split( /\n/, $formatted ) );
		info $curl_output;
	}

	return $self->done();
}

sub results {
	my $self = shift;
	return $self->completed ? 1 : 0;
}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
