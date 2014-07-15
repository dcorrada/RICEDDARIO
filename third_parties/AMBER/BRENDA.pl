#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 14.7.a        - changed default values for options
#                       - changed format of files produced
#                       - interaction energy matrix is now based considering 
#                         only the stabilizing interactions between sidechains
#                       - improved visualization of interaction energy profile 
#                         and related matrix
#
# release 14.6.a        - initial release
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

## GLOBS ##*** REQUIRED SOFTWARE ***
our $workdir = getcwd();
our %bins = ( 'BLOCKS' => '', 'R' => '', 'GNUPLOT' => '' );
our @eigenvalues;
our @eigenvectors;
our @quali_evect;
our @quali_comp;
our $filter = 4;
our $auto = '1';
our $verbose;
our $totres; # numero di residui del sistema
## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    GetOptions('auto|a=i' => \$auto, 'verbose|v' => \$verbose, 'filter|f=i' => \$filter);
    my $splash = <<ROGER
********************************************************************************
BRENDA - BRing the ENergy, ya damned DAemon!
release 14.7.a

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

RELEASE NOTES: see the header in the source code.

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

    \$ BRENDA.pl <enedecomp.dat> [-auto 0] [-filter 2] [-verbose]

    "enedecomp.dat"     mandatory, energy decomposition input file
    
    -auto <integer>     method of eigenvector selection:
                        0 - select only the first eigenvector, see also [1]
                        1 - DEFAULT, use BLOCK for estimating the significant 
                            eigenvectors, see also [3]
    
    -filter <integer>   number of contig residues for which interaction energy 
                        will not considered (DEFAULT: 4)
    
    -verbose            keep intermediate files

*** INPUT FILE ***

The file "enedecomp.dat" is the output file obtained from MM-GBSA pairwise 
energy decomposition. It will be obtained from AMBER's MMPBSA.py program, 
launching a command like follows:

    \$ MMPBSA.py -O -i MMGBSA.in -sp solvated.prmtop -cp dry.prmtop -y MD.mdcrd

The specific output file format accepted by BRENDA could be obtained by 
submitting to MMPBSA.py the following input script:

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
     csv_format = 0,
     dec_verbose = 3,
     idecomp = 3,
    \/
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
    # apro il file di output di MMPBSA.py 
    printf("%s parsing MM-GBSA input data...", clock());
    open(IN, '<' . $ARGV[0]) or croak "E- unable to open <$ARGV[0]> file \n\t";
    my @file_content = <IN>;
    close IN;
    
    # faccio un check preiminare del suo contenuto
    my $match = grep(/Pairwise decomp/, @file_content);
    $match += grep(/Resid 1 \| Resid 2 \| /, @file_content);
    $match += grep(/Total Energy Decomposition:/, @file_content);
    $match += grep(/Sidechain Energy Decomposition:/, @file_content);
    croak "E- wrong input file format, unable to parse\n\t" if ($match < 6);
    
    # creo le matrici di interazione
    my @total_matrix;
    my @sidechain_matrix;
    my $which = 'null';
    while (my $newline = shift @file_content) {
        chomp $newline;
        if ($newline =~ /Total Energy Decomposition:/) {
            $which = 'total';
            next;
        } elsif ($newline =~ /Sidechain Energy Decomposition:/) {
            $which = 'sidechain';
            next;
        } elsif ($newline =~ /Backbone Energy Decomposition:/) {
            $which = 'backbone';
            next;
        }
        if ($which =~ /(total|sidechain)/) {
            next unless $newline;
            next if ($newline =~ /^(-----|Resid)/);
            my @splitted = unpack('Z9Z10Z22Z22Z22Z22Z22Z21', $newline);
            my ($i) = $splitted[0] =~ /(\d+) \|$/;
            my ($j) = $splitted[1] =~ /(\d+) \|$/;
            my ($value) = $splitted[7] =~ /([-\.\d]+) \+\/-/;
            if ($which eq 'total') {
                $total_matrix[$i-1][$j-1] = $value;
            } else {
                $sidechain_matrix[$i-1][$j-1] = $value;
            }
        } else {
            next;
        }
    }
    
    $totres = scalar @total_matrix;
    
    # "simmetrizzo" la matrice delle energie della sidechain
    for my $i (0..$totres-1) {
        for my $j (0..$totres-1) {
            if ($sidechain_matrix[$i][$j] == $sidechain_matrix[$j][$i]) {
                next;
            } else {
                my $ene1 = $sidechain_matrix[$i][$j];
                my $ene2 = $sidechain_matrix[$j][$i];
                my $ave = ($ene1 + $ene2) / 2;
                $ave = sprintf("%.3f", $ave);
                $sidechain_matrix[$i][$j] = $ave;
                $sidechain_matrix[$j][$i] = $ave;
            }
        }
    }
    
    # filtro la matrice delle energie della sidechain
    for my $i (0..$totres-1) {
        for my $j (0..$totres-1) {
            if (abs($i - $j) <= $filter) {
                $sidechain_matrix[$i][$j] = '0.000';
                $sidechain_matrix[$j][$i] = '0.000';
            } elsif ($sidechain_matrix[$i][$j] >= 0) {
                $sidechain_matrix[$i][$j] = '0.000';
            }
        }
    }
    
    # scrivo le matrici su file
    open(OUTT, '>' . "$workdir/BRENDA.IMATRIX.csv");
    open(OUTS, '>' . "$workdir/_BRENDA.SMATRIX.csv");
    for my $i (0..$totres-1) {
        my ($linet, $lines) = ('', '');
        for my $j (0..$totres-1) {
            $linet .= sprintf("%.3f;", $total_matrix[$i][$j]);
            $lines .= sprintf("%.3f;", $sidechain_matrix[$i][$j]);
        }
        $linet =~ s/;$/\n/;
        $lines =~ s/;$/\n/;
        print OUTT $linet;
        print OUTS $lines;
    }
    close OUTT;
    close OUTS;
    
    print "done\n";
}

