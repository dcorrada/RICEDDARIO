#!/usr/bin/perl
# -d

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
use threads;

## GLOBS ##
our $workdir = getcwd();
our $basepath = $workdir . '/';
our $AMBERHOME = $ENV{'AMBERHOME'};
our $mpi = 'null';
our $ligprefix = 'null';
our %bins = ( # file binari
    'tleap'     =>  $AMBERHOME . '/bin/tleap',
    'sander'    =>  $AMBERHOME . '/bin/pmemd',
    'mpirun'    =>  qx/which mpirun/
);
our @thr;
our $ligname;
our $ligsander = $bins{'sander'};
our $boxtype = 'oct';
## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    GetOptions('mpi=i' => \$mpi, 'lig=s' => \$ligprefix, 'box' => \$boxtype);
    my $usage = <<END
********************************************************************************
miniAMBER
release 14.5.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

This script is aimed to perform all the preparatory steps in order to set up a 
classical full atom moleclular dynamics in explicit solvent (ie protein, also 
with a small molecule ligand, plus TIP3P water and counterions in a 10A 
truncated octahedron box).

The main steps of the workflow are:

    A) PRE-PROCESSING, performed by the user prior to launch this script. The 
       receptor/protein molecule needs to be pre-processed in a pdb format 
       compliant with AMBER (maybe you want to use 'PDB4AMBER.pl' tool). 
       Moreover, if you plan to submit a complex system you must pre-process 
       the ligand small molecule with antechamber/parmcheck AMBER tools.
    
    B) TOPOLOGY, launching tleap to obtain parameters and coordinate files of 
       receptor, ligamd and complex systems.
    
    C) MINIMIZATION, protein backbone and ligand position restraints 
       (500 kcal/molA), 500 steps steepest descent + 1500 coniugated gradient 
    
    D) HEATING, in NVT ensemble to 300K (10ps, dt 2fs)
    
    E) EQUILIBRATION, in NPT ensemble at 300K (100ps, dt 2fs)
    
SYNOPSIS
    
    \$ miniAMBER.pl protein.pdb                 # single protein preparation
    
    \$ miniAMBER.pl protein.pdb  -mpi 2         # parallelized jobs(*)
    
    \$ miniAMBER.pl protein.pdb  -lig ligand    # receptor/ligand preparation

(*)In the case of receptor/ligand systems the script launches three concurrent 
jobs at a time (for receptor, ligand and complex respectively). Therefore, the 
number of the threads required with the '-mpi' should be finely tuned.

OPTIONS
    
    -lig <string>       use small molecule ligand, the string identify the name 
                        prefix for .mol2 and .frcmod files (e.g: "ligand" refers 
                        to files <ligand.mol2> and <ligand.frcmod>)
    
    -mpi <integer>      use mpirun, you must specify the number of threads
                        required
    
    -box <"cubic|oct">  type of solvation box, cubic or octahedron (default)
END
    ;
    unless ($ARGV[0]) {
        print $usage;
        goto FINE;
    }
}

