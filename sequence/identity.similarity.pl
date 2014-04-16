#!/usr/bin/perl
# -d

use strict;
use warnings;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| = 1;

# paths di librerie personali
use lib $ENV{HOME};

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;

###################################################################
use Carp;

my $query = { 'header' => '', 'sequence' => '' };
my $target = { 'header' => '', 'sequence' => '' };
my $query_length;
my $target_length;
my $identity = 0E0;
my $similarity = 0E0;
my $insertion = 0E0;
my $deletion = 0E0;
my $coverage = 0E0;
my $BLOSUM62 = {
    'C' => { 'C' =>  9},
    'S' => { 'C' => -1, 'S' =>  4},
    'T' => { 'C' => -1, 'S' =>  1, 'T' =>  5},
    'P' => { 'C' => -3, 'S' => -1, 'T' => -1, 'P' =>  7},
    'A' => { 'C' =>  0, 'S' =>  1, 'T' =>  0, 'P' => -1, 'A' =>  4},
    'G' => { 'C' => -3, 'S' =>  0, 'T' => -2, 'P' => -2, 'A' =>  0, 'G' =>  6},
    'N' => { 'C' => -3, 'S' =>  1, 'T' =>  0, 'P' => -2, 'A' => -2, 'G' =>  0, 'N' =>  6},
    'D' => { 'C' => -3, 'S' =>  0, 'T' => -1, 'P' => -1, 'A' => -2, 'G' => -1, 'N' =>  1, 'D' => 6},
    'E' => { 'C' => -4, 'S' =>  0, 'T' => -1, 'P' => -1, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' =>  2, 'E' =>  5},
    'Q' => { 'C' => -3, 'S' =>  0, 'T' => -1, 'P' => -1, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' =>  0, 'E' =>  2, 'Q' =>  5},
    'H' => { 'C' => -3, 'S' => -1, 'T' => -2, 'P' => -2, 'A' => -2, 'G' => -2, 'N' =>  1, 'D' => -1, 'E' =>  0, 'Q' =>  0, 'H' =>  8},
    'R' => { 'C' => -3, 'S' => -1, 'T' => -1, 'P' => -2, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' => -2, 'E' =>  0, 'Q' =>  1, 'H' =>  0, 'R' =>  5},
    'K' => { 'C' => -3, 'S' =>  0, 'T' => -1, 'P' => -1, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' => -1, 'E' =>  1, 'Q' =>  1, 'H' => -1, 'R' =>  2, 'K' =>  5},
    'M' => { 'C' => -1, 'S' => -1, 'T' => -1, 'P' => -2, 'A' => -1, 'G' => -3, 'N' => -2, 'D' => -3, 'E' => -2, 'Q' =>  0, 'H' => -2, 'R' => -1, 'K' => -1, 'M' =>  5},
    'I' => { 'C' => -1, 'S' => -2, 'T' => -1, 'P' => -3, 'A' => -1, 'G' => -4, 'N' => -3, 'D' => -3, 'E' => -3, 'Q' => -3, 'H' => -3, 'R' => -3, 'K' => -3, 'M' =>  1, 'I' =>  4},
    'L' => { 'C' => -1, 'S' => -2, 'T' => -1, 'P' => -3, 'A' => -1, 'G' => -4, 'N' => -3, 'D' => -4, 'E' => -3, 'Q' => -2, 'H' => -3, 'R' => -2, 'K' => -2, 'M' =>  2, 'I' =>  2, 'L' =>  4},
    'V' => { 'C' => -1, 'S' => -2, 'T' =>  0, 'P' => -2, 'A' =>  0, 'G' => -3, 'N' => -3, 'D' => -3, 'E' => -2, 'Q' => -2, 'H' => -3, 'R' => -3, 'K' => -2, 'M' =>  1, 'I' =>  3, 'L' =>  1, 'V' =>  4},
    'F' => { 'C' => -2, 'S' => -2, 'T' => -2, 'P' => -4, 'A' => -2, 'G' => -3, 'N' => -3, 'D' => -3, 'E' => -3, 'Q' => -3, 'H' => -1, 'R' => -3, 'K' => -3, 'M' =>  0, 'I' =>  0, 'L' =>  0, 'V' => -1, 'F' => 6},
    'Y' => { 'C' => -2, 'S' => -2, 'T' => -2, 'P' => -3, 'A' => -2, 'G' => -3, 'N' => -2, 'D' => -3, 'E' => -2, 'Q' => -1, 'H' =>  2, 'R' => -2, 'K' => -2, 'M' => -1, 'I' => -1, 'L' => -1, 'V' => -1, 'F' => 3, 'Y' => 7 },
    'W' => { 'C' => -2, 'S' => -3, 'T' => -2, 'P' => -4, 'A' => -3, 'G' => -2, 'N' => -4, 'D' => -4, 'E' => -3, 'Q' => -2, 'H' => -2, 'R' => -3, 'K' => -3, 'M' => -1, 'I' => -3, 'L' => -2, 'V' => -3, 'F' => 1, 'Y' => 2, 'W' => 11},
};

USAGE: {
    print "\n*** identity.similarity ***\n\n";
    my $usage = <<END
SYNOPSYS

  $0 <alignment.fasta>

This script reads as input a fasta file obtained form a previous pairwise 
alignment. It return statistics such as identity, similarity, gaps...
END
    ;
    unless ($ARGV[0]) {
        print $usage;
        goto FINE;
    }
}

READFILE: {
    open(FASTA, "<$ARGV[0]") or croak "E- unable to open <$ARGV[0]>...\n\t";
    my $records;
    while (my $content = <FASTA>) {
        chomp $content;
        if ($content =~ /^>/) {
            $records++;
            if ($records == 1) {
                ($query->{'header'}) = $content =~ /^>(.*)$/;
            } elsif ($records == 2) {
                ($target->{'header'}) = $content =~ /^>(.*)$/;
            }
        } elsif ($content =~ /^[\w\-]*$/) {
            if ($records == 1) {
                $query->{'sequence'} .= $content;
            } elsif ($records == 2) {
                $target->{'sequence'} .= $content;
            }
        }
    }
    close FASTA;
    croak "E- aligned strings have different lengths\n\t"
        unless (length $query->{'sequence'} == length $target->{'sequence'});
}

CORE: {
    my @query = split(//, $query->{'sequence'});
    my @target = split(//, $target->{'sequence'});
    while (my $q = shift @query) {
        my $t = shift @target;
        unless ($q eq '-') {
            $q = uc $q;
            $query_length++;
        };
        unless ($t eq '-') {
            $t = uc $t;
            $target_length++;
        };
        if (($q eq '-') and ($t eq '-')) {
            next;
        } elsif ($t eq '-') {
            $insertion++;
            next;
        } elsif ($q eq '-') {
            $deletion++;
            next;
        } elsif ($q eq $t) {
            $coverage++;
            $identity++;
            next;
        } else {
            $coverage++;
            my $score;
            if (exists $BLOSUM62->{$q}->{$t}) {
                $score = $BLOSUM62->{$q}->{$t};
            } else {
                 $score = $BLOSUM62->{$t}->{$q};
            }
            $similarity++ if ($score > 0);
            next;
        }
    }
    $similarity += $identity;
}

RESULTS: {
    my @seqs = ($query_length, $target_length);
    my @align_length =  sort {$a <=> $b} @seqs;
    my $gaps = ($insertion + $deletion);
    my $identity_percent = sprintf("%.1f", ($identity/$align_length[0])*100);
    my $similarity_percent = sprintf("%.1f", ($similarity/$align_length[0])*100);
    my $coverage_percent = sprintf("%.1f", ($coverage/$query_length)*100);
    my $results = <<END
QUERY...: $query->{'header'} of $query_length residues
TARGET..: $target->{'header'} of $target_length residues

GAPS........: $gaps\t(INS $insertion - DEL $deletion)
COVERAGE....: $coverage_percent%\t($coverage residues)
IDENTITY....: $identity_percent%\t($identity residues)
SIMILARITY..: $similarity_percent%\t($similarity residues)
END
    ;
    print $results;
}

FINE: {
    print "\n*** ytiralimis.ytitnedi ***\n";
    exit;
}