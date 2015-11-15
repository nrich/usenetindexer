#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Std qw/getopts/;
use HTTP::Daemon qw//;
use Data::Dumper qw/Dumper/;
use XML::RSS qw//;

use lib qw(lib);
use UsenetIndexer qw//;

my %CHILDREN = ();

my %GET = ();
my %POST = ();

sub get {
    my ($url, $handler) = @_;

    $GET{$url} = sub {
        my ($request) = @_;

        my $host = $request->header('Host');
        print STDERR Dumper $request->headers();

        print STDERR $host, "\n";
        print STDERR $request->as_string(), "\n";

        my %params = $request->uri()->query_form();

        local %ENV = (HOST => $host);
        $handler->(\%params);
    };
}

my %opts = ();
getopts('hc:', \%opts);
$opts{h} and usage();

get '/' => sub {
    my ($params) = @_;

    return <<HTML;
<html>
    <form action="/search">
        <input type="text" name="search">
        <button>Search</button>
    </form>
</html>
HTML
};

get '/search' => sub {
    my ($params) = @_;

    my $query = $params->{search};

    $query =~ s/ /&/g;

    my $config = $opts{c} || 'etc/common.conf';
    my $dbh = UsenetIndexer::GetDB($config);

    my $sth = $dbh->prepare('SELECT id,name FROM usenet_binary WHERE name @@ to_tsquery(?)');
    $sth->execute($query);

    my $content = [];
    while (my ($id, $name) = $sth->fetchrow_array()) {
        push @$content, [$id, $name];
    }
    $sth->finish();

    $dbh->disconnect();

    my $rss = XML::RSS->new(version => '1.0');
    $rss->channel(
        title        => "",
        link         => "/search?title=?$query",
        description  => "Search results",
    );

    for my $file (@$content) {
        $rss->add_item(
            title => $file->[1],
            link => "http://$ENV{HOST}/nzb?id=$file->[0]",
        );
    } 

    return $rss->as_string(), type => 'application/rss+xml;';
};

get '/latest' => sub {
    my ($params) = @_;

    my $limit = $params->{limit}||25;

    my $config = $opts{c} || 'etc/common.conf';
    my $dbh = UsenetIndexer::GetDB($config);

    my $sth = $dbh->prepare('SELECT id,name FROM usenet_binary ORDER BY posted DESC limit ?');
    $sth->execute($limit);

    my $content = [];
    while (my ($id, $name) = $sth->fetchrow_array()) {
        push @$content, [$id, $name];
    }
    $sth->finish();

    $dbh->disconnect();

    my $rss = XML::RSS->new(version => '1.0');
    $rss->channel(
        title        => "",
        link         => "/latest?limit=?$limit",
        description  => "Latest",
    );

    for my $file (@$content) {
        $rss->add_item(
            title => $file->[1],
            link => "http://$ENV{HOST}/nzb?id=$file->[0]",
        );
    } 

    return $rss->as_string(), type => 'application/rss+xml;';
};


get '/nzb' => sub {
    my ($params) = @_;

    my $id = $params->{id};

    my $config = $opts{c} || 'etc/common.conf';
    my $dbh = UsenetIndexer::GetDB($config);

    my ($content,$filename) = UsenetIndexer::BuildNZB($dbh, $id);
    $filename =~ s/\..+$//;

    $dbh->disconnect();

    return $content, type => 'application/xml', filename => "$filename.nzb";
};


main(@ARGV);

sub main {
    my $config = $opts{c} || 'etc/common.conf';

    my $cfg = Config::Tiny->read($config);

    my $daemon = HTTP::Daemon->new(
        LocalPort => $cfg->{Web}->{port},
        LocalAddr => $cfg->{Web}->{address},
        Reuse => 1,
        Timeout => 300,
    ) or die "Could not create HTTP listener: $!";

    while (1) {
        while (keys %CHILDREN < 4) {
            spawn_child($daemon);
        }

        sleep 1;

        foreach my $child (keys %CHILDREN) {
            unless (kill 0 => $child) {
                say("Child $child has died");
                delete $CHILDREN{$child};
            }
        }

        sleep 1;
    }
}


sub spawn_child {
    my ($daemon) = @_;

    my $pid = fork();

    if ($pid) {
        $CHILDREN{$pid} = 1;
    } elsif (defined $pid) {
        my $requests = 0;
        while (++$requests < 10) {
            my $connection = $daemon->accept() or last;
            $connection->autoflush(1);

            my $request = $connection->get_request() or last;
            
            if ($request->method() eq 'GET') {
                print STDERR $request->url()->path(), "\n";

                my $handler = $GET{$request->url()->path()};

                if ($handler) {
                    eval {
                        my ($content, %res) = $handler->($request);
                        
                        print STDERR Dumper \%res;

                        my $response = HTTP::Response->new(200);

                        $response->content($content);
                        $response->header('Content-Type' => $res{type} ||'text/html');

                        if (my $filename = $res{filename}) {
                            $response->header('Content-Disposition' => "Attachment; filename=\"$filename\"");
                        }

                        $connection->send_response($response);
                        $connection->close();
                    };

                    if (my $error = $@) {
                        chomp $error;
                        $connection->send_error(500, $error);
                        $connection->close();
                    }
                } else {
                    $connection->send_error(404) unless $handler; 
                }
            } elsif ($request->method eq 'POST') { 

            } else {
                $connection->send_error(400);
                $connection->close();
            }
        }


        exit 0;
    } else {
        die "Spawn child failed: $!\n";
    }
}

sub usage {
    print <<EOF;
Usage: $0
    [-c config file|etc/common.conf]
EOF

    exit 1;
}