# TOTAL: { # plot della matrice di interazione originale
#     printf("%s generating raw interaction energy matrix...", clock());
#     
#     # parso il file della matrice delle energie di interazione
#     open(IN, '<' . "$workdir/BRENDA.IMATRIX.csv");
#     my @file_content = <IN>;
#     close IN;
#     
#     my @enematrix;
#     my $i = 0;
#     while (my $newline = shift @file_content) {
#         chomp $newline;
#         next unless $newline;
#         my @record = split(';', $newline);
#         $enematrix[$i] = [ @record ];
#         $i++;
#     }
#     
#     # riscrivo la matrice in un formato leggibile da gnuplot
#     my $content = '';
#     foreach my $i (0..$totres-1) {
#         foreach my $j (0..$totres-1) {
#             $content .= sprintf("%d  %d  %.6f\n", $i+1, $j+1, $enematrix[$i][$j]);
#         }
#         $content .= "\n";
#     }
#     open(OUT, '>' . "$workdir/_BRENDA.IMATRIX.dat");
#     print OUT $content;
#     close OUT;
#     
#     # plotto la matrice
#     my $gnuscript = <<ROGER
# # Gnuplot script to draw energy matrix
# # 
# set terminal png size 2400, 2400
# set output "BRENDA.IMATRIX.png"
# set size square
# set pm3d map
# set palette defined ( 0 "blue", 1 "white", 2 "red" )
# set cbrange[-1 to 1]
# set tics out
# set xrange[0:$totres+1]
# set yrange[0:$totres+1]
# set xtics 10
# set xtics rotate
# set ytics 10
# set mxtics 10
# set mytics 10
# splot "_BRENDA.IMATRIX.dat"
# ROGER
#     ;
#     open(GPL, '>' . "$workdir/_BRENDA.IMATRIX.gnuplot");
#     print GPL $gnuscript;
#     close GPL;
#     my $gplot_log = qx/cd $workdir; $bins{'GNUPLOT'} _BRENDA.IMATRIX.gnuplot 2>&1/;
#     
#     print "done\n";
# }

