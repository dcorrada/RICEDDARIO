#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.01.a    - modified summary csv and boxplots on STEP7
#                    - added timelog
#
# release 14.12.b    - shell option
#                    - per-residue energy decomposition
#                    - box plots of decomposed terms
#
# release 14.12.a    - prime_mmgbsa job optimized (see STEP6 block)
#                    - pdb format conversion during STEP0
#
# release 14.11.a    - initial release
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
use Statistics::Descriptive;

## FLAGS ##

our $PLANARIZE = 0; # force aromatic rings to be planar, during post-docking minimization step (option avalaible only for ff OPLS_200X)
our $PRIME_FREEZER = 0; # if enabled, force prime_mmgbsa to calculte energy without structure optimization
our $JUMP = 'STEP1'; # force to (re)start the protocol from a specific step
our $SHELL = 5.0; # shell by which residues will be considered during enedecomp analysis

## SGALF ##

## GLOBS ##

our $license = $ENV{LM_LICENSE_FILE}; # Schrodinger license

# paths
our $schrodinger = $ENV{SCHRODINGER};
our $riceddario = $ENV{RICEDDARIOHOME};
our $homedir = getcwd();
our $sourcedir;
our $destdir;

# i vari programmi che verranno usati
my $wheRe = qx/which R/; chomp $wheRe;
our %bins = (
    'glide'             => $schrodinger . '/glide',
    'macromodel'        => $schrodinger . '/macromodel',
    'prepwizard'        => $schrodinger . '/utilities/prepwizard',
    'prime_mmgbsa'      => $schrodinger . '/prime_mmgbsa',
    'run'               => $schrodinger . '/run',
    'structcat'         => $schrodinger . '/utilities/structcat',
    'structconvert'     => $schrodinger . '/utilities/structconvert',
    'compute_centroid'  => $riceddario . '/third_parties/SCHRODINGER' . '/Compute_centroid.py',
    'pv_convert'        => $riceddario . '/third_parties/SCHRODINGER' .  '/pv_convert.py',
    'quest'             => $riceddario . '/Qlite' . '/QUEST.client.pl',
    'split_complexes'   => $riceddario . '/third_parties/SCHRODINGER' . '/split_complexes.py',
    'enedecomp_parser'  => $riceddario . '/third_parties/SCHRODINGER' . '/enedecomp_parser.pl',
    'R'                 => $wheRe
);

our $gridsize;
our $ligands;
our $substructure;
our $refstruct;
our %iofiles;
our $cmdline; 
our %joblist;

## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    my $help;
    my $workflow;
    GetOptions('planarize|p' => \$PLANARIZE, 'freeze|f' => \$PRIME_FREEZER, 'help|h' => \$help, 'jump|j=s' => \$JUMP, 'shell|s=f' => \$SHELL);
    my $header = <<ROGER
********************************************************************************
DONKEY - DON't use KnimE Yet
release 15.01.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
ROGER
    ;
    print $header;
    
    if ($help) {
        my $spiega = <<ROGER

DONKEY is a script to perform (ensemble) docking, connecting the several tools 
offered from the Schrodinger suite into an automated pipeline. The current 
version use OPLS_2005 as forcefield to perform the minimization steps.

*** SYNOPSIS ***
    
    # default usage
    \$ DONKEY.pl
    
    # custom mode
    \$ DONKEY.pl -f
    \$ DONKEY.pl -j STEP4
    
*** OPTIONS ***
    
    -freeze|f           do not perform mimimization during the rescoring step
                        (ie minimization with prime_mmgbsa)
    
    -jump|j <STEPX>     start workflow from a specific step
    
    -planarize|p        enforce planarity of aromatic rings during post-docking 
                        minimization step, recommended if you have ligands with 
                        extended coniugated aromatic systems
    
    -shell|s <float>    shell, in Angstrom, by which residues will be considered
                        for energy decomposition analysis (default: 5.0 A)
    
*** INPUT FILES ***
    
    ----------------------------------------------------------------------------
     FILENAME                DESCRIPTION
    ----------------------------------------------------------------------------
     reference_comp.mae      the reference complex on which the models will be 
                             structurally aligned; the embedded ligand will 
                             define the center of the grids of the models
    
     input_ligands.maegz     the library of the ligands to be docked, ligands 
                             should be previously optimized
     
     model_A.pdb             the structure files (only protein) of the different 
     model_B.pdb             models on which ligands will be docked
     [...]
     
     shells.sbc              the substructure file where are defined the 
                             constraint shell for the minimization steps
     
     gridsize.grid           template file containing the sizes of the grid box
    ----------------------------------------------------------------------------
ROGER
        ;
        print $spiega;
        goto FINE;
    }
}

READY2GO: {
    # faccio un check per assicurarmi che ci siano tutti i programmi
    foreach my $bin (keys %bins) {
        if (-e $bins{$bin}) {
            next;
        } else {
            croak "\nE- file <$bins{$bin}> not found\n\t";
        }
    }
    
    # aggiorno il comando per lanciare R
    $bins{'R'} .= ' --vanilla <';
    
    # verifico che il server QUEST sia su
    my $status = qx/$bins{'quest'} -l 2>&1/;
    if ($status =~ /E\- Cannot open socket/) {
        croak "\nE- QUEST server seems to be down\n\t";
    }
}

my $warn = <<ROGER

++++++++++++++++++++++++++++++++++++ WARNING +++++++++++++++++++++++++++++++++++
+ In this shell session do not use CTRL+C while appear log messages like       +
+ "job XXX submitted"; using CTRL+C shortcut may cause conflicts with the      +
+ QUEST server (it could manage also running jobs other than the DONKEY ones). +
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ROGER
;
print $warn;
goto $JUMP;

