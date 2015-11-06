#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.04.a    - the docking protocol details are parsed from a 
#                      configuration file (see DONKEYrc file)
#                    - accurate fit of the models to the reference complex
#                    - jobs are submitted as 'slow' (see QUEST '-q' option)
#                    - option '-t' for defining the number of threads used for 
#                      each job (see QUEST '-n' option)
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
use Switch;

## GLOBS ##

our $license = $ENV{LM_LICENSE_FILE}; # licenza di Schrodinger

# percorsi
our $schrodinger = $ENV{SCHRODINGER};
our $riceddario = $ENV{RICEDDARIOHOME};
our $homedir = getcwd();
our $sourcedir;
our $destdir;

# variabili modificabili tramite le opzioni
our $JUMP       = 'STEP1';
our $THREADSN   = 1;
our $DONKEYRC   = $ENV{HOME} . '/.DONKEYrc';

# i vari programmi che verranno usati
my $wheRe = qx/which R/; chomp $wheRe;
our %bins = (
    'glide'             => $schrodinger . '/glide',
    'macromodel'        => $schrodinger . '/macromodel',
    'maesubset'         => $schrodinger . '/utilities/maesubset',
    'prepwizard'        => $schrodinger . '/utilities' . '/prepwizard',
    'prime_mmgbsa'      => $schrodinger . '/prime_mmgbsa',
    'ska'               => $schrodinger . '/utilities' . '/align_binding_sites',
    'run'               => $schrodinger . '/run',
    'structcat'         => $schrodinger . '/utilities' . '/structcat',
    'structconvert'     => $schrodinger . '/utilities' . '/structconvert',
    'compute_centroid'  => $riceddario . '/third_parties/SCHRODINGER' . '/Compute_centroid.py',
    'enedecomp_parser'  => $riceddario . '/third_parties/SCHRODINGER' . '/enedecomp_parser.pl',
    'mae_cleaner'       => $riceddario . '/third_parties/SCHRODINGER' . '/mae_property_cleaner.pl',
    'pv_convert'        => $riceddario . '/third_parties/SCHRODINGER' .  '/pv_convert_3.1.py',
    'split_complexes'   => $riceddario . '/third_parties/SCHRODINGER' . '/split_complexes.py',
    'quest'             => $riceddario . '/Qlite' . '/QUEST.client.pl',
    'R'                 => $wheRe
);

# contenuto del file DONKErc di configurazione del protocollo
our $rc_contents = {
    'deco'      => { }, # opzioni per lo STEP7
    'glide'     => '',  # templato per il job di docking
    'grid'      => '',  # templato per l'allestimento della griglia di docking
    'mini'      => '',  # templato per l'allestimento della minimizzazione
    'post'      => '',  # templato per l'allestimento della minimizzazione post-docking
    'prime'     => '',  # templato per l'allestimento del calcolo MM-GBSA
    'sbc'       => '',  # templato di substructure per la definizione delle shell
    'fit'       => [ ], # opzioni per SKA, il tool per l'allineamento strutturale dei modelli
};

our $ligands;           # la lista dei ligandi da dockare
our $refstruct;         # complesso di riferimento per costruire la griglia
our %iofiles;           # lista degli input files, cambia ad ogni STEP
our $cmdline;           # stringa per lanciare comandi da shell
our %joblist;           # lista dei job attivi

## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    my $help;
    my $workflow;
    GetOptions('help|h' => \$help, 'jump|j=s' => \$JUMP, 'script|s=s' => \$DONKEYRC, 'threads|t=i' => \$THREADSN);
    my $header = <<ROGER
********************************************************************************
DONKEY - DON't use KnimE Yet
release 15.04.a

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
    \$ DONKEY.pl -j STEP4
    
*** OPTIONS ***
    
    -jump|j <STEPX>     start workflow from a specific step
    
    -script|s <file>    docking protocol file
    
    -threads|t <int>    number of threads required for each jobrun 
    
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

