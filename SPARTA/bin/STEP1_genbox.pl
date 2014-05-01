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

my $working_dir = getcwd();
my $mdp_file = '/home/dario/GOLEM_RAWDATA/tools/em.mdp';
my $PDB_file = $ARGV[0];

my $usage = <<END

SYNOPSYS

  $0 PDB_file

Dato in input un file PDB lo script importa la struttura per GROMACS, allestisce
il box, lo solvata e aggiunge gli ioni

END
;
unless ($PDB_file) { print $usage; exit; };
croak("\nE- file [$PDB_file] not found\n\t") unless (-e $PDB_file);
croak("\nE- file [$mdp_file] not found\n\t") unless (-e $mdp_file);

system "pdb2gmx -f $PDB_file -ignh"; # creo il gro file

print "\n-- Appuntarsi la carica del sistema prima di proseguire...";
my $nextstep = <STDIN>;

system "editconf -f conf.gro -o conf.box.gro -d 1.2 -bt triclinic"; # allestisco il box

print "\n-- Appuntarsi le dimensioni del box prima di proseguire...";
$nextstep = <STDIN>;

system "genbox -cp conf.box.gro -cs -p topol.top -o conf.water.gro"; # solvato il box

print "\n-- Appuntarsi il numero di atomi prima di proseguire...";
$nextstep = <STDIN>;

print "\n-- Neutralizzazione del sistema: quante cariche inserire? [es. -1, +2, +0]\n";
my $charges = <STDIN>; chomp $charges;

while ($charges !~ m/^[+-]\d+$/) {
    print "\nE- Sintassi [$charges] errata\n";
    $charges = <STDIN>; chomp $charges;
}

my ($sign, $tot) = $charges =~ m/^([+-])(\d+)$/;

my $flag;
if ($tot == 0) { $flag = "";
} elsif ($sign eq '-') { $flag = "-nn $tot"
} elsif ($sign eq '+') { $flag = "-np $tot"
}

# aggiungo gli ioni
system "grompp -f $mdp_file -c conf.water.gro -p topol.top -o ions.tpr -maxwarn 2";
system "genion -s ions.tpr -p topol.top -pname NA+ -nname CL- $flag -o conf.ions.gro";

print "\n---\nFINE PROGRAMMA\n";
exit;
