package Genesis::Hook::New::CF v3.0.1;

use v5.20;
use warnings;    # Genesis min perl version is 5.20

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . './.genesis/lib' }

use parent qw(Genesis::Hook);

use Genesis     qw/bail info warning run/;
use Genesis::UI qw/prompt_for_choice/;
use JSON::PP;

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->{database}          = '';
	$obj->{bucket_prefix}     = '';
	$obj->{use_provided_cert} = '';
	$obj->{features}          = [];
	$obj->{base_domain}       = '';
	$obj->{system_domain}     = '';
	$obj->{apps_domain}       = '';
	return $obj;
}

sub perform {
	bail("new hook not currently supported");
}


1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
