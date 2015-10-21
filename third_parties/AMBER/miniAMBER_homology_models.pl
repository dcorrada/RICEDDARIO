#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.10.a        - initial release
#
# ##############################################################################

use strict;
use warnings;
use Carp;

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

## GLOBS ##
our $workdir = getcwd();
our $basepath = $workdir . '/';
our $AMBERHOME = $ENV{'AMBERHOME'};
our $mpi = 4;
our $ligprefix = 'null';
our %bins = ( # file binari
    'tleap'     =>  $AMBERHOME . '/bin/tleap',
    'sander'    =>  $AMBERHOME . '/bin/pmemd.MPI',
    'mpirun'    =>  qx/which mpirun/
);
our $ligname;
our $pmemd_enhance = 'mpi';
our $boxtype = 'oct';
## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    GetOptions('pmemd=s' => \$pmemd_enhance, 'mpi=i' => \$mpi, 'lig=s' => \$ligprefix, 'box=s' => \$boxtype);
    
    my $splash = <<END
********************************************************************************
miniAMBER for homology models
release 15.10.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
END
    ;
    print $splash;
    
    my $usage = <<END

*** WARNING *** 
Since the calculations for heating and equilibration are quite demanding this 
script run only with MPI or CUDA implementation of pmemd program.

This script is aimed to perform all the preparatory steps in order to set up a 
classical full atom molecular dynamics in explicit solvent (ie protein, also 
with a small molecule ligand, plus TIP3P water and counterions in a 10A box).

This script is a variant of the original miniAMBER, dedicated to sensitive 
systems like homology models. The main steps of the workflow are:

    A) PRE-PROCESSING, performed by the user prior to launch this script. The 
       receptor/protein molecule needs to be pre-processed in a pdb format 
       compliant with AMBER (maybe you want to use 'PDB4AMBER.pl' tool). 
       Moreover, if you plan to submit a complex system you must pre-process 
       the ligand small molecule with antechamber/parmcheck AMBER tools.
    
    B) TOPOLOGY, launching tleap to obtain parameters and coordinate files of 
       receptor, ligamd and complex systems.
    
    C) MINIMIZATION, multistep (4 stages) with sequential position restraints 
       (500 kcal/(mol A)), 500 steps steepest descent + 1500 coniugated gradient 
    
    D) HEATING, in NVT ensemble from 0 to 100K (100ps, dt 2fs) protein backbone 
       position restraints (4 kcal/(mol A))
    
    E) HEATING, in NPT ensemble from 100 to 300K (250ps, dt 2fs) protein backbone 
       position restraints (1 kcal/(mol A))
    
    F) EQUILIBRATION, in NPT ensemble at 300K (750ps, dt 2fs) protein backbone 
       position restraints (1 kcal/(mol A))
    
    G) EQUILIBRATION, in NPT ensemble at 300K (1,000ps, dt 2fs) with no restraint
    
SYNOPSIS
    
    \$ miniAMBER.pl protein.pdb                 # protein preparation
    
    \$ miniAMBER.pl protein.pdb  -lig ligand    # complex preparation
    
    \$ miniAMBER.pl protein.pdb  -mpi 2         # parallelized jobs
    
    \$ miniAMBER.pl protein.pdb  -pmemd cuda    # use CUDA

OPTIONS
    
    -lig <string>         use small molecule ligand, the string identify the name 
                          prefix for .mol2 and .frcmod files (e.g: "ligand" refers 
                          to files <ligand.mol2> and <ligand.frcmod>)
    
    -mpi <integer>        only for MPI implementation of pmemd, number of threads
                          required (default: $mpi)
    
    -box <"cubic|oct">    type of solvation box, cubic or octahedron (default: $boxtype)
    
    -pmemd <"cuda|mpi">   implementation of pmemd (default: $pmemd_enhance)
END
    ;
    unless ($ARGV[0]) {
        print $usage;
        goto FINE;
    }
}