INIT: {
    my $splash = <<END
********************************************************************************
miniAMBER
release 14.5.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
END
    ;
    print $splash;
    
    # verifico che i binari ci siano tutti
    chomp $bins{'mpirun'};
    foreach my $key (keys %bins) {
        if (-e $bins{$key}) {
            next;
        } else {
            croak "\nE- file <$bins{$key}> not found\n\t";
        }
    }
    
    # verifico se l'opzione mpi è abilitata
    unless ($mpi eq 'null') {
        $mpi = $bins{'mpirun'} . " -np $mpi ";
        my $sandermpi = $bins{'sander'} . '.MPI';
        if (-e $sandermpi) {
            $bins{'sander'} = $mpi . $sandermpi;
        } else {
            print "\nW- file <$sandermpi> not found, '-mpi' option disabled\n";
            $mpi = 'null';
        }
    }
    
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
    } elsif ($boxtype eq "oct") {
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
    
    my $logfile = $workdir . '/miniAMBER.log';
    open(LEGO, ">$logfile");
    my $log;
    
    # preparo il tleap per la proteina
    $tleap_script = <<END
set default PBRadii mbondi2                             # atomic radii for GB calculations
source leaprc.ff99SB                                    # load AMBER force field
source leaprc.gaff                                      # load GAFF forcefield
REC = loadpdb $ARGV[0]                                  # load molecule (processed with PDB4AMBER.pl)
check REC                                               # check unit for internal inconsistencies
$boxtype REC TIP3PBOX 10.0                            # solvating box
addIons REC Na+ 0                                       # add counterions
addIons REC Cl- 0                                       # add counterions
saveamberparm REC solv.rec.prmtop solv.rec.inpcrd       # save solvated UNIT and PARMSET
savepdb REC solv.rec.pdb                                # export the solvated system in pdb
quit 
END
    ;
    open(CALIPPO, ">$workdir/tleap.rec.in");
    print CALIPPO $tleap_script;
    close CALIPPO;
    printf("%s TLEAPS receptor\n", clock());
    $log = qx/cd $workdir; $bins{'tleap'} -f tleap.rec.in/;
    print LEGO "*** RECEPTOR ***\n$log";
    
    unless ($ligprefix eq 'null') { # solo se ho un ligando...
        # preparo il tleap per il ligando
        $tleap_script = <<END
set default PBRadii mbondi2                             # atomic radii for GB calculations
source leaprc.ff99SB                                    # load AMBER force field
source leaprc.gaff                                      # load GAFF forcefield
LIG = loadmol2 $ligprefix.mol2                          # load molecule (processed with antechamber)
check LIG                                               # check unit for internal inconsistencies
loadamberparams $ligprefix.frcmod                       # load extensions to GAFF forcefield (processed with parmcheck)
saveOff LIG vacuo.lig.lib                               # save vacuo UNITs and PARMSETs to a Object File Format (off) file
$boxtype LIG TIP3PBOX 10.0                            # solvating box
addIons LIG Na+ 0                                       # add counterions
addIons LIG Cl- 0                                       # add counterions
saveamberparm LIG solv.lig.prmtop solv.lig.inpcrd       # save solvated UNIT and PARMSET
savepdb LIG solv.lig.pdb                                # export the solvated system in pdb
quit 
END
        ;
        open(CALIPPO, ">$workdir/tleap.lig.in");
        print CALIPPO $tleap_script;
        close CALIPPO;
        printf("%s TLEAPS ligand\n", clock());
        $log = qx/cd $workdir; $bins{'tleap'} -f tleap.lig.in/;
        print LEGO "\n\n*** LIGAND ***\n$log";
        
        # preparo il tleap per il complesso
        $tleap_script = <<END
set default PBRadii mbondi2                             # atomic radii for GB calculations
source leaprc.ff99SB                                    # load AMBER force field
source leaprc.gaff                                      # load GAFF forcefield
loadamberparams $ligprefix.frcmod                       # load extensions to GAFF forcefield (processed with parmcheck)
loadoff vacuo.lig.lib                                   # load Object file for ligand
REC = loadpdb $ARGV[0]                                  # load receptor (processed with PDB4AMBER.pl)
LIG = loadmol2 $ligprefix.mol2                          # load ligand (processed with antechamber)
COM = combine {REC LIG}                                 # complexing receptor and ligand
$boxtype COM TIP3PBOX 10.0                            # solvating box
addIons COM Na+ 0                                       # add counterions
addIons COM Cl- 0                                       # add counterions
charge COM                                              # checking net charge
saveamberparm COM solv.com.prmtop solv.com.inpcrd       # save solvated UNIT and PARMSET
savepdb COM solv.com.pdb                                # export the solvated system in pdb
quit
END
        ;
        open(CALIPPO, ">$workdir/tleap.com.in");
        print CALIPPO $tleap_script;
        close CALIPPO;
        printf("%s TLEAPS complex\n", clock());
        $log =qx/cd $workdir; $bins{'tleap'} -f tleap.com.in/;
        print LEGO "\n\n*** COMPLEX ***\n$log";
        
    }
    
    close LEGO;
}

