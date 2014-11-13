#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
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

## GLOBS ##

# flag per mantenere planari gli anelli, funza solo però per i forcefield OPLS_200X
our $PLANARIZE = 0;

# flag per stabilire se prime_mmgbsa deve condurre una minimizzazione ($PRIME_FREEZER = 0) oppure no ($PRIME_FREEZER = 1)
our $PRIME_FREEZER = 0;

# flag per saltare ad uno step specifico
our $jump = 'STEP1';

# percorsi di default
our $schrodinger = $ENV{SCHRODINGER};
our $pandora = $ENV{RICEDDARIOHOME};
our $homedir = getcwd();
our $sourcedir;
our $destdir;

# TUTORIAL FILE
our $doc = $ENV{PANDORAHOME} . '/Maestro_Script/AhR_full_protocol/README.txt';

# licenza per accedere ai programmi Schrodinger
our $license = $ENV{LM_LICENSE_FILE};

# i vari programmi che verranno usati
our %bins = (
    'glide'             => $schrodinger . '/glide',
    'compute_centroid'  => $pandora . '/Maestro_Script/Compute_centroid.py', # calcola il centroide usando le coordinate atomiche di un file .mae
    'macromodel'        => $schrodinger . '/macromodel',
    'prepwizard'        => $schrodinger . '/utilities/prepwizard', # preparation wizard
    'prime_mmgbsa'      => $schrodinger . '/prime_mmgbsa',
    'pv_convert'        => $pandora . '/Maestro_Script/pv_convert.py', # manipolatore per files pose viewer
    'quest'             => $pandora . '/QUEST/QUEST.client.pl', # gestore di code mio
    'run'               => $schrodinger . '/run', # shell script per lanciare gli script Schrodinger
    'split_complexes'   => $pandora . '/Maestro_Script/split_complexes.py', # splitta un file pose viewer nei complessi delle singole pose
    'structcat'         => $schrodinger . '/utilities/structcat', # concatena file mae
    'structconvert'     => $schrodinger . '/utilities/structconvert', # converte formati
);

# file di input iniziali (verranno cercati in automatico nello step 0)
our $ligands; # lista dei leganti già ottimizzati
our $refstruct; # complesso recettore/ligando di riferimento
our %iofiles; # file di input/output che vengono passati da uno step all'altro

# stringa contenente righe di comando per la shell
our $cmdline;

# lista dei job lanciati con quest
our %joblist;


## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    my $help;
    my $workflow;
    GetOptions('planarize|p' => \$PLANARIZE, 'freeze|f' => \$PRIME_FREEZER, 'help|h' => \$help, 'jump|j=s' => \$jump, 'workflow|w' => \$workflow);
    my $header = <<ROGER
********************************************************************************
AhR Full Protocol
release 14.11.a

Copyright (c) 2014, BonatiLab <bonati.lab\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
ROGER
    ;
    print $header;
    
    if ($help) {
        my $spiega = <<ROGER

*** SYNOPSIS ***
    
    # default usage
    \$ AhR_full_protocol.pl
    
    # custom mode
    \$ AhR_full_protocol.pl -f
    \$ AhR_full_protocol.pl -j STEP4
    
*** OPTIONS ***
    
    -freeze|f           do not perform mimimization during the rescoring step
                        (ie minimization with prime_mmgbsa)
    
    -jump|j <STEPX>     start workflow from a specific step
    
    -planarize|p        enforce planarity of aromatic rings during post-docking 
                        minimization step, recommended if you have ligands with 
                        extended coniugated aromatic systems
    
    -workflow|w         do nothing, only print an exaplanation of the workflow
    
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
    } elsif ($workflow) {
        open(DOC, '<' . $doc);
        while (my $newline = <DOC>) {
            print $newline;
        }
        close DOC;
        goto FINE;
    }
}