PARSERC: { # configurazione del protocollo
    
    unless (-e $DONKEYRC) {
        printf("\n%s W- No DONKErc file found, using default settings\n", clock());
        $DONKEYRC = $ENV{HOME} . '/.DONKEYrc';
        my $template = $riceddario . '/third_parties/SCHRODINGER/DONKEY' . '/DONKEYrc';
        copy($template, $DONKEYRC);
    }
    
    printf("\n%s using <%s>\n", clock(), $DONKEYRC);
    
    # parso il file di configurazione
    open(RC, '<' . $DONKEYRC);
    my $section = 'null';
    while (my $newline = <RC>) {
        chomp $newline;
        next if ($newline =~ m/^#/); # salto le righe di commento
        
        # verifico se inizia una nuova sezione
        if ($newline =~ m/^&end/) {
            $section = 'null';
        } elsif ($newline =~ m/^&/) {
            ($section) = $newline =~ m/^&(.+)/;
            next;
        }
        
        # gestisco i contenuti delle sezioni
        switch ($section) {
            case 'deco' {
                my ($key,$value) = $newline =~ /(\w+) +([\w\.-]+)/;
                $rc_contents->{'deco'}->{$key} = $value;
            }
            
            case 'glide' {
                if ($newline =~ /(GRIDFILE|LIGANDFILE)/) {
                    next; # espressioni "riservate" da bypassare
                } else {
                    $rc_contents->{'glide'} .= $newline . "\n";
                }
            }
            
            case 'grid' {
                if ($newline =~ /(GRID_CENTER|GRIDFILE|RECEP_FILE)/) {
                    next; # espressioni "riservate" da bypassare
                } else {
                    $rc_contents->{'grid'} .= $newline . "\n";
                }
            }
            
            case 'fit' {
                if ($newline =~ /(-NOJOBID|-j)/) {
                    next; # espressioni "riservate" da bypassare
                } else {
                    push(@{$rc_contents->{'fit'}}, $newline);
                }
            }
            
            case 'mini' {
                if ($newline =~ /(INPUT_STRUCTURE_FILE|OUTPUT_STRUCTURE_FILE|JOB_TYPE|USE_SUBSTRUCTURE_FILE)/) {
                    next; # espressioni "riservate" da bypassare
                } else {
                    $rc_contents->{'mini'} .= $newline . "\n";
                }
            }
            
            case 'post' {
                if ($newline =~ /(mae|maegz)/) {
                    next; # espressioni "riservate" da bypassare
                } else {
                    $rc_contents->{'post'} .= $newline . "\n";
                }
            }
            
            case 'prime' {
                if ($newline =~ /(STRUCT_FILE)/) {
                    next; # espressioni "riservate" da bypassare
                } else {
                    $rc_contents->{'prime'} .= $newline . "\n";
                }
            }
            
            case 'sbc' {
                $rc_contents->{'sbc'} .= $newline . "\n";
            }
            
            else {
                next;
            }
        }
        
    }
    close RC;
    
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
    print "\n\n*** STEP 1: preparing models ***\n";
    
    $sourcedir = $homedir;
    $destdir = "$sourcedir/STEP1_preparation";
    mkdir $destdir;
    chdir $destdir;
    
    # cerco i file di input
    opendir(DIR, $sourcedir);
    my @file_list = grep { /\.\w{3,5}$/ } readdir(DIR);
    closedir DIR;
    for my $infile (@file_list) {
        if ($infile =~ /\.mae$/) { # complesso di riferimento per costruire la griglia
            $refstruct = $infile;
        } elsif ($infile =~ /\.maegz$/) { # lista dei ligandi
            $ligands = $infile;
        } elsif ($infile =~ /\.pdb$/) { # lista dei recettori
            my ($basename) = $infile =~ /(.+)\.pdb/;
            $iofiles{$basename} = $infile;
        } else {
            next;
        }
    }
    
    # lancio il PrepWizard, assegno ex-novo gli idrogeni (-rehtreat), senza fare minimizzazioni preliminari (-noimpref)
    printf("\n%s adding/replacing hydrogens\n", clock());
    foreach my $basename (keys %iofiles) {
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'prepwizard'} -noimpref -rehtreat $sourcedir/$iofiles{$basename} prep-$basename.mae -NOJOBID > prep-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    # allineo i modelli ad un subset di residui del complesso di riferimento (a
    # meno che non sia esplicitamente specificato nel file di configurazione il
    # fitting verrà effettuato sui residui che definiscono la cavità di binding)
    printf("\n%s fitting models to the reference complex\n", clock());
    my $prepared_maes = "../$refstruct";
    foreach my $basename (sort keys %iofiles) {
        $prepared_maes .= " prep-$basename.mae";
    }
    my $opts = join(' ', @{$rc_contents->{'fit'}});
    $cmdline = "$bins{'ska'} $opts -jobname SKA $prepared_maes -NOJOBID > SKA.log";
    qx/$cmdline/;
    
    # splitto i modelli fittati in singoli file mae
    my $skanum = 2;
    foreach my $basename (sort keys %iofiles) {
        my $skaname= "ska-$basename.mae";
        $cmdline = "$bins{'maesubset'} -n $skanum SKA-align-final.maegz > $skaname";
        qx/$cmdline/;
        $skanum++;
    }
    
    # estraggo il ligando dalla struttura di riferimento
    $cmdline = <<ROGER
$bins{'run'} $bins{'pv_convert'} -l $sourcedir/$refstruct;
mv $sourcedir/*_lig.mae $destdir/toclean.mae;
$bins{'mae_cleaner'} toclean.mae;
rm toclean.mae;
mv toclean-cleaned.mae REFLIG.mae;
ROGER
    ;
    qx/$cmdline/;
    
    # aggiungo il ligando ad ogni modello preparato e creo il pose viewer
    printf("\n%s complexing models\n", clock());
    foreach my $basename (keys %iofiles) {
        print "    $basename...\n";
        $cmdline = <<ROGER
$bins{'structcat'} -imae ska-$basename.mae -imae REFLIG.mae -omae cat-$basename.mae;
$bins{'run'} $bins{'pv_convert'} -m cat-$basename.mae;
mv cat-$basename\_complex.mae $basename\-complex.mae;
ROGER
        ;
        qx/$cmdline/;
    }
    
    
    printf("\n%s compressing intermediate files\n", clock());
    
    # ligando dal complesso di riferimento
    my $tozip = "REFLIG.mae"; 
    
    # intermedi del fitting dei modelli sul complesso di riferimento
    $tozip .= " SKA-align-final.maegz";
    $tozip .= " SKA-align-initial.mae";
    $tozip .= " SKA.csv";
    $tozip .= " SKA.log";
    $tozip .= " SKA-matrix.csv";
    $tozip .= " SKA-merged-input.maegz";
    
    foreach my $basename (keys %iofiles) {
        # ri-assegnazione degli atomi di idrogeno
        $tozip .= " $basename-protassign.log";
        $tozip .= " $basename-protassign.mae";
        $tozip .= " $basename-protassign-out.mae";
        
        # output dal PreparationWizard
        $tozip .= " prep-$basename.mae";
        $tozip .= " prep-$basename.log";
        
        # modelli fittati
        $tozip .= " ska-$basename.mae";
        
        # modelli complessati con il ligando di riferimento (con entry separate)
        $tozip .= " cat-$basename.mae";
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
    
    # aggiorno la lista dei file di input
    opendir (DIR, $sourcedir);
    my @filelist = grep { /^(.+)-complex\.mae$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^(.+)-complex\.mae$/;
        $iofiles{$basename}= $filename;
    }
    
    # creo l'input file per MacroModel
    printf("\n%s shell minimization with MacroModel\n", clock());
    foreach my $basename (keys %iofiles) {
        # minimizzazione a shell
        my $incontent = <<ROGER
INPUT_STRUCTURE_FILE $iofiles{$basename}
OUTPUT_STRUCTURE_FILE mini-$basename.maegz
JOB_TYPE MINIMIZATION
USE_SUBSTRUCTURE_FILE True
ROGER
        ;
        # aggiungo parametri specifici dal file di configurazione
        $incontent .= $rc_contents->{'mini'};
    
        open(INFILE, '>' . "mini-$basename.in");
        print INFILE $incontent;
        close INFILE;
        
        # devo fare una copia del file sbc per ogni modello, uso il templato
        # fornito dal file di configurazione il basename del file deve essere
        # identico al basename del file mae di input
        my $sbcfilename = $iofiles{$basename};
        $sbcfilename =~ s/mae$/sbc/;
        open(INFILE, '>' . $sbcfilename);
        print INFILE $rc_contents->{'sbc'};
        close INFILE;
        
        # lancio la minimizzazione
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
cp $sourcedir/$iofiles{$basename} $destdir;
$bins{'macromodel'} mini-$basename.in -NOJOBID > mini-$basename.log;
rm $iofiles{$basename};
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    my $summary_file = 'SUMMARY.csv';
    my $summary_content = "MODEL;ENERGY;GRADIENT\n";
    foreach my $basename (keys %iofiles) {
        my $logfile = "mini-$basename.log";
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
    foreach my $basename (keys %iofiles) {
        $tozip .= " mini-$basename.in";         # run input file
        $tozip .= " mini-$basename.com";        # run input file in formato com
        $tozip .= " $basename-complex.sbc";     # shell di minimizzazione
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
    my @filelist = grep { /^mini-(.+)\.maegz$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^mini-(.+)\.maegz$/;
        $iofiles{$basename}= $filename;
    }
    
    # estraggo ligando e recettore
    printf("\n%s parsing mimimized models\n", clock());
    foreach my $basename (keys %iofiles) {
        $cmdline = <<ROGER
$bins{'run'} $bins{'pv_convert'} -r $sourcedir/$iofiles{$basename};
mv $sourcedir/mini-$basename\_recep.maegz $destdir/$basename\_recep.maegz;
$bins{'run'} $bins{'pv_convert'} -l $sourcedir/$iofiles{$basename};
$bins{'structconvert'} -imae $sourcedir/mini-$basename\_lig.maegz -omae $basename\_lig.mae;
rm $sourcedir/mini-$basename\_lig.maegz;
ROGER
        ;
        qx/$cmdline/;
        print "    <$basename> parsed\n";
    }
    
    printf("\n%s generating grid\n", clock());
    foreach my $basename (keys %iofiles) {
        # calcolo il centro della griglia
        $cmdline = <<ROGER
$bins{'compute_centroid'} $basename\_lig.mae;
cat centroid-$basename\_lig.txt
ROGER
        ;
        my $grid_center = qx/$cmdline/;
        
        # input file per definire la griglia
        # le dimensioni della griglia vengono specificate dal file di configurazione
        my $incontent = <<ROGER
GRIDLIG YES
USECOMPMAE YES
$rc_contents->{'grid'}
$grid_center
GRIDFILE grid-$basename.zip
RECEP_FILE $basename\_recep.maegz
ROGER
        ;
        open(INFILE, '>' . "grid-$basename.in");
        print INFILE $incontent;
        close INFILE;
        
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'glide'} grid-$basename.in -NOJOBID > grid-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    printf("\n%s compressing intermediate files\n", clock());
    my $tozip = '';
    foreach my $basename (keys %iofiles) {
        $tozip .= " grid-$basename.in";                 # run input file
        $tozip .= " grid-$basename.out";                # log verboso
        $tozip .= " $basename\_lig.mae";                # ligando di riferimento
        $tozip .= " $basename\_recep.maegz";            # recettore
        $tozip .= " centroid-$basename\_lig.txt";       # coordinate del centro della griglia
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
    
    # aggiorno la lista dei file di input
    opendir (DIR, $sourcedir);
    my @filelist = grep { /^grid-(.+)\.zip$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^grid-(.+)\.zip$/;
        $iofiles{$basename}= $filename;
    }
    
    # cerco la lista dei leganti (se uso DONKEY con l'opzione -j)
    unless ($ligands) {
        opendir(DIR, $homedir);
        my @file_list = grep { /\.maegz$/ } readdir(DIR);
        closedir DIR;
        $ligands = $file_list[0];
    }
    
    printf("\n%s launch GlideXP\n", clock());
    foreach my $basename (keys %iofiles) {
        # input file per il docking
        my $incontent = <<ROGER
GRIDFILE $sourcedir/$iofiles{$basename}
LIGANDFILE $homedir/$ligands
ROGER
        ;
        
        # parametri dal file di configurazione
        $incontent = $rc_contents->{'glide'} . $incontent;
        
        open(INFILE, '>' . "glide-$basename.in");
        print INFILE $incontent;
        close INFILE;
        
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'glide'} glide-$basename.in -NOJOBID > glide-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    my $summary_file = 'SUMMARY.csv';
    my $summary_content = "MODEL;LIGAND;GlideScore;Emodel;E;Eint\n";
    foreach my $basename (keys %iofiles) {
        my $logfile = "glide-$basename.log";
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
    my $tozip = '';
    foreach my $basename (keys %iofiles) {
        $tozip .= " glide-$basename.in";        # run input file
        $tozip .= " glide-$basename.out";       # log verboso
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
    
    # aggiorno la lista dei file di input
    opendir (DIR, $sourcedir);
    my @filelist = grep { /^glide-(.+)_pv\.maegz$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^glide-(.+)_pv\.maegz$/;
        $iofiles{$basename}= $filename;
    }
    
    # splitto il pose viewer di ogni complesso di modo da ottenere un mae per ogni posa
    printf("\n%s parsing pose viewer files\n", clock());
    foreach my $basename (keys %iofiles) {
        $cmdline = <<ROGER
$bins{'run'} $bins{'pv_convert'} -m $sourcedir/$iofiles{$basename};
mv $sourcedir/glide-$basename\_complex.maegz $destdir/$basename\_complex.maegz;
$bins{'structconvert'} -imae $basename\_complex.maegz -omae $basename-complexes.mae;
rm $basename\_complex.maegz;
$bins{'split_complexes'} $basename-complexes.mae;
rm $basename-complexes.mae;
ROGER
        ;
        qx/$cmdline/;
        print "    <$basename> parsed\n";
    }
    
    # reinizializzo la lista dei file di input
    undef %iofiles;
    opendir(DIR, $destdir);
    my @file_list = grep { /-complex-\d+\.mae$/ } readdir(DIR);
    closedir DIR;
    foreach my $infile (@file_list) {
        my ($basename) = $infile =~ /^(.+)\.mae$/;
        $iofiles{$basename} = $infile;
    }
    
    printf("\n%s shell minimization with MacroModel\n", clock());
    # creo l'input file per MacroModel
    foreach my $basename (keys %iofiles) {
        # RUN INPUT FILE
        my $incontent = <<ROGER
$iofiles{$basename}
minipost-$basename.maegz
ROGER
        ;
        # vedi file di conifgurazione per i parametri di minimizzazione
        $incontent .= $rc_contents->{'post'};
        open(INFILE, '>' . "minipost-$basename.com");
        print INFILE $incontent;
        close INFILE;
        
        # devo fare una copia del file sbc per ogni modello, uso il templato
        # fornito dal file di configurazione il basename del file deve essere
        # identico al basename del file mae di input
        my $sbcfilename = $iofiles{$basename};
        $sbcfilename =~ s/mae$/sbc/;
        open(INFILE, '>' . $sbcfilename);
        print INFILE $rc_contents->{'sbc'};
        close INFILE;
        
        # lancio la minimizzazione
#         my $suffix = ($PLANARIZE)? 'com' : 'in'; # quale formato di run input file scelgo?
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'macromodel'} minipost-$basename.com -NOJOBID > minipost-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    my $summary_file = 'SUMMARY.csv';
    my $summary_content = "MODEL;ENERGY;GRADIENT\n";
    foreach my $basename (keys %iofiles) {
        my $logfile = "minipost-$basename.log";
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
    foreach my $basename (keys %iofiles) {
        $tozip .= " $basename.mae";             # complesso da minimizzare
        $tozip .= " minipost-$basename.com";    # run input file in formato com
        $tozip .= " $basename.sbc";             # shell di minimizzazione
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
    
    # aggiorno la lista dei file di input
    opendir (DIR, $sourcedir);
    my @filelist = grep { /^minipost-(.+)\.maegz$/ } readdir(DIR);
    close DIR;
    undef %iofiles;
    foreach my $filename (@filelist) {
        my ($basename) = $filename =~ /^minipost-(.+)\.maegz$/;
        $iofiles{$basename}= $filename;
    }
    
    # creo i file pose viewer
    printf("\n%s parsing pose viewer files\n", clock());
    foreach my $basename (keys %iofiles) {
        $cmdline = <<ROGER
$bins{'run'} $bins{'pv_convert'} -p $sourcedir/$iofiles{$basename};
mv $sourcedir/minipost-$basename\_1_pv.maegz $destdir/$basename\_pv.maegz
ROGER
        ;
        qx/$cmdline/;
        print "    <$basename> parsed\n";
    }
    
    # creo l'input file per Prime
    printf("\n%s MM-GBSA with Prime\n", clock());
    
    foreach my $basename (keys %iofiles) {
        my $incontent = "STRUCT_FILE  $basename\_pv.maegz\n";
        $incontent .= $rc_contents->{'prime'}; # vedi file di configurazione
        open(INFILE, '>' . "prime-$basename.inp");
        print INFILE $incontent;
        close INFILE;
        
        # lancio il rescoring
        $cmdline = <<ROGER
#!/bin/bash
export SCHRODINGER=$schrodinger
export LM_LICENSE_FILE=$license

cd $destdir;
$bins{'prime_mmgbsa'} prime-$basename.inp -NOJOBID > prime-$basename.log
ROGER
        ;
        quelo($cmdline, $basename);
    }
    
    job_monitor($destdir);
    
    my $summary_file = 'SUMMARY.csv';
    my $summary_content = "MODEL;LIGAND;MMGBSA_dG_Bind;MMGBSA_dG_Bind(NS)\n";
    foreach my $basename (keys %iofiles) {
        my $logfile = "prime-$basename.log";
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
        $tozip .= " $basename\_pv.maegz";       # complesso in formato pose viewer
        $tozip .= " prime-$basename.inp";       # run input file
        $tozip .= " prime-$basename-out.csv";   # voci della project table
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
    my @file_list = grep { /^prime-(.*)-out\.maegz$/ } readdir(DIR);
    closedir DIR;
    
    # lancio lo script enedecomp_parser.pl
    printf("\n%s parsing maegz files\n", clock());
    foreach my $infile (@file_list) {
        my ($basename) = $infile =~ /prime-(.+)-out\.maegz/;
        copy("$sourcedir/$infile", "$destdir/$basename.maegz");
        $cmdline = <<ROGER
#!/bin/bash

cd $destdir;
$bins{'enedecomp_parser'} $basename.maegz -shell $rc_contents->{'deco'}->{'shell'};
rm $basename.maegz
ROGER
        ;
        quelo($cmdline, $basename);
    }
    job_monitor($destdir);
    
    printf("\n%s summary of dG components\n", clock());
    # reinizializzo la lista dei file di input
    opendir(DIR, $destdir);
    @file_list = grep { /\.csv$/ } readdir(DIR);
    closedir DIR;
    
    # faccio una tabella di riepilogo dei csv prodotti da enedecomp_parser.pl
    my $csv_summary = { };
    my @pose_list;
    foreach my $infile (@file_list) {
        
        # ogni file csv prodotto è relativo ad una posa
        my ($pose) = $infile =~ /(.+)\.csv$/;
        push(@pose_list, $pose);
        
        # parso il csv prodotto per ogni posa
        open(CSV, '<' . $infile);
        my $newline = <CSV>; # salto la prima riga (intestazione)
         
        while ($newline = <CSV>) {
            chomp $newline;
            my @values = split(';', $newline);
            next if ($values[2] eq 'OUT'); # il residuo è fuori dalla shell, non lo considero
            my $resi = sprintf("%04d", $values[0]);
            $csv_summary->{$resi} = { }
                unless (exists $csv_summary->{$resi});
            my $dg_tot = $values[4];
            my $coulomb = $values[5] + $values[6] + $values[12]; # Hbond + Coulomb + SelfCont
            my $vdw = $values[7] + $values[8];                   # Packing + vdW
            my $solv = $values[9] + $values[10];                 # Lipo + SolvGB
            $csv_summary->{$resi}->{$pose} = [ $dg_tot, $coulomb, $vdw, $solv ];
        }
        
        close CSV;
    }
    
    # filtro solo i residui condivisi almeno dal $ratio delle pose
    my $ref = scalar @pose_list; # numero totale di pose
    my $ratio = $rc_contents->{'deco'}->{'ratio'};
    printf("    Entries parsed.....: %d\n", scalar keys %{$csv_summary});
    foreach my $res (keys %{$csv_summary}) {
        my $tot = scalar keys %{$csv_summary->{$res}};
        if ($tot <= ($ref * $ratio)) {
            delete $csv_summary->{$res};
        }
    }
    printf("    Entries filtered...: %d\n", scalar keys %{$csv_summary});
    
    # Scrivo il csv di riepilogo
    my %outfile = ('dG' => '0', 'Coulomb' => '1', 'VdW' => '2', 'Solv' => '3');
    foreach my $filename (keys %outfile) {
        print "    $filename term...";
        open(CSV, '>' . 'enedecomp_' . $filename . '.csv');
        my $header = 'MODEL;res_' . join(';res_', sort keys %{$csv_summary}) . "\n";
        print CSV $header;
        
        my %resi_values;
        foreach my $pose (@pose_list) {
            my $row = $pose;
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
            my $row = $statlabels{$statlabel};
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
    my $wider = 15 * scalar keys %{$csv_summary};
    $wider = 1280 if ($wider < 1280); # larghezza minima dell'immagine
    printf("\n%s creating box plots...", clock());
    my $inlist = '"enedecomp_Coulomb.csv", "enedecomp_VdW.csv", "enedecomp_dG.csv", "enedecomp_Solv.csv"';
    my $outlist = '"enedecomp_Coulomb.ps", "enedecomp_VdW.ps", "enedecomp_dG.ps", "enedecomp_Solv.ps"';
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
    postscript(file = outfile,  width = $wider, height = 800)
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
    
    # comprimo i csv prodotti da enedecomp_parser.pl e lo script per produrre i boxplot
    printf("\n%s compressing intermediate files\n", clock());
    opendir(DIR, $destdir);
    @file_list = grep { /-complex-/ } readdir(DIR);
    closedir DIR;
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
    my $string = "$bins{'quest'} -n $THREADSN -q slow $filename";
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