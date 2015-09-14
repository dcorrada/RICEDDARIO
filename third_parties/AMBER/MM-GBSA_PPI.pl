#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.02.a        - initial release
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
use File::Copy;

## GLOBS ##
our $input_pdb = $ARGV[0];
our $ligand_mask;
our $workdir;
our %bins = (
    'pdb4amber'        => $ENV{RICEDDARIOHOME} . '/third_parties/AMBER'. '/PDB4AMBER.pl',
    'quest'            => $ENV{RICEDDARIOHOME} . '/Qlite' . '/QUEST.client.pl',
    'structconvert'    => $ENV{SCHRODINGER} . '/utilities/' . 'structconvert',
    'prepwizard'       => $ENV{SCHRODINGER} . '/utilities/' . 'prepwizard',
    'antechamber'      => $ENV{AMBERHOME} . '/bin/' . 'antechamber',
    'parmchk'          => $ENV{AMBERHOME} . '/bin/' . 'parmchk',
    'tleap'            => $ENV{AMBERHOME} . '/bin/' .'tleap',
    'sander'           => $ENV{AMBERHOME} . '/bin/' .'pmemd',
    'ante-mmpbsa'      => $ENV{AMBERHOME} . '/bin/' .'ante-MMPBSA.py',
    'mmpbsa'           => $ENV{AMBERHOME} . '/bin/' .'MMPBSA.py',
);
our $script; # generica variabile che contiene gli script che vengono di volta in volta evocati
our $fh; # filehandle generico
## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    my $help;
    GetOptions('help|h' => \$help);
    my $header = <<ROGER
********************************************************************************
MM-GBSA_PPI
release 15.02.a

Copyright (c) 2015, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
ROGER
    ;
    print $header;
    
    if ($help) {
        my $spiega = <<ROGER

This script performs MM-GBSA calculations, and related per-residue energy (dG) 
decomposition analysis, from an input pdb file. This script is aimed to energy 
evaluation of protein dimers. Moreover, the script also takes into account if 
one of the composing protomers is already complexed with a small molecule. The 
correct synopsys should be as follows:

    \$ MM-GBSA_PPI.pl <input_file.pdb>
ROGER
        ;
        print $spiega;
        goto FINE;
    }
}

READY2GO: {
    # verifico la sintassi
    croak "\nE- mandatory argument(s) not defined, try option '-h' for help\n\t"
        unless (-e $input_pdb);
    
    # verifico che i binari ci siano tutti
    for my $bin (keys %bins) {
        croak "\nE- unable to find <$bins{$bin}>\n\t"
            unless (-e $bins{$bin});
    }
    
    # creo la cartella temporanea
    my ($folder_name) = $input_pdb =~ /(.*)\.pdb$/;
    if ($folder_name) {
        $workdir = getcwd();
        $workdir .= '/.' . $folder_name;
        mkdir $workdir;
        mkdir "$workdir/LOGS";
        copy($input_pdb, $workdir);
        chdir $workdir;
    } else {
        croak "\nE- format of the input file unknown\n\t";
    }
}

