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
use Cwd;
use Carp;

## GLOBS ##
our $workdir = getcwd();
our %bins = ( 'BLOCKS' => '', 'R' => '', 'GNUPLOT' => '' );
our @eigenvalues;
our @eigenvectors;
our @quali;
our $filter = 0;
our $snob; # bypass BLOCKS?
## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    GetOptions('snob|s' => \$snob, 'filter|f=i' => \$filter);
    my $splash = <<ROGER
********************************************************************************
BRENDA - BRing the ENergy, ya damned DAemon!
release 14.6.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

ROGER
    ;
    print $splash;
    
    unless ($ARGV[0]) {
        my $help = <<ROGER
BRENDA is a Perl script for capturing the main determinants from the 
stabilization energy of a protein.

It takes as an input the tabulated values obtained by the Energy Decomposition 
Analysis from MM-GBSA calculations. Such values will constitute the pairwise 
interaction energy matrix [1,2].

The interaction energy matrix values include the energy terms derived from 
solvation energy and pairwise electrostatic and van der Waals interactions. 
Intramolecular type 1-4 interaction are excluded from the calculation.

From the diagonalization of this matrix the most representative eigenvectors 
will be collected  [3].

For further theoretical details and in order to use this program please cite the 
following references:

[1] Tiana G, Simona F, De Mori G, Broglia R, Colombo G. Protein Sci. 2004;13(1):113-24
[2] Corrada D, Colombo G. J Chem Inf Model. 2013;53(11):2937-50
[3] Genoni A, Morra G, Colombo G. J Phys Chem B. 2012;116(10):3331-43

*** REQUIRED SOFTWARE ***

- BLOCKS - release 11.5
- GnuPlot 4.4.4 or higher
- R v2.10.0 or higher

*** USAGE ***

    \$ BRENDA.pl <enedecomp.dat> [-snob] [-filter 4]

    "enedecomp.dat"     mandatory, energy decomposition input file
    
    -snob               the script will bypass the eigenvector list evaluation 
                        and will choose only the first one (see also ref. [1] 
                        for further details)
    
    -filter <integer>   number of contig residues for which interaction energy 
                        will not considered (DEFAULT: 0)

*** INPUT FILE ***

The file "enedecomp.dat" is the output file obtained from MM-GBSA pairwise 
energy decomposition. It will be obtained from AMBER's "MMPBSA.py" program, 
launching a command like follows:

    \$ MMPBSA.py -O -i MMGBSA.in -sp solvated.prmtop -cp dry.prmtop -y MD.mdcrd

A template of the input script file "MMGBSA.in" could be as follows:

    Input file for GB calculation
    \&general
     verbose = 2,
     entropy = 0,
     keep_files = 0,
    \/
    \&gb
     igb = 5,
    \/
    \&decomp
     dec_verbose = 2,
     idecomp = 3,
    \/

*** NOTE ABOUT FILTER OPTION ***

The '-filter' option should be used carefully, diverse values will produce 
really different results. As rule of thumb, a value of 0 usually emphasizes 
interactions internals to secondary structure elements; values greater than 0 
will rise interactions between distal residues.
ROGER
        ;
        print $help;
        goto FINE;
    }
}

INIT: {
    # valuto l'architettura dell'OS
    my $arch = qx/uname -m/;
    chomp $arch;
    
    # cerco BLOCKS
    if ($arch eq 'i686') { # architettura 32bit
        $bins{'BLOCKS'} = qx/which BLOCKS.i686/;
    } elsif ($arch eq 'x86_64') { # architettura 64bit
        $bins{'BLOCKS'} = qx/which BLOCKS.x86_64/;
    } else {
        croak "E- unexpected OS architecture\n\t";
    }
    
    # cerco R
    $bins{'R'} = qx/which R/;
    
    # cerco GNUPLOT
    $bins{'GNUPLOT'} = qx/which gnuplot/;
    
    # check dei binari
    foreach my $key (keys %bins) {
        chomp $bins{$key};
        croak "E- unable to find \"$key\" binary\n\t" unless (-e $bins{$key});
    }
    
    $bins{'R'} .= ' --vanilla <'; # opzione per far girare R in batch
}

