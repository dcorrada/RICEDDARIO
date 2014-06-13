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
our $logfile = "$workdir/ISABEL.log";
our $inputfiles = [ ];
our $filter = 0;
our %bins;
## SBLOG ##

USAGE: {
    my $splash = <<ROGER
********************************************************************************
ISABEL - ISabel is Another BEppe Layer
release 14.6.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

ROGER
    ;
    print $splash;
    
    use Getopt::Long;no warnings;
    GetOptions('filter|f=i' => \$filter);
    unless ($ARGV[0]) {
        my $help = <<ROGER
ISABEL is a Perl script which offers an automated pipeline for:

    1) performing MM-GBSA calculation from a structure file (in PDB format);

    2) calulating the interaction energy matrix through Energy Decomposition 
       Analysis from the output obtained in step 1;
    
    3) extracting the energetic determinants through the Principal Component 
       Analysis over the matrix obtained in step 2.

*** REQUIRED SOFTWARE ***

The tools flagged with (*) are already packaged with the current release of 
RICEDDARIO.

ISABEL
├── PDB4AMBER 14.5.a (*)
├── AMBER 12 or higher
│   └── AMBER Tools compliant version
└── BRENDA 14.6.a (*)
    ├── BLOCKS 11.5 (*)
    ├── GnuPlot 4.4.4 or higher
    └── R 2.10.0 or higher

*** USAGE ***

    \$ ISABEL.pl <protein.pdb> [-filter 4]

    "protein.pdb"       the input structure, it must be correctly protonated
    
    -filter <integer>   number of contig residues for which interaction energy 
                        will not considered (DEFAULT: 0)

*** REFERENCES ***
Please cite the following papers if you publish this work:

[1] Tiana G, Simona F, De Mori G, Broglia R, Colombo G. 
    Protein Sci. 2004;13(1):113-24
[2] Corrada D, Colombo G.
    J Chem Inf Model. 2013;53(11):2937-50
[3] Genoni A, Morra G, Colombo G. 
    J Phys Chem B. 2012;116(10):3331-43
[4] Miller B, McGee T, Swails J, Homeyer N, Gohlke H, Roitberg A. 
    J Chem Theory Comput. 2012;8(9):3314-21
ROGER
        ;
        print $help;
        goto FINE;
    }
}

INIT: {
    # apro il log file
    open(ISALOG, '>' . $logfile);
    print ISALOG "*** ISABEL LOG ***";
    my $warning = <<ROGER
WARNING: ISABEL does not track the messages of its components at stdout level. 
Please check further in the log file <$logfile>

ROGER
    ;
    
    # cerco binari e script vari
    $bins{'PDB4AMBER'} = qx/which PDB4AMBER.pl/;
    $bins{'ANTEMMPBSA'} = qx/which ante-MMPBSA.py/;
    $bins{'MMPBSA'} = qx/which MMPBSA.py/;
    $bins{'TLEAP'} = qx/which tleap/;
    $bins{'SANDER'} = qx/which sander/;
    $bins{'AMBPDB'} = qx/which ambpdb/;
    $bins{'BRENDA'} = qx/which BRENDA.pl/;
    
    foreach my $key (keys %bins) {
        chomp $bins{$key};
        croak "E- unable to find \"$key\" binary\n\t" unless (-e $bins{$key});
    }
}

PDBCONVERSION: {
    message(sprintf("%s converting PDB to AMBER compliant format...", clock()));
    
    # input check from previous stage
    my $infile = $ARGV[0];
    push(@{$inputfiles}, $infile);
    check_inputs($inputfiles);
    
    my $log = qx/$bins{'PDB4AMBER'} $infile 2>&1/;
    print ISALOG $log;
    
    # cerco il file convertito e lo rinomino
    opendir (PWD, $workdir);
    my @list = readdir PWD;
    closedir PWD;
    my ($outfile) = grep(/amber.pdb$/, @list);
    qx/mv $outfile ISABELtmp.initial_structure.pdb/;
    
    print "done\n";
}