PDBPARSER: {
    print "\n*** PARSING PDB INPUT FILE ***\n\n";
    
    # aggiungo gli idrogeni, tramite il Preparation Wizard e ritorno un pdb
    $script = <<ROGER
#!/bin/bash

# SCHRODINGER CONFIGS
export SCHRODINGER=$ENV{SCHRODINGER}
export LM_LICENSE_FILE=$ENV{LM_LICENSE_FILE}

cd $workdir
$bins{'prepwizard'} -noimpref -rehtreat -noepik -NOJOBID $input_pdb complex.mae
$bins{'structconvert'} -imae complex.mae -opdb complex.pdb
ROGER
    ;
    quelo($script, "adding/replacing hydrogens");
    job_monitor($workdir);
    
    # verifico se il pdb contiene una small molecule
    my $theressmallmol;
    open $fh, '<', 'complex.pdb';
    my @incontent = <$fh>;
    close $fh;
    $theressmallmol = 1 if (grep { /HETATM/ } @incontent);
    
    # se c'è una small molecule allestisco due pdb separati
    if ($theressmallmol) {
        printf("%s small molecule found\n", clock());
        my @outcontent;
        
        # proteina
        @outcontent = grep { !/(HETATM|CONECT)/ } @incontent;
        open $fh, '>' . 'protein.pdb';
        print $fh @outcontent;
        close $fh;
        
        # small molecule
        @outcontent = grep { /(HETATM|CONECT)/ } @incontent;
        push(@outcontent, "END\n");
        open $fh, '>' . 'smallmolecule.pdb';
        print $fh @outcontent;
        close $fh;
        
        # converto il file della small molecule in formato mol2
        $script = <<ROGER
#!/bin/bash

# SCHRODINGER CONFIGS
export SCHRODINGER=$ENV{SCHRODINGER}
export LM_LICENSE_FILE=$ENV{LM_LICENSE_FILE}

# AMBER14 CONFIGS
export AMBERHOME=$ENV{AMBERHOME}
export PATH=\$PATH:\$AMBERHOME/bin
if [ -z \$LD_LIBRARY_PATH ]; then
   export LD_LIBRARY_PATH=\$AMBERHOME/lib
else
   export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$AMBERHOME/lib
fi

cd $workdir
$bins{'prepwizard'} -noimpref -noepik -NOJOBID smallmolecule.pdb smallmolecule.mae
$bins{'structconvert'} -imae smallmolecule.mae -omol2 smallmolecule.mol2
$bins{'antechamber'} -i smallmolecule.mol2 -fi mol2 -o smallmolecule.amber.mol2 -fo mol2 -c bcc -s 2
$bins{'parmchk'} -i smallmolecule.amber.mol2 -f mol2 -o smallmolecule.frcmod
ROGER
        ;
        quelo($script, "small molecule topology");
        job_monitor($workdir);
    } else {
        copy('complex.pdb', 'protein.pdb');
    }
    
    # converto il pdb della proteina in un formato compatibile per AMBER
    $script = <<ROGER
#!/bin/bash

cd $workdir
$bins{'pdb4amber'} protein.pdb
ROGER
    ;
    quelo($script, "converting protein PDB format");
    job_monitor($workdir);
}

LIGMASK: {
    open $fh, '<', 'protein.amber.pdb';
    my @ters = <$fh>;
    close $fh;
    @ters = grep { /^TER/ } @ters;
    my ($chaina) = $ters[0] =~ / A (\d+)/;
    my ($chainb) = $ters[1] =~ / B (\d+)/;
    printf("%s specify the ligand partner [\"%d-%d\" or \"%d-%d\"]: ", clock(), 1, $chaina, $chaina+1, $chainb);
    $ligand_mask = <STDIN>;
    chomp $ligand_mask;
    croak "\nE- format of the ligand mask unknown\n\t"
        unless ($ligand_mask  =~ /^\d+\-\d+$/);
}

