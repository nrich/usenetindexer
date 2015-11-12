#!/usr/bin/perl 

package UsenetIndexer;

use strict;
use warnings;

use DBI qw//;
use Net::NNTP qw//;
use Config::Tiny qw//;

sub GetNNTP {
    my ($configfile) = @_;

    my $cfg = Config::Tiny->read($configfile);

    my $nntp = Net::NNTP->new(
        $cfg->{NNTP}->{server}, 
        Port => $cfg->{NNTP}->{port}, 
        SSL => $cfg->{NNTP}->{ssl}, 
        Debug => $cfg->{NNTP}->{debug}, 
        Timeout => $cfg->{NNTP}->{timeout},
    );

    $nntp->authinfo($cfg->{NNTP}->{username}, $cfg->{NNTP}->{password});

    return $nntp;
}

sub GetDB {
    my ($configfile, %extra) = @_;

    my $cfg = Config::Tiny->read($configfile);

    my $dbh = DBI->connect(
        "DBI:Pg:dbname=$cfg->{Database}->{name};host=$cfg->{Database}->{host};port=$cfg->{Database}->{port}",
        $cfg->{Database}->{username},
        $cfg->{Database}->{password},
        {   
            AutoCommit => $extra{AutoCommit}||0,
            RaiseError => $extra{RaiseError}||0,
        }
    );

    return $dbh;
}

sub GetNewsGroupID {
    my ($dbh, $newsgroup) = @_;

    my $sth = $dbh->prepare('SELECT id FROM usenet_newsgroup WHERE name=?');
    $sth->execute($newsgroup);
    my ($id) = $sth->fetchrow_array();
    $sth->finish();

    return $id;
}

sub GetNewsGroupName {
    my ($dbh, $newsgroup_id) = @_;

    my $sth = $dbh->prepare('SELECT name FROM usenet_newsgroup WHERE id=?');
    $sth->execute($newsgroup_id);
    my ($name) = $sth->fetchrow_array();
    $sth->finish();

    return $name;
}


sub GetArticle {
    my ($nntp, $article_id) = @_;

    my $lines = $nntp->head($article_id);


    my $subject = '';
    my $message = '';
    my $posted = '';

    for my $line (@$lines) {
        chomp $line;

        if ($line =~ /Message-ID: <([^<>]+)>/) {
            $message = $1;
        } elsif ($line =~ /Subject: ([^\r]+)/) {
            $subject = $1;
        } elsif ($line =~ /Date: (.+)/) {
            $posted = $1;
        }
    }
 
    return {
        article => $article_id,
        message => $message,
        subject => $subject,
        posted => $posted,
    };
}

1;