INPUT: {
    # parso il file di output di MMPBSA.py
    printf("%s parsing MM-GBSA input data...", clock());
    open(IN, '<' . $ARGV[0]) or croak "E- unable to open <$ARGV[0]> file \n\t";
    my @ene_matrix;
    while (my $newline = <IN>) {
        chomp $newline;
        if ($newline =~ /^\w{1,3}\s{1,3}\d{1,3},/) {
            my @values = split(',',$newline);
            my ($resa) = $values[0] =~ /([\d]+)$/;
            my ($resb) = $values[1] =~ /([\d]+)$/;
            my $internal = $values[2];
            my $total = $values[17];
            $resa = $resa - 1;
            $resb = $resb - 1;
            $total = sprintf("%.6f", $total - $internal);
            $ene_matrix[$resa][$resb] = $total;
        } else {
            next;
        }
    }
    close IN;
    
    # "simmetrizzo" la matrice delle energie d'interazione
    my $rows = scalar @{$ene_matrix[0]};
    for (my $i = 0; $i < $rows; $i++) {
        for (my $j = 0; $j < $rows; $j++) {
            if (abs($i - $j) <= $filter) {
                $ene_matrix[$i][$j] = 0E0;
                $ene_matrix[$j][$i] = 0E0;
            } elsif ($ene_matrix[$i][$j] == $ene_matrix[$j][$i]) {
                next;
            } else {
                my $ene1 = $ene_matrix[$i][$j];
                my $ene2 = $ene_matrix[$j][$i];
                my $ave = ($ene1 + $ene2) / 2;
                $ave = sprintf("%.6f", $ave);
                $ene_matrix[$i][$j] = $ave;
                $ene_matrix[$j][$i] = $ave;
            }
        }
    }
    
    open(OUT, '>' . "$workdir/BRENDA.IMATRIX.csv");
    for (my $i = 0; $i < $rows; $i++) {
        my $newline = '';
        for (my $j = 0; $j < $rows; $j++) {
            $newline .= sprintf("%.6f;", $ene_matrix[$i][$j]);
        }
        $newline =~ s/;$/\n/;
        print OUT $newline;
    }
    close OUT;
    
    print "done\n";
}

DIAGONALLEY: { # diagonalizzo la matrice delle energie d'interazione
    printf("%s diagonalizing interaction energy matrix...", clock());
    my $eval_file = "$workdir/BRENDAtmp.evalreverse.dat";
    my $evect_file = "$workdir/BRENDAtmp.evectreverse.dat";
    my $mat_file = "$workdir/BRENDA.IMATRIX.csv";
    my $R_file = "$workdir/BRENDAtmp.pca.R";
    
    # creo lo script per R
    my $scRipt = <<ROGER
ene.mat <- as.matrix(read.csv("$mat_file", header = FALSE, sep = ";", row.names = NULL, stringsAsFactors = FALSE, dec = ".")) # importing interactione energy matrix
diago <- eigen(ene.mat, symmetric = TRUE) # diagonalization
eval <- diago\$values
write.table(eval, file = "$eval_file", quote = FALSE, row.names = FALSE, col.names = FALSE, sep = ",", dec = ".") # eigenvalues list
evec <- as.data.frame(diago\$vectors)
write.table(evec, file = "$evect_file", quote = FALSE, row.names = FALSE, col.names = FALSE, sep = "\t", dec = ".") # eigenvectors list
ROGER
    ;
    open(SCRIPT, '>' . $R_file);
    print SCRIPT $scRipt;
    close SCRIPT;
    
    # lancio la diagonalizzazione
    my $log = qx/cd $workdir;$bins{'R'} $R_file 2>&1/;
#     print "\n<<$log>>"; # vedo cosa combina lo script
    
    print "done\n";
}

REVERSI: { # inverto l'ordine di autovalori e autovettori (i discriminanti in questo caso sono gli autovettori associati agli autovalori più negativi)
    printf("%s reversing eigenlists...", clock());
    open(EVAL, '<' . "$workdir/BRENDAtmp.evalreverse.dat");
    my @content = <EVAL>;
    close EVAL;
    @content = reverse @content;
    for (my $i = 0; $i < scalar @content; $i++) {
        chomp $content[$i];
        my $value = sprintf("%.6f",$content[$i]);
        push(@eigenvalues, $value);
    }
    open(EVAL, '>' . "$workdir/BRENDA.EVAL.dat");
    foreach my $record (@eigenvalues) {
        print EVAL "$record\n";
    }
    close EVAL;
    
    open(EVEC, '<' . "$workdir/BRENDAtmp.evectreverse.dat");
    my $component = 0;
    while (my $newline = <EVEC>) {
        chomp $newline;
        my @evectors = split("\t", $newline);
        @evectors = reverse @evectors;
        for (my $evect = 0; $evect < scalar @evectors; $evect++) {
            my $value = sprintf("%.6f", $evectors[$evect]);
            $eigenvectors[$evect][$component] = $value;
        }
        $component++
    }
    close EVEC;
    open(EVEC, '>' . "$workdir/BRENDA.EVECT.dat");
    for (my $component = 0; $component < scalar @eigenvalues; $component++) {
        my $string = '  ';
        for (my $evect = 0; $evect < scalar @eigenvalues; $evect++) {
            $string .= "$eigenvectors[$evect][$component]\t";
        }
        $string =~ s/\t$/\n/;
        print EVEC $string;
    }
    close EVEC;
    
    print "done\n";
}

