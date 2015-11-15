#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use Data::Dumper qw/Dumper/;

use lib qw(lib);
use UsenetIndexer qw//;

my %opts = ();
getopts('hc:', \%opts);
$opts{h} and usage();
main($_) for @ARGV;

sub main {
    my ($binary_id) = @_;

    my $config = $opts{c} || 'etc/common.conf';
    my $dbh = UsenetIndexer::GetDB($config);

    my ($content,$filename) = UsenetIndexer::BuildNZB($dbh, $binary_id);

    (my $basename = $filename) =~ s/\..+$//;

    open my $fh, '>', "$basename.nzb" or die "Could not open $basename.nzb: $!\n";
    print $fh $content;    
    close $fh;

    $dbh->disconnect();
}

sub usage {
    print <<EOF;
Usage: $0
    [-c config file|etc/common.conf]
EOF

    exit 1;
}

