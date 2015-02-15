#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.02.a    - initial release
#
# ##############################################################################

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
use Cwd;
use Carp;
use Statistics::Descriptive;
use Text::CSV;
use List::Util qw(shuffle);
use threads;
use threads::shared;
use Thread::Semaphore;

## FLAGS ##

our $RANDPER = 10000; # number of random permutations
our $THREADS = 8; # number of threads

## SGALF ##

## GLOBS ##

our @thr;
our @shuffling_data;
our @rand_logRP_flat :shared;

## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    my $help;
    GetOptions('help|h' => \$help, 'permut|p=i' => \$RANDPER, 'threads|t=i' => \$THREADS);
    my $header = <<ROGER
********************************************************************************
RankPride
release 15.02.a

Copyright (c) 2015, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
ROGER
    ;
    print $header;
    
    if ($help) {
        my $spiega = <<ROGER

This Perl script performs a two sample Rank Product analysis according to the 
method proposed in [Koziol, FEBS letters, 2010, 584: 4481-4484].

*** SYNOPSYS ***

    \$ RankPride.pl <datasetA.csv> <datasetB.csv>


*** INPUT FILES ***

Input files are two csv files that define the query and the reference datasets, 
respectively. Each input file must have the following format:

    probe1;probe2;probe3;[...]
    -0.593;-5.697;-4.096;[...]
    -1.428;-3.223;-3.314;[...]
    -0.551;-3.234;-2.909;[...]
    [...]

The columns define the values measured for a specific probe. The first row is a 
header line containing the probe names, the remaining rows are the replicated 
measurements (ie samples). Missing values must be filled with a 'NA' string.

*** OPTIONS ***
    -permut|p <int>     Number of random permutations (default: $RANDPER)
    
    -threads|t <int>    Number of concurrent threads used for calculations 
                        (default: $THREADS)

*** OUTPUT ***

The script produces a csv file called <rankprod.csv> with a content like this:

    PROBE;LOG(RP);Evalue
    R0199;2.1150e-01;3.0000e-04
    R0200;8.5183e-02;1.9720e-01
    R0195;-1.5304e-01;1.5500e-02
    R0117;-4.7448e-02;4.8240e-01
    [...]

The "PROBE" column indicate the probe names.

The "LOG(RP)" column is the rank product score. For each probe, the more 
positive score defines a more positive delta between values of datasetA 
versus datasetB. Viceversa, the more negative score defines a more negative 
delta between values of datasetA versus datasetB.

The "Evalue" column indicates how much significant is the rank product score, 
based on an amount of random permutations of input data (defined with option -p).
ROGER
        ;
        print $spiega;
        goto FINE;
    }
}

CHECKIN: {
    unless ($ARGV[0] && $ARGV[1]){
        my $spiega = <<ROGER

*** SYNOPSYS ***

    \$ RankPride.pl <datasetA.csv> <datasetB.csv>
ROGER
        ;
        print $spiega;
        goto FINE;
    }
    
    # verifico che i file di input abbiano le stesse probes
    my @headers;
    for my $i (0..1) {
        open(CSV, '<' . $ARGV[$i]);
        $headers[$i] = <CSV>;
        close CSV;
    }
    unless ($headers[0] eq $headers[1]) {
        croak "\nE- Probe names are different (or sorted in different fashion) between input files\n\t";
    }
}

