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
	"[[  #y{-f}                 >>Force installation of plugins, overwriting existing versions";
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
	my $force = $options{f} ? 1 : 0;

	my ( $out, $rc ) = run(
		{interactive => 0}, q{cf plugins | grep -q '^cf-targets'}
	);
	if ( $rc == 0 && !$force ) {
        my ($existing) = run(
            { interactive => 0 },
            q{cf plugins --checksum | grep '^cf-targets' | tr -s ' ' | cut -d ' ' -f2}
        );
        chomp $existing;
        info("#G{cf-targets is already installed} #C{(version $existing)}. No action needed.");
        return $self->done(1);
	}

	# 1) Determine OS/ARCH
    my ($os)   = run('uname -s | tr A-Z a-z'); chomp $os;
    $os = 'darwin' if $os eq 'darwin';
    $os = 'linux'  if $os eq 'linux';

    my ($arch) = run('uname -m'); chomp $arch;
    $arch = 'amd64' if $arch eq 'x86_64';
    $arch = 'arm64' if $arch eq 'aarch64';

    # 2) Fetch latest release tag from GitHub
    info("Fetching latest cf-targets-plugin release from GitHub...");
    my ($tag) = run(
      q{curl -s https://api.github.com/repos/cloudfoundry-community/cf-targets-plugin/releases/latest} .
      q{ | jq -r .tag_name}
    );
    chomp $tag;
    $tag =~ s/^v//;   # strip leading “v”, e.g. “v2.0.1” → “2.0.1”

	# 3) Find the right download URL for our OS/ARCH, using jq
	info("Resolving download URL for $os/$arch ...");
	my $api       = 'https://api.github.com/repos/cloudfoundry-community/cf-targets-plugin/releases/latest';
	my $asset     = "cf-targets-plugin-$os-$arch";
	my $jq_filter = qq{.assets[] | select(.name=="$asset") | .browser_download_url};

	my ($download_url) = run(
	{ interactive => 0 },
	"curl -s $api | jq -r '$jq_filter'"
	);
	chomp $download_url;
	bail("Couldn’t find a $asset asset in release $tag") unless $download_url;

	# 4) Download, chmod and install
    info("Downloading cf-targets #C{v$tag} from $download_url ...");
    my $tmp = "/tmp/cf-targets-$tag-$$";
    run("curl -sL -f -o $tmp '$download_url'");
    bail("Download failed or empty") unless -s $tmp;
    run("chmod +x $tmp");

	info("Installing plugin (force) ...");
    ($out, $rc) = run("cf install-plugin -f $tmp");
    run("rm -f $tmp");    # cleanup

	# 5) Verify
    ( undef, $rc ) = run(q{cf plugins | grep -q '^cf-targets'});
    bail("Installation failed; cf-targets not found after install") if $rc;

	info("#G{[OK]} cf-targets v$tag installed successfully.");
    run('cf plugins');

    return $self->done(1);

}

1;

# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
