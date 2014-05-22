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
use EMMA::lib::FileIO;

## GLOBS ##
our $basepath; # path di base dei dati di simulazione
our $workdir; # path di lavoro di EMMA
our $sample_size; # numero massimo di frames da campionare
our $rmsd; # soglia di RMSD entro cui campionare i frames
our $driven; # nuova modalità di campionamento, fare l'help
our $ranges;
our $filter;
our $cp_cutoff; # distance cutoff per la communication propensity
our $rage_cmd; # stringa di comando specifica per RAGE
our $file_obj = EMMA::lib::FileIO->new(); # oggetto per leggere/scrivere su file
our $content = [ ]; # buffer in cui butto dentro il contenuto dei file 
## SBLOG ##

## BIN n' CONFS ##
our $bin_file = $ENV{HOME} . '/.EMMA.conf'; 
our %paths = (
    'gnuplot'   => '',
    'R'         => '',
    'trjconv'   => '',
    'editconf'  => '',
    'gmxcheck'  => '',
    'g_rms'     => '',
    'RAGE.pl'   => '',
);

our $components; # lo script che lancia i componenti di EMMA
our $par_file;
our %params; # set di parametri di configurazione
## SFONC 'n NIB ##

USAGE: {
    print "\n*** EMMA ***\n";
    
    my $help;
    use Getopt::Long;no warnings;
    GetOptions('h' => \$help, 'p=s' => \$basepath, 'r=s' => \$ranges, 's=i' => \$sample_size, 'z=s' => \$filter, 't=f{1}' => \$rmsd, 'd' => \$driven, 'cp=i' => \$cp_cutoff, 'cmd=s' => \$rage_cmd);
    my $usage = <<END

********************************************************************************
EMMA - Empathy Motions along fluctuation MAtrix
release 14.4.lbpc7

Copyright (c) 2011-2014, Dario CORRADA <dario.corrada\@gmail.com>


This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

DESCRIPTION

    EMMA is a script which evaluates the degree mechanical coordination of 
    proteins and/or complexes, in order to define long range communication 
    networks that can be described by internal structural flexibilities [1].

    EMMA offers several way of sampling snapshots from trajectory files. 
    With no options EMMA behaves in "-s 1000" mode.
    
    The output results are strongly influenced by how the trajectory file is 
    generated. It is suggested to consider only the equilibrated part of your 
    MD simulation.
    
    The trajectory should be checked for periodic boundary conditions artifacts.
    
    WARNING: driven mode ('-d' option) requires very demanding computations. 
    It is strongly suggested to submit trajectory files that not exceed 1,000 
    timeframes.
    
    [1] Corrada D, Morra G, Colombo G. J Phys Chem B. 2013 Jan 17;117(2):535-52

SYNOPSYS
    
    # 500 timeframes sampled, total coordination calculate for two ranges
    EMMA.reloaded.pl -s 500 -r 2-50,60-92
    
    # snapshots sampled within 0.2nm of RMSD, matrix is calculate for res 10-20
    EMMA.reloaded.pl -t 0.20 -z 10-20
    
    # driven mode with a custom RAGE command line
    EMMA.reloaded.pl -d -cmd "RAGE.pl -dist euclidean"
    
    # communication propensity will be calculated above 10A of distance
    EMMA.reloaded.pl -cp 10

OPTIONS
    
    -p <string>     working dir (default: pwd)
    
    -z <string>     zooms over a subset of residues
    
    -r <string>     range of residues by which total coordination will be 
                    calculated
    
    -s [int]        number of frames sampled from trajectory (default: 1000)
    
    -t <float>      RMSD threshold for sampling frames
    
    -d              timeframes are subjected to hierarchical clustering method, 
                    the sampled snapshots belongs to one of the most populated 
                    clusters which also shows the best silhouette value 
    
    -cmd <string>   custom RAGE command line, see RAGE.pl help. By default -d 
                    option run with the RAGE command line as follows:
                    "RAGE.pl -min 6 -max 14 -clust complete -dist manhattan"
    
    -cp [int]       distance fluctuation cutoff, in Angstrom (default: 30)

INPUT FILES

    The following exact filenames are required:
    
    ----------------------------------------------------------------------------
     FILENAME                DESCRIPTION
    ----------------------------------------------------------------------------
     topol[.tpr|.gro]        the topology file
    
     traj.xtc                trajectory file
    
     rmsd.xpm                RMSD matrix, mandatory with '-d' option. The xpm 
                             file format agrees with GROMACS 'g_rms -m' output 
                             file
    
     cluster.log             clustering report, mandatory with '-t' option. The 
                             log file format agrees with GROMACS 'g_cluster' 
                             output file
    ----------------------------------------------------------------------------

OUTPUT FILES
    
    Other intermediate output files are available by commenting lines in
    "EMMA.reloaded.pl" at "CLEANSWEEP" section.
    
    ----------------------------------------------------------------------------
     FILENAME                DESCRIPTION
    ----------------------------------------------------------------------------
     DF.matrix.png           distance fluctuation matrix
    
     DF.profile.dat          distance fluctuation profiles, "up" and "down" bins 
     DF.profile.png          indentify those values above or below the fixed 
                             threshold defined as sqrt(1/[tot_res])
    
     DF.ave.csv              only with '-r' option, mean DF values
    
     CP.matrix.png           communication propensity matrix
     CP.matrix.csv
    
     CP.profile.dat          communication propensity profile, this output 
     CP.profile.png          depends on how '-cp' option is setted (usually it 
                             should be setted by measuring the protein 
                             block/domain size
    
     EMMA.log                log file
    
     dist.matrix.png         only with '-d' option, paired RMSD distance matrix
    
     cluster.summary.csv     only with '-d' option, clustering perfomance table
    
     RAGE.cluster.log        only with '-d' option, log file of the best cluster 
                             analysis
    
     RankAggreg.png          only with '-d' option, Rank Aggregation plot
    ----------------------------------------------------------------------------
END
    ;
    
    $help and do { print $usage; goto FINE; };
}

INIT: {
    # verifico la presenza del file ~/.EMMA.conf
    unless (-e $bin_file) {
        my $ans;
        print "\nEMMA is not yet configured, do you want to proceed? [y/N] ";
        $ans = <STDIN>; chomp $ans;
        unless ($ans eq 'y') {
            print "\nNothing to do";
            goto FINE;
        }
        print "\n";
        open(CONF, '>' . $bin_file) or croak("E- unable to open <$bin_file>\n\t");
        print CONF "# Paths of binaries used by EMMA\n";
        foreach my $key (sort keys %paths) {
            my $path = qx/which $key/; chomp $path; # tento una ricerca automatica
            printf("    %-8s [%s]: ", $key, $path);
            my $ans = <STDIN>; chomp $ans;
            if ($ans) {
                print CONF "$key = $ans\n";
            } else {
                print CONF "$key = $path\n";
            }
        }
        close CONF;
    }
    
    open(CONF, '<' . $bin_file) or croak("E- unable to open <$bin_file>\n\t"); 
    while (my $newline = <CONF>) {
        if ($newline =~ /^#/) {
            next; # skippo le righe di commento
        } elsif ($newline =~ / = /) {
            chomp $newline;
            my ($key, $value) = $newline =~ m/([\w\d_\.]+) = ([\w\d_\.\/]+)/;
            $paths{$key} = $value if (exists $paths{$key});
        } else {
            next;
        }
    }
    close CONF;
    
    $filter = 'null' unless ($filter);
    $basepath = getcwd() unless ($basepath);
    $workdir = $basepath . '/EMMA';
    
    $components = $0;
    $components =~ s/bin\/EMMA\.reloaded\.pl$/lib\/components\.pl/;
    
    # verifico se ci sono già dei dati esistenti e ne faccio una copia di backup
    if (-e $workdir) {
        my @info = stat($workdir);
        my $mtime = $info[9];
        qx/mv $workdir $workdir.$mtime/;
    }
    mkdir $workdir;
    
    # scrivo un file dei parametri acquisiti che girerò a components
    %params = (
        'basepath'      => $basepath,
        'workdir'       => $workdir,
        'sample_size'   => $sample_size || 1000,
        'rmsd'          => $rmsd || 0.2,
        'ranges'        => $ranges || 'null',
        'filter'        => $filter,
        'gnuplot'       => $paths{'gnuplot'},
        'R'             => qq/$paths{'R'} --vanilla < /, # opzione per far girare R in batch
        'trjconv'       => $paths{'trjconv'},
        'editconf'      => $paths{'editconf'},
        'gmxcheck'      => $paths{'gmxcheck'},
        'g_rms'         => $paths{'g_rms'},
        'RAGE'          => $rage_cmd || qq/$paths{'RAGE.pl'} -min 6 -max 14 -clust complete -dist manhattan/,
        'cp_cutoff'     => $cp_cutoff || 30,
        'xtc_file'      => $basepath . '/traj.xtc',
        'tpr_file'      => $basepath . '/topol.tpr',
        'cluster_log'   => $basepath . '/cluster.log',
        'xpm_file'      => $basepath . '/rmsd.xpm', # ATTENZIONE: non si tratta del file xpm in output a "g_cluster" ma di quello prodotto da "g_rms" con l'opzione "-m"
    );
    
    if (-e $basepath . '/topol.gro') {
        $params{'tpr_file'} = $basepath . '/topol.gro';
    }
    
    $par_file = $workdir . '/params.txt';
    $file_obj->set_filename($par_file);
    $content = [ ];
    foreach my $key (keys %params) {
        my $string = sprintf("%s = %s\n", $key, $params{$key});
        push(@{$content}, $string);
    }
    $file_obj->set_filedata($content);
    $file_obj->write;
}


LAUNCHER: {
    my $mem_file = $workdir . '/EMMA.log';
    my $header = "--- EMMA - Empathy Motions along fluctuation MAtrix ---\n";
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $header ],
        'mode' => '>'
    );
    
    my $memlog = '';
    
    # modalità di campionamento
    if ($driven) {
        
        unless (-e $params{'xpm_file'}) {
            printf("\nE- input file <%s> not found, aborting job", $params{'xpm_file'});
            goto FINE;
        }
        
        # check delle dimensioni del file XPM
        my $xpmrows; my $flag;
        open(XPM, '<' . $params{'xpm_file'});
        while (my $content = <XPM>) {
            chomp $content;
            if ($xpmrows) {
                $xpmrows++;
                next;
            } elsif ($flag) {
                unless ($content =~ /^\/\* y\-axis\: /) {
                    $xpmrows = 1;
                    next;
                }
            } elsif ($content =~ /^\/\* y\-axis\: /) {
                $flag = 1;
                next;
            }
        }
        close XPM;
        if ($xpmrows > 1000) {
            print "\nWARNING: this process could be very expensive, more than 1,000 snapshots will\nbe considered. Maybe you prefer to reduce the dimensions of your input files\n(traj.xtc and/or rmsd.xpm). Do you want to proceed anyway? [y/N] ";
            my $answer = <STDIN>;
            chomp $answer;
            unless ($answer eq 'y') {
                print "JOB ABORTED";
                goto FINE;
            }
        }
        
        printf("\nI- %s sampling trajectory (driven mode)...", clock());
        $memlog = qx/$components $par_file driven 2>&1/;
        $file_obj->write(
            'filename' => $mem_file,
            'filedata' => [ $memlog ],
            'mode' => '>>'
        );
    } elsif ($rmsd) {
        # snapshots entro una soglia di RMSD dalla struttura di riferimento del primo cluster
        printf("\nI- %s sampling trajectory (RMSD %.2f)...", clock(), $rmsd);
        
        unless (-e $params{'cluster_log'}) {
            printf("\nE- input file <%s> not found, aborting job", $params{'cluster_log'});
            goto FINE;
        }
        
        $memlog = qx/$components $par_file samplecluster 2>&1/;
        $file_obj->write(
            'filename' => $mem_file,
            'filedata' => [ $memlog ],
            'mode' => '>>'
        );
    } else {
        # tot snapshot spalmati su tutta la traiettoria a tempi regolari
        printf("\nI- %s sampling trajectory (%i snapshots)...", clock(), $sample_size || 1000);
        
        unless (-e $params{'tpr_file'}) {
            printf("\nE- input file <%s> not found, aborting job", $params{'tpr_file'});
            goto FINE;
        }
        
        unless (-e $params{'xtc_file'}) {
            printf("\nE- input file <%s> not found, aborting job", $params{'xtc_file'});
            goto FINE;
        }
        
        $memlog = qx/$components $par_file sampling 2>&1/;
        $file_obj->write(
            'filename' => $mem_file,
            'filedata' => [ $memlog ],
            'mode' => '>>'
        );
    }
    
    if ($filter =~ /^\d+-\d+$/) {
        printf("\nI- %s subset filtering...", clock());
        $memlog = qx/$components $par_file subset 2>&1/;
        $file_obj->write(
            'filename' => $mem_file,
            'filedata' => [ $memlog ],
            'mode' => '>>'
        );
    } elsif ($filter !~ /^null$/) {
        croak(sprintf("\nE- filter \"$filter\" unknown\n\t"));
    }
    
    printf("\nI- %s processing average distance matrix...", clock());
    $memlog = qx/$components $par_file ave 2>&1/;
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $memlog ],
        'mode' => '>>'
    );
    
    printf("\nI- %s processing signal-to-noise ratio matrix...", clock());
    $memlog = qx/$components $par_file flumat 2>&1/;
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $memlog ],
        'mode' => '>>'
    );
    
    printf("\nI- %s performing diagonalization...", clock());
    $memlog = qx/$components $par_file diago 2>&1/;
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $memlog ],
        'mode' => '>>'
    );
    
    printf("\nI- %s selecting eigenvectors...", clock());
    $memlog = qx/$components $par_file forecast 2>&1/;
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $memlog ],
        'mode' => '>>'
    );
    
    printf("\nI- %s processing minimal matrix...", clock());
    $memlog = qx/$components $par_file minimal 2>&1/;
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $memlog ],
        'mode' => '>>'
    );
    
    printf("\nI- %s processing components distribution...", clock());
    $memlog = qx/$components $par_file distrib 2>&1/;
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $memlog ],
        'mode' => '>>'
    );
    
    printf("\nI- %s calculating coordination value...", clock());
    $memlog = qx/$components $par_file total 2>&1/;
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $memlog ],
        'mode' => '>>'
    );
    
    printf("\nI- %s calculating communication propensity...", clock());
    $memlog = qx/$components $par_file propensity 2>&1/;
    $memlog .= qx/$components $par_file cytoscape 2>&1/;
    $file_obj->write(
        'filename' => $mem_file,
        'filedata' => [ $memlog ],
        'mode' => '>>'
    );
}

