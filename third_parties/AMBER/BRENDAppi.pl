#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 14.8.a        - initial release
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
our %bins = ( 'R' => '', 'GNUPLOT' => '' );
our @eigenvalues;
our @eigenvectors;
our @quali_evect;
our @quali_comp;
our $filter = 4;
our $verbose;
our $cbrange = 0.1;
our $ppifile = 'null'; # lista dei residui che definiscono l'interfaccia
our $totres; # numero di residui del sistema
our $varthres = 0.75; # quanta varianza cumulata devono spiegare gli autovettori?
our $maxprof = 0; # massima valore degli hotspot
## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    GetOptions('ppi|p=s' => \$ppifile, 'verbose|v' => \$verbose, 'limit|l=f' => \$varthres, 'filter|f=i' => \$filter, 'range|r=f' => \$cbrange);
    my $splash = <<ROGER
********************************************************************************
BRENDA - BRing the ENergy, ya damned DAemon!
PPI version
release 14.8.a

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
stabilization energy of a protein. In particular, the PPI version of BRENDA is 
dedicated to extract such determinants that mostly contribute to the overall 
variation on the binding energy, along the interface of protein-protein 
interactions.

It takes as an input the tabulated values obtained by the Energy Decomposition 
Analysis from MM-GBSA calculations. Such values will constitute the pairwise 
interaction energy matrix [1,2].

The interaction energy matrix values include the energy terms derived from 
solvation energy and pairwise electrostatic and van der Waals interactions. 
Intramolecular type 1-4 interaction are excluded from the calculation.

From the diagonalization of this matrix the most representative eigenvectors 
will be collected (until the cumulated variance threshold is reached).

RELEASE NOTES: see the header in the source code.

For further theoretical details and in order to use this program please cite the 
following references:

[1] Tiana G, Simona F, De Mori G, Broglia R, Colombo G. Protein Sci. 2004;13(1):113-24
[2] Corrada D, Colombo G. J Chem Inf Model. 2013;53(11):2937-50

*** REQUIRED SOFTWARE ***

- GnuPlot 4.4.4 or higher
- R v2.10.0 or higher

*** SYNOPSIS ***
    
    # default usage
    \$ BRENDAppi.pl enedecomp.dat
    
    # changing default parameters
    \$ BRENDAppi.pl enedecomp.dat -range 0.2 -filter 2

*** USAGE ***
    
    -filter <integer>   number of contig residues for which interaction energy 
                        will not considered (DEFAULT: 4)
    
    -limit <float>      rate of comulated variance explained by the selected
                        eigenvectors (DEFAULT: 0.75)
    
    -ppi <filename>     list of residues that define the PPI interface; 
                        otherwise, determinants will be evaluated considering 
                        the whole complex 
    
    -range <float>      energy threshold to normalize the plot of interaction 
                        energy matrix, in kcal/mol (DEFAULT: 0.1)
    
    -verbose            keep intermediate files

*** INPUT FILE ***

The file "enedecomp.dat" is the output file obtained from MM-GBSA pairwise 
energy decomposition. It will be obtained from AMBER's MMPBSA.py program, 
launching a command like follows:
    
    # example using the STP protocol
    \$ MMPBSA.py -O -i MMGBSA.in -sp solvated.prmtop -cp comp.prmtop -rp rec.prmtop -lp lig.prmtop -y MD.mdcrd

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
     saltcon = 0.154,
    \/
    \&decomp
     csv_format = 0,
     dec_verbose = 3,
     idecomp = 3,
    \/

*** OUTPUT FILES ***

The interaction energy matrix is depicted in "BRENDA.SMATRIX.png", the color 
ramp scale is defined within '-range xxx' kcal/mol. At bottom the hotspots 
profile is shown. The interaction energy matrix show only the non-bonded 
interactions between sidechains.

Tabulated values of interaction energy matrix are in "BRENDA.SMATRIX.csv" file.