MINIMIZATION: {
    my $sander_script;
    my $cmd;
    
    # copio i file di input
    mkdir 'MINIMIZATION';
    $workdir = $basepath . 'MINIMIZATION';
    qx/cp TOPOLOGY\/solv.*.prmtop $workdir\//;
    qx/cp TOPOLOGY\/solv.*.inpcrd $workdir\//;
    
    # minimizzazione recettore
    $sander_script = <<END
Minimisation: backbone w/ position restraints (500 kcal/molA)
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1,
 ntr = 1,
 restraint_wt = 500.0,
 restraintmask = '\@N,CA,C,O,CB',
 cut = 8.0
&end
END
    ;
    open(SANDRO, ">$workdir/min.rec.in");
    print SANDRO $sander_script;
    close SANDRO;
    
    # lancio la minimizzazione
    $cmd = "cd $workdir; $bins{'sander'} -O -i min.rec.in -p solv.rec.prmtop -c solv.rec.inpcrd -ref solv.rec.inpcrd -r min.rec.rst7 -o min.rec.mdout";
    printf("%s MINIMIZATION receptor started...\n", clock());
    push @thr, threads->new(\&launch_thr, $cmd, "MINIMIZATION receptor");
    
    unless ($ligprefix eq 'null') { 
        # minimizzazione del complesso
        $sander_script = <<END
Minimisation: backbone and ligand w/ position restraints (500 kcal/molA)
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1,
 ntr = 1,
 restraint_wt = 500.0,
 restraintmask = '\@N,CA,C,O,CB | :$ligname',
 cut = 8.0
&end
END
        ;
        
        open(SANDRO, ">$workdir/min.com.in");
        print SANDRO $sander_script;
        close SANDRO;
        
        $cmd = "cd $workdir; $bins{'sander'} -O -i min.com.in -p solv.com.prmtop -c solv.com.inpcrd -ref solv.com.inpcrd -r min.com.rst7 -o min.com.mdout";
        printf("%s MINIMIZATION complex started...\n", clock());
        push @thr, threads->new(\&launch_thr, $cmd, "MINIMIZATION complex");
        
        # minimizzazione del ligando
        $sander_script = <<END
Minimisation: ligand w/ position restraints (500 kcal/molA)
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 ntb = 1,
 ntr = 1,
 restraint_wt = 500.0,
 restraintmask = ':$ligname',
 cut = 8.0
&end
END
        ;
        
        open(SANDRO, ">$workdir/min.lig.in");
        print SANDRO $sander_script;
        close SANDRO;
        
        $cmd = "cd $workdir; $ligsander -O -i min.lig.in -p solv.lig.prmtop -c solv.lig.inpcrd -ref solv.lig.inpcrd -r min.lig.rst7 -o min.lig.mdout";
        printf("%s MINIMIZATION ligand started...\n", clock());
        push @thr, threads->new(\&launch_thr, $cmd, "MINIMIZATION ligand");
    }
    
    for (@thr) { $_->join() }; # attendo che le minimizzazioni finiscano
    undef @thr;
}

HEATING: {
    my $sander_script;
    my $cmd;
    
    # copio i file di input
    mkdir 'HEATING';
    $workdir = $basepath . 'HEATING';
    qx/cp TOPOLOGY\/solv.*.prmtop $workdir\//;
    qx/cp MINIMIZATION\/min.*.rst7 $workdir\//;
    
    # heating recettore
    $sander_script = <<END
Heating up the system in NVT ensemble (10 ps)
&cntrl
 imin = 0,
 irest= 0,
 ntpr = 500,
 ntwx = 500,
 ntwe = 500,
 ioutfm = 0,
 nstlim = 5000,
 dt = 0.002,
 nscm = 1000,
 ig = 71277,
 temp0 = 300.0,
 tempi = 100.0,
 ntt = 3,
 gamma_ln = 2.0,
 vlimit = 20.0,
 ntp = 0,
 ntc = 2,
 ntb = 1,
 ntf = 2,
 cut = 8.0,
 nsnb = 25,
 ipol = 0,
 igb = 0
&end

END
    ;
    open(SANDRO, ">$workdir/eq.nvt.in");
    print SANDRO $sander_script;
    close SANDRO;
    
    # lancio la simulazione del recettore
    $cmd = "cd $workdir; $bins{'sander'} -O -i eq.nvt.in -p solv.rec.prmtop -c min.rec.rst7 -r eq.nvt.rec.rst7 -o eq.nvt.rec.mdout -x eq.nvt.rec.mdcrd -e eq.nvt.rec.mden";
    printf("%s HEATING receptor started...\n", clock());
    push @thr, threads->new(\&launch_thr, $cmd, "HEATING receptor");
    
    unless ($ligprefix eq 'null') {
        # lancio la simulazione del ligando
        $cmd = "cd $workdir; $ligsander -O -i eq.nvt.in -p solv.lig.prmtop -c min.lig.rst7 -r eq.nvt.lig.rst7 -o eq.nvt.lig.mdout -x eq.nvt.lig.mdcrd -e eq.nvt.lig.mden";
        printf("%s HEATING ligand started...\n", clock());
        push @thr, threads->new(\&launch_thr, $cmd, "HEATING ligand");
        
        # lancio la simulazione del complesso
        $cmd = "cd $workdir; $bins{'sander'} -O -i eq.nvt.in -p solv.com.prmtop -c min.com.rst7 -r eq.nvt.com.rst7 -o eq.nvt.com.mdout -x eq.nvt.com.mdcrd -e eq.nvt.com.mden";
        printf("%s HEATING complex started...\n", clock());
        push @thr, threads->new(\&launch_thr, $cmd, "HEATING complex");
    }
    
    for (@thr) { $_->join() }; # attendo che le simulazioni finiscano
    undef @thr;
}