DIAGONALLEY: { # diagonalizzo la matrice delle energie d'interazione
    printf("%s diagonalizing interaction energy matrix...", clock());
    my $eval_file = "$workdir/_BRENDA.EVAL.dat";
    my $evect_file = "$workdir/_BRENDA.EVECT.dat";
    my $mat_file = "$workdir/_BRENDA.SMATRIX.csv";
    my $R_file = "$workdir/_BRENDA.pca.R";
    
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
    open(EVAL, '<' . "$workdir/_BRENDA.EVAL.dat");
    my @content = <EVAL>;
    close EVAL;
    @content = reverse @content;
    for (my $i = 0; $i < scalar @content; $i++) {
        chomp $content[$i];
        my $value = sprintf("%.6f",$content[$i]);
        push(@eigenvalues, $value);
    }
    open(EVAL, '>' . "$workdir/_BRENDA.EVAL.dat");
    foreach my $record (@eigenvalues) {
        print EVAL "$record\n";
    }
    close EVAL;
    
    open(EVEC, '<' . "$workdir/_BRENDA.EVECT.dat");
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
    open(EVEC, '>' . "$workdir/_BRENDA.EVECT.dat");
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
    if ($auto eq '0') { 
        @quali_evect = ( '0' );
        printf("%s selected eigenvectors: 1\n", clock());
    } elsif ($auto eq '1') {
        printf("%s extracting significant eigenvectors...", clock());
        my $cmd = <<ROGER
cd $workdir;
touch fort.35;
cp _BRENDA.EVECT.dat fort.30
cp _BRENDA.EVAL.dat fort.31
echo '\$PARAMS  NRES=$totres FRACT=0.6d0 TOTAL=.TRUE. NTM=3 PERCOMP=0.5 NGRAIN=5 LENGTH=50 \$END' | $bins{'BLOCKS'} 2> BLOCKS.error;
ROGER
        ;
        my $blocks_log = qx/$cmd/;
        my ($match_string) = $blocks_log =~ m/ESSENTIAL CLUSTER OF EIGENVECTORS:\s+([\s\d]+)\n/m;
        open(BLOCKS, '>' . "$workdir/_BRENDA.BLOCKS.log");
        print BLOCKS $blocks_log;
        close BLOCKS;
        unless ($match_string) {
            croak("\nE- forecasting error, please see _BRENDA.BLOCKS.log\n\t");
        }
        @quali_evect = split(/\s+/, $match_string);
        print "done\n";
        printf("%s selected eigenvectors: %s\n", clock(), join(' ',sort {$a <=> $b} @quali_evect));
        @quali_evect = map { $_-1 } @quali_evect;
        qx/rm -rfv fort.*/;
        unlink "BLOCKS.error";
    } else {
        croak("\nE- unknown method chosen for selecting eigenvectors\n\t");
    }
}

