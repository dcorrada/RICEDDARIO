#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.11.a       - initial release
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
use Carp;

our @matC;
our $contrast = 100; # livello di contrasto

USAGE: {
    my $splash = <<ROGER
********************************************************************************
merge.matrices
release 15.11.a

Copyright (c) 2015, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

ROGER
    ;
    print $splash;
    
    unless ($ARGV[0] and $ARGV[1]) {
        my $help = <<ROGER
This script takes as input two simmetrical matrices, in CSV format.

It returns a PNG image of the combined matrix in which the two input matrices 
are half represented in upper and lower trianglular sections, respectively.

SYNOPSIS
    
    \$ merge.matrices.pl <matrixA.csv> <matrixB.csv> [contrast]

[contrast] is a constant for rescaling the color ramp (default: $contrast)
ROGER
        ;
        print $help;
        goto FINE;
    }
}

INIT: {
    $contrast = $ARGV[2] if ($ARGV[2]);
    
    my @matA;
    my @matB;
    my $i;
    my @file_content;
    
    open(INFILE, '<' . $ARGV[0]);
    @file_content = <INFILE>;
    close INFILE;
    $i = 0;
    while (my $newline = shift @file_content) {
        chomp $newline;
        next unless $newline;
        my @record = split(';', $newline);
        $matA[$i] = [ @record ];
        $i++;
    }
    
    open(INFILE, '<' . $ARGV[1]);
    @file_content = <INFILE>;
    close INFILE;
    $i = 0;
    while (my $newline = shift @file_content) {
        chomp $newline;
        next unless $newline;
        my @record = split(';', $newline);
        $matB[$i] = [ @record ];
        $i++;
    }
    
    # faccio un check della dimensionalita' delle matrici in input
    my $dimA = sprintf("%d x %d", scalar @matA, scalar @{$matA[0]});
    my $dimB = sprintf("%d x %d", scalar @matB, scalar @{$matB[0]});
    croak "E- input matrices have different dimensions\n\t" 
        unless ($dimA eq $dimB);
    
    # inizializzo la matrice combinata
    for my $i (0 .. (scalar @matA)-1) {
        for my $j (0 .. (scalar @matA)-1) {
            if ($i > $j) {
                $matC[$i][$j] = $matA[$i][$j];
            } elsif ($i < $j) {
                $matC[$i][$j] = $matB[$i][$j];
            } else {
                $matC[$i][$j] = 0E0;
            }
        }
    }
}

GRAPHICS: {
    my $tot_res = scalar @matC;
    
    # individuo i valori minimo e massimo della matrice
    my $min = 0E0;
    my $max = 0E0;
    for my $i (0 .. $tot_res-1) {
        for my $j (0 .. $tot_res-1) {
            if ($matC[$i][$j] < $min) {
                $min = $matC[$i][$j];
            } elsif ($matC[$i][$j] > $max){
                $max = $matC[$i][$j];
            }
        }
    }
    
    # cerco GNUPLOT
    my $gnuplot = qx/which gnuplot/;
    chomp $gnuplot;
    
    # riscrivo la matrice in un formato leggibile da gnuplot
    my $content = '';
    foreach my $i (0 .. $tot_res-1) {
        foreach my $j (0 .. $tot_res-1) {
            $content .= sprintf("%d  %d  %.6f\n", $i+1, $j+1, $matC[$i][$j]);
        }
        $content .= "\n";
    }
    open(OUT, '>' . "_merge.matrices.dat");
    print OUT $content;
    close OUT;
    
    my $gnuscript = <<ROGER
set terminal png size 2400, 2400
set output "MERGED.png"
set size square
set pm3d map
set palette defined ( 0 "black", 1 "dark-red", 2 "orange", 3 "white" )
set cbrange[$min/$contrast to $max/$contrast]
set tics out
set xrange[-1:$tot_res+2]
set yrange[-1:$tot_res+2]
set xtics 10
set xtics rotate
set ytics 10
set mxtics 10
set mytics 10
splot "_merge.matrices.dat"
ROGER
    ;
    open(GPL, '>' . "_merge.matrices.gnuplot");
    print GPL $gnuscript;
    close GPL;
    my $gplot_log = qx/$gnuplot _merge.matrices.gnuplot 2>&1/;
}

FINE: {
    qx/rm -rfv _merge.matrices.*/; # rimuovo i file intermedi
    print "\n\n*** secirtam.egrem ***\n";
    exit;
}