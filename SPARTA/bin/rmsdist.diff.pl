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
use SPARTA::lib::MatrixDiff; # classe x generare matrici differenza

#######################
## VARIABILI GLOBALI ##
our $working_dir = getcwd();
our $filename = {   'inputA' => 'matrix.APO.dat',
                    'inputB' => 'matrix.OLO.dat',
                    'output' => 'matrix.diff.dat' };
our $neo = SPARTA::lib::MatrixDiff->new(); # istanzio l'oggetto su cui lavoro
#######################

USAGE: {
    my $options = { };
    use Getopt::Long;no warnings;
    GetOptions($options, 'help|h', 'mata|a=s', 'matb|b=s', 'output|o=s');
    my $usage = <<END

SYNOPSYS

  $0 [-a string] [-b string] [-o string]

Questo script legge in input due file di matrici ottenute dallo script relativo 
all'analisi della fluttuazione delle distanze e restituisce in output una 
matrice differenza. Un caso d'uso tipico puo' essere quando si intende fare un 
confornto diretto tra le matrici di una proteina nelle forme apo e olo. 

OPZIONI

  -a <string>,      INPUT, file relativi alle matrici che si intendono 
  -b <string>       confrontare

  -o <string>       OUTPUT, file della matrice differenza

ESEMPI:
   
   $0 -a matrix.APO.dat -b matrix.OLO.dat -o matrix.diff.dat

END
    ;
    if (exists $options->{'help'}) { print $usage; exit; };

    $filename->{'inputA'} = $options->{'mata'} if (exists $options->{'mata'});
    $filename->{'inputB'} = $options->{'matb'} if (exists $options->{'matb'});
    $filename->{'output'} = $options->{'output'} if (exists $options->{'output'});
    
}

FILCHECK: {
    print "\n-- FILES";
    foreach my $opt (sort(keys %{$filename})) {
         printf("\n%s -> [%s]", $opt, $filename->{$opt});
    }
    print "\n-- SELIF\n";
    
    croak("\nE- file [$filename->{'inputA'}] not found\n\t") unless (-e $filename->{'inputA'});
    croak("\nE- file [$filename->{'inputB'}] not found\n\t") unless (-e $filename->{'inputB'});
}


MATDIFF: { # calcolo la matrice differenza e la esporto su file
    my $obj = SPARTA::lib::MatrixDiff->new();
    
    $obj->import_gpl($filename->{'inputA'});
    $obj->import_gpl($filename->{'inputB'});
    
    $obj->export_gpl($filename->{'output'});
}

FINE: {
    print "\n---\nFINE PROGRAMMA\n";
    exit;
}