MINIMIZER: {
    print "\n*** MINIMIZATION ***\n\n";
    my $protein = "$workdir/protein.amber.pdb";
    my $smallmol = "$workdir/smallmolecule.amber.mol2";
    my $frcmod = "$workdir/smallmolecule.frcmod";
    
    # preparo lo script per allestire un sistema solvatato in AMBER
    $script = <<ROGER
set default PBRadii mbondi2                             # atomic radii for GB calculations
source leaprc.ff99SB                                    # load AMBER force field
source leaprc.gaff                                      # load GAFF forcefield
ROGER
    ;
    
    if (-e $smallmol) {
        $script .= <<ROGER
loadamberparams $frcmod                                 # load extensions to GAFF forcefield
loadoff vacuo.lig.lib                                   # load Object file for ligand
REC = loadpdb $protein                                  # load protein
LIG = loadmol2 $smallmol                                # load small molecule
COM = combine {REC LIG}                                 # complexing receptor and small miolecule
ROGER
        ;
    } else {
        $script .= <<ROGER
COM = loadpdb $protein                                  # load protein
ROGER
        ;
    }
    
    # solvato il complesso
    $script .= <<ROGER
solvateOct COM TIP3PBOX 10.0                            # solvating box
addIons COM Na+ 0                                       # add counterions
addIons COM Cl- 0                                       # add counterions
saveamberparm COM solvated.prmtop solvated.inpcrd       # save solvated UNIT and PARMSET
savepdb COM solvated.pdb                                # export the solvated system in pdb
quit 
ROGER
    ;
    open $fh, '>' . 'tleap.in';
    print $fh $script;
    close $fh;
    
    $script = <<ROGER
#!/bin/bash

# AMBER14 CONFIGS
export AMBERHOME=$ENV{AMBERHOME}
export PATH=\$PATH:\$AMBERHOME/bin
if [ -z \$LD_LIBRARY_PATH ]; then
export LD_LIBRARY_PATH=\$AMBERHOME/lib
else
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$AMBERHOME/lib
fi


cd $workdir
$bins{'tleap'} -f tleap.in
ROGER
    ;
    quelo($script, "solvating complex");
    job_monitor($workdir);
    
    # preparo lo script di minimizzazione per AMBER
    $script = <<END
Minimisation: backbone and ligand w/ position restraints (500 kcal/molA)
&cntrl
 imin = 1,
 maxcyc = 2000,
 ncyc = 500,
 drms = 0.01,
 ntb = 1,
 ntr = 1,
 restraint_wt = 500.0,
 restraintmask = '\@N,CA,C,O,CB | :UNK',
 cut = 8.0
&end
END
    ;
    open $fh, '>' . 'min.in';
    print $fh $script;
    close $fh;
    
    # minimizzo
    $script = <<ROGER
#!/bin/bash

# AMBER14 CONFIGS
export AMBERHOME=$ENV{AMBERHOME}
export PATH=\$PATH:\$AMBERHOME/bin
if [ -z \$LD_LIBRARY_PATH ]; then
   export LD_LIBRARY_PATH=\$AMBERHOME/lib
else
   export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$AMBERHOME/lib
fi


cd $workdir
$bins{'sander'} -O -i min.in -p solvated.prmtop -c solvated.inpcrd -ref solvated.inpcrd -r minimized.rst7 -o minimized.mdout
ROGER
    ;
    quelo($script, "minimizing");
    job_monitor($workdir);
}

MMGBSA: {
    print "\n*** MM-GBSA ***\n";
    
    printf("%s ligand mask setted as <%s>\n", clock(), $ligand_mask);
    
    # preparo gli input con ante-MMPBSA.py
    $script = <<ROGER
#!/bin/bash

# AMBER14 CONFIGS
export AMBERHOME=$ENV{AMBERHOME}
export PATH=\$PATH:\$AMBERHOME/bin
if [ -z \$LD_LIBRARY_PATH ]; then
   export LD_LIBRARY_PATH=\$AMBERHOME/lib
else
   export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$AMBERHOME/lib
fi

cd $workdir
$bins{'ante-mmpbsa'} -p solvated.prmtop -c comp.prmtop -l lig.prmtop -r rec.prmtop -s ":WAT,Cl-,Na+" -n ":$ligand_mask"
ROGER
    ;
    quelo($script, "MM-GBSA inputs");
    job_monitor($workdir);
    
    # preparo l'input script per MMPBSA.py
    $script = <<ROGER
MM-GBSA calculation, SFP strategy
&general
 verbose = 2,
 entropy = 0,
 keep_files = 0,
/
&gb
 igb = 5,
 saltcon = 0.154,
/
&decomp
 csv_format = 0,
 dec_verbose = 2,
 idecomp = 1,
/
ROGER
    ;
    open $fh, '>', "$workdir/MMGBSA.in";
    print $fh $script;
    close $fh;
    
    # lancio il calcolo di MM-GBSA
    $script = <<ROGER
#!/bin/bash

# AMBER14 CONFIGS
export AMBERHOME=$ENV{AMBERHOME}
export PATH=\$PATH:\$AMBERHOME/bin
if [ -z \$LD_LIBRARY_PATH ]; then
   export LD_LIBRARY_PATH=\$AMBERHOME/lib
else
   export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$AMBERHOME/lib
fi

cd $workdir
$bins{'mmpbsa'} -O -i MMGBSA.in -sp solvated.prmtop -cp comp.prmtop -rp rec.prmtop -lp lig.prmtop -y minimized.rst7
ROGER
    ;
    quelo($script, "energy decomposition analysis");
    job_monitor($workdir);
}