# READY2GO: {
#     # faccio un check per assicurarmi che ci siano tutti i programmi
#     foreach my $bin (keys %bins) {
#         if (-e $bins{$bin}) {
#             next;
#         } else {
#             croak "\nE- file <$bins{$bin}> not found\n\t";
#         }
#     }
#     
#     # verifico che il server QUEST sia su
#     my $status = qx/$bins{'quest'} -l 2>&1/;
#     if ($status =~ /E\- Cannot open socket/) {
#         croak "\nE- QUEST server seems to be down\n\t";
#     }
# }
# 
# print "\n*** WARNING: do not use CTRL+C during job submission ***\n";
# goto $jump;
# 
# STEP1: {
#     print "\n*** STEP 0: checking input files ***\n";
#     
#     # NOTA: nella cartella da cui lancio lo script devo avere:
#     # -> un file .mae del complesso di riferimento
#     # -> un file .maegz della libreria di ligandi già opportunamente otiimizzati
#     # -> più file .pdb relativi ai diversi modelli
#     
#     $sourcedir = getcwd();
#     opendir(DIR, $sourcedir);
#     my @file_list = grep { /\.\w{3,5}$/ } readdir(DIR);
#     closedir DIR;
#     
#     my $mods = ' ';
#     for my $infile (@file_list) {
#         if ($infile =~ /\.mae$/) {
#             $refstruct = $infile;
#         } elsif ($infile =~ /\.maegz$/) {
#             $ligands = $infile;
#         } elsif ($infile =~ /\.pdb$/) {
#             my ($basename) = $infile =~ /(.+)\.pdb/;
#             $iofiles{$basename} = $infile;
#             $mods .= "$infile\n                         ";
#         } else {
#             next;
#         }
#     }
#     printf("\n%s SUMMARY CHECK\n", clock());
#     printf("\n    FLAG freeze........: %d\n\n    FLAG planarize.....: %d\n", $PRIME_FREEZER, $PLANARIZE);
#     printf("\n    ligands library....: %s\n\n    reference complex..: %s\n\n    input models.......:%s", $ligands, $refstruct, $mods);
#     print "\n\nInput files are alright? [Y/n] ";
#     my $ans = <STDIN>;
#     chomp $ans;
#     $ans = 'y' unless ($ans);
#     unless ($ans =~ /[Yy]/) {
#         print "\naborting";
#         goto FINE;
#     }
# 
#     print "\n\n*** STEP 1: preparing models ***\n";
#     
#     $sourcedir = $homedir;
#     $destdir = "$sourcedir/STEP1_preparation";
#     mkdir $destdir;
#     chdir $destdir;
#     
#     # copio i file di input
#     copy("$sourcedir/$refstruct", $destdir);
#     foreach my $basename (keys %iofiles) {
#         copy("$sourcedir/$iofiles{$basename}", $destdir);
#     }
#     
#     # lancio il preparation wizard per ogni modello
#     printf("\n%s parsing models with PrepWizard\n", clock());
#     foreach my $basename (keys %iofiles) {
#         # con il PrepWizard faccio:
#         # -> allinemanto strutturale di ogni modello al complesso di riferimento (-reference_st_file)
#         # -> evito di fare minimizzazioni preliminari (-noimpref)
#         # -> assegno ex-novo gli idrogeni (-rehtreat)
#         $cmdline = <<ROGER
# #!/bin/bash
# export SCHRODINGER=$schrodinger
# export LM_LICENSE_FILE=$license
# 
# cd $destdir;
# $bins{'prepwizard'} -reference_st_file $refstruct -noimpref -rehtreat $iofiles{$basename} prep-$basename.mae -NOJOBID > prep-$basename.log
# ROGER
#         ;
#         quelo($cmdline, $basename);
#     }
#     
#     job_monitor($destdir);
# 
#     # estraggo il ligando dalla struttura di riferimento e rinomino il file
#     $cmdline = "$bins{'run'} $bins{'pv_convert'} -l $refstruct";
#     qx/$cmdline/;
#     my $ligandfile = $refstruct;
#     $ligandfile =~ s/\.mae$/_1_lig.mae/;
#     rename($ligandfile, 'THS-017.mae');
#     $ligandfile = 'THS-017.mae';
#     
#     printf("\n%s complexing models\n", clock());
#     # aggiungo il ligando ad ogni modello preparato e creo il pose viewer
#     foreach my $basename (keys %iofiles) {
#         print "    $basename...";
#         $cmdline = "$bins{'structcat'} -imae prep-$basename.mae -imae $ligandfile -omae prep-THS-$basename.mae";
#         qx/$cmdline/;
#         $cmdline = "$bins{'run'} $bins{'pv_convert'} -m prep-THS-$basename.mae";
#         qx/$cmdline/;
#         if (-e "prep-THS-$basename\_complex.mae") {
#             rename ("prep-THS-$basename\_complex.mae", "prep-THS-$basename\-complex.mae");
#             print "done\n";
#         } else {
#             croak "\nE- molecule <prep-$basename.mae> NOT complexed\n\t";
#         }
#     }
#     
#     printf("\n%s compressing intermediate files\n", clock());
#     my $tozip = "$refstruct $ligandfile ";
#     foreach my $basename (keys %iofiles) {
#         $tozip .= " $basename.pdb";
#         $tozip .= " $basename-protassign.log";
#         $tozip .= " $basename-protassign.mae";
#         $tozip .= " $basename-protassign-out.mae";
#         $tozip .= " prep-$basename.mae";
#         $tozip .= " prep-$basename.log";
#         $tozip .= " prep-THS-$basename.mae";
# #         $tozip .= " prep-THS-$basename.log";
#     }
#     $cmdline = <<ROGER
# cd $destdir;
# tar -c $tozip | gzip -c9 > intermediate.tar.gz;
# rm -rfv $tozip;
# ROGER
#     ;
#     qx/$cmdline/;
# }
# 
# STEP2: {
#     print "\n\n*** STEP 2: minimization ***\n";
#     
#     $sourcedir = "$homedir/STEP1_preparation";
#     $destdir = "$homedir/STEP2_mini_THS";
#     mkdir $destdir;
#     chdir $destdir;
#     
#     # aggiorno la lista dei file di input e li copio nella nuova directory
#     opendir (DIR, $sourcedir);
#     my @filelist = grep { /^prep-THS-(.+)-complex.mae$/ } readdir(DIR);
#     close DIR;
#     undef %iofiles;
#     foreach my $filename (@filelist) {
#         my ($basename) = $filename =~ /^prep-THS-(.+)-complex.mae$/;
#         $iofiles{$basename}= $filename;
#         copy("$sourcedir/$iofiles{$basename}", $destdir);
#     }
#     
#     # creo l'input file per MacroModel
#     printf("\n%s shell minimization with MacroModel\n", clock());
#     foreach my $basename (keys %iofiles) {
#         # minimizzazione a shell con 1500 steps di Truncated Newton Coinugated Gradient (TNCG)
#         my $incontent = <<ROGER
# INPUT_STRUCTURE_FILE $iofiles{$basename}
# OUTPUT_STRUCTURE_FILE mini-THS-$basename.maegz
# JOB_TYPE MINIMIZATION
# FORCE_FIELD OPLS_2005
# SOLVENT Water
# USE_SUBSTRUCTURE_FILE True
# MINI_METHOD TNCG
# MAXIMUM_ITERATION 1500
# CONVERGE_ON Gradient
# ROGER
#         ;
#         open(INFILE, '>' . "mini-THS-$basename.in");
#         print INFILE $incontent;
#         close INFILE;
#         
#         # definisco le shell a cui applicare i constraint:
#         # -> minimizzazione senza vincoli per il ligando e le sidechain in un intorno di 5A
#         # -> constraint di 200kJ/A sul per il backbone nell'intorno di 5A
#         # -> constraint di 500kJ/A sui residui nella fascia tra 5A e 7A
#         # -> posizioni congelate oltre i 7A
#         
#         # queste sono le shell di Domenico che riproducono alla perfezione i run precedenti
#         $incontent = <<ROGER
#  ASL1       0 ( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) )
#  ASL2 200.000 ( ((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) ) and not (( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) ))
#  ASL2 500.000 ( ((not (mol.entry 2) and fillres within 7 (mol.entry 2 ) )) and not ((( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) or (((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )))) ) and not ((( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) )) or (( ((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) ) and not (( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) ))))
#  ASL2  -1.000 ( (not ((( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) or (((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ))) or (((not (mol.entry 2) and fillres within 7 (mol.entry 2 ) )) and not ((( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) or (((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ))))))) ) and not ((( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) )) or (( ((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) ) and not (( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) ))) or (( ((not (mol.entry 2) and fillres within 7 (mol.entry 2 ) )) and not ((( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) or (((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )))) ) and not ((( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) )) or (( ((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) ) and not (( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) ))))))
# ROGER
#         ;
#         
# #         # queste sono le shell mie, "sembrano" formalmente corrette ma NON danno gli stessi risultati facendo subtract in sequenza dei diversi set (il modo di fare dall'interfaccia grafica con MacroModel)
# #         $incontent = <<ROGER
# #  ASL1       0 ( ( fillres within 5 ( mol.entry 2 ) ) AND NOT ( backbone ) )
# #  ASL2 200.000 ( ( fillres within 5 ( mol.entry 2 ) ) AND ( backbone ) )
# #  ASL2 500.000 ( ( fillres within 7 ( mol.entry 2 ) ) AND NOT ( fillres within 5 ( mol.entry 2 ) ) )
# #  ASL2  -1.000 ( ( mol.entry 1 ) AND NOT ( fillres within 7 ( mol.entry 2 ) ) )
# # ROGER
# #         ;
# 
#         # devo fare una copia del file sbc per ogni modello, il basename del file deve essere identico al basename del file mae di input
#         my $sbcfilename = $iofiles{$basename};
#         $sbcfilename =~ s/mae$/sbc/;
#         open(INFILE, '>' . $sbcfilename);
#         print INFILE $incontent;
#         close INFILE;
#         
#         # lancio la minimizzazione
#         $cmdline = <<ROGER
# #!/bin/bash
# export SCHRODINGER=$schrodinger
# export LM_LICENSE_FILE=$license
# 
# cd $destdir;
# $bins{'macromodel'} mini-THS-$basename.in -NOJOBID > mini-THS-$basename.log
# ROGER
#         ;
#         quelo($cmdline, $basename);
#     }
#     
#     job_monitor($destdir);
#     
#     my $summary_file = 'SUMMARY.csv';
#     my $summary_content = "MODEL;ENERGY;GRADIENT\n";
#     foreach my $basename (keys %iofiles) {
#         my $logfile = "mini-THS-$basename.log";
#         if (-e $logfile) {
#             open(LOG, '<' . $logfile);
#             while (my $newline = <LOG>) {
#                 chomp $newline;
#                 if ($newline =~ /^ Conf/) {
#                     my ($energy,$gradient) = $newline =~ /E = +([\d\.\-]+) \( *([\d\.]+)/;
#                     $summary_content .= "$basename;$energy;$gradient\n";
#                 }
#             }
#             close LOG;
#         } else {
#             croak "\nE- molecule <$basename> not minimized\n\t";
#         }
#     }
#     printf("\n%s SUMMARY:\n\n%s", clock(), $summary_content);
#     open(SUM, '>' . $summary_file);
#     print SUM $summary_content;
#     close SUM;
#     
#     printf("\n%s compressing intermediate files\n", clock());
#     my $tozip = '';
#     qx/rm -f *.pdb/; # i modelli iniziali
#     foreach my $basename (keys %iofiles) {
#         $tozip .= " prep-THS-$basename-complex.mae";
#         $tozip .= " mini-THS-$basename.in";
#         $tozip .= " mini-THS-$basename.com";
#         $tozip .= " prep-THS-$basename-complex.sbc";
#     }
#     $cmdline = <<ROGER
# cd $destdir;
# tar -c $tozip | gzip -c9 > intermediate.tar.gz;
# rm -rfv $tozip;
# ROGER
#     ;
#     qx/$cmdline/;
# }
# 
# STEP3: {
#     print "\n\n*** STEP 3: grid setting ***\n";
#     
#     $sourcedir = "$homedir/STEP2_mini_THS";
#     $destdir = "$homedir/STEP3_grid_THS";
#     mkdir $destdir;
#     chdir $destdir;
#     
#     # aggiorno la lista dei file di input e li copio nella nuova directory
#     opendir (DIR, $sourcedir);
#     my @filelist = grep { /^mini-THS-(.+).maegz$/ } readdir(DIR);
#     close DIR;
#     undef %iofiles;
#     foreach my $filename (@filelist) {
#         my ($basename) = $filename =~ /^mini-THS-(.+).maegz$/;
#         $iofiles{$basename}= $filename;
#         copy("$sourcedir/$iofiles{$basename}", $destdir);
#     }
#     
#     # estraggo ligando e recettore
#     printf("\n%s parsing mimimized models\n", clock());
#     foreach my $basename (keys %iofiles) {
#         $cmdline = "$bins{'run'} $bins{'pv_convert'} -l $iofiles{$basename}";
#         qx/$cmdline/;
#         $cmdline = "$bins{'run'} $bins{'pv_convert'} -r $iofiles{$basename}";
#         qx/$cmdline/;
#         $cmdline = "$bins{'structconvert'} -imae mini-THS-$basename\_1_lig.maegz -omae mini-THS-$basename\_1_lig.mae";
#         qx/$cmdline/;
#         unlink "mini-THS-$basename\_1_lig.maegz";
#         print "    <$basename> parsed\n";
#     }
#     
#     printf("\n%s generating grid\n", clock());
#     foreach my $basename (keys %iofiles) {
#         # calcolo il centro della griglia usando le coordinate atomiche del ligando estratto precedentemente
#         $cmdline = "$bins{'compute_centroid'} mini-THS-$basename\_1_lig.mae; ";
#         $cmdline .= "cat centroid-mini-THS-$basename\_1_lig.txt";
#         my $grid_center = qx/$cmdline/;
#         
#         # input file per definire la griglia
#         my $incontent = <<ROGER
# GRIDLIG YES
# USECOMPMAE YES
# INNERBOX 10, 10, 10
# ACTXRANGE 22.000000
# ACTYRANGE 22.000000
# ACTZRANGE 22.000000
# $grid_center
# OUTERBOX 22.000000, 22.000000, 22.000000
# GRIDFILE $basename-grid-THS.zip
# RECEP_FILE mini-THS-$basename\_1_recep.maegz
# ROGER
#         ;
#         open(INFILE, '>' . "grid_THS_$basename.in");
#         print INFILE $incontent;
#         close INFILE;
#         
#         $cmdline = <<ROGER
# #!/bin/bash
# export SCHRODINGER=$schrodinger
# export LM_LICENSE_FILE=$license
# 
# cd $destdir;
# $bins{'glide'} grid_THS_$basename.in -NOJOBID > grid_THS_$basename.log
# ROGER
#         ;
#         quelo($cmdline, $basename);
#     }
#     
#     job_monitor($destdir);
#     
#     printf("\n%s SUMMARY:\n", clock());
#     foreach my $basename (keys %iofiles) {
#         my $logfile = "grid_THS_$basename.out";
#         if (-e $logfile) {
#             print "  grid prepared for molecule <$basename>\n";
#         } else {
#             croak "\nE- grid not prepared for molecule <$basename>\n\t";
#         }
#     }
#     
#     # rimuovo un po' di file inutili
#     qx/cd $destdir; rm -f *_1_lig.*/;
#     
#     printf("\n%s compressing intermediate files\n", clock());
#     my $tozip = '';
#     qx/rm -f *.pdb/; # i modelli iniziali
#     foreach my $basename (keys %iofiles) {
#         $tozip .= " grid_THS_$basename.in";
#         $tozip .= " grid_THS_$basename.out";
#         $tozip .= " mini-THS-$basename\_1_recep.maegz";
#         $tozip .= " mini-THS-$basename.maegz";
#     }
#     $cmdline = <<ROGER
# cd $destdir;
# tar -c $tozip | gzip -c9 > intermediate.tar.gz;
# rm -rfv $tozip;
# ROGER
#     ;
#     qx/$cmdline/;
# }
# 
# STEP4: {
#     print "\n\n*** STEP 4: docking ***\n";
#     
#     $sourcedir = "$homedir/STEP3_grid_THS";
#     $destdir = "$homedir/STEP4_docking_BestXP";
#     mkdir $destdir;
#     chdir $destdir;
#     
#     unless ($ligands) {
#         opendir(DIR, $homedir);
#         my @file_list = grep { /\.maegz$/ } readdir(DIR);
#         closedir DIR;
#         print "\n<$file_list[0]> is the ligands' library? [Y/n] ";
#         my $ans = <STDIN>;
#         chomp $ans;
#         $ans = 'y' unless ($ans);
#         if ($ans =~ /[Yy]/) {
#             $ligands = $file_list[0];
#         } else {
#             print "\naborting";
#             goto FINE;
#         }
#     }
#     
#     # aggiorno la lista dei file di input e li copio nella nuova directory
#     copy("$homedir/$ligands", $destdir);
#     opendir (DIR, $sourcedir);
#     my @filelist = grep { /^(.+)-grid-THS.zip$/ } readdir(DIR);
#     close DIR;
#     undef %iofiles;
#     foreach my $filename (@filelist) {
#         my ($basename) = $filename =~ /^(.+)-grid-THS.zip$/;
#         $iofiles{$basename}= $filename;
#         copy("$sourcedir/$iofiles{$basename}", $destdir);
#     }
#     
#     printf("\n%s launch GlideXP\n", clock());
#     foreach my $basename (keys %iofiles) {
#         # input file per il docking
#         # NOTA: nella versione 2014 hanno introdotto due flag per gestire gli alogeni come accettori/donatori di interazioni tipo Hbond (HBOND_ACCEP_HALO e HBOND_DONOR_HALO di default disabilitate); da notare che i ff disponibili per Glide sono ancora OPLS2001 e OPLS2005
#         my $incontent = <<ROGER
# POSES_PER_LIG 1
# POSTDOCK NO
# WRITE_RES_INTERACTION YES
# WRITE_XP_DESC YES
# USECOMPMAE YES
# MAXREF 800
# RINGCONFCUT 2.500000
# GRIDFILE $iofiles{$basename}
# LIGANDFILE $ligands
# PRECISION XP
# ROGER
#         ;
#         open(INFILE, '>' . "BestXP_$basename.in");
#         print INFILE $incontent;
#         close INFILE;
#         
#         $cmdline = <<ROGER
# #!/bin/bash
# export SCHRODINGER=$schrodinger
# export LM_LICENSE_FILE=$license
# 
# cd $destdir;
# $bins{'glide'} BestXP_$basename.in -NOJOBID > BestXP_$basename.log
# ROGER
#         ;
#         quelo($cmdline, $basename);
#     }
#     
#     job_monitor($destdir);
#     
#     my $summary_file = 'SUMMARY.csv';
#     my $summary_content = "MODEL;LIGAND;GlideScore;Emodel;E;Eint\n";
#     foreach my $basename (keys %iofiles) {
#         my $logfile = "BestXP_$basename.log";
#         if (-e $logfile) {
#             open(LOG, '<' . $logfile);
#             my $ligand;
#             while (my $newline = <LOG>) {
#                 chomp $newline;
#                 if ($newline =~ /^DOCKING RESULTS FOR LIGAND/) {
#                     ($ligand) = $newline =~ /^DOCKING RESULTS FOR LIGAND  *\d+ \((.+)\)/;
#                 } elsif ($newline =~ /^Best XP pose:/) {
#                     my ($glidescore,$emodel,$e,$eint) = $newline =~ /^Best XP pose: +\d+;  GlideScore = +([\-\d\.]+) Emodel = +([\-\d\.]+) E = +([\-\d\.]+) Eint = +([\-\d\.]+)/;
#                     $summary_content .= "$basename;$ligand;$glidescore;$emodel;$e;$eint\n";
#                 } else {
#                     next;
#                 }
#             }
#             close LOG;
#         } else {
#             print"\nW- no pose found for <$basename>\n\t";
#         }
#     }
#     printf("\n%s SUMMARY:\n\n%s", clock(), $summary_content);
#     open(SUM, '>' . $summary_file);
#     print SUM $summary_content;
#     close SUM;
#     
#     printf("\n%s compressing intermediate files\n", clock());
#     my $tozip = " $ligands";
#     foreach my $basename (keys %iofiles) {
#         $tozip .= " BestXP_$basename.in";
#         $tozip .= " BestXP_$basename.out";
#         $tozip .= " $basename-grid-THS.zip";
#     }
#     $cmdline = <<ROGER
# cd $destdir;
# tar -c $tozip | gzip -c9 > intermediate.tar.gz;
# rm -rfv $tozip;
# ROGER
#     ;
#     qx/$cmdline/;
# }
# 
# STEP5: {
#     print "\n\n*** STEP 5: post-dock minimization ***\n";
#     
#     $sourcedir = "$homedir/STEP4_docking_BestXP";
#     $destdir = "$homedir/STEP5_mini_postBestXP";
#     mkdir $destdir;
#     chdir $destdir;
#     
#     # aggiorno la lista dei file di input e li copio nella nuova directory
#     opendir (DIR, $sourcedir);
#     my @filelist = grep { /^BestXP_(.+)\_pv.maegz$/ } readdir(DIR);
#     close DIR;
#     undef %iofiles;
#     foreach my $filename (@filelist) {
#         my ($basename) = $filename =~ /^^BestXP_(.+)\_pv.maegz$/;
#         $iofiles{$basename}= $filename;
#         copy("$sourcedir/$iofiles{$basename}", $destdir);
#     }
#     
#     # splitto il pose viewer di ogni complesso di modo da ottenere un mae per ogni posa
#     printf("\n%s parsing pose viewer files\n", clock());
#     foreach my $basename (keys %iofiles) {
#         $cmdline = "$bins{'run'} $bins{'pv_convert'} -m $iofiles{$basename}";
#         qx/$cmdline/;
#         $cmdline = "$bins{'structconvert'} -imae BestXP_$basename\_complex.maegz -omae BestXP_$basename-complexes.mae";
#         qx/$cmdline/;
#         unlink "BestXP_$basename\_complex.maegz";
#         $cmdline = "$bins{'split_complexes'} BestXP_$basename-complexes.mae";
#         qx/$cmdline/;
#         print "    <$basename> parsed\n";
#     }
#     
#     # reinizializzo la lista dei file di input
#     my %old_iofiles = %iofiles;
#     undef %iofiles;
#     opendir(DIR, $destdir);
#     my @file_list = grep { /-complex-\d+\.mae$/ } readdir(DIR);
#     closedir DIR;
#     foreach my $infile (@file_list) {
#         my ($basename) = $infile =~ /^BestXP_(.+)\.mae$/;
#         $iofiles{$basename} = $infile;
#     }
#     
#     printf("\n%s shell minimization with MacroModel\n", clock());
#     # creo l'input file per MacroModel
#     foreach my $basename (keys %iofiles) {
#         # RUN INPUT FILE
#         my $incontent; my $infilename;
#         if ($PLANARIZE) {
#             # per forzare la planarità sui sistemi aromatici il run input file deve essere scritto nel formato .com meno leggibile (MacroModel converte comunque il formato .in in formato .com prima di lanciare i job)
#             $incontent .= <<ROGER
# $iofiles{$basename}
# minipostXP-$basename.maegz
#  DEBG       0      0      0      0     0.0000     0.0000     0.0000     0.0000
#  SOLV       3      1      0      0     0.0000     0.0000     0.0000     0.0000
#  BDCO       0      0      0      0     0.0000 99999.0000     0.0000     0.0000
#  FFLD      14      1      0      0     1.0000     0.0000     1.0000     0.0000
#  BGIN       0      0      0      0     0.0000     0.0000     0.0000     0.0000
#  SUBS       0      0      0      0     0.0000     0.0000     0.0000     0.0000
#  READ       0      0      0      0     0.0000     0.0000     0.0000     0.0000
#  CONV       2      0      0      0     0.0500     0.0000     0.0000     0.0000
#  MINI       9      0   1500      0     0.0000     0.0010     0.0000     0.0000
#  END        0      0      0      0     0.0000     0.0000     0.0000     0.0000
# ROGER
#             ;
#             $infilename = "minipostXP-$basename.com";
#         } else {
#             $incontent = <<ROGER
# INPUT_STRUCTURE_FILE $iofiles{$basename}
# OUTPUT_STRUCTURE_FILE minipostXP-$basename.maegz
# JOB_TYPE MINIMIZATION
# FORCE_FIELD OPLS_2005
# SOLVENT Water
# USE_SUBSTRUCTURE_FILE True
# MINI_METHOD TNCG
# MAXIMUM_ITERATION 1500
# CONVERGE_ON Gradient
# ROGER
#             ;
#             $infilename = "minipostXP-$basename.in";
#         }
#         
#         open(INFILE, '>' . $infilename);
#         print INFILE $incontent;
#         close INFILE;
#         
#         # SUBSTRUCTURE FILE
#         $incontent = '';
#         # PATCH: applico torsional constraint sul diossano della TCDD
#         #
#         # ATTENZIONE: questa patch funziona SOLO con i file mae contenenti la 
#         # TCDD chiamata "2378-CDD", NON è adatta per altre TCDD create ex-novo
#         open(INFILE, '<' . $iofiles{$basename});
#         my @maecontent = <INFILE>;
#         close INFILE;
#         my @match = grep { /2378-CDD/ } @maecontent;
#         if (scalar @match) {
#             print "      [2378-CDD] found in <$iofiles{$basename}>, applying patch\n";
#             $incontent .= torscons_2378cdd($iofiles{$basename});
#         }
#         
#         # definisco le shell a cui applicare i constraint:
#         # -> minimizzazione senza vincoli per il ligando e le sidechain in un intorno di 5A
#         # -> constraint di 200kJ/A sul per il backbone nell'intorno di 5A
#         # -> constraint di 500kJ/A sui residui nella fascia tra 5A e 7A
#         # -> posizioni congelate oltre i 7A
#         
#         # queste sono le shell di Domenico che riproducono alla perfezione i run precedenti
#         $incontent .= <<ROGER
#  ASL1       0 ( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) )
#  ASL2 200.000 ( ((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) ) and not (( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) ))
#  ASL2 500.000 ( ((not (mol.entry 2) and fillres within 7 (mol.entry 2 ) )) and not ((( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) or (((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )))) ) and not ((( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) )) or (( ((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) ) and not (( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) ))))
#  ASL2  -1.000 ( (not ((( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) or (((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ))) or (((not (mol.entry 2) and fillres within 7 (mol.entry 2 ) )) and not ((( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) or (((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ))))))) ) and not ((( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) )) or (( ((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) ) and not (( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) ))) or (( ((not (mol.entry 2) and fillres within 7 (mol.entry 2 ) )) and not ((( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) or (((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )))) ) and not ((( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) )) or (( ((not (mol.entry 2) and fillres within 5 (mol.entry 2 ) ) AND NOT (( sidechain ) )) and not (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) )) ) and not (( (( (fillres within 5 (mol.entry 2 ) ) AND NOT (( backbone ) ) ) ) ))))))
# ROGER
#         ;
#         
# #         # queste sono le shell mie, "sembrano" formalmente corrette ma NON danno gli stessi risultati facendo subtract in sequenza dei diversi set (il modo di fare dall'interfaccia grafica con MacroModel)
# #         $incontent .= <<ROGER
# #  ASL1       0 ( ( fillres within 5 ( mol.entry 2 ) ) AND NOT ( backbone ) )
# #  ASL2 200.000 ( ( fillres within 5 ( mol.entry 2 ) ) AND ( backbone ) )
# #  ASL2 500.000 ( ( fillres within 7 ( mol.entry 2 ) ) AND NOT ( fillres within 5 ( mol.entry 2 ) ) )
# #  ASL2  -1.000 ( ( mol.entry 1 ) AND NOT ( fillres within 7 ( mol.entry 2 ) ) )
# # ROGER
# #         ;
#         
#         # devo fare una copia del file sbc per ogni modello, il basename del file deve essere identico al basename del file mae di input
#         my $sbcfilename = $iofiles{$basename};
#         $sbcfilename =~ s/mae$/sbc/;
#         open(INFILE, '>' . $sbcfilename);
#         print INFILE $incontent;
#         close INFILE;
#         
#         # lancio la minimizzazione
#         my $suffix = ($PLANARIZE)? 'com' : 'in'; # quale formato di run input file scelgo?
#         $cmdline = <<ROGER
# #!/bin/bash
# export SCHRODINGER=$schrodinger
# export LM_LICENSE_FILE=$license
# 
# cd $destdir;
# $bins{'macromodel'} minipostXP-$basename.$suffix -NOJOBID > minipostXP-$basename.log
# ROGER
#         ;
#         quelo($cmdline, $basename);
#     }
#     
#     job_monitor($destdir);
#     
#     my $summary_file = 'SUMMARY.csv';
#     my $summary_content = "COMPLEX;LIGAND;ENERGY;GRADIENT\n";
#     foreach my $basename (keys %iofiles) {
#         my $logfile = "minipostXP-$basename.log";
#         my $posefile = $iofiles{$basename};
#         if (-e $logfile) {
#             my $ligand_line = 'null';
#             open(MAE, '<' . $posefile);
#             while (my $newline = <MAE>) {
#                 chomp $newline;
#                 if ($newline =~ / i_m_ct_format/) {
#                     $newline = <MAE>;
#                     if ($newline =~ / :::/) {
#                         $ligand_line = <MAE>;
#                         $ligand_line =~ s/^ :://; # il nome del ligando ha solitamente questo prefisso nel file mae
#                         $ligand_line =~ s/[\n :"\\\/]//g;
#                         $summary_content .= "$basename;$ligand_line;";
#                         last;
#                     }
#                     
#                 }
#                 $ligand_line = $newline;
#             }
#             close MAE;
#             
#             open(LOG, '<' . $logfile);
#             while (my $newline = <LOG>) {
#                 chomp $newline;
#                 if ($newline =~ /^ Conf/) {
#                     my ($energy,$gradient) = $newline =~ /E = +([\d\.\-]+) \( *([\d\.]+)/;
#                     $summary_content .= "$energy;$gradient\n";
#                 }
#             }
#             close LOG;
#         } else {
#             croak "\nE- molecule <$basename> not minimized\n\t";
#         }
#     }
#     printf("\n%s SUMMARY:\n\n%s", clock(), $summary_content);
#     open(SUM, '>' . $summary_file);
#     print SUM $summary_content;
#     close SUM;
#     
#     # rimuovo un po' di file inutili
#     qx/cd $destdir; rm -f BestXP_*_pv.maegz/;
#     
#     printf("\n%s compressing intermediate files\n", clock());
#     my $tozip = '';
#     foreach my $basename (keys %old_iofiles) {
#         $tozip .= " BestXP_$basename-complexes.mae";
#     }
#     foreach my $basename (keys %iofiles) {
#         $tozip .= " BestXP_$basename.mae";
#         $tozip .= " BestXP_$basename.sbc";
#         $tozip .= " minipostXP-$basename.in" unless ($PLANARIZE);
#         $tozip .= " minipostXP-$basename.com";
#     }
#     $cmdline = <<ROGER
# cd $destdir;
# tar -c $tozip | gzip -c9 > intermediate.tar.gz;
# rm -rfv $tozip;
# ROGER
#     ;
#     qx/$cmdline/;
# }
# 
# STEP6: {
#     print "\n\n*** STEP 6: rescoring ***\n";
#     
#     $sourcedir = "$homedir/STEP5_mini_postBestXP";
#     $destdir = "$homedir/STEP6_rescore_MMGBSA";
#     mkdir $destdir;
#     chdir $destdir;
#     
#     # reinizializzo la lista dei file di input
#     undef %iofiles;
#     opendir(DIR, $sourcedir);
#     my @file_list = grep { /minipostXP-(.*)\.maegz/ } readdir(DIR);
#     closedir DIR;
#     foreach my $infile (@file_list) {
#         my ($basename) = $infile =~ /^minipostXP-(.*)\.maegz$/;
#         $iofiles{$basename} = $infile;
#         copy("$sourcedir/$iofiles{$basename}", $destdir);
#     }
#     
#     # creo i file pose viewer
#     printf("\n%s parsing pose viewer files\n", clock());
#     foreach my $basename (keys %iofiles) {
#         $cmdline = "$bins{'run'} $bins{'pv_convert'} -p $iofiles{$basename}";
#         qx/$cmdline/;
#         unlink $iofiles{$basename};
#         print "    <$basename> parsed\n";
#     }
#     
#     # creo l'input file per Prime
#     printf("\n%s MM-GBSA with Prime\n", clock());
#     foreach my $basename (keys %iofiles) {
#         my $incontent = <<ROGER
# STRUCT_FILE  minipostXP-$basename\_1_pv.maegz
# JOB_TYPE     REAL_MIN
# RFLEXDIST    8
# OUT_TYPE     COMPLEX
# ROGER
#         ;
#         
#         if ($PRIME_FREEZER) {
#             $incontent .= "\nFROZEN\n";
#         }
#         
#         open(INFILE, '>' . "prime_mmgbsa-$basename.inp");
#         print INFILE $incontent;
#         close INFILE;
#         
#         # lancio il rescoring
#         $cmdline = <<ROGER
# #!/bin/bash
# export SCHRODINGER=$schrodinger
# export LM_LICENSE_FILE=$license
# 
# cd $destdir;
# $bins{'prime_mmgbsa'} prime_mmgbsa-$basename.inp -NOJOBID > prime_mmgbsa-$basename.log
# ROGER
#         ;
#         quelo($cmdline, $basename);
#     }
#     
#     job_monitor($destdir);
#     
#     my $summary_file = 'SUMMARY.csv';
#     my $summary_content = "MODEL;LIGAND;MMGBSA_dG_Bind;MMGBSA_dG_Bind(NS)\n";
#     foreach my $basename (keys %iofiles) {
#         my $logfile = "prime_mmgbsa-$basename.log";
#         if (-e $logfile) {
#             open(LOG, '<' . $logfile);
#             my $recordline = 'null';
#             while (my $newline = <LOG>) {
#                 chomp $newline;
#                 if ($newline =~ /------------ Averaged Properties -------/) {
#                     $recordline =~ s/[: ]//g;
#                     $recordline =~ s/,/;/g;
#                     $summary_content .= "$basename;$recordline\n";
#                 } else {
#                     $recordline = $newline;
#                     next;
#                 }
#             }
#             close LOG;
#         } else {
#             croak("\nE- no MM-GBSA rescore for <$basename>\n\t");
#         }
#     }
#     printf("\n%s SUMMARY:\n\n%s", clock(), $summary_content);
#     open(SUM, '>' . $summary_file);
#     print SUM $summary_content;
#     close SUM;
#     
#     printf("\n%s compressing intermediate files\n", clock());
#     my $tozip = '';
#     foreach my $basename (keys %iofiles) {
#         $tozip .= " minipostXP-$basename\_1_pv.maegz";
#         $tozip .= " prime_mmgbsa-$basename.inp";
#         $tozip .= " prime_mmgbsa-$basename-out.csv";
#     }
#     $cmdline = <<ROGER
# cd $destdir;
# tar -c $tozip | gzip -c9 > intermediate.tar.gz;
# rm -rfv $tozip;
# ROGER
#     ;
#     qx/$cmdline/;
# }
# 
# STEP7: {
#     print "\n\n*** STEP 7: gathering workflow data ***\n";
#     
#     $sourcedir = "$homedir/STEP6_rescore_MMGBSA";
#     $destdir = "$homedir/STEP7_gathering";
#     mkdir $destdir;
#     chdir $destdir;
#     
#     # reinizializzo la lista dei file di input
#     opendir(DIR, $sourcedir);
#     my @file_list = grep { /^prime_mmgbsa-(.*)-out\.maegz$/ } readdir(DIR);
#     closedir DIR;
#     
#     printf("\n%s converting maegz files\n", clock());
#     my @mae_infiles;
#     foreach my $infile (@file_list) {
#         copy("$sourcedir/$infile", $destdir);
#         my ($basename) = $infile =~ /prime_mmgbsa-(.+)-out\.maegz/;
#         print "    $basename...";
#         $cmdline = "$bins{'structconvert'} -imae $infile -omae $basename.mae";
#         qx/$cmdline/;
#         push(@mae_infiles, "$basename.mae");
#         unlink $infile;
#         print "done\n";
#     }
#     
#     printf("\n%s parsing mae files\n", clock());
#     my %ligposes;
#     foreach my $infile (@mae_infiles) {
#         my $ligand_line;
#         open(MAE, '<' . $infile);
#         while (my $newline = <MAE>) {
#             chomp $newline;
#             if ($newline =~ / i_m_ct_format/) {
#                 $newline = <MAE>;
#                 if ($newline =~ / :::/) {
#                     $ligand_line = <MAE>;
#                     $ligand_line =~ s/^ :://; # il nome del ligando ha solitamente questo prefisso nel file mae
#                     $ligand_line =~ s/[\n :"\\\/]//g;
#                 }
#                 if (exists $ligposes{$ligand_line}) {
#                     push(@{$ligposes{$ligand_line}}, $infile);
#                 } else {
#                     $ligposes{$ligand_line} = [ $infile ];
#                 }
#                 last;
#             }
#             $ligand_line = $newline;
#         }
#         close MAE;
#     }
#     
#     printf("\n%s grouping poses per ligand\n", clock());
#     foreach my $ligand (keys %ligposes) {
#         print "    $ligand...";
#         my $maelist = join(' ', @{$ligposes{$ligand}});
#         $cmdline = <<ROGER
# cat $maelist | gzip -c > $ligand.maegz;
# rm -f $maelist;
# ROGER
#         ;
#         qx/$cmdline/;
#         print "done\n";
#     }
# }

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