STEP1: {
    print "\n*** STEP 0: checking input files ***\n";
    
    $sourcedir = getcwd();
    opendir(DIR, $sourcedir);
    my @file_list = grep { /\.\w{3,5}$/ } readdir(DIR);
    closedir DIR;
    
    my $mods = ' ';
    for my $infile (@file_list) {
        if ($infile =~ /\.mae$/) {
            $refstruct = $infile;
        } elsif ($infile =~ /\.maegz$/) {
            $ligands = $infile;
        } elsif ($infile =~ /\.pdb$/) {
            my ($basename) = $infile =~ /(.+)\.pdb/;
            $iofiles{$basename} = $infile;
            $mods .= "$infile\n                         ";
        } elsif ($infile =~ /\.sbc$/) {
            $substructure = $infile;
        } elsif ($infile =~ /\.grid$/) {
            $gridsize = $infile;
        } else {
            next;
        }
    }
    printf("\n%s SUMMARY CHECK\n", clock());
    printf("\n    FLAG freeze........: %d\n\n    FLAG planarize.....: %d\n\n    FLAG shell.........: %f\n", $PRIME_FREEZER, $PLANARIZE, $SHELL);
    printf("\n    ligands library....: %s\n\n    reference complex..: %s\n\n    input models.......:%s\n    substructure.......: %s\n\n    grid sizes.........: %s", $ligands, $refstruct, $mods, $substructure, $gridsize);
    print "\n\nInput files are alright? [Y/n] ";
    my $ans = <STDIN>;
    chomp $ans;
    $ans = 'y' unless ($ans);
    unless ($ans =~ /[Yy]/) {
        print "\naborting";
        goto FINE;
    }

    print "\n\n*** STEP 1: preparing models ***\n";
    
    $sourcedir = $homedir;
    $destdir = "$sourcedir/STEP1_preparation";
    mkdir $destdir;
    chdir $destdir;
    
    # copio i file di input
    copy("$sourcedir/$refstruct", $destdir);
    
    printf("\n%s parsing pdb files...", clock());
    foreach my $basename (keys %iofiles) {
        my $filename = $iofiles{$basename};
        open(INFILE, '<' . "$sourcedir/$iofiles{$basename}");
        my @infilecontent = <INFILE>;
        close INFILE;
        my $outfilecontent = [ ];
        foreach my $newline (@infilecontent) {
            chomp $newline;
            next unless ($newline =~ /^ATOM/);
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            # le righe "ATOM" sono strutturate così:
            #   [1]     Atom serial number
            #   [3]     Atom name
            #   [4]     Alternate location indicator
            #   [5]     Residue name
            #   [7]     Chain identifier
            #   [8]     Residue sequence number
            #   [9]     Code for insertion of residues
            #   [11-13] XYZ coordinates
            #   [14]    Occupancy volume
            #   [15]    T-factor
            push(@{$outfilecontent}, [ @splitted ]);
        }
        
        open(OUTFILE, '>' . $iofiles{$basename});
        my ($inc_atom, $inc_resi) = (1, 1);
        my $current_res = $outfilecontent->[0][8];
        foreach my $newline (@{$outfilecontent}) {
            my $newer_res = $newline->[8];
            unless ($newer_res eq $current_res) {
                $inc_resi++;
                $current_res = $newer_res;
            }
            
            $newline->[1] = sprintf("% 5d",$inc_atom); # right justified format
            $newline->[8] = sprintf("% 4d",$inc_resi); # right justified format
            $newline->[7] = ' ';
            
            my $string = join('', @{$newline}) . "\n";
            print OUTFILE $string;
            
            $inc_atom++; # aggiorno l'atom number
        }
        print OUTFILE "END\n";
        close OUTFILE;
    }
    print "done\n";
    
    # lancio il preparation wizard per ogni modello
    printf("\n%s preparing models with PrepWizard\n", clock());
    foreach my $basename (keys %iofiles) {
        # con il PrepWizard faccio:
        # -> allinemanto strutturale di ogni modello al complesso di riferimento (-reference_st_file)
        # -> evito di fare minimizzazioni preliminari (-noimpref)
        # -> assegno ex-novo gli idrogeni (-rehtreat)
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'prepwizard'} -reference_st_file $refstruct -noimpref -rehtreat $iofiles{$basename} prep-$basename.mae -NOJOBID > prep-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);

    # estraggo il ligando dalla struttura di riferimento e rinomino il file
    $cmdline = "$bins{'run'} $bins{'pv_convert'} -l $refstruct";
    qx/$cmdline/;
    my $ligandfile = $refstruct;
    $ligandfile =~ s/\.mae$/_1_lig.mae/;
    rename($ligandfile, 'REFLIG.mae');
    $ligandfile = 'REFLIG.mae';
    
    printf("\n%s complexing models\n", clock());
    # aggiungo il ligando ad ogni modello preparato e creo il pose viewer
    foreach my $basename (keys %iofiles) {
        print "    $basename...";
        $cmdline = "$bins{'structcat'} -imae prep-$basename.mae -imae $ligandfile -omae prep-LIG-$basename.mae";
        qx/$cmdline/;
        $cmdline = "$bins{'run'} $bins{'pv_convert'} -m prep-LIG-$basename.mae";
        qx/$cmdline/;
        if (-e "prep-LIG-$basename\_complex.mae") {
            rename ("prep-LIG-$basename\_complex.mae", "prep-LIG-$basename\-complex.mae");
            print "done\n";
        } else {
            croak "\nE- molecule <prep-$basename.mae> NOT complexed\n\t";
        }
    }
    
    printf("\n%s compressing intermediate files\n", clock());
    my $tozip = "$refstruct $ligandfile ";
    foreach my $basename (keys %iofiles) {
        $tozip .= " $basename.pdb";
        $tozip .= " $basename-protassign.log";
        $tozip .= " $basename-protassign.mae";
        $tozip .= " $basename-protassign-out.mae";
        $tozip .= " prep-$basename.mae";
        $tozip .= " prep-$basename.log";
        $tozip .= " prep-LIG-$basename.mae";
#         $tozip .= " prep-LIG-$basename.log";
    }
    $cmdline = <<ROGER
