#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.02.b    - updated probe selection
#
# release 15.02.a    - initial release
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

our %opts = (
    'SHELL'     => 5.5,         # shell by which residues will be considered during enedecomp analysis
    'RATIO'     => 0.75,        # how many poses/residue retain (lower threshold)?
);
our $riceddario = $ENV{RICEDDARIOHOME};
our $workdir = getcwd();
our $tempus = "$workdir/.RankPride.PRIME";
our $infiles = { 'REFERENCE' => [ ], 'QUERY' => [ ] };
our %bins = (
    'quest'             => $riceddario . '/Qlite' . '/QUEST.client.pl',
    'enedecomp_parser'  => $riceddario . '/third_parties/SCHRODINGER' . '/enedecomp_parser.pl',
    'RankPride'         => $riceddario . '/unsorted/PERL' . '/RankPride.pl',
);

## SBLOG ##

mkdir $tempus; # prima di tutto creo una tempdir

USAGE: {
    use Getopt::Long;no warnings;
    my $help;
    GetOptions('help|h' => \$help, 'shell|s=f' => \$opts{'SHELL'}, 'ratio|r=f' => \$opts{'RATIO'});
    my $header = <<ROGER
********************************************************************************
RankPride for PRIME
release 15.02.b

Copyright (c) 2015, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
ROGER
    ;
    print $header;
    
    if ($help) {
        my $spiega = <<ROGER

This Perl script is aimed to find significative differences between the dG 
signatures of two dataset of poses obtained from a docking workflow performed 
with the Schrodinger suite software.

A "dG signature" is a profile of the per-residue energy contributions that 
define the free energy of binding of a specific receptor::ligand complex.


*** INPUT FILES ***

Input files are pose viewer files (in maegz format), each of them must contains 
a single pose. Such files are obtained from <prime_mmgbsa> job runs.

Prior to launch the script the input files must be moved in two folders defining
the "REFERENCE" and the "QUERY" complexes, respectively.


*** OPTIONS ***
    -ratio|r <float>    ratio of the minimal number of poses per residue to 
                        retain (default: $opts{'RATIO'})
    
    -shell|s <float>    shell, in Angstrom, by which residues will be considered
                        for energy decomposition analysis (default: $opts{'SHELL'} A)


*** OUTPUT ***

The script produces a csv file called <rankprod.csv> with a content like this:

    PROBE;LOG(RP);Evalue
    R0199;2.1150e-01;3.0000e-04
    R0200;8.5183e-02;1.9720e-01
    R0195;-1.5304e-01;1.5500e-02
    R0117;-4.7448e-02;4.8240e-01
    [...]

The "PROBE" column indicate the probe names.

The "LOG(RP)" column is the rank product score. For each probe, the more 
positive score defines a more positive delta between values of QUERY dataset 
versus REFERENCE dataset. Viceversa, the more negative score defines a more n
egative delta between values of QUERY dataset versus REFERENCE dataset.

The "Evalue" column indicates how much significant is the rank product score, 
based on an amount of random permutations of input data (defined with option -p).
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
    
    # verifico che il server QUEST sia su
    my $status = qx/$bins{'quest'} -l 2>&1/;
    if ($status =~ /E\- Cannot open socket/) {
        croak "\nE- QUEST server seems to be down\n\t";
    }
    
    # faccio un check sui file di input
    my @file_list;
    foreach my $dataset (keys %{$infiles}) {
        if (-d "$workdir/$dataset") {
            opendir(INDIR, "$workdir/$dataset");
            @file_list = grep { /\.maegz$/ } readdir(INDIR);
            $infiles->{$dataset} = [ @file_list ];
            close INDIR;
        } else {
            croak("\nE- folder [$dataset] not found\n\t");
        }
    }
}

ENEDECOMP: {
    print "\n*** ENERGY DECOMPOSITION ***\n";
    foreach my $dataset (keys $infiles) {
        my $csv_summary = { };
        chdir $tempus;
        printf("\n%s Processing %s data\n", clock(), $dataset);
        foreach my $maegz (@{$infiles->{$dataset}}) {
            my ($jobname) = $maegz =~ m/(.*)\.maegz$/;
            my $cmdline = <<ROGER
#!/bin/bash

cp $workdir/$dataset/$maegz $tempus;
cd $tempus;
$bins{'enedecomp_parser'} $maegz -shell $opts{'SHELL'};
rm $jobname.mae*;
ROGER
            ;
            quelo($cmdline, $jobname);
        }
        job_monitor($tempus);
        
        # faccio un hash di riepilogo dei csv prodotti da enedecomp_parser.pl
        opendir(DIR, $tempus);
        my @file_list = grep { /\.csv$/ } readdir(DIR);
        closedir DIR;
        
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
                $csv_summary->{$resi}->{$pose} = $dg_tot;
            }
            close CSV;
            unlink $infile;
        }
        
        # filtro solo i residui condivisi almeno dal $opts{'RATIO'} delle pose
        my $ref = scalar @{$infiles->{$dataset}};
        printf("    Entries parsed.....: %d\n", scalar keys %{$csv_summary});
        foreach my $res (keys %{$csv_summary}) {
            my $tot = scalar keys %{$csv_summary->{$res}};
            if ($tot <= ($ref * $opts{'RATIO'})) {
                delete $csv_summary->{$res};
            }
        }
        printf("    Entries filtered...: %d\n", scalar keys %{$csv_summary});
    
        # Scrivo il csv di riepilogo
        chdir $workdir;
        open(CSV, '>' . 'enedecomp_' . $dataset . '.csv');
        my $header = 'POSE;res_' . join(';res_', sort keys %{$csv_summary}) . "\n";
        print CSV $header;
        my %resi_values;
        foreach my $pose (@pose_list) {
            my $row = $pose;
            foreach my $resi (sort keys %{$csv_summary}) {
                $resi_values{$resi} = [ ] unless (exists $resi_values{$resi});
                if (exists $csv_summary->{$resi}->{$pose}) {
                    my $value = $csv_summary->{$resi}->{$pose};
                    $row .= ';' . $value;
                    push(@{$resi_values{$resi}}, $value);
                } else {
                    $row .= ';NA';
                }
            }
            $row .= "\n";
            print CSV $row;
        }
        close CSV;
    }
}

