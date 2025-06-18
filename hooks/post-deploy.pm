package Genesis::Hook::PostDeploy::CF;

use v5.20;
use warnings;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib' }

use parent qw(Genesis::Hook::PostDeploy);

use Genesis qw/info/;

# init - Initialize the hook {{{
sub init {
	my ( $class, %ops ) = @_;
	my $obj = $class->SUPER::init(%ops);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

# }}}

# perform - Main hook execution {{{
sub perform {
	my ($self) = @_;

	if ( $ENV{GENESIS_DEPLOY_RC} == 0 ) {
		my $genesis_env      = "$ENV{GENESIS_ENVIRONMENT}";
		my $genesis_call_env = "$ENV{GENESIS_CALL_ENV}";
		info(
			"#M{%s} Cloud Foundry deployed!\n\n"
			  . "For details about the deployment, run\n\n"
			  . "  #G{%s} info\n\n"
			  . "To see a list of available addons, run\n\n"
			  . "  #G{%s} do -- list\n\n"
			  . "To set up your local cf CLI installation with useful plugins:\n\n"
			  . "  #G{%s} do -- setup-cli\n\n"
			  . "To log into Cloud Foundry, run\n\n"
			  . "  #G{%s} do -- login\n\n",
			$genesis_env,      $genesis_call_env, $genesis_call_env,
			$genesis_call_env, $genesis_call_env
		);
	}

	return $self->done();
}

# }}}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
