#!/usr/bin/perl
use strict;
use warnings;
use JSON::PP qw/decode_json/;

my $rc = 0;
my $data = decode_json(do { local $/; <> });
for my $r (@{$data->{releases} || []}) {
	chomp(my $sha1 = `curl -Lsk "$r->{url}" | sha1sum`);
	$sha1 =~ s/ .*//;

	if ($r->{sha1} eq $sha1) {
		print "[ok] $r->{name} sha1 checkums are correct.\n";
	} else {
		print "[!!] $r->{name} sha1 checkums are INCORRECT.\n";
		print "[!!]     the kit has '$r->{sha1}' (wrong)\n";
		print "[!!]    actually got '$sha1' (correct)\n";
		$rc = 1;
	}
}
exit $rc;
