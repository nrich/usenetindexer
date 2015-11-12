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

    my $newsgroup = '';
    
    my $number = 1;
    my $segments = '';

    my $sth = $dbh->prepare('SELECT newsgroup_id,message FROM usenet_article WHERE binary_id=? ORDER BY subject');
    $sth->execute($binary_id);

    while (my ($newsgroup_id, $message) = $sth->fetchrow_array()) {
        $newsgroup ||= UsenetIndexer::GetNewsGroupName($dbh, $newsgroup_id);

        $segments .= "  <segment bytes=\"100\" number=\"$number\">$message</segment>\n";
        $number++;
    }

    chomp $segments;

    my $bin = $dbh->prepare('SELECT name,extract(epoch from posted) FROM usenet_binary WHERE id=?');
    $bin->execute($binary_id);
    my ($filename, $posted) = $bin->fetchrow_array();
    $bin->finish();

    $dbh->rollback();

    (my $basename = $filename) =~ s/\..+$//;

    open my $fh, '>', "$basename.nzb" or die "Could not open $basename.nzb: $!\n";

    print $fh <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE nzb PUBLIC "-//newzBin//DTD NZB 1.1//EN" "http://www.newzbin.com/DTD/nzb/nzb-1.1.dtd">
<nzb xmlns="http://www.newzbin.com/DTD/2003/nzb">

<file poster="nobody (nobody\@nowhere.com)" date="$posted" subject="$filename">
 <groups>
  <group>$newsgroup</group>
 </groups>
 <segments>
$segments
 </segments>
</file>
</nzb>
EOF
    
}

sub usage {
    print <<EOF;
Usage: $0
    [-c config file|etc/common.conf]
EOF

    exit 1;
}