OUTFILES: {
    print "\n*** FINAL OUTPUTS ***\n";
    printf("\n%s copying dat files...", clock());
    for my $datfile ('FINAL_DECOMP_MMPBSA.dat', 'FINAL_RESULTS_MMPBSA.dat') {
        my ($prefix) = $input_pdb =~ /(.*)\.pdb$/;
        my ($suffix) = $datfile =~ /^FINAL_(.*)_MMPBSA.dat$/;
        my $outfile = $prefix . '_' . $suffix . '.dat';
        qx/cd $workdir; cp $datfile ..\/$outfile/;
    }
    print "done\n";
}

CLEANSWEEP: {
    qx/rm -r $workdir/; # rimuovo la directory temporanea
}

FINE: {
    print "\n*** IPP_ASBG-MM ***\n";
    exit;
}


sub quelo { # serve per lanciare job su QUEST
    my ($content, $message) = @_;
    my $basename = $message;
    $basename =~ s/[ \/]/_/g;
    my $filename = "$basename.quest.sh";
    
    # creo uno shell script di modo che il job possa venire sottomesso tramite QUEST
    open(SH, '>' . $filename);
    # aggiungo questa riga di controllo allo script: prima di terminare lo script 
    # accoda al file 'JOBS_FINISHED.txt' una stringa per dire che ha finito
    $content .= "echo $basename >> $workdir/JOBS_FINISHED.txt\n";
    
    print SH $content;
    close SH;
    qx/chmod +x $filename/; # rendo il file sh eseguibile
    
    # lancio il file sh su QUEST
    my $string = "$bins{'quest'} -n 1 -q fast $filename";
    qx/$string/;
    
    printf("%s $message...", clock());
}

sub job_monitor {
    my ($path) = @_;
    
    # la lista dei job lanciati è basata sul numero di shell script di QUEST che trovo nella cartella di lavoro
    opendir(SH, $path);
    my @scripts = grep { /\.quest\.sh$/ } readdir(SH);
    closedir SH;
    my %joblist;
    foreach my $basename (@scripts) {
        $basename =~ s/\.quest\.sh$//;
        $joblist{$basename} = 'wait';
    }
    
    # file contenente la lista dei jobs che sono finiti
    my $jobfile = "$path/JOBS_FINISHED.txt";
    
    while (1) {
        if (-e $jobfile) {
            open(LOG, '<' . $jobfile);
            while (my $newline = <LOG>) {
                chomp $newline;
                if (exists $joblist{$newline}) {
                    $joblist{$newline} = 'finished';
                }
            }
            close LOG;
            my ($wait, $finished);
            
            # verifico quanti job sono finiti
            foreach my $i (keys %joblist) {
                if ($joblist{$i} eq 'wait') {
                    $wait++;
                } elsif ($joblist{$i} eq 'finished') {
                    $finished++;
                }
            }
            
            # se non ci sono più job in coda o che stanno girando esco dal loop
            last unless ($wait);
            
        }
        sleep 1;
    }
    
    # pulisco i file intermedi
    my $cleansweep = <<ROGER
#!/bin/bash

cd $path;
mv QUEST.job.*.log $path/LOGS;
mv *.sh $path/LOGS;
rm -f JOBS_FINISHED.txt
ROGER
    ;
    open(LOGOS, '>' . "$path/cleansweep");
    print LOGOS $cleansweep;
    close LOGOS;
    qx/chmod +x $path\/cleansweep; $path\/cleansweep; rm -f $path\/cleansweep/;
    
    print "done\n";
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