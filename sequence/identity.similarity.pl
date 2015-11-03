#!/usr/bin/perl

# CHANGELOG
#
# release 15.10.a                - support for different BLOSUM matrices
#                                - new output file
#
# release 15.4.a                 - initial release


use strict;
use warnings;
use Carp;

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

our $infile;
our $inquery = { 'header' => '', 'sequence' => '' };
our $intarget = { 'header' => '', 'sequence' => '' };
our $automatrix = 'auto';
our $BLOSUM45 = {
    'C' => { 'C' => 12},
    'S' => { 'C' => -1, 'S' =>  4},
    'T' => { 'C' => -1, 'S' =>  2, 'T' =>  5},
    'P' => { 'C' => -4, 'S' => -1, 'T' => -1, 'P' =>  9},
    'A' => { 'C' => -1, 'S' =>  1, 'T' =>  0, 'P' => -1, 'A' =>  5},
    'G' => { 'C' => -3, 'S' =>  0, 'T' => -2, 'P' => -2, 'A' =>  0, 'G' =>  7},
    'N' => { 'C' => -2, 'S' =>  1, 'T' =>  0, 'P' => -2, 'A' => -1, 'G' =>  0, 'N' =>  6},
    'D' => { 'C' => -3, 'S' =>  0, 'T' => -1, 'P' => -1, 'A' => -2, 'G' => -1, 'N' =>  2, 'D' =>  7},
    'E' => { 'C' => -3, 'S' =>  0, 'T' => -1, 'P' =>  0, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' =>  2, 'E' =>  6},
    'Q' => { 'C' => -3, 'S' =>  0, 'T' => -1, 'P' => -1, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' =>  0, 'E' =>  2, 'Q' =>  6},
    'H' => { 'C' => -3, 'S' => -1, 'T' => -2, 'P' => -2, 'A' => -2, 'G' => -2, 'N' =>  1, 'D' =>  0, 'E' =>  0, 'Q' =>  1, 'H' => 10},
    'R' => { 'C' => -3, 'S' => -1, 'T' => -1, 'P' => -2, 'A' => -2, 'G' => -2, 'N' =>  0, 'D' => -1, 'E' =>  0, 'Q' =>  1, 'H' =>  0, 'R' =>  7},
    'K' => { 'C' => -3, 'S' => -1, 'T' => -1, 'P' => -1, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' =>  0, 'E' =>  1, 'Q' =>  1, 'H' => -1, 'R' =>  3, 'K' =>  5},
    'M' => { 'C' => -2, 'S' => -2, 'T' => -1, 'P' => -2, 'A' => -1, 'G' => -2, 'N' => -2, 'D' => -3, 'E' => -2, 'Q' =>  0, 'H' =>  0, 'R' => -1, 'K' => -1, 'M' =>  6},
    'I' => { 'C' => -3, 'S' => -2, 'T' => -1, 'P' => -2, 'A' => -1, 'G' => -4, 'N' => -2, 'D' => -4, 'E' => -3, 'Q' => -2, 'H' => -3, 'R' => -3, 'K' => -3, 'M' =>  2, 'I' =>  5},
    'L' => { 'C' => -2, 'S' => -3, 'T' => -1, 'P' => -3, 'A' => -1, 'G' => -3, 'N' => -3, 'D' => -3, 'E' => -2, 'Q' => -2, 'H' => -2, 'R' => -2, 'K' => -3, 'M' =>  2, 'I' =>  2, 'L' =>  5},
    'V' => { 'C' => -1, 'S' => -1, 'T' =>  0, 'P' => -3, 'A' =>  0, 'G' => -3, 'N' => -3, 'D' => -3, 'E' => -3, 'Q' => -3, 'H' => -3, 'R' => -2, 'K' => -2, 'M' =>  1, 'I' =>  3, 'L' =>  1, 'V' =>  5},
    'F' => { 'C' => -2, 'S' => -2, 'T' => -1, 'P' => -3, 'A' => -2, 'G' => -3, 'N' => -2, 'D' => -4, 'E' => -3, 'Q' => -4, 'H' => -2, 'R' => -2, 'K' => -3, 'M' =>  0, 'I' =>  0, 'L' =>  1, 'V' =>  0, 'F' => 8},
    'Y' => { 'C' => -3, 'S' => -2, 'T' => -1, 'P' => -3, 'A' => -2, 'G' => -3, 'N' => -2, 'D' => -2, 'E' => -2, 'Q' => -1, 'H' =>  2, 'R' => -1, 'K' => -1, 'M' =>  0, 'I' =>  0, 'L' =>  0, 'V' => -1, 'F' => 3, 'Y' =>  8},
    'W' => { 'C' => -5, 'S' => -4, 'T' => -3, 'P' => -3, 'A' => -2, 'G' => -2, 'N' => -4, 'D' => -4, 'E' => -3, 'Q' => -2, 'H' => -3, 'R' => -2, 'K' => -2, 'M' => -2, 'I' => -2, 'L' => -2, 'V' => -3, 'F' => 1, 'Y' =>  3, 'W' => 15},
};
our $BLOSUM62 = {
    'C' => { 'C' =>  9},
    'S' => { 'C' => -1, 'S' =>  4},
    'T' => { 'C' => -1, 'S' =>  1, 'T' =>  5},
    'P' => { 'C' => -3, 'S' => -1, 'T' => -1, 'P' =>  7},
    'A' => { 'C' =>  0, 'S' =>  1, 'T' =>  0, 'P' => -1, 'A' =>  4},
    'G' => { 'C' => -3, 'S' =>  0, 'T' => -2, 'P' => -2, 'A' =>  0, 'G' =>  6},
    'N' => { 'C' => -3, 'S' =>  1, 'T' =>  0, 'P' => -2, 'A' => -2, 'G' =>  0, 'N' =>  6},
    'D' => { 'C' => -3, 'S' =>  0, 'T' => -1, 'P' => -1, 'A' => -2, 'G' => -1, 'N' =>  1, 'D' =>  6},
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
    'Y' => { 'C' => -2, 'S' => -2, 'T' => -2, 'P' => -3, 'A' => -2, 'G' => -3, 'N' => -2, 'D' => -3, 'E' => -2, 'Q' => -1, 'H' =>  2, 'R' => -2, 'K' => -2, 'M' => -1, 'I' => -1, 'L' => -1, 'V' => -1, 'F' => 3, 'Y' =>  7},
    'W' => { 'C' => -2, 'S' => -3, 'T' => -2, 'P' => -4, 'A' => -3, 'G' => -2, 'N' => -4, 'D' => -4, 'E' => -3, 'Q' => -2, 'H' => -2, 'R' => -3, 'K' => -3, 'M' => -1, 'I' => -3, 'L' => -2, 'V' => -3, 'F' => 1, 'Y' =>  2, 'W' => 11},
};
our $BLOSUM80 = {
    'C' => { 'C' =>  9},
    'S' => { 'C' => -2, 'S' =>  5},
    'T' => { 'C' => -1, 'S' =>  1, 'T' =>  5},
    'P' => { 'C' => -4, 'S' => -1, 'T' => -2, 'P' =>  8},
    'A' => { 'C' => -1, 'S' =>  1, 'T' =>  0, 'P' => -1, 'A' =>  5},
    'G' => { 'C' => -4, 'S' => -1, 'T' => -2, 'P' => -3, 'A' =>  0, 'G' =>  6},
    'N' => { 'C' => -3, 'S' =>  0, 'T' =>  0, 'P' => -3, 'A' => -2, 'G' => -1, 'N' =>  6},
    'D' => { 'C' => -4, 'S' => -1, 'T' => -1, 'P' => -2, 'A' => -2, 'G' => -2, 'N' =>  1, 'D' =>  6},
    'E' => { 'C' => -5, 'S' =>  0, 'T' => -1, 'P' => -2, 'A' => -1, 'G' => -3, 'N' => -1, 'D' =>  1, 'E' =>  6},
    'Q' => { 'C' => -4, 'S' =>  0, 'T' => -1, 'P' => -2, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' => -1, 'E' =>  2, 'Q' =>  6},
    'H' => { 'C' => -4, 'S' => -1, 'T' => -2, 'P' => -3, 'A' => -2, 'G' => -3, 'N' =>  0, 'D' => -2, 'E' =>  0, 'Q' =>  1, 'H' =>  8},
    'R' => { 'C' => -4, 'S' => -1, 'T' => -1, 'P' => -2, 'A' => -2, 'G' => -3, 'N' => -1, 'D' => -2, 'E' => -1, 'Q' =>  1, 'H' =>  0, 'R' =>  6},
    'K' => { 'C' => -4, 'S' => -1, 'T' => -1, 'P' => -1, 'A' => -1, 'G' => -2, 'N' =>  0, 'D' => -1, 'E' =>  1, 'Q' =>  1, 'H' => -1, 'R' =>  2, 'K' =>  5},
    'M' => { 'C' => -2, 'S' => -2, 'T' => -1, 'P' => -3, 'A' => -1, 'G' => -4, 'N' => -3, 'D' => -4, 'E' => -2, 'Q' =>  0, 'H' => -2, 'R' => -2, 'K' => -2, 'M' =>  6},
    'I' => { 'C' => -2, 'S' => -3, 'T' => -1, 'P' => -4, 'A' => -2, 'G' => -5, 'N' => -4, 'D' => -4, 'E' => -4, 'Q' => -3, 'H' => -4, 'R' => -3, 'K' => -3, 'M' =>  1, 'I' =>  5},
    'L' => { 'C' => -2, 'S' => -3, 'T' => -2, 'P' => -3, 'A' => -2, 'G' => -4, 'N' => -4, 'D' => -5, 'E' => -4, 'Q' => -3, 'H' => -3, 'R' => -3, 'K' => -3, 'M' =>  2, 'I' =>  1, 'L' =>  4},
    'V' => { 'C' => -1, 'S' => -2, 'T' =>  0, 'P' => -3, 'A' =>  0, 'G' => -4, 'N' => -4, 'D' => -4, 'E' => -3, 'Q' => -4, 'H' => -4, 'R' => -3, 'K' => -3, 'M' =>  1, 'I' =>  3, 'L' =>  1, 'V' =>  4},
    'F' => { 'C' => -3, 'S' => -3, 'T' => -2, 'P' => -4, 'A' => -3, 'G' => -4, 'N' => -4, 'D' => -4, 'E' => -4, 'Q' => -4, 'H' => -2, 'R' => -4, 'K' => -4, 'M' =>  0, 'I' => -1, 'L' =>  0, 'V' => -1, 'F' => 6},
    'Y' => { 'C' => -3, 'S' => -2, 'T' => -2, 'P' => -4, 'A' => -2, 'G' => -4, 'N' => -3, 'D' => -4, 'E' => -3, 'Q' =>  2, 'H' =>  2, 'R' => -3, 'K' => -3, 'M' => -2, 'I' => -2, 'L' => -2, 'V' => -2, 'F' => 3, 'Y' => 7},
    'W' => { 'C' => -3, 'S' => -4, 'T' => -4, 'P' => -5, 'A' => -3, 'G' => -4, 'N' => -4, 'D' => -6, 'E' => -4, 'Q' => -3, 'H' => -3, 'R' => -4, 'K' => -4, 'M' => -2, 'I' => -3, 'L' => -2, 'V' => -3, 'F' => 0, 'Y' => 2, 'W' => 11},
};


INIT: {
    use Getopt::Long;no warnings;
    GetOptions('m=s' => \$automatrix);
    my $splash = <<ROGER
********************************************************************************
identity.similarity.pl
release 15.10.a

Copyright (c) 2015, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
ROGER
    ;
    print $splash;
    my $usage = <<ROGER
This script reads as input a fasta file obtained form a previous pairwise 
alignment. It return a consensus string and statistics such as identity, 
similarity, gaps...

SYNOPSYS

  \$ identity.similarity.pl [-m BLOSUM80] <alignment.fasta>

OPTIONS
    
    -m <string>    specify a specific substitution matrix, by default it 
                   automatically selects the optimal one; the avaliable matrices 
                   are BLOSUM45, BLOSUM62 and BLOSUM80
ROGER
    ;
    unless ($ARGV[0]) {
        print $usage;
        goto FINE;
    }
}

READFILE: {
    $infile = $ARGV[0];
    croak "E- <$infile> not a FASTA file...\n\t"
        unless ($infile =~ /\.(fas|fasta)$/);
    
    open(FASTA, "<$infile") or croak "E- unable to open <$infile>...\n\t";
    my $records;
    while (my $content = <FASTA>) {
        chomp $content;
        if ($content =~ /^>/) {
            $records++;
            if ($records == 1) {
                ($inquery->{'header'}) = $content =~ /^>(.*)$/;
            } elsif ($records == 2) {
                ($intarget->{'header'}) = $content =~ /^>(.*)$/;
            }
        } elsif ($content =~ /^[\w\-]*$/) {
            if ($records == 1) {
                $inquery->{'sequence'} .= $content;
            } elsif ($records == 2) {
                $intarget->{'sequence'} .= $content;
            }
        }
    }
    close FASTA;
    croak "E- aligned strings have different lengths\n\t"
        unless (length $inquery->{'sequence'} == length $intarget->{'sequence'});
}

CORE: {
    # rimuovo eventuali gaps in comune e metto tutti i residui in uppercase
    my @input_query = split(//, $inquery->{'sequence'});
    my @input_target = split(//, $intarget->{'sequence'});
    my @query;
    my @target;
    while (my $q = shift @input_query) {
        my $t = shift @input_target;
        if (($q eq '-') && ($t eq '-')) {
            next;
        } else {
            $q = uc $q;
            push(@query, $q);
            $t = uc $t;
            push(@target, $t);
        }
    }
    
    # calcolo l'identità
    my $query_length = 0E0;
    my $target_length  = 0E0;
    my $identity = 0E0;
    for (my $i = 0; $i < scalar @query; $i++) {
        $query_length++ unless ($query[$i] eq '-');
        $target_length++ unless ($target[$i] eq '-');
        $identity++ if ($query[$i] eq $target[$i]);
    }
    my @seqs = ($query_length, $target_length);
    my @ali_length = sort {$a <=> $b} @seqs;
    $identity = sprintf("%.2f", ($identity / $ali_length[0]) * 100);
    
    # scelgo la matrice di sostituzione ottimale
    my $submatrix;
    my $whichmatrix;
    if ($automatrix eq 'BLOSUM45') {
        $submatrix = $BLOSUM45;
        $whichmatrix = 'BLOSUM45';
    } elsif ($automatrix eq 'BLOSUM62') {
        $submatrix = $BLOSUM62;
        $whichmatrix = 'BLOSUM62'
    } elsif ($automatrix eq 'BLOSUM80') {
        $submatrix = $BLOSUM80;
        $whichmatrix = 'BLOSUM80'
    } elsif ($automatrix eq 'auto') {
        if ($identity >= 80) {
            $submatrix = $BLOSUM80;
            $whichmatrix = 'BLOSUM80';
        } elsif ($identity <= 45) {
            $submatrix = $BLOSUM45;
            $whichmatrix = 'BLOSUM45';
        } else {
            if ($identity > 62) {
                my $diff80 = 80 - $identity;
                my $diff62 = $identity - 62;
                if ($diff80 > $diff62) {
                    $submatrix = $BLOSUM62;
                    $whichmatrix = 'BLOSUM62';
                } else {
                    $submatrix = $BLOSUM80;
                    $whichmatrix = 'BLOSUM80';
                }
            } else {
                my $diff62 = 62 - $identity;
                my $diff45 = $identity - 45;
                if ($diff62 > $diff45) {
                    $submatrix = $BLOSUM45;
                    $whichmatrix = 'BLOSUM45';
                } else {
                    $submatrix = $BLOSUM62;
                    $whichmatrix = 'BLOSUM62';
                }
            }
        }
    } else {
        croak "E- matrix [$automatrix] unknown\n\t";
    }
    
    # calcolo la similarità e annoto gli score per residuo della matrice scelta
    my $similarity = 0E0;
    my $insertion = 0E0;
    my $deletion = 0E0;
    my $coverage = 0E0;
    my $consensus_string = '';
    my @scores;
    for (my $i = 0; $i < scalar @query; $i++) {
        if ($target[$i] eq '-') {
            push(@scores, 'null');
            $insertion++;
            $consensus_string .= ' ';
            next;
        } elsif ($query[$i] eq '-') {
            $deletion++;
            $consensus_string .= ' ';
            next;
        } else {
            $coverage++;
            my $score;
            if (exists $submatrix->{$query[$i]}->{$target[$i]}) {
                $score = $submatrix->{$query[$i]}->{$target[$i]};
            } else {
                $score = $submatrix->{$target[$i]}->{$query[$i]};
            }
            push(@scores, $score);
            
            # notazione dei simboli consensus
            if ($target[$i] eq $query[$i]) {
                $similarity++;
                $consensus_string .= '*';
            } elsif ($score == 1) {
                $similarity++;
                $consensus_string .= '.';
            } elsif ($score > 1) {
                $similarity++;
                $consensus_string .= ':';
            } else {
                $consensus_string .= ' ';
            }
        }
    }
    $similarity = sprintf("%.2f", ($similarity / $ali_length[0]) * 100);
    $coverage = sprintf("%.2f", ($coverage / $query_length) * 100);
    
    # scrivo i risultati su file
    my $output = <<ROGER
>QUERY...: $inquery->{'header'} of $query_length residues
ROGER
    ;
    $output .= sprintf("%s\n%s\n%s\n", join('',@query), $consensus_string, join('',@target));
    $output .= <<ROGER
>TARGET..: $intarget->{'header'} of $target_length residues

MATRIX......: $whichmatrix
GAPS........: INS $insertion - DEL $deletion
COVERAGE....: $coverage%
IDENTITY....: $identity%
SIMILARITY..: $similarity%

QUERY SCORES:
ROGER
    ;
    while (my $res = shift @query) {
        next if ($res eq '-');
        my $value = shift @scores;
        $output .= "$res;$value\n";
    }
    my ($outfile) = $infile =~ /(.+)\.(fas|fasta)$/;
    $outfile .= '.identity.similarity.out';
    open(OUT, ">$outfile") or croak "E- unable to open <$outfile>...\n\t";
    print OUT $output;
    close OUT;
    print "\n[$outfile] written\n";
}

FINE: {
    print "\n*** ytiralimis.ytitnedi ***\n";
    exit;
}