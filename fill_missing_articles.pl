#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use Data::Dumper qw/Dumper/;
use POSIX qw/:sys_wait_h strftime/;

use lib qw(lib);
use UsenetIndexer qw//;

my %CHILDREN = ();

sub REAPER {
    while ((my $child = waitpid(-1, WNOHANG)) > 0) {
        print("Reaping child $child\n");
        delete $CHILDREN{$child};
    }

    $SIG{CHLD} = \&REAPER;
}

my %opts = ();
getopts('fhc:', \%opts);
$opts{h} and usage();
main(@ARGV);

sub main {
    my ($newsgroup) = @_;

    usage() unless $newsgroup;

    my $config = $opts{c} || 'etc/common.conf';

    my $fill_missing = $opts{f} ? 1 : 0;

    my $dbh = UsenetIndexer::GetDB($config, AutoCommit=>1);

    my $sth = $dbh->prepare('SELECT MIN(article), MAX(article) FROM usenet_article');
    $sth->execute();
    my ($min, $max) = $sth->fetchrow_array();
    $sth->finish();

    my $middle = int(($max-$min)/2);

    my $newsgroup_id = UsenetIndexer::GetNewsGroupID($dbh, $newsgroup);

    my @missing = ();
    missing_between($dbh, $min, $max, $newsgroup_id);

    $dbh->disconnect();

    $SIG{CHLD} = \&REAPER;

    my @work = ();
    while (my $article_id = shift @missing) {
        push @work, $article_id;

        if (scalar @work >= 100) {
            my $pid = fork();

            if ($pid) {
                @work = ();
                $CHILDREN{$pid} = 1;

                while (scalar keys %CHILDREN >= 10) {
                    sleep 1;
                }
            } elsif (defined $pid) {
                srand();
                my $dbh = UsenetIndexer::GetDB($config, AutoCommit=>1);
                my $nntp = UsenetIndexer::GetNNTP($config);
                $nntp->group($newsgroup);

                get_article($nntp, $dbh, $_, $newsgroup_id, $fill_missing) for @work;
                exit 0;
            } else {
                die "Fork failed: $!\n";
            }
        }
    }

    if (@work) {
        my $dbh = UsenetIndexer::GetDB($config, AutoCommit=>1);
        my $nntp = UsenetIndexer::GetNNTP($config);
        $nntp->group($newsgroup);
        get_article($nntp, $dbh, $_, $newsgroup_id, $fill_missing) for @work;
    }

    while (%CHILDREN) {
        sleep 1;
    }
}

sub missing_between {
    my ($dbh, $min, $max, $newsgroup_id, $missing) = @_;

    my $sth = $dbh->prepare('SELECT COUNT(1) FROM usenet_article WHERE article >= ? AND article <= ?');
    $sth->execute($min, $max);
    my ($count) = $sth->fetchrow_array();

    if ($max-$min <= 200) {
        if ($count < $max-$min) {
            for my $article ($min .. $max) {
                my $exists = $dbh->prepare('SELECT COUNT(1) FROM usenet_article WHERE article = ?');
                $exists->execute($article);
                my ($article_exists) = $exists->fetchrow_array();
                $exists->finish();

                push @$missing, $article unless $article_exists;
            }
        }
        return;
    }

    if ($count != ($max-$min)) {
        my $middle = int(($max-$min)/2);

        missing_between($dbh, $min, $min+$middle, $newsgroup_id, $missing);
        missing_between($dbh, $min+$middle, $max, $newsgroup_id, $missing);
    }
}

sub get_article {
    my ($nntp, $dbh, $article_id, $newsgroup_id, $fill_missing) = @_;

    my $sth = $dbh->prepare('INSERT INTO usenet_article(article,message,subject,posted,newsgroup_id) VALUES(?,?,?,?,?)');

    my $article = UsenetIndexer::GetArticle($nntp, $article_id);

    if ($fill_missing) {
        my $message = '_' x 254;
        my @tokens = ('A' .. 'Z', 'a' .. 'z', '0' .. '9');
        $message =~ s/_/$tokens[rand @tokens]/ge;
        my $posted = strftime '%Y-%m-%d %H:%M:%S', localtime();

        $article ||= {message => $message, subject => 'MISSING ARTICLE', posted => $posted};
    }

    return unless $article;

    $sth->execute($article_id, $article->{message}, $article->{subject}, $article->{posted}, $newsgroup_id);
}

sub usage {
    print <<EOF;
Usage: $0 <newsgroup name>
    [-c config file|etc/common.conf]
    [-f fill missing articles with dummy data]
EOF

    exit 1;
}

