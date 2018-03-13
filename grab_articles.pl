#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use Data::Dumper qw/Dumper/;
use POSIX qw/:sys_wait_h strftime ceil floor/;
use File::Basename qw/basename/;

use lib qw(lib);
use UsenetIndexer qw//;

my %CHILDREN = ();
my %opts = ();

sub REAPER {
    while ((my $child = waitpid(-1, WNOHANG)) > 0) {
        print("Reaping child $child\n");
        delete $CHILDREN{$child};
    }

    $SIG{CHLD} = \&REAPER;
}

getopts('hbc:p:a:o', \%opts);
$opts{h} and usage();
main(@ARGV);

sub main {
    my ($newsgroup) = @_;

    usage() unless $newsgroup;

    $SIG{CHLD} = \&REAPER;

    my $config = $opts{c} || 'etc/common.conf';

    my $articlecount = $opts{a} || 1000;
    my $forks = $opts{p}||20;

    my $dbh = UsenetIndexer::GetDB($config, AutoCommit => 1); 
    my $newsgroup_id = UsenetIndexer::GetNewsGroupID($dbh, $newsgroup);

    my $sth = $dbh->prepare('SELECT min(article), max(article) FROM usenet_article WHERE newsgroup_id=?');
    $sth->execute($newsgroup_id);
    my ($first_article, $last_article) = $sth->fetchrow_array();
    $first_article ||= 0;
    $last_article ||= 0;
    $sth->finish();

    my $nntp = UsenetIndexer::GetNNTP($config);
    my ($nof_arts, $first_art, $last_art) = $nntp->group($newsgroup);

    undef $nntp;

    my $end = $opts{b} ? $first_article : $last_art;
    my $first = $opts{b} ? $first_art : $last_article||($end - $articlecount * $forks);

    if ($opts{o}) {
        die "Cannot use -o with -a or -b\n" if $opts{b}||$opts{f}||$opts{a};

        my $count = $end - $first;

        while ($forks > 1) {
            $articlecount = ceil($count/$forks);

            last if $articlecount > 30;
            $forks--;
        }

        $articlecount = $count if $forks == 1;
    }

    if ($end) {
        if (not $opts{b} and $end - $first > ($articlecount * $forks)) {
            my $total = $articlecount * $forks;
            my $count = $end - $first;
            die "Will not be able to grab $count in run, only grabbing $total articles\n";
        }
    }

    $dbh->disconnect();

    for my $id (1 .. $forks) {
        my $pid = fork();

        if ($pid) {
            $CHILDREN{$pid} = 1;
        } elsif (defined $pid) {
            my $nntp = UsenetIndexer::GetNNTP($config);
            $nntp->group($newsgroup);

            my $dbh = UsenetIndexer::GetDB($config, AutoCommit => 1);
            $dbh->do("SET client_encoding TO 'latin1'");

            $SIG{CHLD} = 'IGNORE';
            my $start = $end - $articlecount;
            if ($start < $first) {
                $start = $first + 1;
            }
            get($dbh, $nntp, $start, $end, $id, $newsgroup_id);
            $dbh->disconnect();
            exit 0;
        } else {
            die "Fork failed: $!\n";
        }

        $end -= $articlecount;
        last if $end < $first;
    }

    while (%CHILDREN) {
        sleep 1;
    }

}

sub get {
    my ($dbh, $nntp, $start, $end, $id, $newsgroup_id) = @_;

    my $count = $end-$start;

    print STDERR "$id -> [$start,$end] -> $count\n";

    my $name = basename $0;
    $0 = "$name $id";

    my $sth = $dbh->prepare('INSERT INTO usenet_article(article,message,subject,posted,bytes,newsgroup_id) VALUES(?,?,?,?,?,?)');

    my $article_id = $start;
    while ($article_id <= $end) {
        my $remaining = $end - $article_id;

        $0 = "$name $id remaining $remaining";
        my $article = UsenetIndexer::GetArticle($nntp, $article_id);        

        unless ($article) {
            $article_id++;
            next;
        }

        unless ($article->{message}) {
            $article_id++;
            next;
        }

        $sth->execute($article_id, $article->{message}, $article->{subject}, $article->{posted}, $article->{bytes}, $newsgroup_id);
        $article_id++;
    }
}

sub usage {
    print <<EOF;
Usage: $0 <newsgroup name> 
    [-o optimal grab]
    [-b backfill]
    [-c config file|etc/common.conf]
    [-a article count|1000]
    [-p process count|20] 
EOF

    exit 1;
}


