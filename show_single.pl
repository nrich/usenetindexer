#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use Data::Dumper qw/Dumper/;
use POSIX qw/:sys_wait_h strftime/;

use lib qw(lib);
use UsenetIndexer qw//;

my %opts = ();
getopts('hc:', \%opts);
$opts{h} and usage();
main(@ARGV);

sub main {
    my ($newsgroup, $article_id) = @_;

    usage() unless $newsgroup;

    my $config = $opts{c} || 'etc/common.conf';

    my $dbh = UsenetIndexer::GetDB($config);

    my $newsgroup_id = UsenetIndexer::GetNewsGroupID($dbh, $newsgroup);
    my $nntp = UsenetIndexer::GetNNTP($config);
    $nntp->group($newsgroup);

    my $article = UsenetIndexer::GetArticle($nntp, $article_id);
    print STDERR Dumper $article;
}


sub usage {
    print <<EOF;
Usage: $0 <newsgroup> <message ID>
    [-c config file|etc/common.conf]
EOF

    exit 1;
}