INIT: {
    
    # se AMBER implementa CUDA lo uso altrimenti ricorro all'MPI
    if ($pmemd_enhance eq 'cuda') {
        $bins{'sander'} = $AMBERHOME . '/bin/pmemd.cuda';
    } elsif ($pmemd_enhance eq 'mpi') {
        chomp $bins{'mpirun'};
        $mpi = $bins{'mpirun'} . " -np $mpi ";
        $bins{'sander'} = $mpi . $bins{'sander'};
    } else {
        croak "\nE- no suitable version of pmemd (CUDA or MPI) found, aborting\n\t";
    }
    printf("\nI- using <%s>\n", $bins{'sander'});
    
    # verifico che esista il recettore
    unless (-e $ARGV[0]) {
        croak "\nE- file <$ARGV[0]> not found\n\t";
    }
    
    # verifico se esiste il ligando e come si chiama
    unless ($ligprefix eq 'null') {
        foreach my $postifx ('.mol2', '.frcmod') {
            my $filename = $ligprefix . $postifx;
            if (-e $filename) {
                next;
            } else {
                croak "\nE- file <$filename> not found\n\t";
            }
        }
        open(TRIPPA, "<$ligprefix.mol2");
        my @content = <TRIPPA>;
        close TRIPPA;
        my $astring = join('', @content);
        ($ligname) = $astring =~ m/\@<TRIPOS>SUBSTRUCTURE\n[\s\d]+(\w{3})/g;
    }
    
    # boxtype
    if ($boxtype eq "oct") {
        $boxtype = 'solvateOct';
    } elsif ($boxtype eq "cubic") {
        $boxtype = 'solvateBox';
    } else {
        croak "\nE- boxtype [$boxtype] unkown\n\t";
    }
    
    
}

TLEAPS: {
    my $tleap_script;
    
    # copio i file di input
    mkdir 'TOPOLOGY';
    $workdir = $basepath . 'TOPOLOGY';
    unless ($ligprefix eq 'null') {
        qx/cp $ligprefix.mol2 $workdir\//;
        qx/cp $ligprefix.frcmod $workdir\//;
    }
    qx/cp $ARGV[0] $workdir\//;
    
    if ($ligprefix eq 'null') {
        # preparo il tleap per la proteina
        $tleap_script = <<END
set default PBRadii mbondi2                             # atomic radii for GB calculations
source leaprc.ff14SB                                    # load AMBER force field
source leaprc.gaff                                      # load GAFF forcefield
loadamberparams frcmod.ionsjc_tip3p                     # parametrization for counterions
REC = loadpdb $ARGV[0]                                  # load molecule (processed with PDB4AMBER.pl)
check REC                                               # check unit for internal inconsistencies
saveamberparm REC dry.prmtop dry.inpcrd                 # save UNIT and PARMSET
$boxtype REC TIP3PBOX 10.0                              # solvating box
addIons REC Na+ 0                                       # add counterions
addIons REC Cl- 0                                       
charge REC                                              # checking net charge
saveamberparm REC solvated.prmtop solvated.inpcrd       # save solvated UNIT and PARMSET
savepdb REC solvated.pdb                                # export the solvated system in pdb format
quit 
END
        ;
    } else {
        # preparo il tleap per il complesso
        $tleap_script = <<END
set default PBRadii mbondi2
source leaprc.ff14SB
source leaprc.gaff
loadamberparams frcmod.ionsjc_tip3p
loadamberparams $ligprefix.frcmod
loadoff vacuo.lig.lib                                   # load Object file for ligand
REC = loadpdb $ARGV[0]                                  # load receptor (processed with PDB4AMBER.pl)
LIG = loadmol2 $ligprefix.mol2                          # load ligand (processed with antechamber)
COM = combine {REC LIG}                                 # complexing receptor and ligand
saveamberparm COM dry.prmtop dry.inpcrd
$boxtype COM TIP3PBOX 10.0
addIons COM Na+ 0
addIons COM Cl- 0
charge COM
saveamberparm COM solvated.prmtop solvated.inpcrd
savepdb COM solvated.pdb
quit
END
        ;
    }
    
    open(CALIPPO, ">$workdir/tleap.in");
    print CALIPPO $tleap_script;
    close CALIPPO;
    printf("%s TLEAPS\n", clock());
    my $cmd = "cd $workdir; $bins{'tleap'} -f tleap.in";
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    printf("%s TLEAPS terminated\n", clock());
}

