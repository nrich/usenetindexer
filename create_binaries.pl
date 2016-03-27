#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use Data::Dumper qw/Dumper/;
use POSIX qw/:sys_wait_h strftime/;

use lib qw(lib);
use UsenetIndexer qw//;

my %opts = ();
getopts('thc:', \%opts);
$opts{h} and usage();
main(@ARGV);

sub main {
    my $config = $opts{c} || 'etc/common.conf';

    my $dbh = UsenetIndexer::GetDB($config);

    my $sth = $dbh->prepare('SELECT article,subject,posted FROM usenet_article WHERE binary_id IS NULL ORDER BY subject');
    $sth->execute();

    my $test = '';
    my $articles = [];
    while (my ($article, $subject, $posted) = $sth->fetchrow_array()) {
        my ($number, $count) = $subject =~ /.*\((\d+)\/(\d+)\)/g;

        $number ||= '';
        $count ||= '';

        my $pattern = quotemeta $subject;
        my $find = quotemeta "\\($number\\\/$count\\)";
        my $replace = "\\(\\d+\\\/$count\\)";

        $pattern =~ s/$find/$replace/g;

        $test ||= $pattern;

        if ($subject =~ /$test/) {
            push @$articles, [$article, $subject, $posted];
        } else {
            create_binary($dbh, $articles);

            $articles = [[$article, $subject, $posted]];
            $test = $pattern;
        }
    }

    create_binary($dbh, $articles);

    $dbh->rollback();
}

sub create_binary {
    my ($dbh, $articles) = @_;

    if (@$articles) {
        my $s = $articles->[0]->[1];

        my ($number, $count) = $s =~ /.*\((\d+)\/(\d+)\)/g;
        my $ac = scalar @$articles;

        $count ||= 0;

        if ($ac == $count) {
            insert_binary($dbh, $articles);
        } elsif ($count) {
            if ($ac > $count) {
                my %parts = ();

    #            print "$ac, $count -> $s\n";

                my @dedupe = ();

                for my $ref (@$articles) {
                    my $subject = $ref->[1];
                    my ($num, undef) = $subject =~ /.*\((\d+)\/(\d+)\)/g;
                    $num ||= 0;

                    #print STDERR "$number, $count\n";

                    next unless $num;
                    next if $num > $count;
                    next if $parts{$num};

                    $parts{$num} = 1;

                    push @dedupe, $ref;
                }

                if (scalar @dedupe == $count) {
                    insert_binary($dbh, \@dedupe);
                }
            }
        }
    }
}

sub insert_binary {
    my ($dbh, $articles) = @_;

    my $s = $articles->[0]->[1];

    my ($filename) = $s =~ /\"([^"]+)\"/g;
    $filename ||= $s;

    print STDERR $filename;
    my $ins = $dbh->prepare('INSERT INTO usenet_binary(name, posted) VALUES(?,?) RETURNING id');
    $ins->execute($filename, $articles->[0]->[2]);
    my ($binary_id) = $ins->fetchrow_array();
    $ins->finish();

    print STDERR " -> $binary_id\n";

    my $upd = $dbh->prepare('UPDATE usenet_article SET binary_id=? WHERE article=?');
    for my $ref (@$articles) {
        $upd->execute($binary_id, $ref->[0]);
    }
    $upd->finish();

    if ($opts{t}) {
        $dbh->rollback();
    } else {
        $dbh->commit();
    }
}

sub usage {
    print <<EOF;
Usage: $0
    [-c config file|etc/common.conf]
    [-t test mode]
EOF

    exit 1;
}
