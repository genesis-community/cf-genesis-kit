package Genesis::Hook::Addon::CF::Smoketest;

use v5.20;
use warnings;    # Genesis min perl version is 5.20
use Genesis     qw/bail info run/;
use Genesis::UI qw/prompt_for_boolean/;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . './.genesis/lib' }

use parent qw(Genesis::Hook::Addon);

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

sub cmd_details {
	return "Run the smoke tests errand on the first vm in the api instance group.";
}

sub perform {
	my ($self) = @_;

	$self->bosh->execute(
		'run-errand',
		'smoke_tests',
		{ interactive => 1 },    # Run in interactive mode means seeing output as it happens
	  )

	  return $self->done();
}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