MINIMIZATION: {
    my $sander_stage1;
    my $sander_stage2;
    my $sander_stage3;
    my $sander_stage4;
    my $cmd;
    
    # copio i file di input
    mkdir 'MINIMIZATION';
    $workdir = $basepath . 'MINIMIZATION';
    qx/cp TOPOLOGY\/solvated.prmtop $workdir\//;
    qx/cp TOPOLOGY\/solvated.inpcrd $workdir\//;
    
    # input files per la minimizzazione
    $sander_stage1 = <<END
Minimisation Stage 1: solvent + ions - Holding the solute fixed
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1, ntp = 0,
 ntr = 1,
 restraint_wt = 500.0,
 restraintmask = '!:WAT',
 cut = 10
/
END
    ;
    $sander_stage3 = <<END
Minimisation Stage 3: solute atoms - Holding solvent + ions fixed
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1,
 ntr = 1,
 restraint_wt=500.0,
 restraintmask=':WAT,Na+,Cl-',
 cut = 10
/
END
    ;
    $sander_stage4 = <<END
Minimisation Stage 4: all atoms - no restraints
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1,
 cut = 10
/
END
        ;
    
    # aggiunta di restraint al ligando
    if ($ligprefix eq 'null') {
        $sander_stage2 = <<END
Minimisation Stage 2: sidechain atoms - Holding backbone, solvent + ions fixed
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1,
 ntr = 1,
 restraint_wt=500.0,
 restraintmask='\@N,CA,C,O,CB | :WAT,Na+,Cl-',
 cut = 10
/
END
        ;
    } else {
        $sander_stage2 = <<END
Minimisation Stage 2: sidechain atoms - Holding backbone, solvent + ions fixed
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1,
 ntr = 1,
 restraint_wt=500.0,
 restraintmask='\@N,CA,C,O,CB | :WAT,Na+,Cl-,$ligname',
 cut = 10
/
END
        ;
    }
    
    open(SANDRO, ">$workdir/mini_stage1.in");
    print SANDRO $sander_stage1;
    close SANDRO;
    
    open(SANDRO, ">$workdir/mini_stage2.in");
    print SANDRO $sander_stage2;
    close SANDRO;
    
    open(SANDRO, ">$workdir/mini_stage3.in");
    print SANDRO $sander_stage3;
    close SANDRO;
    
    open(SANDRO, ">$workdir/mini_stage4.in");
    print SANDRO $sander_stage4;
    close SANDRO;
    
    # lancio la minimizzazione
    printf("%s MINIMIZATION\n", clock());
    
    print"\tStage 1: solvent + ions - Holding the solute fixed\n";
    $cmd = "cd $workdir; $bins{'sander'} -O -i mini_stage1.in -o mini_stage1.mdout -p solvated.prmtop -c solvated.inpcrd -r mini_stage1.rst7 -ref solvated.inpcrd -inf mdinfo";
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    
    print"\tStage 2: sidechain atoms - Holding backbone, solvent + ions fixed\n";
    $cmd = "cd $workdir; $bins{'sander'} -O -i mini_stage2.in -o mini_stage2.mdout -p solvated.prmtop -c mini_stage1.rst7 -r mini_stage2.rst7 -ref mini_stage1.rst7 -inf mdinfo";
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    
    print"\tStage 3: solute atoms - Holding solvent + ions fixed\n";
    $cmd = "cd $workdir; $bins{'sander'} -O -i mini_stage3.in -o mini_stage3.mdout -p solvated.prmtop -c mini_stage2.rst7 -r mini_stage3.rst7 -ref mini_stage2.rst7 -inf mdinfo";
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    
    print"\tStage 4: all atoms - no restraints\n";
    $cmd = "cd $workdir; $bins{'sander'} -O -i mini_stage4.in -o mini_stage4.mdout -p solvated.prmtop -c mini_stage3.rst7 -r mini_stage4.rst7 -ref mini_stage3.rst7 -inf mdinfo";
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    
    printf("%s MINIMIZATION terminated\n", clock());
}

