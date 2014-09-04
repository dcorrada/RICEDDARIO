#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 14.7.b        - added physiological salt concentration (0.154 M)
#
# release 14.7.a        - treatment of systems containing small ligand
#
# release 14.6.a        - code completely revisited, new options and format of 
#                         the file produced
#                       - the major steps of the workflow are now committed by
#                         indipendent scripts (vide infra)
#                       - compliant with AMBER14
#                       - changed minimization protocol
#                       - new pre-processing approach for PDB files (PDB4AMBER 
#                         release 14.5.a)
#                       - new eigendecomposition approach based on MMPBSA.py, 
#                         instead of mm_pbsa.pl (BRENDA release 14.6.a)
#                       - calculations based on AMBER fofrcefield ff99SB, 
#                         instead of ff03
#
# release 14.4.*        - updated config file
#                       - PDB re-format directives for AMBER software
#
# release 14.3.*        - initial release
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

## GLOBS ##
our $workdir = getcwd();
our $logfile = "$workdir/ISABEL.log";
our $inputfiles = [ ];
our $filter = 4;
our $auto = 1;
our $ligand;
our $verbose;
our %bins;
our $cbrange = 0.1;
our $forcefield = 'ff99SB';
our %ff = ( 
            'ff99SB'    => 'leaprc.ff99SB',
            'ff03.r1'   => 'leaprc.ff03.r1'
          );
## SBLOG ##

USAGE: {
    my $splash = <<ROGER
********************************************************************************
ISABEL - ISabel is Another BEppe Layer
release 14.7.b

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

ROGER
    ;
    print $splash;
    
    use Getopt::Long;no warnings;
    GetOptions('auto|a=i' => \$auto, 'verbose|v' => \$verbose, 'filter|f=i' => \$filter, 'ligand|l=s' => \$ligand, 'forcefield|f=s' => \$forcefield, 'range|r=f' => \$cbrange);
    unless ($ARGV[0]) {
        my $help = <<ROGER
ISABEL is a Perl script which offers an automated pipeline for:

    1) performing MM-GBSA calculation from a structure file;

    2) calulating the interaction energy matrix through Energy Decomposition 
       Analysis;
    
    3) extracting the energetic determinants through the Principal Component 
       Analysis over the interaction energy matrix.

RELEASE NOTES: see the header in the source code.

For further theoretical details and in order to use this program please cite the 
following references:

[1] Tiana G, Simona F, De Mori G, Broglia R, Colombo G. 
    Protein Sci. 2004;13(1):113-24
[2] Corrada D, Colombo G.
    J Chem Inf Model. 2013;53(11):2937-50
[3] Genoni A, Morra G, Colombo G. 
    J Phys Chem B. 2012;116(10):3331-43
[4] Miller B, McGee T, Swails J, Homeyer N, Gohlke H, Roitberg A. 
    J Chem Theory Comput. 2012;8(9):3314-21

*** REQUIRED SOFTWARE ***

The tools flagged with (*) are already packaged with the current release of 
RICEDDARIO.

ISABEL
├── PDB4AMBER 14.5.a (*)
├── AMBER 12 or higher
│   └── AMBER Tools compliant version
└── BRENDA 14.8.a (*)
    ├── BLOCKS 11.5 (*)
    ├── GnuPlot 4.4.4 or higher
    └── R 2.10.0 or higher

*** SYNOPSIS ***

    # standard usage
    \$ ISABEL.pl protein.pdb
    
    # a protein complexed with a small ligand
    \$ ISABEL.pl protein.pdb -lig ligand
    
    # changing default parameters
    \$ ISABEL.pl protein.pdb -auto 0 -filter 2 -forcefield ff03.r1

*** OPTIONS ***

    -forcefield <string>  specify the forcefield, avalaible options:
                          ff03.r1 - Duan et al., 2003
                          ff99SB  - Hornak et al., 2006 (DEFAULT)
    
    -ligand <string>      specify if your system will contain a small molecule, 
                          the string identify the name prefix for .mol2 and 
                          .frcmod files (e.g: "ligand" refers to files 
                          <ligand.mol2> and <ligand.frcmod>)
    
    -auto <integer>       method of eigenvector selection:
                          0 - select only the first eigenvector, see also [1]
                          1 - DEFAULT, use BLOCKS for estimating the 
                              significant eigenvectors, see also [3]
                          2 - collects the first n eigenvectors until a 
                              threshold of cumulated variance is reached (0.75)
    
    -range <float>        energy threshold to normalize the plot of interaction 
                          energy matrix, in kcal/mol (DEFAULT: 0.1)
    
    -filter <integer>     number of contig residues for which interaction energy 
                          will not considered (DEFAULT: 4)
    
    -verbose              keep intermediate files

*** INPUT FILES ***

    ----------------------------------------------------------------------------
     FILE                     DESCRIPTION
    ----------------------------------------------------------------------------
     protein.pdb              the protein structure file in PDB format, it must
                              be correctly protonated; in case of complex with 
                              small molecule (-ligand option) this file 
                              identifies ONLY the receptor molecule
     
     ligand.mol2              required with -ligand option, the small molecule 
                              structure file in MOL2 format obtained by a 
                              pre-processing step performed with antechamber
    
     ligand.frcmod            required with -ligand option, ligand topology 
                              checked by parmchk
    ----------------------------------------------------------------------------