AUTOMAN: {
    my $resnumber = scalar @eigenvalues;
    
    ($snob) and do { 
        @quali = ( '0' );
        printf("%s selected eigenvectors: 1\n", clock());
        goto DISTRIB;
    };
    
    FORECAST: {
        printf("%s extracting significant eigenvectors...", clock());
        ($resnumber) = $resnumber =~ /^(\d+)/;
        my $cmd = <<ROGER
cd $workdir;
touch fort.35;
cp BRENDA.EVECT.dat fort.30
cp BRENDA.EVAL.dat fort.31
echo '\$PARAMS  NRES=$resnumber FRACT=0.6d0 TOTAL=.TRUE. NTM=3 PERCOMP=0.5 NGRAIN=5 LENGTH=50 \$END' | $bins{'BLOCKS'} 2> BLOCKS.error;
ROGER
        ;
        my $blocks_log = qx/$cmd/;
        my ($match_string) = $blocks_log =~ m/ESSENTIAL CLUSTER OF EIGENVECTORS:\s+([\s\d]+)\n/m;
        open(BLOCKS, '>' . "$workdir/BRENDAtmp.BLOCKS.log");
        print BLOCKS $blocks_log;
        close BLOCKS;
        unless ($match_string) {
            croak("\nE- forecasting error, please see BRENDAtmp.BLOCKS.log\n\t");
        }
        @quali = split(/\s+/, $match_string);
        print "done\n";
        printf("%s selected eigenvectors: %s\n", clock(), join(' ',sort {$a <=> $b} @quali));
        @quali = map { $_-1 } @quali;

    }
    
    qx/rm -rfv fort.*/;
    unlink "BLOCKS.error";
}

DISTRIB: {
    my $resnumber = scalar @eigenvalues;
    my $threshold = sqrt ( 1 / $resnumber);
    printf("%s generating energy profile (threshold: %.3f)...", clock(), $threshold);
    my @components = split(':', "0:" x $resnumber);
    foreach my $av (@quali) {
        for (my $i = 0; $i < $resnumber; $i++) {
            $components[$i] = abs($eigenvectors[$av][$i])
                if (abs($eigenvectors[$av][$i]) > abs($components[$i]));
        }
    }
    my $profile = ''; my $i = 1;
    foreach my $value (@components) {
        $profile .= sprintf("%d  %.6f\n", $i, $value);
        $i++;
    }
    
    open(OUT, '>' . "$workdir/BRENDA.PROFILE.dat");
    print OUT $profile;
    close OUT;
    
    
    GNUPLOT: {
        open(IN, '<' . "$workdir/BRENDA.PROFILE.dat");
        my $content = [ ];
        @{$content} = <IN>;
        close IN;
        my @components;
        while (my $newline = shift @{$content}) {
            chomp $newline;
            next unless $newline;
            my ($res, $value) = $newline =~ /(\d+)\s+([\-\.\d]+)/;
            push(@components, $value);
        }
        my $threshold = sqrt ( 1 / scalar @components); 
        
        # separating values above or below threshold
        open(DOWN, '>' . "$workdir/BRENDAtmp.down");
        my $down = ''; my $i = 1;
        foreach my $value (@components) {
            my $eval = $value;
            $eval = 0E0 if (abs($eval) > $threshold);
            $down .= sprintf("%d  %.6f\n", $i, $eval);
            $i++;
        }
        print DOWN $down;
        close DOWN;
        open(UP, '>' . "$workdir/BRENDAtmp.up");
        my $up = ''; $i = 1;
        foreach my $value (@components) {
            my $eval = $value;
            $eval = 0E0 if (abs($eval) < $threshold);
            $up .= sprintf("%d  %.6f\n", $i, $eval);
            $i++;
        }
        print UP $up;
        close UP;
        
        my $max = 0E0; my $min = 0E0;
        foreach my $value (@components) {
            $max = $value if ($value > $max);
            $min = $value if ($value < $min);
        }
        
        my $gnuscript = <<ROGER
# Gnuplot script to draw energy distribution
# 
set terminal png size 2400, 800
set size ratio 0.33
set output "BRENDA.PROFILE.png"
set key
set tics out
set xrange[1:$resnumber]
set xtics rotate
set xtics nomirror
set xtics 10
set mxtics 10
set xlabel "resID"
set yrange [$min:$max+0.1]
set ytics 0.1
set mytics 10
plot    "BRENDAtmp.up" with impulses lw 3 lt 1, \\
        "BRENDAtmp.down" with impulses lw 3 lt 9
ROGER
        ;
        open(GPL, '>' . "$workdir/BRENDAtmp.enedist.gnuplot");
        print GPL $gnuscript;
        close GPL;
        my $gplot_log = qx/cd $workdir; $bins{'GNUPLOT'} BRENDAtmp.enedist.gnuplot 2>&1/;
    }
    print "done\n";
}

