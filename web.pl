#!/usr/bin/perl

use strict;
use warnings;

use Dancer;
use Dancer::Cookies;

use Getopt::Std qw/getopts/;
use lib qw(lib);
use UsenetIndexer qw//;

set template => 'template_toolkit';

set show_errors => 1;
set server => '127.0.0.1';
set port => 8088;

my %opts = ();

get '/' => sub {
    my $config = $ENV{CONFIG} || $opts{c} || 'etc/common.conf';
    my $filter_file = $ENV{FILTER} || $opts{f} || 'etc/filter.txt';
    my $dbh = UsenetIndexer::GetDB($config);

    my $limit = param('limit') || 25;
    my $offset = param('offset') || 0;

    my @filter_terms = ();

    if (-f $filter_file) {
        open my $fh, '<', $filter_file;

        if ($fh) {
            while (my $filter_term = <$fh>) {
                chomp $filter_term;

                next unless $filter_term;

                push @filter_terms, $filter_term;
            }
        } else {
            warn "Could not open `$filter_file': $!\n";
        }
    }

    my $filter = '""';
    if (@filter_terms) {
        $filter = join '|', @filter_terms;
    }

    my $sth = $dbh->prepare("SELECT id,name,posted FROM usenet_binary WHERE name !~* ? ORDER BY posted desc,id DESC LIMIT ? OFFSET ?");
    $sth->execute($filter, $limit, $offset);

    my $host = request->header('Host');

    my @history = ();
    while (my ($id, $name, $posted) = $sth->fetchrow_array()) {
        push @history, {
            title => $name,
            link => "https://$host/nzb?id=$id",
            posted => $posted,
        };
    }
    $sth->finish();

    $dbh->disconnect();

    return template "index.tt", {'usenet_history' => \@history, limit => $limit, offset => $offset, search => ''};
};

post '/' => sub {
    my $config = $ENV{CONFIG} || $opts{c} || 'etc/common.conf';
    my $dbh = UsenetIndexer::GetDB($config);

    my $search = param('search') || '';

    die "No search provided" unless $search;

    my $sth = $dbh->prepare("SELECT id,name,posted FROM usenet_binary WHERE to_tsvector('english', name) @@ plainto_tsquery(?)");
    $sth->execute($search);

    my $host = request->header('Host');

    my @history = ();
    while (my ($id, $name, $posted) = $sth->fetchrow_array()) {
        push @history, {
            title => $name,
            link => "https://$host/nzb?id=$id",
            posted => $posted,
        };
    }
    $sth->finish();

    $dbh->disconnect();

    return template "index.tt", {'usenet_history' => \@history, limit => 0, offset => 0, search => $search};
};

get '/nzb' => sub {
    my $id = param 'id';

    my $config = $ENV{CONFIG} || $opts{c} || 'etc/common.conf';
    my $dbh = UsenetIndexer::GetDB($config);

    my ($content, $filename) = UsenetIndexer::BuildNZB($dbh, $id);
    $filename =~ s/\.[^.]+?$//;

    $dbh->disconnect();

    headers 'Content-type' => 'application/xml', 'Content-Disposition' => "Attachment; filename=\"$filename.nzb\"";
    return $content;
};


getopts('c', \%opts);
main(@ARGV);

sub main {
    dance();
}

