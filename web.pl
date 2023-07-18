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
    my $dbh = UsenetIndexer::GetDB($config);

    my $limit = param('limit') || 25;
    my $offset = param('offset') || 0;

    my $sth = $dbh->prepare('SELECT id,name,posted FROM usenet_binary ORDER BY posted desc,id DESC LIMIT ? OFFSET ?');
    $sth->execute($limit, $offset);

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

    return template "index.tt", {'usenet_history' => \@history, limit => $limit, offset => $offset};
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