NEWMATRIX: {
    printf("%s generating minimal interaction energy matrix...", clock());
    my $resnumber = scalar @eigenvalues;
    my @enematrix;
    foreach (my $i = 0; $i < $resnumber; $i++) {
        foreach (my $j = 0; $j < $resnumber; $j++) {
            $enematrix[$i][$j] = 0E0;
        }
    }
    
    foreach my $automan (@quali) {
        foreach (my $i = 0; $i < $resnumber; $i++) {
            foreach (my $j = 0; $j < $resnumber; $j++) {
                my $value = $eigenvalues[$automan] * $eigenvectors[$automan][$i] * $eigenvectors[$automan][$j];
                $enematrix[$i][$j] += $value;
            }
        }
    }
    
    my $content = '';
    foreach (my $i = 0; $i < $resnumber; $i++) {
        foreach (my $j = 0; $j < $resnumber; $j++) {
            $content .= sprintf("%d  %d  %.6f\n", $i+1, $j+1, $enematrix[$i][$j]);
        }
        $content .= "\n";
    }
    
    open(OUT, '>' . "$workdir/BRENDA.MMATRIX.dat");
    print OUT $content;
    close OUT;
    
    GNUPLOT: {
        open(IN, '<' . "$workdir/BRENDA.MMATRIX.dat");
        my $content = [ ];
        @{$content} =<IN>;
        close IN;
        my $ave = 0E0; my $counter = 0E0;
        while (my $row = shift @{$content}) {
            chomp $row;
            next unless $row;
            my ($r1,$r2,$value) = split(/\s+/, $row);
            if ($value < 0) {
                $ave += $value;
                $counter++;
            }
        }
        $ave = $ave / $counter;
        
        my $gnuscript = <<ROGER
# Gnuplot script to draw energy matrix
# 
set terminal png size 2400, 2400
set output "BRENDA.MMATRIX.png"
set size square
set pm3d map
set palette rgbformulae 34,35,36
set cbrange[$ave-0.5 to $ave]
set tics out
set xrange[0:$resnumber+1]
set yrange[0:$resnumber+1]
set xtics 10
set xtics rotate
set ytics 10
set mxtics 10
set mytics 10
splot "BRENDA.MMATRIX.dat"
ROGER
        ;
        open(GPL, '>' . "$workdir/BRENDAtmp.enematrix.gnuplot");
        print GPL $gnuscript;
        close GPL;
        my $gplot_log = qx/cd $workdir; $bins{'GNUPLOT'} BRENDAtmp.enematrix.gnuplot 2>&1/;
    }
    
    print "done";
}

FINE: {
    qx/rm -rfv BRENDAtmp.*/; # rimuovo i file intermedi
    
    print "\n\n*** ADNERB ***\n";
    exit;
}

sub clock {
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    $mese = $mese+1;
    $mese = sprintf("%02d", $mese);
    $giom = sprintf("%02d", $giom);
    $ore = sprintf("%02d", $ore);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    my $date = '[' . ($anno+1900)."/$mese/$giom $ore:$min:$sec]";
    return $date;
}