The hotspot profile is tabulated in "BRENDA.PROFILE.dat". An hotspot is defined 
if, among the selected eigenvectors, show a component value higher than average. 
Each hotspot has a score related to the cumulated variance explained by the 
eigenvectors in which it belongs.
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
    printf("%s parsing MM-GBSA input data...", clock());
    open(IN, '<' . $ARGV[0]) or croak "E- unable to open <$ARGV[0]> file \n\t";
    my @file_content = <IN>;
    close IN;
    
    # faccio un check preliminare del file per assicurarmi che MMPBSA.py abbia prodotto l'output nel formato corretto
    my $match = grep(/Pairwise decomp/, @file_content);
    $match += grep(/Resid 1 \| Resid 2 \| /, @file_content);
    $match += grep(/DELTAS:/, @file_content);
    croak "E- wrong input file format, unable to parse\n\t" if ($match < 3);
    
    # creo le matrici di interazione
    my @sidechain_matrix;
    my $which = 'null';
    while (my $newline = shift @file_content) {
        chomp $newline;
        if ($newline =~ /DELTAS:/) {
            $which = 'DELTAS';
            next;
        }
        if ($newline =~ /Sidechain Energy Decomposition:/) {
            $which .= 'sidechain';
            next;
        }
        if ($which eq 'DELTASsidechain') {
            unless ($newline) { # fine della sezione
                $which = 'null';
                next;
            }
            next if ($newline =~ /^(-----|Resid)/); # righe di intestazione
            my @splitted = unpack('Z9Z10Z22Z22Z22Z22Z22Z21', $newline);
            my ($i) = $splitted[0] =~ /(\d+) \|$/;
            my ($j) = $splitted[1] =~ /(\d+) \|$/;
            my ($value) = $splitted[7] =~ /([-\.\d]+) \+\/-/;
            $sidechain_matrix[$i-1][$j-1] = $value;
        }
    }
    
    $totres = scalar @sidechain_matrix;
    
    # "simmetrizzo" la matrice delle energie
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
    
    # filtro la matrice delle energie
    for my $i (0..$totres-1) {
        for my $j (0..$totres-1) {
            if (abs($i - $j) <= $filter) {
                $sidechain_matrix[$i][$j] = '0.000';
                $sidechain_matrix[$j][$i] = '0.000';
#             } elsif ($sidechain_matrix[$i][$j] >= 0) { # filtro le interazioni destabilizzanti
#                 $sidechain_matrix[$i][$j] = '0.000';
            }
        }
    }
    
    # scrivo la matrice su file
    open(OUTS, '>' . "$workdir/BRENDA.SMATRIX.csv");
    for my $i (0..$totres-1) {
        my $lines;
        for my $j (0..$totres-1) {
            $lines .= sprintf("%.3f;", $sidechain_matrix[$i][$j]);
        }
        $lines =~ s/;$/\n/;
        print OUTS $lines;
    }
    close OUTS;
    
    print "done\n";
}

