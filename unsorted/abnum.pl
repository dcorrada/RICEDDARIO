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
use RICEDDARIO::lib::Kabat;
use Carp;


#######################
## VARIABILI GLOBALI ##
our @filelist;
#######################


USAGE: {
    my $options = { };
    use Getopt::Long;no warnings;
    GetOptions($options, 'help|h', 'file|f=s@');
    my $usage = <<END

SYNOPSYS

  $0 -f file1.pdb [ -f file2.pdb [...] ]

Questo script sottomette in batch uno o piu' file pdb sul servizio abnum. Per
ogni pdb viene allestito un file Excel contenente le diverse numerazioni di
riferimento attualmente usate.
(v. Abhinandan KR, Martin AC. - Mol Immunol. 2008 Aug;45(14):3832-9)

OPZIONI

  -f <string>       INPUT, PDB filename

END
    ;
    
    if (exists $options->{'file'}) {
        @filelist = @{$options->{'file'}};
    } else {
        print $usage; exit;
    };
}

print "\n--- ABNUM ---\n";

my $kabat = RICEDDARIO::lib::Kabat->new();

while (my $actual = shift @filelist) {
    if (-e $actual) {
        print "\nI- processing [$actual]...";
        $kabat->numbers($actual);
    } else {
        carp("\nW- [$actual] file not found\n\t")
    }
}

print "\n--- MUNBA ---\n";
exit;