MAINSTREAM: {
    # recupero i nomi delle probes
    open(CSV, '<' . $ARGV[0]);
    my $newline = <CSV>;
    chomp $newline;
    my @probe_names = split(/[;,]/, $newline);
    close CSV;
    
    # importo i dati grezzi dai file di input
    my $raw_data = { };
    my @values_range = (0,0);
    for my $i (0..1) {
        # inizializzo l'hash
        $raw_data->{$ARGV[$i]} = { };
        for my $j (@probe_names) {
            $raw_data->{$ARGV[$i]}->{$j} = [ ];
        }
        
        # riempio l'hash
        open(CSV, '<' . $ARGV[$i]);
        $newline = <CSV>; # rimuovo l'header
        while ($newline = <CSV>) {
            chomp $newline;
            my @values = split(/[;,]/, $newline);
            for my $j (0..(scalar @values)-1) {
                push(@{$raw_data->{$ARGV[$i]}->{$probe_names[$j]}}, $values[$j]);
                unless ($values[$j] =~ /NA/) {
                    $values_range[0] = $values[$j] if ($values[$j] < $values_range[0]);
                    $values_range[1] = $values[$j] if ($values[$j] > $values_range[1]);
                }
            }
        }
        close CSV;
    }
    
    # riscalo i valori su un range che va da 1 a 2
    my $range = abs($values_range[1]-$values_range[0]);
    my $scaled_data = [ ];
    for my $probe_name (@probe_names) {
        my @sample = (@{$raw_data->{$ARGV[0]}->{$probe_name}}, @{$raw_data->{$ARGV[1]}->{$probe_name}});
        for my $i (0..(scalar @sample)-1) {
            if ($sample[$i] =~ /NA/) {
                $sample[$i] = 1;
            } else {
                $sample[$i] = (($sample[$i]-$values_range[0])/$range)+1;
            }
            push(@shuffling_data, $sample[$i]);
        }
        push(@{$scaled_data}, [ @sample ]);
    }
    
    # la matrice di input ha struttura $scaled_data->[$probes][$samples]
    my $samples_from_A = scalar(@{$raw_data->{$ARGV[0]}->{$probe_names[0]}});
    my $samples_from_B = scalar(@{$raw_data->{$ARGV[1]}->{$probe_names[1]}});
    my $tot_probes = scalar @probe_names;
    my $tot_samples = $samples_from_A + $samples_from_B;

    # calcolo i valori di rank products
    my @logRP;
    foreach my $probe (0..$tot_probes-1) {
        my ($rp_A, $rp_B) = (1, 1);
        foreach my $sample (0..$samples_from_A-1) {
            $rp_A *= $scaled_data->[$probe][$sample];
        }
        $rp_A = $rp_A**(1/$samples_from_A);
        foreach my $sample ($samples_from_A..$tot_samples-1) {
            $rp_B *= $scaled_data->[$probe][$sample];
        }
        $rp_B = $rp_B**(1/$samples_from_B);
        my $diff = log($rp_A/$rp_B)/log(10);
        push(@logRP, $diff);
    }
    
    # permutazioni
    print "\nPerforming random permutations...";
    undef @thr;
    for (1..$THREADS) {
        push @thr, threads->new(\&rp_random, $tot_probes, $samples_from_A, $samples_from_B);
    }
    for (@thr) { 
        $_->join()
    }
    my $rand_logRP = [ ];
    for my $i (0..$RANDPER-1) {
        my @array = split(';', $rand_logRP_flat[$i]);
        push(@{$rand_logRP}, [ @array ]);
    }
    print "done\n";
    
    # statistiche
    print "\nCalculating Evalue...";
    my @evalues;
    foreach my $probe (0..$tot_probes-1) {
        my $x = 0;
        foreach my $run (0..$RANDPER-1) {
            my $reference = abs($logRP[$probe]);
            my $query = abs($rand_logRP->[$run][$probe]);
            $x++ if ($query >= $reference);
        }
        $evalues[$probe] = $x/$RANDPER;
    }
    print "done\n";
    
    # scrivo il file .csv
    open(CSV, '>' . 'rankprod.csv');
    print CSV "PROBE;LOG(RP);Evalue\n";
    foreach my $probe (0..$tot_probes-1) {
        my $logrp_format = sprintf("%.04e", $logRP[$probe]);
        $logrp_format =~ s/e\+/e/ if ($logrp_format =~ /e\+/);
        my $evalue_format = sprintf("%.04e", $evalues[$probe]);
        $evalue_format =~ s/e\+/e/ if ($evalue_format =~ /e\+/);
        my $string = sprintf("%s;%s;%s\n", $probe_names[$probe], $logrp_format, $evalue_format);
        print CSV $string;
    }
    close CSV;
}

FINE: {
    print "\n*** edirPknaR ***\n";
    exit;
}

sub rp_random {
    my ($probes, $samplesA, $samplesB) = @_;
    
    while (1) {
        my $how_many = scalar @rand_logRP_flat;
        if ($how_many >= $RANDPER) {
            last;
        } else {
            # mischio i valori rigenero una matrice casuale di input
            my @shuffled = shuffle @shuffling_data;
            my $data = [ ];
            for my $probe (0..$probes-1) {
                for my $sample (0..($samplesA+$samplesB)-1) {
                    $data->[$probe][$sample] = shift @shuffled;
                }
            }
            
            # calcolo i valori di rank products
            my $logRP;
            foreach my $probe (0..$probes-1) {
                my ($rp_A, $rp_B) = (1, 1);
                foreach my $sample (0..$samplesA-1) {
                    $rp_A *= $data->[$probe][$sample];
                }
                $rp_A = $rp_A**(1/$samplesA);
                foreach my $sample ($samplesA..($samplesA+$samplesB)-1) {
                    $rp_B *= $data->[$probe][$sample];
                }
                $rp_B = $rp_B**(1/$samplesB);
                my $diff = log($rp_A/$rp_B)/log(10);
                $logRP .= $diff . ';';
            }
            $logRP =~ s/;$//;
            
            {   # aggiorno l'array con i valori di logRP
                lock @rand_logRP_flat;
                push(@rand_logRP_flat, $logRP);
            }
        }
    }
}