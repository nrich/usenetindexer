#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use Data::Dumper qw/Dumper/;
use POSIX qw/:sys_wait_h strftime/;

use lib qw(lib);
use UsenetIndexer qw//;

my $articlecount;

my %CHILDREN = ();
my %opts = ();

sub REAPER {
    while ((my $child = waitpid(-1, WNOHANG)) > 0) {
        print("Reaping child $child\n");
        delete $CHILDREN{$child};
    }

    $SIG{CHLD} = \&REAPER;
}

getopts('hbc:p:a:', \%opts);
$opts{h} and usage();
main(@ARGV);

sub main {
    my ($newsgroup) = @_;

    usage() unless $newsgroup;

    $SIG{CHLD} = \&REAPER;

    my $config = $opts{c} || 'etc/common.conf';

    $articlecount = $opts{a} || 2000;
    my $forks = $opts{p}||8;

    my $dbh = UsenetIndexer::GetDB($config); 

    my $sth = $dbh->prepare('SELECT min(article), max(article) FROM usenet_article');
    $sth->execute();
    my ($first_article, $last_article) = $sth->fetchrow_array();
    $sth->finish();

    my $nntp = UsenetIndexer::GetNNTP($config);
    my ($nof_arts, $first_art, $last_art) = $nntp->group($newsgroup);
    undef $nntp;

    my $end = $opts{b} ? $first_article : $last_art;
    my $first = $opts{b} ? $first_art : $last_article;

    my $newsgroup_id = UsenetIndexer::GetNewsGroupID($dbh, $newsgroup);

    for my $id (1 .. $forks) {
        my $pid = fork();

        if ($pid) {
            $CHILDREN{$pid} = 1;
        } elsif (defined $pid) {
            my $nntp = UsenetIndexer::GetNNTP($config);
            $nntp->group($newsgroup);

            $dbh->disconnect();
            my $dbh = UsenetIndexer::GetDB($config, AutoCommit => 1);

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

    $dbh->disconnect();
}

sub get {
    my ($dbh, $nntp, $start, $end, $id, $newsgroup_id) = @_;

print STDERR "$id -> [$start, $end]\n";

    $0 = "$0 $id";

    my $sth = $dbh->prepare('INSERT INTO usenet_article(article,message,subject,posted,newsgroup_id) VALUES(?,?,?,?,?)');

    my $article_id = $start;
    while ($article_id <= $end) {
        my $article = UsenetIndexer::GetArticle($nntp, $article_id);        

        $sth->execute($article_id, $article->{message}, $article->{subject}, $article->{posted}, $newsgroup_id);
        $article_id++;
    }
}

sub usage {
    print <<EOF;
Usage: $0 <newsgroup name> 
    [-b backfile]
    [-c config file|etc/common.conf]
    [-a article count|2000]
    [-p process count|8] 
EOF

    exit 1;
}