EQUILIBRATION: {
    my $sander_script;
    my $cmd;
    
    # copio i file di input
    mkdir 'EQUILIBRATION';
    $workdir = $basepath . 'EQUILIBRATION';
    qx/cp TOPOLOGY\/solv.*.prmtop $workdir\//;
    qx/cp HEATING\/eq.nvt.*.rst7 $workdir\//;
    
    # equilibrazione recettore
    $sander_script = <<END
Equilibrating the system in NPT ensemble (100 ps)
&cntrl
 imin = 0,
 ntx = 5,
 irest= 1,
 ntpr = 500,
 ntwx = 500,
 ntwe = 500,
 ioutfm = 0,
 nstlim = 50000,
 dt = 0.002,
 nscm = 1000,
 ig = 71277,
 temp0 = 300.0,
 ntt = 3,
 gamma_ln = 2.0,
 vlimit = 20.0,
 ntp = 1,
 pres0 = 1.0,
 comp = 44.6,
 taup = 2,
 ntc = 2,
 ntb = 2,
 ntf = 2,
 cut = 8.0,
 nsnb = 25,
 ipol = 0,
 igb = 0
&end

END
    ;
    open(SANDRO, ">$workdir/eq.npt.in");
    print SANDRO $sander_script;
    close SANDRO;
    
    # lancio la simulazione del recettore
    $cmd = "cd $workdir; $bins{'sander'} -O -i eq.npt.in -p solv.rec.prmtop -c eq.nvt.rec.rst7 -r eq.npt.rec.rst7 -o eq.npt.rec.mdout -x eq.npt.rec.mdcrd -e eq.npt.rec.mden";
    printf("%s EQUILIBRATION receptor started...\n", clock());
    push @thr, threads->new(\&launch_thr, $cmd, "EQUILIBRATION receptor");
    
    unless ($ligprefix eq 'null') {
        # lancio la simulazione del ligando
        $cmd = "cd $workdir; $ligsander -O -i eq.npt.in -p solv.lig.prmtop -c eq.nvt.lig.rst7 -r eq.npt.lig.rst7 -o eq.npt.lig.mdout -x eq.npt.lig.mdcrd -e eq.npt.lig.mden";
        printf("%s EQUILIBRATION ligand started...\n", clock());
        push @thr, threads->new(\&launch_thr, $cmd, "EQUILIBRATION ligand");
        
        # lancio la simulazione del complesso
        $cmd = "cd $workdir; $bins{'sander'} -O -i eq.npt.in -p solv.com.prmtop -c eq.nvt.com.rst7 -r eq.npt.com.rst7 -o eq.npt.com.mdout -x eq.npt.com.mdcrd -e eq.npt.com.mden";
        printf("%s EQUILIBRATION complex started...\n", clock());
        push @thr, threads->new(\&launch_thr, $cmd, "EQUILIBRATION complex");
    }
    
    for (@thr) { $_->join() }; # attendo che le simulazioni finiscano
    undef @thr;
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

sub launch_thr {
    my ($cmd, $jobname) = @_;
    system($cmd) && do { print "\nW- failed to run <$cmd>\n" };
    printf("%s %s terminated\n", clock(), $jobname);
}
