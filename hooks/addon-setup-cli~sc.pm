package Genesis::Hook::Addon::CF::SetupCLI;

use v5.20;
use warnings;    # Genesis min perl version is 5.20

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . './.genesis/lib' }

use parent         qw(Genesis::Hook::Addon);
use Genesis        qw/bail info run/;
use Genesis::UI    qw/prompt_for_boolean/;
use File::Basename qw/basename/;

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

sub cmd_details {
	return
	"Installs cf CLI plugins like 'Targets', which helps to manage multiple Cloud Foundries from a single jumpbox.\n".
	"Supports the following options:\n".
	"[[  #y{--f}                 >>Force installation of plugins, overwriting existing versions";
}

sub perform {
	my ($self) = @_;
	my $env = $self->env;

	# Parse options according to the proper pattern
	my %options = $self->parse_options(
		[
			'f', # Force installation of plugins
		]
	);

	# Check for unexpected arguments
	if ( scalar( @{ $self->{args} } ) > 0 ) {
		bail("#R{[ERROR]} setup-cli does not take any arguments");
	}

	my $force = $options{f} ? 1 : 0;

	my ( $out, $rc ) = run({interactive => 0}, 'cf list-plugin-repos | grep -q CF-Community');
	if ( $rc != 0 ) {
		info('Adding #G{Cloud Foundry Community} plugins repository...');
		run(
			{interactive => 0},
			'cf', 'add-plugin-repo', 'CF-Community', 'http://plugins.cloudfoundry.org'
		);
	}

	# TODO: Parse output in Perl not grep
	( $out, $rc ) = run(
		{interactive => 0}, 'cf plugins | grep -q \'^cf-targets\''
	);
	bail("#R{[ERROR]} cf plugins listing failed with rc=$rc") unless ( $rc == 0 );

	info('Installing the #C{cf-targets} plugin...');
	my $cmd = 'cf install-plugin -r CF-Community Targets';
	$cmd += ' -f' if ($force);
	run($cmd);

	run({interactive => 0},'cf plugins');

	return $self->done(1);
}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