cd $destdir;
tar -c $tozip | gzip -c9 > intermediate.tar.gz;
rm -rfv $tozip;
ROGER
    ;
    qx/$cmdline/;
}

STEP2: {
    print "\n\n*** STEP 2: minimization ***\n";
    
    $sourcedir = "$homedir/STEP1_preparation";
    $destdir = "$homedir/STEP2_mini";
    mkdir $destdir;
    chdir $destdir;
    
    # aggiorno la lista dei file di input e li copio nella nuova directory
    opendir (DIR, $sourcedir);
    my @filelist = grep { /^prep-LIG-(.+)-complex.mae$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^prep-LIG-(.+)-complex.mae$/;
        $iofiles{$basename}= $filename;
        copy("$sourcedir/$iofiles{$basename}", $destdir);
    }
    
    # definisco le shell a cui applicare i constraint
    unless ($substructure) {
        opendir (DIR, $homedir);
        my @filelist = grep { /.sbc$/ } readdir(DIR);
        close DIR;
        $substructure = $filelist[0];
    }
    open(SBC, '<' . $homedir . '/' . $substructure);
    my $sbccontent;
    while (my $newline = <SBC>) {
        $sbccontent .= $newline;
    }
    close SBC;
    
    # creo l'input file per MacroModel
    printf("\n%s shell minimization with MacroModel\n", clock());
    foreach my $basename (keys %iofiles) {
        # minimizzazione a shell con 1500 steps di Truncated Newton Coinugated Gradient (TNCG)
        my $incontent = <<ROGER
INPUT_STRUCTURE_FILE $iofiles{$basename}
OUTPUT_STRUCTURE_FILE mini-LIG-$basename.maegz
JOB_TYPE MINIMIZATION
FORCE_FIELD OPLS_2005
SOLVENT Water
USE_SUBSTRUCTURE_FILE True
MINI_METHOD TNCG
MAXIMUM_ITERATION 1500
CONVERGE_ON Gradient
ROGER
        ;
        open(INFILE, '>' . "mini-LIG-$basename.in");
        print INFILE $incontent;
        close INFILE;
        
        # devo fare una copia del file sbc per ogni modello, il basename del file deve essere identico al basename del file mae di input
        my $sbcfilename = $iofiles{$basename};
        $sbcfilename =~ s/mae$/sbc/;
        open(INFILE, '>' . $sbcfilename);
        print INFILE $sbccontent;
        close INFILE;
        
        # lancio la minimizzazione
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'macromodel'} mini-LIG-$basename.in -NOJOBID > mini-LIG-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    my $summary_file = 'SUMMARY.csv';
    my $summary_content = "MODEL;ENERGY;GRADIENT\n";
    foreach my $basename (keys %iofiles) {
        my $logfile = "mini-LIG-$basename.log";
        if (-e $logfile) {
            open(LOG, '<' . $logfile);
            while (my $newline = <LOG>) {
                chomp $newline;
                if ($newline =~ /^ Conf/) {
                    my ($energy,$gradient) = $newline =~ /E = +([\d\.\-]+) \( *([\d\.]+)/;
                    $summary_content .= "$basename;$energy;$gradient\n";
                }
            }
            close LOG;
        } else {
            croak "\nE- molecule <$basename> not minimized\n\t";
        }
    }
    printf("\n%s SUMMARY:\n\n%s", clock(), $summary_content);
    open(SUM, '>' . $summary_file);
    print SUM $summary_content;
    close SUM;
    
    printf("\n%s compressing intermediate files\n", clock());
    my $tozip = '';
    qx/rm -f *.pdb/; # i modelli iniziali
    foreach my $basename (keys %iofiles) {
        $tozip .= " prep-LIG-$basename-complex.mae";
        $tozip .= " mini-LIG-$basename.in";
        $tozip .= " mini-LIG-$basename.com";
        $tozip .= " prep-LIG-$basename-complex.sbc";
    }
    $cmdline = <<ROGER
cd $destdir;
tar -c $tozip | gzip -c9 > intermediate.tar.gz;
rm -rfv $tozip;
ROGER
    ;
    qx/$cmdline/;
}

STEP3: {
    print "\n\n*** STEP 3: grid setting ***\n";
    
    $sourcedir = "$homedir/STEP2_mini";
    $destdir = "$homedir/STEP3_grid";
    mkdir $destdir;
    chdir $destdir;
    
    # aggiorno la lista dei file di input e li copio nella nuova directory
    opendir (DIR, $sourcedir);
    my @filelist = grep { /^mini-LIG-(.+).maegz$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^mini-LIG-(.+).maegz$/;
        $iofiles{$basename}= $filename;
        copy("$sourcedir/$iofiles{$basename}", $destdir);
    }
    
    # estraggo ligando e recettore
    printf("\n%s parsing mimimized models\n", clock());
    foreach my $basename (keys %iofiles) {
        $cmdline = "$bins{'run'} $bins{'pv_convert'} -l $iofiles{$basename}";
        qx/$cmdline/;
        $cmdline = "$bins{'run'} $bins{'pv_convert'} -r $iofiles{$basename}";
        qx/$cmdline/;
        $cmdline = "$bins{'structconvert'} -imae mini-LIG-$basename\_1_lig.maegz -omae mini-LIG-$basename\_1_lig.mae";
        qx/$cmdline/;
        unlink "mini-LIG-$basename\_1_lig.maegz";
        print "    <$basename> parsed\n";
    }
    
    printf("\n%s generating grid\n", clock());
    
    # definisco le shell a cui applicare i constraint
    unless ($gridsize) {
        opendir (DIR, $homedir);
        my @filelist = grep { /.grid$/ } readdir(DIR);
        close DIR;
        $gridsize = $filelist[0];
    }
    open(GRD, '<' . $homedir . '/' . $gridsize);
    my $grdcontent;
    while (my $newline = <GRD>) {
        $grdcontent .= $newline;
    }
    close GRD;
    
    foreach my $basename (keys %iofiles) {
        # calcolo il centro della griglia usando le coordinate atomiche del ligando estratto precedentemente
        $cmdline = "$bins{'compute_centroid'} mini-LIG-$basename\_1_lig.mae; ";
        $cmdline .= "cat centroid-mini-LIG-$basename\_1_lig.txt";
        my $grid_center = qx/$cmdline/;
        
        # input file per definire la griglia
        my $incontent = <<ROGER
GRIDLIG YES
USECOMPMAE YES
$grdcontent
$grid_center
GRIDFILE $basename-grid-LIG.zip
RECEP_FILE mini-LIG-$basename\_1_recep.maegz
ROGER
        ;
        open(INFILE, '>' . "grid_LIG_$basename.in");
        print INFILE $incontent;
        close INFILE;
        
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'glide'} grid_LIG_$basename.in -NOJOBID > grid_LIG_$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    printf("\n%s SUMMARY:\n", clock());
    foreach my $basename (keys %iofiles) {
        my $logfile = "grid_LIG_$basename.out";
        if (-e $logfile) {
            print "  grid prepared for molecule <$basename>\n";
        } else {
            croak "\nE- grid not prepared for molecule <$basename>\n\t";
        }
    }
    
    # rimuovo un po' di file inutili
    qx/cd $destdir; rm -f *_1_lig.*/;
    
    printf("\n%s compressing intermediate files\n", clock());
    my $tozip = '';
    qx/rm -f *.pdb/; # i modelli iniziali
    foreach my $basename (keys %iofiles) {
        $tozip .= " grid_LIG_$basename.in";
        $tozip .= " grid_LIG_$basename.out";
        $tozip .= " mini-LIG-$basename\_1_recep.maegz";
        $tozip .= " mini-LIG-$basename.maegz";
    }
    $cmdline = <<ROGER
cd $destdir;
tar -c $tozip | gzip -c9 > intermediate.tar.gz;
rm -rfv $tozip;
ROGER
    ;
    qx/$cmdline/;
}

STEP4: {
    print "\n\n*** STEP 4: docking ***\n";
    
    $sourcedir = "$homedir/STEP3_grid";
    $destdir = "$homedir/STEP4_docking";
    mkdir $destdir;
    chdir $destdir;
    
    unless ($ligands) {
        opendir(DIR, $homedir);
        my @file_list = grep { /\.maegz$/ } readdir(DIR);
        closedir DIR;
        $ligands = $file_list[0];
    }
    
    # aggiorno la lista dei file di input e li copio nella nuova directory
    copy("$homedir/$ligands", $destdir);
    opendir (DIR, $sourcedir);
    my @filelist = grep { /^(.+)-grid-LIG.zip$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^(.+)-grid-LIG.zip$/;
        $iofiles{$basename}= $filename;
        copy("$sourcedir/$iofiles{$basename}", $destdir);
    }
    
    printf("\n%s launch GlideXP\n", clock());
    foreach my $basename (keys %iofiles) {
        # input file per il docking
        # NOTA: nella versione 2014 hanno introdotto due flag per gestire gli alogeni come accettori/donatori di interazioni tipo Hbond (HBOND_ACCEP_HALO e HBOND_DONOR_HALO di default disabilitate); da notare che i ff disponibili per Glide sono ancora OPLS2001 e OPLS2005
        my $incontent = <<ROGER
POSES_PER_LIG 1
POSTDOCK NO
WRITE_RES_INTERACTION YES
WRITE_XP_DESC YES
USECOMPMAE YES
MAXREF 800
RINGCONFCUT 2.500000
GRIDFILE $iofiles{$basename}
LIGANDFILE $ligands
PRECISION XP
ROGER
        ;
        open(INFILE, '>' . "BestXP_$basename.in");
        print INFILE $incontent;
        close INFILE;
        
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'glide'} BestXP_$basename.in -NOJOBID > BestXP_$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    my $summary_file = 'SUMMARY.csv';
    my $summary_content = "MODEL;LIGAND;GlideScore;Emodel;E;Eint\n";
    foreach my $basename (keys %iofiles) {
        my $logfile = "BestXP_$basename.log";
        if (-e $logfile) {
            open(LOG, '<' . $logfile);
            my $ligand;
            while (my $newline = <LOG>) {
                chomp $newline;
                if ($newline =~ /^DOCKING RESULTS FOR LIGAND/) {
                    ($ligand) = $newline =~ /^DOCKING RESULTS FOR LIGAND  *\d+ \((.+)\)/;
                } elsif ($newline =~ /^Best XP pose:/) {
                    my ($glidescore,$emodel,$e,$eint) = $newline =~ /^Best XP pose: +\d+;  GlideScore = +([\-\d\.]+) Emodel = +([\-\d\.]+) E = +([\-\d\.]+) Eint = +([\-\d\.]+)/;
                    $summary_content .= "$basename;$ligand;$glidescore;$emodel;$e;$eint\n";
                } else {
                    next;
                }
            }
            close LOG;
        } else {
            print"\nW- no pose found for <$basename>\n\t";
        }
    }
    printf("\n%s SUMMARY:\n\n%s", clock(), $summary_content);
    open(SUM, '>' . $summary_file);
    print SUM $summary_content;
    close SUM;
    
    printf("\n%s compressing intermediate files\n", clock());
    my $tozip = " $ligands";
    foreach my $basename (keys %iofiles) {
        $tozip .= " BestXP_$basename.in";
        $tozip .= " BestXP_$basename.out";
        $tozip .= " $basename-grid-LIG.zip";
    }
    $cmdline = <<ROGER
cd $destdir;
tar -c $tozip | gzip -c9 > intermediate.tar.gz;
rm -rfv $tozip;
ROGER
    ;
    qx/$cmdline/;
}

STEP5: {
    print "\n\n*** STEP 5: post-docking minimization ***\n";
    
    $sourcedir = "$homedir/STEP4_docking";
    $destdir = "$homedir/STEP5_mini_post";
    mkdir $destdir;
    chdir $destdir;
    
    # aggiorno la lista dei file di input e li copio nella nuova directory
    opendir (DIR, $sourcedir);
    my @filelist = grep { /^BestXP_(.+)\_pv.maegz$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^^BestXP_(.+)\_pv.maegz$/;
        $iofiles{$basename}= $filename;
        copy("$sourcedir/$iofiles{$basename}", $destdir);
    }
    
    # definisco le shell a cui applicare i constraint
    unless ($substructure) {
        opendir (DIR, $homedir);
        my @filelist = grep { /.sbc$/ } readdir(DIR);
        close DIR;
        $substructure = $filelist[0];
    }
    open(SBC, '<' . $homedir . '/' . $substructure);
    my $sbccontent;
    while (my $newline = <SBC>) {
        $sbccontent .= $newline;
    }
    close SBC;
    
    # splitto il pose viewer di ogni complesso di modo da ottenere un mae per ogni posa
    printf("\n%s parsing pose viewer files\n", clock());
    foreach my $basename (keys %iofiles) {
        $cmdline = "$bins{'run'} $bins{'pv_convert'} -m $iofiles{$basename}";
        qx/$cmdline/;
        $cmdline = "$bins{'structconvert'} -imae BestXP_$basename\_complex.maegz -omae BestXP_$basename-complexes.mae";
        qx/$cmdline/;
        unlink "BestXP_$basename\_complex.maegz";
        $cmdline = "$bins{'split_complexes'} BestXP_$basename-complexes.mae";
        qx/$cmdline/;
        print "    <$basename> parsed\n";
    }
    
    # reinizializzo la lista dei file di input
    my %old_iofiles = %iofiles;
    undef %iofiles;
    opendir(DIR, $destdir);
    my @file_list = grep { /-complex-\d+\.mae$/ } readdir(DIR);
    closedir DIR;
    foreach my $infile (@file_list) {
        my ($basename) = $infile =~ /^BestXP_(.+)\.mae$/;
        $iofiles{$basename} = $infile;
    }
    
    printf("\n%s shell minimization with MacroModel\n", clock());
    # creo l'input file per MacroModel
    foreach my $basename (keys %iofiles) {
        # RUN INPUT FILE
        my $incontent; my $infilename;
        if ($PLANARIZE) {
            # per forzare la planarità sui sistemi aromatici il run input file deve essere scritto nel formato .com meno leggibile (MacroModel converte comunque il formato .in in formato .com prima di lanciare i job)
            $incontent .= <<ROGER
$iofiles{$basename}
minipostXP-$basename.maegz
 DEBG       0      0      0      0     0.0000     0.0000     0.0000     0.0000
 SOLV       3      1      0      0     0.0000     0.0000     0.0000     0.0000
 BDCO       0      0      0      0     0.0000 99999.0000     0.0000     0.0000
 FFLD      14      1      0      0     1.0000     0.0000     1.0000     0.0000
 BGIN       0      0      0      0     0.0000     0.0000     0.0000     0.0000
 SUBS       0      0      0      0     0.0000     0.0000     0.0000     0.0000
 READ       0      0      0      0     0.0000     0.0000     0.0000     0.0000
 CONV       2      0      0      0     0.0500     0.0000     0.0000     0.0000
 MINI       9      0   1500      0     0.0000     0.0010     0.0000     0.0000
 END        0      0      0      0     0.0000     0.0000     0.0000     0.0000
ROGER
            ;
            $infilename = "minipostXP-$basename.com";
        } else {
            $incontent = <<ROGER
INPUT_STRUCTURE_FILE $iofiles{$basename}
OUTPUT_STRUCTURE_FILE minipostXP-$basename.maegz
JOB_TYPE MINIMIZATION
FORCE_FIELD OPLS_2005
SOLVENT Water
USE_SUBSTRUCTURE_FILE True
MINI_METHOD TNCG
MAXIMUM_ITERATION 1500
CONVERGE_ON Gradient
ROGER
            ;
            $infilename = "minipostXP-$basename.in";
        }
        
        open(INFILE, '>' . $infilename);
        print INFILE $incontent;
        close INFILE;
        
        # devo fare una copia del file sbc per ogni modello, il basename del file deve essere identico al basename del file mae di input
        my $sbcfilename = $iofiles{$basename};
        $sbcfilename =~ s/mae$/sbc/;
        open(INFILE, '>' . $sbcfilename);
        print INFILE $sbccontent;
        close INFILE;
        
        # lancio la minimizzazione
        my $suffix = ($PLANARIZE)? 'com' : 'in'; # quale formato di run input file scelgo?
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'macromodel'} minipostXP-$basename.$suffix -NOJOBID > minipostXP-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    my $summary_file = 'SUMMARY.csv';
    my $summary_content = "COMPLEX;LIGAND;ENERGY;GRADIENT\n";
    foreach my $basename (keys %iofiles) {
        my $logfile = "minipostXP-$basename.log";
        my $posefile = $iofiles{$basename};
        if (-e $logfile) {
            my $ligand_line = 'null';
            open(MAE, '<' . $posefile);
            while (my $newline = <MAE>) {
                chomp $newline;
                if ($newline =~ / i_m_ct_format/) {
                    $newline = <MAE>;
                    if ($newline =~ / :::/) {
                        $ligand_line = <MAE>;
                        $ligand_line =~ s/^ :://; # il nome del ligando ha solitamente questo prefisso nel file mae
                        $ligand_line =~ s/[\n :"\\\/]//g;
                        $summary_content .= "$basename;$ligand_line;";
                        last;
                    }
                    
                }
                $ligand_line = $newline;
            }
            close MAE;
            
            open(LOG, '<' . $logfile);
            while (my $newline = <LOG>) {
                chomp $newline;
                if ($newline =~ /^ Conf/) {
                    my ($energy,$gradient) = $newline =~ /E = +([\d\.\-]+) \( *([\d\.]+)/;
                    $summary_content .= "$energy;$gradient\n";
                }
            }
            close LOG;
        } else {
            croak "\nE- molecule <$basename> not minimized\n\t";
        }
    }
    printf("\n%s SUMMARY:\n\n%s", clock(), $summary_content);
    open(SUM, '>' . $summary_file);
    print SUM $summary_content;
    close SUM;
    
    # rimuovo un po' di file inutili
    qx/cd $destdir; rm -f BestXP_*_pv.maegz/;
    
    printf("\n%s compressing intermediate files\n", clock());
    my $tozip = '';
    foreach my $basename (keys %old_iofiles) {
        $tozip .= " BestXP_$basename-complexes.mae";
    }
    foreach my $basename (keys %iofiles) {
        $tozip .= " BestXP_$basename.mae";
        $tozip .= " BestXP_$basename.sbc";
        $tozip .= " minipostXP-$basename.in" unless ($PLANARIZE);
        $tozip .= " minipostXP-$basename.com";
    }
    $cmdline = <<ROGER
cd $destdir;
tar -c $tozip | gzip -c9 > intermediate.tar.gz;
rm -rfv $tozip;
ROGER
    ;
    qx/$cmdline/;
}

STEP6: {
    print "\n\n*** STEP 6: rescoring ***\n";
    
    $sourcedir = "$homedir/STEP5_mini_post";
    $destdir = "$homedir/STEP6_rescore_MMGBSA";
    mkdir $destdir;
    chdir $destdir;
    
    # reinizializzo la lista dei file di input
    undef %iofiles;
    opendir(DIR, $sourcedir);
    my @file_list = grep { /minipostXP-(.*)\.maegz/ } readdir(DIR);
    closedir DIR;
    foreach my $infile (@file_list) {
        my ($basename) = $infile =~ /^minipostXP-(.*)\.maegz$/;
        $iofiles{$basename} = $infile;
        copy("$sourcedir/$iofiles{$basename}", $destdir);
    }
    
    # creo i file pose viewer
    printf("\n%s parsing pose viewer files\n", clock());
    foreach my $basename (keys %iofiles) {
        $cmdline = "$bins{'run'} $bins{'pv_convert'} -p $iofiles{$basename}";
        qx/$cmdline/;
        unlink $iofiles{$basename};
        print "    <$basename> parsed\n";
    }
    
    # creo l'input file per Prime
    printf("\n%s MM-GBSA with Prime\n", clock());
    
    foreach my $basename (keys %iofiles) {
        my $incontent;
        
        if ($PRIME_FREEZER) { # calcolo dell'energia on site, senza minimizzazioni
            $incontent = <<ROGER
STRUCT_FILE  minipostXP-$basename\_1_pv.maegz
FROZEN
ROGER
            ;
        } else {
            $incontent = <<ROGER
STRUCT_FILE  minipostXP-$basename\_1_pv.maegz
JOB_TYPE     REAL_MIN
OUT_TYPE     COMPLEX
RFLEXDIST    7
RFLEXGROUP   side
RCONS        ((fillres within 7 (atom.i_psp_Prime_MMGBSA_Ligand 1)) AND NOT (fillres within 5 (atom.i_psp_Prime_MMGBSA_Ligand 1)))
STR_CONS     120
PRIME_OPT    MINIM_NITER         = 50
PRIME_OPT    MINIM_NSTEP         = 200
PRIME_OPT    MINIM_RMSG          = 0.01
PRIME_OPT    MINIM_METHOD        = tn
ROGER
            ;
            
            if ($PLANARIZE) { # patch per forzare la planarità nei sistemi aromatici
                $incontent .= 'PRIME_OPT    PLANARITY_RESTRAINT = 10';
                $incontent .= "\n";
            }
        }
        
        open(INFILE, '>' . "prime_mmgbsa-$basename.inp");
        print INFILE $incontent;
        close INFILE;
        
        # lancio il rescoring
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'prime_mmgbsa'} prime_mmgbsa-$basename.inp -NOJOBID > prime_mmgbsa-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    my $summary_file = 'SUMMARY.csv';
    my $summary_content = "MODEL;LIGAND;MMGBSA_dG_Bind;MMGBSA_dG_Bind(NS)\n";
    foreach my $basename (keys %iofiles) {
        my $logfile = "prime_mmgbsa-$basename.log";
        if (-e $logfile) {
            open(LOG, '<' . $logfile);
            my $recordline = 'null';
            while (my $newline = <LOG>) {
                chomp $newline;
                if ($newline =~ /------------ Averaged Properties -------/) {
                    $recordline =~ s/[: ]//g;
                    $recordline =~ s/,/;/g;
                    $summary_content .= "$basename;$recordline\n";
                } else {
                    $recordline = $newline;
                    next;
                }
            }
            close LOG;
        } else {
            croak("\nE- no MM-GBSA rescore for <$basename>\n\t");
        }
    }
    printf("\n%s SUMMARY:\n\n%s", clock(), $summary_content);
    open(SUM, '>' . $summary_file);
    print SUM $summary_content;
    close SUM;
    
    printf("\n%s compressing intermediate files\n", clock());
    my $tozip = '';
    foreach my $basename (keys %iofiles) {
        $tozip .= " minipostXP-$basename\_1_pv.maegz";
        $tozip .= " prime_mmgbsa-$basename.inp";
        $tozip .= " prime_mmgbsa-$basename-out.csv";
    }
    $cmdline = <<ROGER
cd $destdir;
tar -c $tozip | gzip -c9 > intermediate.tar.gz;
rm -rfv $tozip;
ROGER
    ;
    qx/$cmdline/;
}

STEP7: {
    print "\n\n*** STEP 7: gathering workflow data ***\n";
    
    $sourcedir = "$homedir/STEP6_rescore_MMGBSA";
    $destdir = "$homedir/STEP7_gathering";
    mkdir $destdir;
    chdir $destdir;
    
    # reinizializzo la lista dei file di input
    opendir(DIR, $sourcedir);
    my @file_list = grep { /^prime_mmgbsa-(.*)-out\.maegz$/ } readdir(DIR);
    closedir DIR;
    printf("\n%s parsing maegz files\n", clock());
    foreach my $infile (@file_list) {
        my ($basename) = $infile =~ /prime_mmgbsa-(.+)-out\.maegz/;
        copy("$sourcedir/$infile", "$destdir/$basename.maegz");
        $cmdline = <<ROGER
#!/bin/bash

cd $destdir;
$bins{'enedecomp_parser'} $basename.maegz -shell $SHELL;
rm $basename.maegz
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    opendir(DIR, $destdir);
    @file_list = grep { /\.mae$/ } readdir(DIR);
    closedir DIR;
    printf("\n%s grouping poses per ligand\n", clock());
    my %ligposes;
    foreach my $infile (@file_list) {
        my $ligand_line;
        open(MAE, '<' . $infile);
        while (my $newline = <MAE>) {
            chomp $newline;
            if ($newline =~ / i_m_ct_format/) {
                $newline = <MAE>;
                if ($newline =~ / :::/) {
                    $ligand_line = <MAE>;
                    $ligand_line =~ s/^ :://; # il nome del ligando ha solitamente questo prefisso nel file mae
                    $ligand_line =~ s/[\n :"\\\/]//g;
                }
                if (exists $ligposes{$ligand_line}) {
                    push(@{$ligposes{$ligand_line}}, $infile);
                } else {
                    $ligposes{$ligand_line} = [ $infile ];
                }
                last;
            }
        }
        close MAE;
    }
    foreach my $ligand (keys %ligposes) {
        print "    $ligand...";
        my $maelist = join(' ', @{$ligposes{$ligand}});
        $cmdline = "cat $maelist | gzip -c > ligand_$ligand.maegz";
        qx/$cmdline/;
        print "done\n";
    }
    
    printf("\n%s summary of dG components\n", clock());
    # reinizializzo la lista dei file di input
    opendir(DIR, $destdir);
    @file_list = grep { /\.csv$/ } readdir(DIR);
    closedir DIR;
    
    # faccio un hash di riepilogo dei csv prodotti da enedecomp_parser.pl
    my $csv_summary = { };
    my @pose_list;
    foreach my $infile (@file_list) {
        my ($pose) = $infile =~ /(.+)\.csv$/;
        push(@pose_list, $pose);
        open(CSV, '<' . $infile);
        my $newline = <CSV>; # salto la prima riga d'intestazione
        while ($newline = <CSV>) {
            chomp $newline;
            my @values = split(';', $newline);
            my $resi = sprintf("%04d", $values[0]);
            $csv_summary->{$resi} = { }
                unless (exists $csv_summary->{$resi});
            my $dg_tot = $values[3];
            my $coulomb = $values[4] + $values[5] + $values[11]; # Hbond + Coulomb + SelfCont
            my $vdw = $values[6] + $values[7]; # Packing + vdW
            my $solv = $values[8] + $values[9]; # Lipo + SolvGB
            $csv_summary->{$resi}->{$pose} = [ $dg_tot, $coulomb, $vdw, $solv ];
        }
        close CSV;
    }
    
    my %pose2lig;
    foreach my $ligand (keys %ligposes) {
        foreach my $mae (@{$ligposes{$ligand}}) {
            my ($pose) = $mae =~ /(.+)\.mae$/;
            $pose2lig{$pose} = $ligand;
        }
    }
    
    # filtro solo i residui condivisi almeno dal $ratio delle pose
    my $ref = scalar keys %pose2lig;
    my $ratio = 0.75;
#     printf("    Entries parsed.....: %d\n", scalar keys %{$csv_summary});
    foreach my $res (keys %{$csv_summary}) {
        my $tot = scalar keys %{$csv_summary->{$res}};
        if ($tot <= ($ref * $ratio)) {
            delete $csv_summary->{$res};
        }
    }
#     printf("    Entries filtered...: %d\n", scalar keys %{$csv_summary});
    
    # Scrivo il csv di riepilogo
    my %outfile = ('dG' => '0', 'Coulomb' => '1', 'VdW' => '2', 'Solv' => '3');
    foreach my $filename (keys %outfile) {
        print "    $filename term...";
        open(CSV, '>' . 'enedecomp_' . $filename . '.csv');
        my $header = 'POSE;LIGAND;res_' . join(';res_', sort keys %{$csv_summary}) . "\n";
        print CSV $header;
        my %resi_values;
        foreach my $pose (@pose_list) {
            my $row = $pose . ';' . $pose2lig{$pose};
            foreach my $resi (sort keys %{$csv_summary}) {
                $resi_values{$resi} = [ ] unless (exists $resi_values{$resi});
                if (exists $csv_summary->{$resi}->{$pose}) {
                    my $value = $csv_summary->{$resi}->{$pose}->[$outfile{$filename}];
                    $row .= ';' . $value;
                    push(@{$resi_values{$resi}}, $value);
                } else {
                    $row .= ';NA';
                }
            }
            $row .= "\n";
            print CSV $row;
        }
        
        # calcolo i range interquartile per ogni residuo
        my %resi_stats;
        foreach my $key (sort keys %resi_values) {
            my $stat = Statistics::Descriptive::Full->new();
            $stat->add_data(@{$resi_values{$key}});
            my ($q1, $q2, $q3) = ($stat->quantile(1), $stat->quantile(2), $stat->quantile(3));
            my $iqr = $q3 -$q1;
            my $lower = $q1 - (1.5 * $iqr);
            my $upper = $q3 + (1.5 * $iqr);
            $resi_stats{$key} = [ $lower, $q1, $q2, $q3, $upper ];
        }
        
        my %statlabels = ('0' => 'LOWER', '1' => 'Q1', '2' =>  'Q2', '3' => 'Q3', '4' => 'UPPER');
        my $separator = ';' x 3 . ";\n";
        print CSV $separator;
        foreach my $statlabel (sort keys %statlabels) {
            my $row = ';' . $statlabels{$statlabel};
            foreach my $resi (sort keys %resi_stats) {
                $row .= sprintf(";%.3f", $resi_stats{$resi}->[$statlabel]);
            }
            $row .= "\n";
            print CSV $row;
        }
        
        close CSV;
        print "done\n";
    }
    
    my $tot_records = scalar @pose_list;
    
    printf("\n%s creating box plots...", clock());
    my $inlist = '"enedecomp_Coulomb.csv", "enedecomp_VdW.csv", "enedecomp_dG.csv", "enedecomp_Solv.csv"';
    my $outlist = '"enedecomp_Coulomb.png", "enedecomp_VdW.png", "enedecomp_dG.png", "enedecomp_Solv.png"';
    my $scRipt = <<ROGER
whiskers<-function(infile,outfile) {
    input.table = read.csv(infile , stringsAsFactors=F, na.strings="NA", sep=";");
    input.subset = input.table[1:$tot_records,3:ncol(input.table)]
    colcol = c();
    for (i in 1:length(input.subset)) {
        if(any(is.na(input.subset[,i]))) {
            colcol = c(colcol, "red");
        } else {
            colcol = c(colcol, "blue");
        }
    }
    png(filename = outfile,  width = 1280, height = 800)
    boxplot(input.subset, notch = FALSE, las = 2, col = colcol);
    abline(h = 0, lty = 2);
    dev.off();
}

inlist = c($inlist);
outlist = c($outlist);
for (i in 1:length(inlist)) {
    cat(inlist[i],outlist[i],"\n");
    whiskers(inlist[i],outlist[i]);
}
ROGER
    ;
    open(R, '>' . 'boxplot.R');
    print R $scRipt;
    close R;
    qx/$bins{'R'} boxplot.R/;
    print "done\n";
    
    opendir(DIR, $destdir);
    @file_list = grep { /-complex-/ } readdir(DIR);
    closedir DIR;
    printf("\n%s compressing intermediate files\n", clock());
    my $tozip = 'boxplot.R ' . join(' ', @file_list);
    $cmdline = <<ROGER
cd $destdir;
tar -c $tozip | gzip -c9 > intermediate.tar.gz;
rm -rfv $tozip;
ROGER
    ;
    qx/$cmdline/;
}

FINE: {
    print "\n\n*** YEKNOD ***\n";
    exit;
}

sub quelo { # serve per lanciare job su QUEST
    my ($content, $basename) = @_;
    my $filename = "$basename.quest.sh";
    
    # creo uno shell script di modo che il job possa venire sottomesso tramite QUEST
    open(SH, '>' . $filename);
    # aggiungo questa riga di controllo allo script: prima di terminare lo script 
    # accoda al file 'JOBS_FINISHED.txt' una stringa per dire che ha finito
    $content .= "echo $basename >> JOBS_FINISHED.txt\n";
    
    print SH $content;
    close SH;
    qx/chmod +x $filename/; # rendo il file sh eseguibile
    
    # lancio il file sh su QUEST
    my $string = "$bins{'quest'} -n 1 -q fast $filename";
    qx/$string/;
    
    print "    job <$basename> submitted\n";
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
            print "\r    $finished jobs finished";
            
            # se non ci sono più job in coda o che stanno girando esco dal loop
            last unless ($wait);
            
        } else {
            # se non esiste il file $jobfile significa che non è ancora terminato nemmeno un job
            print "\r    0 jobs finished";
        }
        sleep 5;
    }
    
    # pulisco i file intermedi
    qx/cd $path; rm -f QUEST.job.*.log/;
    qx/cd $path; rm -f *.quest.sh/;
    qx/cd $path; rm -f JOBS_FINISHED.txt/;
    
    print "\n";
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