sub fetch_jobid {
    my ($basename) = @_;
    
    sleep 1;
    $cmdline = "$bins{'quest'} -l";
    my $string = qx/$cmdline/;
    my @lines = split("\n", $string);
    foreach my $line (@lines) {
        if ($line =~ /$basename/) {
            my ($id) = $line =~ /^\[([\w\d]+)\].*\.quest\.sh>/;
            $joblist{$basename} = $id;
        }
    }
    
}

sub torscons_2378cdd {
    # Questa sub cerca in un mae contenente una posa se è presente la TCDD.
    # In quel caso verranno costruite una serie di espressioni da inserire in
    # un file sbc per imporre un constraint torsionale sul diossano.
    #
    # Questa sub è basata sull'algoritmo dello script "TCDD_tors_cons.py", già
    # presente in PANDORA.
    
    my ($maefile) = @_;
    
    open(INFILE, '<' . $maefile);
    my @maecontent = <INFILE>;
    close INFILE;
    
    # cerco nel file mae le righe relative agli atomi che definiscono i diedri di interesse
    my @ligandx = grep { / 1 X (.+) 0 ("C7"|"C8"|"C9"|"C12"|"C16"|"C17"|"C18"|"C21"|"O2"|"O5")/ } @maecontent;
    my %atom_dict;
    while (my $record = shift @ligandx) {
        my ($at_number,$at_name) = $record =~ /  (\d+) .+("C7"|"C8"|"C9"|"C12"|"C16"|"C17"|"C18"|"C21"|"O2"|"O5")/;
        $atom_dict{$at_name} = $at_number;
    }
    
    my %dihedrals = ( # i nomi degli atomi che definiscono i diedri
        'A' => ['"C9"', '"C8"', '"O5"', '"C17"'],
        'B' => ['"C8"', '"O5"', '"C17"', '"C18"'],
        'C' => ['"C12"', '"C7"', '"O2"', '"C16"'],
        'D' => ['"C7"', '"O2"', '"C16"', '"C21"']
    );
    my $angle = '180.0000';
    my $constraint = '100.0000';
    
    my $sbc_string = '';
    foreach my $quartet (keys %dihedrals) {
        $sbc_string .= ' FXTA ';
        foreach my $name (@{$dihedrals{$quartet}}) {
            $sbc_string .= '   ' . $atom_dict{$name};
        };
        $sbc_string .= '   ' . $constraint . '   ' . $angle . "     0.0000     0.0000\n";
    }
    return $sbc_string;
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