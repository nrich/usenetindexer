#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use Data::Dumper qw/Dumper/;
use POSIX qw/:sys_wait_h strftime/;
use File::Basename qw/basename/;

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
getopts('tfhc:p:a:s:', \%opts);
$opts{h} and usage();
main(@ARGV);

sub main {
    my ($newsgroup) = @_;

    usage() unless $newsgroup;

    my $config = $opts{c} || 'etc/common.conf';

    my $fill_missing = $opts{f} ? 1 : 0;

    my $dbh = UsenetIndexer::GetDB($config, AutoCommit=>1);

    my $newsgroup_id = UsenetIndexer::GetNewsGroupID($dbh, $newsgroup);

    my $sth = $opts{s}
        ? $dbh->prepare('SELECT article FROM usenet_article WHERE newsgroup_id=? AND article>=? ORDER BY article')
        : $dbh->prepare('SELECT article FROM usenet_article WHERE newsgroup_id=? ORDER BY article');

    $opts{s}
        ? $sth->execute($newsgroup_id, $opts{s})
        : $sth->execute($newsgroup_id);

    my $current = undef;
    my @missing = ();
    while (my ($article) = $sth->fetchrow_array()) {
        $current ||= $article;

        while ($current != $article) {
            push @missing, $current;
            $current++;
        }

        $current++;
    }

    $sth->finish();

    $dbh->disconnect();

    print "Found ", scalar @missing, " gaps to retry\n";
    $opts{t} and exit 0;

    $SIG{CHLD} = \&REAPER;

    my $article_count = $opts{a} || 1000;
    my $process_max = $opts{p} || 10;

    my @work = ();
    my $name = basename $0;
    while (my $article_id = shift @missing) {
        push @work, $article_id;

        if (scalar @work >= $article_count) {
            my $pid = fork();

            if ($pid) {
                @work = ();
                $CHILDREN{$pid} = 1;

                while (scalar keys %CHILDREN >= $process_max) {
                    sleep 1;
                }
            } elsif (defined $pid) {
                srand();
                my $dbh = UsenetIndexer::GetDB($config, AutoCommit=>1);
                $dbh->do("SET client_encoding TO 'latin1'");

                my $nntp = UsenetIndexer::GetNNTP($config);
                $nntp->group($newsgroup);

                while (my $article_id = shift @work) {
                    my $remaining = scalar @work;
                    $0 = "$name remaining $remaining";
                    get_article($nntp, $dbh, $article_id, $newsgroup_id, $fill_missing);
                }

                exit 0;
            } else {
                die "Fork failed: $!\n";
            }
        }
    }

    if (@work) {
        my $dbh = UsenetIndexer::GetDB($config, AutoCommit=>1);
        $dbh->do("SET client_encoding TO 'latin1'");

        my $nntp = UsenetIndexer::GetNNTP($config);
        $nntp->group($newsgroup);

        while (my $article_id = shift @work) {
            my $remaining = scalar @work;
            $0 = "$name remaining $remaining";
            get_article($nntp, $dbh, $article_id, $newsgroup_id, $fill_missing);
        }
    }

    $0 = "$name waiting";

    while (%CHILDREN) {
        sleep 1;
    }
}

sub get_article {
    my ($nntp, $dbh, $article_id, $newsgroup_id, $fill_missing) = @_;

    #my $sth = $dbh->prepare('INSERT INTO usenet_article(article,message,subject,posted,bytes,newsgroup_id) VALUES(?,?,?,?,?,?) ON CONFLICT DO NOTHING');
    my $sth = $dbh->prepare('INSERT INTO usenet_article(article,message,subject,posted,bytes,newsgroup_id) VALUES(?,?,?,?,?,?)');

    my $article = UsenetIndexer::GetArticle($nntp, $article_id);

    if ($fill_missing) {
        $article ||= {
            message => random_string(),
            subject => 'MISSING ARTICLE',
            posted => strftime('%Y-%m-%d %H:%M:%S', localtime),
            bytes => 0,
        };
    }

    return unless $article;

    $sth->execute($article_id, $article->{message}, $article->{subject}, $article->{posted}, $article->{bytes}, $newsgroup_id);
}

sub random_string {
    my ($length, $tokens) = @_;

    $length ||= 254;
    $tokens ||= ['A' .. 'Z', 'a' .. 'z', '0' .. '9'];

    my $message = '_' x $length;
    $message =~ s/_/$tokens->[rand @$tokens]/ge;
    
    return $message;
}

sub usage {
    print <<EOF;
Usage: $0 <newsgroup name>
    [-c config file|etc/common.conf]
    [-f fill missing articles with dummy data]
    [-t test mode]
    [-a article count|1000]
    [-p process count|10] 
EOF

    exit 1;
}