*** OUTPUT FILES ***

    ----------------------------------------------------------------------------
     FILE                     DESCRIPTION
    ----------------------------------------------------------------------------
     ISABEL.log               logfile from the standard output
     
     ISABEL.minimized.pdb     solvated and minimized structure file
     
     FINAL_RESULTS_MMPBSA.dat summary of MM-GBSA calculation
     
     FINAL_DECOMP_MMPBSA.dat  summary of Energy Decomposition Analysis
     
     BRENDA.IMATRIX.csv       interaction energy matrix
     
     BRENDA.PROFILE.dat       profile of the main energetic determinants
                              extracted from the Principal Components Analysis
     
     BRENDA.IMATRIX.png       image of the interaction energy matrix, with the 
                              profile of the main energetic determinants
    ----------------------------------------------------------------------------
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
    
    # check del forcefield
    croak "E- unable to find [$forcefield] forcefield\n\t" unless (exists $ff{$forcefield});
}

PDBCONVERSION: {
    message(sprintf("%s converting PDB to AMBER compliant format...", clock()));
    
    # input check
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
    qx/mv $outfile _ISABEL.REC.pdb/;
    
    print "done\n";
}

TOPOLOGY: {
    message(sprintf("%s preparing the topology...", clock()));
    
    my $infile1 = "$workdir/_ISABEL.REC.pdb";
    my $infile2 = $infile1;
    my $infile3 = $infile1;
    if ($ligand) {
        $infile2 = "$workdir/$ligand.mol2";
        $infile3 = "$workdir/$ligand.frcmod";
    };
    my $infile4 = "$workdir/_ISABEL.tleap.in";
    
    # input check
    push(@{$inputfiles}, $infile1, $infile2, $infile3);
    check_inputs($inputfiles);
    
    # in testa scrivo il forcefield che adotterò
    my $tleap_script = <<ROGER
set default PBRadii mbondi2
source $ff{$forcefield}
ROGER
    ;
    # a seconda che il ilgando ci sia o no l'input script sarà diverso
    if ($ligand) {
        $tleap_script .= <<ROGER
source leaprc.gaff
loadamberparams $infile3
loadoff vacuo.lig.lib
REC = loadpdb $infile1
LIG = loadmol2 $infile2
COM = combine {REC LIG}
solvateOct COM TIP3PBOX 10.0
addIons COM Na+ 0
addIons COM Cl- 0
charge COM
saveamberparm COM _ISABEL.solvated.prmtop _ISABEL.solvated.inpcrd
quit
ROGER
        ;
    } else {
        $tleap_script .= <<ROGER
REC = loadpdb $infile1
check REC
solvateOct REC TIP3PBOX 10.0
addIons REC Na+ 0
addIons REC Cl- 0
saveamberparm REC _ISABEL.solvated.prmtop _ISABEL.solvated.inpcrd
quit
ROGER
        ;
    }
    
    # scrivo l'input script per la topologia
    open(INI, '>' . $infile4);
    print INI $tleap_script;
    close INI;
    
    my $log;
    # allestisco la topologia
    $log = qx/$bins{'TLEAP'} -f $infile4/;
    print ISALOG $log;
    
    print "done\n";
}

MINIMIZATION: {
    message(sprintf("%s minimizing the structure...", clock()));
    
    my $infile1 = "$workdir/_ISABEL.solvated.prmtop";
    my $infile2 = "$workdir/_ISABEL.solvated.inpcrd";
    my $infile3 = "$workdir/_ISABEL.mini.in";
    
    # input check from previous stage
    push(@{$inputfiles}, $infile1, $infile2);
    check_inputs($inputfiles);
    
    my $ligname = '';
    if ($ligand) {
        open(TRIPPA, "<$workdir/$ligand.mol2");
        my @content = <TRIPPA>;
        close TRIPPA;
        my $astring = join('', @content);
        ($ligname) = $astring =~ m/\@<TRIPOS>SUBSTRUCTURE\n[\s\d]+(\w{3})/g;
        $ligname = '| :' . $ligname;
    }
    
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
 restraintmask = '\@N,CA,C,O,CB $ligname ',
 cut = 8.0
&end

ROGER
    ;
    open(INI, '>' . $infile3);
    print INI $ini_script;
    close INI;
    
    my $log;
    # lancio la minimizzazione
    $log = qx/$bins{'SANDER'} -O -i $infile3 -p $infile1 -c $infile2 -ref $infile2 -r _ISABEL.minimized.inpcrd -o _ISABEL.minimized.mdout/;
    print ISALOG $log;
    
    print "done\n";
}

MMGBSA: {
    message(sprintf("%s performing MM-GBSA calculation...", clock()));
    
    my $infile1 = "$workdir/_ISABEL.solvated.prmtop";
    my $infile2 = "$workdir/_ISABEL.minimized.inpcrd";
    my $infile3 = "$workdir/_ISABEL.dry.prmtop";
    my $infile4 = "$workdir/_ISABEL.MMGBSA.in";
    
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
 keep_files = 2,
/
&gb
 igb = 5,
 saltcon = 0.154,
/
&decomp
 csv_format = 0,
 dec_verbose = 3,
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
    
    my $log = qx/$bins{'BRENDA'} $infile -filter $filter -auto $auto -range $cbrange -verbose 2>&1/;
    print ISALOG $log;
    print "done\n"
}

CLEANSWEEP: {
    unless ($verbose) {
        printf("%s cleaning intermediate files...", clock());
        qx/rm -rfv _ISABEL*/;
        qx/rm -rfv _BRENDA*/;
        qx/rm -rfv _MMPBSA*/;
        qx/rm -rfv leap.log mdinfo/;
    }
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