RANKPROD: {
    print "\n\n*** RANK PRODUCT ***\n";
    
    # preparo l'hash di input
    my $intable = { };
    my %incsv = (
        'datasetA.csv'  => 'enedecomp_QUERY.csv',
        'datasetB.csv'  => 'enedecomp_REFERENCE.csv'
    );
    for my $dataset (keys %incsv) {
        $intable->{$dataset} = { };
        open(CSV, '<' . $incsv{$dataset});
        my $header = <CSV>;
        chomp $header;
        my @probe_names = split(';', $header);
        foreach my $i (1..scalar(@probe_names)-1) {
            $intable->{$dataset}->{$probe_names[$i]} = [ ];
        }
        while (my $newline = <CSV>) {
            chomp $newline;
            my @values = split(';', $newline);
            foreach my $i (1..scalar(@values)-1) {
                my $value = $values[$i];
                push(@{$intable->{$dataset}->{$probe_names[$i]}}, $value);
            }
        }
        close CSV;
    }
    
    # scrivo i file csv di input per lo script RankPride
    my @shared = sort keys %{$intable->{'datasetA.csv'}};
    for my $dataset (keys %{$intable}) {
        my $outfile = "$tempus/$dataset";
        open(CSV, '>' . $outfile);
        my $string = join(';', @shared) . "\n";
        print CSV $string;
        my $replicas = scalar @{$intable->{$dataset}->{$shared[0]}};
        for my $replica (0..$replicas-1) {
            $string = '';
            for my $probe (@shared) {
                my $value = $intable->{$dataset}->{$probe}->[$replica];
                $value = 'NA' unless ($value);
                $string .= $value . ';';
            }
            $string =~ s/;$/\n/;
            print CSV $string;
        }
        close CSV;
    }
    
    # lancio RankPride
    printf("\n%s Run RankPride\n", clock());
    chdir $tempus;
    my $cmdline = <<ROGER
#!/bin/bash

cd $tempus;
$bins{'RankPride'} datasetA.csv datasetB.csv;
mv rankprod.csv ..;
mv enedecomp_REFERENCE.csv ..;
mv enedecomp_QUERY.csv ..;
ROGER
    ;
    quelo($cmdline, 'RankPride');
    job_monitor($tempus);
    chdir $workdir;
}

FINE: {
    qx/rm -r $tempus/; # rimuovo la directory temporanea
    print "\n\n*** EMIRP.edirPknaR ***\n";
    exit;
}

sub quelo { # serve per lanciare job su QUEST
    my ($content, $basename) = @_;
    my $filename = "$tempus/$basename.quest.sh";
    
    # creo uno shell script di modo che il job possa venire sottomesso tramite QUEST
    open(SH, '>' . $filename);
    # aggiungo questa riga di controllo allo script: prima di terminare lo script 
    # accoda al file 'JOBS_FINISHED.txt' una stringa per dire che ha finito
    $content .= "echo $basename >> $tempus/JOBS_FINISHED.txt\n";
    
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