DIAGONALLEY: {
    printf("%s diagonalizing interaction energy matrix...", clock());
    my $eval_file = "$workdir/_BRENDA.EVAL.dat";
    my $evect_file = "$workdir/_BRENDA.EVECT.dat";
    my $mat_file = "$workdir/BRENDA.SMATRIX.csv";
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

REVERSI: { # inverto l'ordine di autovalori e autovettori, i discriminanti in questo caso sono gli autovettori associati agli autovalori più negativi
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
    my $mat_file = "$workdir/BRENDA.SMATRIX.csv";
    my $R_file = "$workdir/_BRENDA.sdev.R";
    my $sdevtable = "$workdir/_BRENDA.CUMULATIVE.dat";
    
    # creo lo script per R
    my $scRipt = <<ROGER
ene.mat <- as.matrix(read.csv("$mat_file", header = FALSE, sep = ";", row.names = NULL, stringsAsFactors = FALSE, dec = ".")) # importing interactione energy matrix
mypca <- princomp(ene.mat) # performing PCA analysis
summa <- summary(mypca)
vars <- summa\$sdev^2
vars <- vars/sum(vars)
tabela <- rbind("standard_deviation" = summa\$sdev, "proportion_of_variance" = vars, "cumulative_proportion" = cumsum(vars))
transposed <- t(tabela)
write.table(transposed, file = "$sdevtable", quote = FALSE, row.names = FALSE, col.names = TRUE, sep = ";", dec = ".") 
ROGER
    ;
    open(SCRIPT, '>' . $R_file);
    print SCRIPT $scRipt;
    close SCRIPT;
    
    # lancio l'analisi PCA
    my $log = qx/cd $workdir;$bins{'R'} $R_file 2>&1/;
#     print "\n<<$log>>"; # vedo cosa combina lo script

    # leggo la tabella della varianza cumulata
    open(TABLE, '<' . $sdevtable);
    my @file_content = <TABLE>;
    close TABLE;
    shift @file_content; # rimuovo l'header
    my $num = 0E0;
    while (my $newline = shift @file_content) {
        chomp $newline;
        my @values = split(';', $newline);
        my $cumul = sprintf("%.2f", $values[2]);
        push(@quali_evect, $num);
        $num++;
        last if ($cumul > $varthres);
    }
    my @printo = map { $_+1 } @quali_evect;
    printf("%s selected eigenvectors: %s\n", clock(), join(' ', @printo));
}

ENEDIST: {
    my %ppi_interface;
    if ($ppifile eq 'null') {
        printf("%s generating hotspots profile, no PPI interface defined...", clock());
    } else {
        printf("%s generating hotspots profile, using <%s>...", clock(), $ppifile);
        open(IN, '<' . $ppifile) or croak "E- unable to open <$ppifile> file \n\t";
        while (my $newline = <IN>) {
            chomp $newline;
            $newline-- if (int $newline);
            $ppi_interface{$newline} = 1;
        }
        close IN;
    }
    
    # leggo la tabella della varianza cumulata
    open(TABLE, '<' . '_BRENDA.CUMULATIVE.dat');
    my @file_content = <TABLE>;
    close TABLE;
    shift @file_content; # rimuovo l'header
    my @propvar;
    while (my $newline = shift @file_content) {
        chomp $newline;
        my @values = split(';', $newline);
        push(@propvar, $values[1]);
    }
    
    # le chiavi dell'hash %score individuano i residui; i valori individuano la varianza cumulata degli autovettori in cui tali residui sono considerati hotspot
    my %scores;
    foreach my $av (@quali_evect) {
        my $score = $propvar[$av]; # varianza spiegata dall'autovettore $av
        my @components = @{$eigenvectors[$av]};
        
        my @data;
        if ($ppifile eq 'null') {
            @data = @components;
        } else {
            for my $ppi (keys %ppi_interface) {
                push(@data, $components[$ppi]);
            }
        }
        @data = map(abs, @data);
        my $stat = Statistics::Descriptive::Full->new();
        $stat->add_data(@data);
        my $ave = $stat->mean();
        
        for my $i (0..scalar(@components)-1) {
            $scores{$i} = 0E0 unless (exists $scores{$i});
            my $value = abs($components[$i]);
            if ($value > $ave) { # la componente ha un valore sopra la media
                if ($ppifile eq 'null' || exists $ppi_interface{$i}) {
                    $scores{$i} += $score;
                }
            }
        }
    }
    
    # leggo la matrice delle interazioni
    my @stable;
    open(MATRIX, '<' . 'BRENDA.SMATRIX.csv');
    @file_content = <MATRIX>;
    close MATRIX;
    for my $i (0..scalar(@file_content)-1) {
        my $record = $file_content[$i];
        chomp $record;
        next unless $record;
        my @comps = split(';', $record);
        $stable[$i] = 0E0;
        foreach my $value (@comps) {
            $stable[$i] += $value;
        }
    }
    
    # scrivo il profilo su file e definisco se gli hotspots sono stabilizzanti o destabilizzanti
    my $profile = "resid  destabilizing  stabilizing\n";
    foreach my $residue (sort {$a <=> $b} keys %scores) {
        if ($stable[$residue] > 0) {
            $profile .= sprintf("%d  %.3f %.3f\n", $residue+1, $scores{$residue}, 0);
        } else {
            $profile .= sprintf("%d  %.3f %.3f\n", $residue+1, 0, $scores{$residue});
        }
        $maxprof = $scores{$residue} if ($scores{$residue} > $maxprof);
    }
    open(OUT, '>' . "$workdir/BRENDA.PROFILE.dat");
    print OUT $profile;
    close OUT;

    print "done\n";
}

GRAPHICS: {
    printf("%s generating graphs...", clock());
    
    # parso il file della matrice delle energie di interazione
    open(IN, '<' . "$workdir/BRENDA.SMATRIX.csv");
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
    
    my $gnuscript = <<ROGER
set terminal png size 2400, 2400
set output "BRENDA.SMATRIX.png"

set multiplot

#
# first plot (interaction energy matrix)
#
set lmargin at screen 0.10
set rmargin at screen 0.80
set bmargin at screen 0.20
set tmargin at screen 0.90

set pm3d map
set palette defined ( 0 "blue", 1 "white", 2 "red" )
set cbrange[-$cbrange to $cbrange]
set tics out
set xrange[0:$totres+1]
set yrange[0:$totres+1]
set xtics 10
set ytics 10
set mxtics 10
set mytics 10
set xtics format " "
set grid xtics lt 0 lw 1 lc rgb "black"
set grid ytics lt 0 lw 1 lc rgb "black"
splot "_BRENDA.SMATRIX.dat"

unset pm3d

#
# second plot (hotspots profile)
#
set lmargin at screen 0.10
set rmargin at screen 0.80
set bmargin at screen 0.15
set tmargin at screen 0.20

unset key
unset grid
set tics out
set xrange[0:$totres+1]
set xtics format "%.0f"
set xtics rotate
set xtics nomirror
set xtics 10
set mxtics 10
set xtics format "%.0f"
unset ytics;
set yrange [$maxprof:0]
set grid xtics lt 0 lw 1 lc rgb "black"
plot "BRENDA.PROFILE.dat" every ::1 using 1:2 with impulses lw 4 lt rgb "red", \\
     "BRENDA.PROFILE.dat" every ::1 using 1:3 with impulses lw 4 lt rgb "blue"
ROGER
    ;
    open(GPL, '>' . "$workdir/_BRENDA.gnuplot");
    print GPL $gnuscript;
    close GPL;
    my $gplot_log = qx/cd $workdir; $bins{'GNUPLOT'} _BRENDA.gnuplot 2>&1/;
    
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