HEATING: {
    my $sander_script;
    
    # copio i file di input
    mkdir 'HEATING';
    $workdir = $basepath . 'HEATING';
    qx/cp TOPOLOGY\/solvated.prmtop $workdir\//;
    qx/cp MINIMIZATION\/mini_stage4.rst7 $workdir\//;
    
    # input file per l'heating
    $sander_script = <<ROGER
Heating up the system in NVT ensemble (100 ps)
&cntrl
 imin = 0, ntx = 1,                     ! enable MD run with no initial velocity information
 ntb = 1, cut = 8.0,                    ! NVT ensemble at 8 angstrom cutoff
 ntp = 0,                               ! no barostat
 ntf = 2, ntc = 2,                      ! SHAKE algorithm with hydrogens constrained
 ntt = 3, gamma_ln = 1.0,               ! Langevin thermostat every 1.0ps
 tempi = 0.0,                           ! initial temperature of 0K
 nstlim = 50000, dt = 0.002,            ! 50,000 steps x 2fs = 100ps
 iwrap = 1,                             ! wrap coordinates to central box
 nscm = 1000,                           ! removal of translational and rotational center-of-mass every 1,000 steps
 ioutfm = 1,                            ! write output (mdcrd) in NetCDF format
 ntpr = 5000, ntwx = 5000,              ! write to mdout and mdcrd every 5,000 steps
 ntwr = 5000,                           ! write restart file every 5,000 steps
 ntr = 1, restraint_wt = 4.0,           ! restraint backbone atoms with 4.0 Kcal/mol/A
 restraintmask = '\@N,CA,C,O,CB',
 ig = 71277,                            ! random seed
 nmropt = 1,                            ! used to ramp temperature slowly (as follows)
/
&wt type='TEMP0', istep1=0, istep2=50000, value1=0.0, value2=100.0 /
&wt type='END' /
ROGER
    ;
    open(SANDRO, ">$workdir/eq.nvt.in");
    print SANDRO $sander_script;
    close SANDRO;
    
    # lancio la simulazione del recettore
    printf("%s HEATING\n", clock());
    my $cmd = "cd $workdir; $bins{'sander'} -O -i eq.nvt.in -o eq.nvt.mdout -p solvated.prmtop -c mini_stage4.rst7 -r eq.nvt.rst7 -x eq.nvt.nc -ref mini_stage4.rst7 -inf mdinfo";
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    printf("%s HEATING terminated\n", clock());
}

