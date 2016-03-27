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

    unless ($id) {
        my $ins = $dbh->prepare('INSERT INTO usenet_newsgroup(name) VALUES(?) RETURNING id');
        $ins->execute($newsgroup);
        ($id) = $ins->fetchrow_array();
    }

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

    return undef unless $lines;
    return undef unless @$lines;

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
            my $date = $1;

            $date =~ s/\s+(\d+)$/ +${1}/;;
            $posted = $date;
        }
    }
 
    return {
        article => $article_id,
        message => $message,
        subject => $subject,
        posted => $posted,
    };
}

sub BuildNZB {
    my ($dbh, $binary_id) = @_;

    my $newsgroup = '';
    
    my $number = 1;
    my $segments = '';

    my $sth = $dbh->prepare('SELECT newsgroup_id,message FROM usenet_article WHERE binary_id=? ORDER BY subject');
    $sth->execute($binary_id);

    while (my ($newsgroup_id, $message) = $sth->fetchrow_array()) {
        $newsgroup ||= GetNewsGroupName($dbh, $newsgroup_id);

        $segments .= "  <segment bytes=\"100\" number=\"$number\">$message</segment>\n";
        $number++;
    }

    chomp $segments;

    my $bin = $dbh->prepare('SELECT name,extract(epoch from posted) FROM usenet_binary WHERE id=?');
    $bin->execute($binary_id);
    my ($filename, $posted) = $bin->fetchrow_array();
    $bin->finish();

    my $subject = $filename;
    $subject =~ s/&/&amp;/g;
    $subject =~ s/</&lt;/g;
    $subject =~ s/>/&gt;/g;
    $subject =~ s/"/&quote;/g;
    $subject =~ s/'/&#39;/g;

    my $content = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE nzb PUBLIC "-//newzBin//DTD NZB 1.1//EN" "http://www.newzbin.com/DTD/nzb/nzb-1.1.dtd">
<nzb xmlns="http://www.newzbin.com/DTD/2003/nzb">

<file poster="nobody (nobody\@nowhere.com)" date="$posted" subject="$subject">
 <groups>
  <group>$newsgroup</group>
 </groups>
 <segments>
$segments
 </segments>
</file>
</nzb>
EOF

    return wantarray ? ($content, $filename) : $content;
}

1;