DISTRIB: {
    my $threshold = scalar @quali_evect * (sqrt ( 1 / $totres));
    printf("%s generating energy profile (threshold: %.3f)...", clock(), $threshold);
    
    # creo il profilo delle componenti e lo scrivo su file
    my @components = split(':', "0:" x $totres);
    foreach my $av (@quali_evect) {
        for my $i (0..$totres-1) {
            $components[$i] += $eigenvectors[$av][$i];
        }
    }
    my $profile = ''; my $i = 1;
    foreach my $value (@components) {
        $profile .= sprintf("%d  %.3f\n", $i, $value);
        $i++;
    }
    open(OUT, '>' . "$workdir/BRENDA.PROFILE.dat");
    print OUT $profile;
    close OUT;
    
    # separating values above or below threshold
    open(DOWN, '>' . "$workdir/_BRENDA.down");
    my $down = ''; $i = 1;
    foreach my $value (@components) {
        my $eval = $value;
        $eval = 0E0 if (abs($eval) > $threshold);
        $down .= sprintf("%d  %.3f\n", $i, $eval);
        $i++;
    }
    print DOWN $down;
    close DOWN;
    open(UP, '>' . "$workdir/_BRENDA.up");
    my $up = ''; $i = 1;
    foreach my $value (@components) {
        my $eval = $value;
        if (abs($eval) < $threshold) {
            $eval = 0E0;
        } else {
            push(@quali_comp, $i-1);
        }
        $up .= sprintf("%d  %.3f\n", $i, $eval);
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
set xrange[0:$totres+1]
set xtics rotate
set xtics nomirror
set xtics 10
set mxtics 10
set xlabel "resID"
set yrange [$min-0.1:$max+0.1]
set ytics 0.1
set mytics 10
plot    "_BRENDA.up" with impulses lw 3 lt 1, \\
        "_BRENDA.down" with impulses lw 3 lt 9
ROGER
    ;
    open(GPL, '>' . "$workdir/_BRENDA.enedist.gnuplot");
    print GPL $gnuscript;
    close GPL;
    my $gplot_log = qx/cd $workdir; $bins{'GNUPLOT'} _BRENDA.enedist.gnuplot 2>&1/;

    print "done\n";
}

NEWMATRIX: {
    printf("%s generating interaction energy matrix...", clock());
    
    # parso il file della matrice delle energie di interazione
    open(IN, '<' . "$workdir/_BRENDA.SMATRIX.csv");
    my @file_content = <IN>;
    close IN;
    my @enematrix;
    my $i = 0;
    while (my $newline = shift @file_content) {
        chomp $newline;
        next unless $newline;
        my @record = split(';', $newline);
        $enematrix[$i] = [ @record ];
        $i++;
    }
    
    # filtro la matrice sulla base delle component individuate come rilevanti
    for my $i (@quali_comp) {
        for my $j (0..$totres-1) {
            $enematrix[$i][$j] = abs $enematrix[$i][$j];
            $enematrix[$j][$i] = abs $enematrix[$j][$i];
        }
    }
    
#     # ricostruisco la matrice sulla base degli autovettori selezionati
#     for my $automan (@quali_evect) {
#         for my $i (0..$totres-1) {
#             for my $j (0..$totres-1) {
#                 my $value = $eigenvalues[$automan] * $eigenvectors[$automan][$i] * $eigenvectors[$automan][$j];
#                 $enematrix[$i][$j] += $value;
#             }
#         }
#     }
    
    # riscrivo la matrice in un formato leggibile da gnuplot
    my $content = '';
    foreach my $i (0..$totres-1) {
        foreach my $j (0..$totres-1) {
            $content .= sprintf("%d  %d  %.6f\n", $i+1, $j+1, $enematrix[$i][$j]);
        }
        $content .= "\n";
    }
    open(OUT, '>' . "$workdir/_BRENDA.SMATRIX.dat");
    print OUT $content;
    close OUT;
    
    $content = '';
    for my $i (0..$totres-1) {
        for my $j (0..$totres-1) {
            $content .= sprintf("%d  %d  %.6f\n", $i+1, $j+1, $enematrix[$i][$j]);
        }
        $content .= "\n";
    }
    
    open(OUT, '>' . "$workdir/_BRENDA.SMATRIX.dat");
    print OUT $content;
    close OUT;
    
    open(IN, '<' . "$workdir/_BRENDA.SMATRIX.dat");
    $content = [ ];
    @{$content} =<IN>;
    close IN;
    my @data;
    while (my $row = shift @{$content}) {
        chomp $row;
        next unless $row;
        my ($r1,$r2,$value) = split(/\s+/, $row);
        push (@data, $value) if ($value < 0);
    }
    my $stat = Statistics::Descriptive::Full->new();
    $stat->add_data(@data);
    my $ave = $stat->mean();
    my $stdev = $stat->standard_deviation();
    
    my $gnuscript = <<ROGER
# Gnuplot script to draw energy matrix
# 
set terminal png size 2400, 2400
set output "BRENDA.MMATRIX.png"
set size square
set pm3d map
set palette defined ( 0 "blue", 1 "white", 2 "red" )
set cbrange[-0.1 to 0.1]
set tics out
set xrange[0:$totres+1]
set yrange[0:$totres+1]
set xtics 10
set xtics rotate
set ytics 10
set mxtics 10
set mytics 10
splot "_BRENDA.SMATRIX.dat"
ROGER
    ;
    open(GPL, '>' . "$workdir/_BRENDA.enematrix.gnuplot");
    print GPL $gnuscript;
    close GPL;
    my $gplot_log = qx/cd $workdir; $bins{'GNUPLOT'} _BRENDA.enematrix.gnuplot 2>&1/;
    
    print "done";
}

FINE: {
    unless ($verbose) {
        qx/rm -rfv _BRENDA.*/; # rimuovo i file intermedi
    };
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