EQUILIBRATION: {
    my $sander_script;
    
    # copio i file di input
    mkdir 'EQUILIBRATION';
    $workdir = $basepath . 'EQUILIBRATION';
    qx/cp TOPOLOGY\/solvated.prmtop $workdir\//;
    qx/cp HEATING\/eq.nvt.rst7 $workdir\//;
    
    # input file per la equilibrazione
    $sander_script = <<ROGER
Equilibrating the system in NPT ensemble (heating for 250ps + 750ps at 300K)
&cntrl
 imin = 0, ntx = 5, irest= 1,           ! enable MD run reading coordinates and velocities from the restart
 ntb = 2, cut = 8.0,                    ! NPT ensemble at 8 angstrom cutoff
 ntp = 1, pres0 = 1.0,                  ! isotropic pressure scaling at 1 atm
 barostat=1,                            ! Berendsen barostat
 comp = 44.6,                           ! compressibility (units are 1.0E-06 bar-1)
 taup = 2,                              ! pressure coupling every 2 ps
 ntf = 2, ntc = 2,                      ! SHAKE algorithm with hydrogens constrained
 ntt = 3, gamma_ln = 1.0,               ! Langevin thermostat every 1.0ps
 temp0 = 300.0,                         ! reference temperature at 300K
 nstlim = 500000, dt = 0.002,           ! 500,000 steps x 2fs = 1ns
 iwrap = 1,                             ! wrap coordinates to central box
 nscm = 1000,                           ! removal of translational and rotational center-of-mass every 1,000 steps
 ioutfm = 1,                            ! write output (mdcrd) in NetCDF format
 ntpr = 5000, ntwx = 5000,              ! write to mdout and mdcrd every 5,000 steps
 ntwr = 5000,                           ! write restart file every 5,000 steps
 ntr = 1, restraint_wt = 1.0,           ! restraint backbone atoms with 1.0 Kcal/mol/A
 restraintmask = '\@N,CA,C,O,CB',
 ig = 71277,                            ! random seed
 nmropt = 1,                            ! used to ramp temperature slowly (as follows)
/
&wt type='TEMP0', istep1=0, istep2=125000, value1=100.0, value2=300.0 /
&wt type='TEMP0', istep1=125001, istep2=500000, value1=300.0, value2=300.0 /
&wt type='END' /
ROGER
    ;
    open(SANDRO, ">$workdir/eq.npt.in");
    print SANDRO $sander_script;
    close SANDRO;
    
    # lancio la simulazione del recettore
    printf("%s EQUILIBRATION\n", clock());
    my $cmd = "cd $workdir; $bins{'sander'} -O -i eq.npt.in -o eq.npt.mdout -p solvated.prmtop -c eq.nvt.rst7 -r eq.npt.rst7 -x eq.npt.nc  -ref eq.nvt.rst7 -inf mdinfo";
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    printf("%s EQUILIBRATION terminated\n", clock());
}

RELAXATION: {
    my $sander_script;
    
    # copio i file di input
    mkdir 'RELAXATION';
    $workdir = $basepath . 'RELAXATION';
    qx/cp TOPOLOGY\/solvated.prmtop $workdir\//;
    qx/cp EQUILIBRATION\/eq.npt.rst7 $workdir\//;
    
    # input file per la equilibrazione
    $sander_script = <<ROGER
Equilibrating the system in NPT ensemble (1000ps at 300K, no restraint)
&cntrl
 imin = 0, ntx = 5, irest= 1,           ! enable MD run reading coordinates and velocities from the restart
 ntb = 2, cut = 8.0,                    ! NPT ensemble at 8 angstrom cutoff
 ntp = 1, pres0 = 1.0,                  ! isotropic pressure scaling at 1 atm
 barostat=1,                            ! Berendsen barostat
 comp = 44.6,                           ! compressibility (units are 1.0E-06 bar-1)
 taup = 2,                              ! pressure coupling every 2 ps
 ntf = 2, ntc = 2,                      ! SHAKE algorithm with hydrogens constrained
 ntt = 3, gamma_ln = 1.0,               ! Langevin thermostat every 1.0ps
 temp0 = 300.0,                         ! reference temperature at 300K
 nstlim = 500000, dt = 0.002,           ! 500,000 steps x 2fs = 1ns
 iwrap = 1,                             ! wrap coordinates to central box
 nscm = 1000,                           ! removal of translational and rotational center-of-mass every 1,000 steps
 ioutfm = 1,                            ! write output (mdcrd) in NetCDF format
 ntpr = 5000, ntwx = 5000,              ! write to mdout and mdcrd every 5,000 steps
 ntwr = 5000,                           ! write restart file every 5,000 steps
 ntr = 0,                               ! no restraint
 ig = 71277,                            ! random seed
/
ROGER
    ;
    open(SANDRO, ">$workdir/relax.in");
    print SANDRO $sander_script;
    close SANDRO;
    
    # lancio la simulazione del recettore
    printf("%s RELAXATION\n", clock());
    my $cmd = "cd $workdir; $bins{'sander'} -O -i relax.in -o relax.mdout -p solvated.prmtop -c eq.npt.rst7 -r relax.rst7 -x relax.nc  -ref eq.npt.rst7 -inf mdinfo";
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    printf("%s RELAXATION terminated\n", clock());
}

FINE: {
    print "\n\n*** REBMAinim ***\n";
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