MINIMIZATION: {
    message(sprintf("%s minimizing the structure...", clock()));
    
    my $infile1 = "$workdir/ISABELtmp.initial_structure.pdb";
    my $infile2 = "$workdir/ISABELtmp.tleap.in";
    my $infile3 = "$workdir/ISABELtmp.mini.in";
    
    # input check from previous stage
    push(@{$inputfiles}, $infile1);
    check_inputs($inputfiles);
    
    # topology script
    my  $tleap_script = <<ROGER
set default PBRadii mbondi2
source leaprc.ff99SB
REC = loadpdb $infile1
check REC
solvateOct REC TIP3PBOX 10.0
addIons REC Na+ 0
addIons REC Cl- 0
saveamberparm REC ISABELtmp.prot.prmtop ISABELtmp.prot.inpcrd
quit 
ROGER
    ;
    open(INI, '>' . $infile2);
    print INI $tleap_script;
    close INI;
    
    # minimization script
    my $ini_script = <<ROGER
Minimisation: backbone w/ position restraints (120 kcal/molA)
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1,
 ntr = 1,
 restraint_wt = 120.0,
 restraintmask = '\@N,CA,C,O,CB',
 cut = 8.0
&end

ROGER
    ;
    open(INI, '>' . $infile3);
    print INI $ini_script;
    close INI;
    
    my $log;
    # allestisco la topologia
    $log = qx/$bins{'TLEAP'} -f $infile2/;
    print ISALOG $log;
    # lancio la minimizzazione
    $log = qx/$bins{'SANDER'} -O -i $infile3 -p ISABELtmp.prot.prmtop -c ISABELtmp.prot.inpcrd -ref ISABELtmp.prot.inpcrd -r ISABELtmp.prot.min.inpcrd -o ISABELtmp.prot.min.mdout/;
    print ISALOG $log;
    
    print "done\n";
}

MMGBSA: {
    message(sprintf("%s performing MM-GBSA calculation...", clock()));
    
    my $infile1 = "$workdir/ISABELtmp.prot.prmtop";
    my $infile2 = "$workdir/ISABELtmp.prot.min.inpcrd";
    my $infile3 = "$workdir/ISABELtmp.dry.prmtop";
    my $infile4 = "$workdir/ISABELtmp.MMGBSA.in";
    
    # input check from previous stage
    push(@{$inputfiles}, $infile1, $infile2);
    check_inputs($inputfiles);
    
    # creo una topologia desolvatata della proteina
    my $cmd = "$bins{'ANTEMMPBSA'} -p $infile1 -c $infile3 -s \":WAT,Cl-,Na+\"; ";
    $cmd .=  "$bins{'AMBPDB'} -p $infile1 < $infile2 > ISABEL.minimized.pdb; ";
    
    # creo uno script di input per MMGBSA
    my $script = <<ROGER
Input file for GB calculation
&general
 verbose = 2,
 entropy = 0,
 keep_files = 0,
/
&gb
 igb = 5,
/
&decomp
 dec_verbose = 2,
 idecomp = 3,
/
ROGER
    ;
    open(IN, '>' . $infile4);
    print IN $script;
    close IN;
    
    # accodo il comando per lanciare MMPBSA
    $cmd .= "$bins{'MMPBSA'} -O  -i $infile4 -sp $infile1 -cp $infile3 -y $infile2";
    
    # lancio il calcolo
    my $log = qx/$cmd 2>&1/;
    print ISALOG $log;
    print "done\n";
}

BRENDA: {
    message(sprintf("%s extracting energy determinants...", clock()));
    
    # input check from previous stage
    my $infile = "$workdir/FINAL_DECOMP_MMPBSA.dat";
    push(@{$inputfiles}, $infile);
    check_inputs($inputfiles);
    
    # rinomino gli output di MMGBSA
    my $cleansweep = <<ROGER
cd $workdir;
mv FINAL_RESULTS_MMPBSA.dat ISABEL.RESULTS_MMPBSA.dat
mv FINAL_DECOMP_MMPBSA.dat ISABEL.DECOMP_MMPBSA.dat
ROGER
    ;
    qx/$cleansweep/;
    
    my $log = qx/$bins{'BRENDA'} ISABEL.DECOMP_MMPBSA.dat -filter $filter 2>&1/;
    print ISALOG $log;
    print "done\n"
}

CLEANSWEEP: {
    # input check from previous stage
    my $infile = $ARGV[0];
    push(@{$inputfiles}, $infile);
    check_inputs($inputfiles);

    printf("%s cleaning intermediate files...", clock());
    qx/rm -rfv ISABELtmp.*/;
    qx/rm -rfv leap.log mdinfo/;
}

FINE: {
    close ISALOG;
    print "\n\n*** LEBASI ***\n";
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

sub message {
    my ($string) = @_;
    print $string;
    print ISALOG "\n\n*** $string ***\n\n";
}

sub check_inputs {
    my ($input_list) = @_;
    while (my $input = shift @{$input_list}) {
        unless (-e $input) {
            croak(sprintf("\nE- input file <$input> for this stage not found, pipeline aborted\n\t"));
        }
    }
}