CLEANSWEEP: { # elimino i file intermedi prodotti
    printf("\nI- %s cleaning temporary files...", clock());
    
    unlink $workdir . '/params.txt';            # parameter list file
    
    unlink $workdir . '/topol.pdb';             # reference structure
    
    # SAMPLING
    unlink $workdir . '/traj.full.ca.pdb';      # raw trajectory
    unlink $workdir . '/traj.ca.pdb';           # sampled trajectory
    
    # CLUSTERING (only with -t option)
    unlink $workdir . '/reference.gro';         # reference structure from the representative cluster
    unlink $workdir . '/rmsd.xvg';              # RMSD over reference.gro
    
    # MATRICES
    unlink $workdir . '/pairs.dat';             # average distance matrix between Calpha pairs
    unlink $workdir . '/flu_matrix.csv';        # raw DF matrix
    unlink $workdir . '/DF.matrix.dat';         # Distance Fluctuation matrix (dat format)
    unlink $workdir . '/CP.matrix.dat';         # Communication Propensity matrix (dat format)
    
    # EIGEN DECOMPOSITION
    unlink $workdir . '/pca.R';                 # R script for diagonalization
    unlink $workdir . '/EIGENVAL.txt';          # eigenvalues
    unlink $workdir . '/EIGENVECT.txt';         # eigenvectors
    unlink $workdir . '/which.txt';             # selected eigenvectors
    
    # GNUPLOT
    unlink $workdir . '/up';
    unlink $workdir . '/down';
    unlink $workdir . '/CP.matrix.gnuplot';
    unlink $workdir . '/CP.profile.gnuplot';
    unlink $workdir . '/DF.matrix.gnuplot';
    unlink $workdir . '/DF.profile.gnuplot';
}

FINE: {
    print "\n\n*** AMME ***\n";
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
