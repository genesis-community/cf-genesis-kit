# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
package Genesis::Hook::PostDeploy::CF;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::PostDeploy);

use Genesis qw/describe/;

# init - Initialize the hook {{{
sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
  $obj->check_minimum_genesis_version('3.1.0');
  return $obj;
}
# }}}

# perform - Main hook execution {{{
sub perform {
  my ($self) = @_;
  
  if ($ENV{GENESIS_DEPLOY_RC} == 0) {
    describe(
      "",
      "#M{$ENV{GENESIS_ENVIRONMENT}} Cloud Foundry deployed!",
      "",
      "For details about the deployment, run",
      "",
      "  #G{$ENV{GENESIS_CALL_ENV} info}",
      "",
      "To see a list of available addons, run",
      "",
      "  #G{$ENV{GENESIS_CALL_ENV} do -- list}",
      "",
      "To set up your local cf CLI installation with useful plugins:",
      "",
      "  #G{$ENV{GENESIS_CALL_ENV} do -- setup-cli}",
      "",
      "To log into Cloud Foundry, run",
      "",
      "  #G{$ENV{GENESIS_CALL_ENV} do -- login}",
      ""
    );
  }
  
  return $self->done();
}
# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
