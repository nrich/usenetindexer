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
    my ($newsgroup) = @_;

    usage() unless $newsgroup;

    my $config = $opts{c} || 'etc/common.conf';

    my $dbh = UsenetIndexer::GetDB($config, AutoCommit=>1);

    my $sth = $dbh->prepare('SELECT MIN(article), MAX(article) FROM usenet_article');
    $sth->execute();
    my ($min, $max) = $sth->fetchrow_array();
    $sth->finish();

    my $middle = int(($max-$min)/2);


    my $newsgroup_id = UsenetIndexer::GetNewsGroupID($dbh, $newsgroup);
    my $nntp = UsenetIndexer::GetNNTP($config);
    $nntp->group($newsgroup);

    missing_between($nntp, $dbh, $min, $max, $newsgroup_id);
}

sub missing_between {
    my ($nntp, $dbh, $min, $max, $newsgroup_id) = @_;

    my $sth = $dbh->prepare('SELECT COUNT(1) FROM usenet_article WHERE article >= ? AND article <= ?');
    $sth->execute($min, $max);
    my ($count) = $sth->fetchrow_array();

    if ($max-$min <= 200) {
        if ($count < $max-$min) {
            my @missing = ();

            print STDERR "Looking for gap in $min -> $max (count is $count)\n";

            for my $article ($min .. $max) {
                my $exists = $dbh->prepare('SELECT COUNT(1) FROM usenet_article WHERE article = ?');
                $exists->execute($article);
                my ($article_exists) = $exists->fetchrow_array();
                $exists->finish();

                push @missing, $article unless $article_exists;
            }

            get($nntp, $dbh, $_, $newsgroup_id) for @missing;
        }
        return;
    }

    if ($count != ($max-$min)) {
        my $middle = int(($max-$min)/2);

        missing_between($nntp, $dbh, $min, $min+$middle, $newsgroup_id);
        missing_between($nntp, $dbh, $min+$middle, $max, $newsgroup_id);
    }
}

sub get {
    my ($nntp, $dbh, $article_id, $newsgroup_id) = @_;

    my $sth = $dbh->prepare('INSERT INTO usenet_article(article,message,subject,posted,newsgroup_id) VALUES(?,?,?,?,?)');

    my $article = UsenetIndexer::GetArticle($nntp, $article_id);
    return unless $article;

    $sth->execute($article_id, $article->{message}, $article->{subject}, $article->{posted}, $newsgroup_id);
}

sub usage {
    print <<EOF;
Usage: $0
    [-c config file|etc/common.conf]
EOF

    exit 1;
}

