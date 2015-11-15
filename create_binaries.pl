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
    my $config = $opts{c} || 'etc/common.conf';

    my $dbh = UsenetIndexer::GetDB($config);

    my $sth = $dbh->prepare('SELECT article,subject,posted FROM usenet_article WHERE binary_id IS NULL ORDER BY subject');
    $sth->execute();

    my $test = '';
    my $articles = [];
    while (my ($article, $subject, $posted) = $sth->fetchrow_array()) {
        (my $pattern = $subject) =~ s/\(\d+\/(\d+)\)//;

        $test ||= quotemeta $pattern;

        if ($subject =~ /$test/) {
            push @$articles, [$article, $subject, $posted];
        } else {
            if (@$articles) {
                my $s = $articles->[0]->[1];

                next unless $s;

                my ($number, $count) = $s =~ /\((\d+)\/(\d+)\)/g;
                my $ac = scalar @$articles;

                if (not defined $count) {
                    print STDERR $s, "\n";
                    next;
                }

                if ($ac == $count) {
                    my ($filename) = $s =~ /\"([^"]+)\"/g;
                    $filename ||= $s;

                    print STDERR $filename, "\n";
                    my $ins = $dbh->prepare('INSERT INTO usenet_binary(name, posted) VALUES(?,?) RETURNING id');
                    $ins->execute($filename, $articles->[0]->[2]);
                    my ($binary_id) = $ins->fetchrow_array();
                    $ins->finish();

                    my $upd = $dbh->prepare('UPDATE usenet_article SET binary_id=? WHERE article=?');
                    for my $ref (@$articles) {
                        $upd->execute($binary_id, $ref->[0]);
                    }
                    $upd->finish();

                    $dbh->commit();
                }
            }

            $articles = [[$article, $subject, $posted]];
            $test = undef;
        }
    }

    $dbh->rollback();
}

sub usage {
    print <<EOF;
Usage: $0
    [-c config file|etc/common.conf]
EOF

    exit 1;
}
