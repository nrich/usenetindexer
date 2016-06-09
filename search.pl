#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use Data::Dumper qw/Dumper/;

use lib qw(lib);
use UsenetIndexer qw//;

my %opts = ();
getopts('hbc:', \%opts);
$opts{h} and usage();
main($_) for @ARGV;

sub main {
    my ($query, $optional) = @_;

    $optional ||= '';

    my $config = $opts{c} || 'etc/common.conf';
    my $dbh = UsenetIndexer::GetDB($config);

    $query =~ s/ /&/g;
    $optional =~ s/ /\|/g;

    my $search = "$query";
    if ($optional) {
        $search = "${search}&($optional)";
    }

    my $sth = $dbh->prepare("SELECT id,name,posted FROM usenet_binary WHERE to_tsvector('english', name) @@ to_tsquery('english', ?) ORDER BY posted");
    $sth->execute($search);

    while (my ($id, $name, $posted) = $sth->fetchrow_array()) {
        print "$id -> $name\n";

        if ($opts{b}) {
            my ($content,$filename) = UsenetIndexer::BuildNZB($dbh, $id);
            (my $basename = $filename) =~ s/\.[^.]+?$//;

            open my $fh, '>', "$basename.nzb" or die "Could not open $basename.nzb: $!\n";
            print $fh $content;    
            close $fh;
        }
    }
    $sth->finish();

    $dbh->disconnect();
}

sub usage {
    print <<EOF;
Usage: $0
    [-c config file|etc/common.conf]
EOF

    exit 1;
}

