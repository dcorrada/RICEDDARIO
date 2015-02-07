#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
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
use threads;
use File::Copy;

## GLOBS ##
our %opts = (
    'RATIO'             => 0.75,        # how many poses/residue retain (lower threshold)?
    'THREADS'           => 2,
    'LIGMASK'           => '',
    'DGTHRESHOLD'       => 1.0,
);
our $workdir;
our $infiles = { 'REFERENCE' => [ ], 'QUERY' => [ ] };
our %bins = (
    'quest'             => $ENV{RICEDDARIOHOME} . '/Qlite' . '/QUEST.client.pl',
    'MM-GBSA_PPI'       => $ENV{RICEDDARIOHOME} . '/third_parties/AMBER' . '/MM-GBSA_PPI.pl',
    'RankPride'         => $ENV{RICEDDARIOHOME} . '/unsorted/PERL' . '/RankPride.pl',
);
our $script; # generica variabile che contiene gli script che vengono di volta in volta evocati
our $fh; # filehandle generico
## SBLOG ##

USAGE: {
    use Getopt::Long;no warnings;
    my $help;
    GetOptions('help|h' => \$help, 'dgbind|d=f' => \$opts{'DGTHRESHOLD'}, 'ligmask|l=s' => \$opts{'LIGMASK'}, 'ratio|r=f' => \$opts{'RATIO'}, 'threads|t=i' => \$opts{'THREADS'});
    my $header = <<ROGER
********************************************************************************
RankPride for AMBER (PPI version)
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

This Perl script is aimed to find significative differences between the dG 
signatures of two dataset of protein dimers.

A "dG signature" is a profile of the per-residue energy contributions that 
define the free energy of binding of a specific complex.


*** SYNOPSYS ***

    \$ RankPride.AMBER.PPI.pl -l "ligandmask" [more options]

"ligand_mask" is a string that specify the residue range that could be defined 
as the ligand partner in the complexed molecule (e.g.: "108-218")


*** INPUT FILES ***

Input files are 3D structure files of the dimer complex (in pdb format). Prior 
to launch the script the input files must be moved in two folders defining the 
"REFERENCE" and the "QUERY" datasets, respectively.


*** OPTIONS ***
    -dgbind|d <float>       threshold value for per-residue energy contribute to
                            the global dG binding (default: +/- $opts{'DGTHRESHOLD'} kcal/mol)
    
    -ligmask|l <string>     MANDATORY: ligand mask, used during MM-GBSA 
                            calculation step (default: $opts{'LIGMASK'})
    
    -ratio|r <float>        ratio of the minimal number of poses per residue to 
                            retain (default: $opts{'RATIO'})
    
    -threads|t <int>        number of concurrent threads during MM-GBSA 
                            calculation step (default: $opts{'THREADS'})
ROGER
        ;
        print $spiega;
        goto FINE;
    }
}

READY2GO: {
    # verifico la sintassi
    croak "\nE- ligand mask not defined, try option '-h' for help\n\t"
        unless ($opts{'LIGMASK'} =~ /^\d+\-\d+$/);
    
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
    $workdir = getcwd();
    my @file_list;
    foreach my $dataset (keys %{$infiles}) {
        if (-d "$workdir/$dataset") {
            opendir(INDIR, "$workdir/$dataset");
            @file_list = grep { /\.pdb$/ } readdir(INDIR);
            $infiles->{$dataset} = [ @file_list ];
            close INDIR;
        } else {
            croak("\nE- folder [$dataset] not found\n\t");
        }
    }
    
    # creo la cartella temporanea
    mkdir '.RankPride.AMBER.PPI';
    $workdir .= '/.RankPride.AMBER.PPI';
    mkdir "$workdir/LOGS";
    chdir $workdir;
}

MMGBSA: {
    print "\n*** MM-GBSA ***\n\n";
    
    # lancio i calcoli di MM-GBSA a gruppi di $opts{'THREADS'} per volta
    my @thr;
    my ($sourcedir) = $workdir =~ /(.*)\/\.RankPride\.AMBER\.PPI$/;
    for my $dataset (keys %{$infiles}) {
        my $i;
        for ($i = 0; $i < scalar @{$infiles->{$dataset}}; $i++) {
            for my $j (1..$opts{'THREADS'}) {
                if ($infiles->{$dataset}->[$i]) {
                    my $infile = $infiles->{$dataset}->[$i];
                    my $outfile = $dataset . '.' . $infile;
                    copy("$sourcedir/$dataset/$infile", "$workdir/$outfile");
                    push(@thr, threads->new(\&mmgbsappi, $outfile));
                    printf("%s <%s> submitted\n", clock(), $infile)
                }
                $i++;
            }
            for (@thr) { $_->join() }
            undef @thr;
            $i--;
        }
    }
}

ENEDECOMP: {
    print "\n*** ENERGY DECOMPOSITION ***\n";
    
    my $rawdata = { };
    
    # leggo dalla lista dei dat files relativi alla decomposiozione energetica
    printf("\n%s parsing input data...", clock());
    opendir(DH, $workdir);
    my @dat_infiles = grep { /_DECOMP\.dat$/ } readdir(DH);
    closedir DH;
    for my $indat (@dat_infiles) {
        my ($dataset, $sample) = $indat =~ /^(REFERENCE|QUERY)\.(.+)_DECOMP\.dat$/;
        $rawdata->{$dataset} = { } unless (exists $rawdata->{$dataset});
        open $fh, '<', $indat;
        my $start = 0;
        while (my $newline = <$fh>) {
            chomp $newline;
            if ($newline =~ /DELTAS:/) {
                $start = 1;
                next;
            } elsif ($start) {
                next if ($newline =~ /(Total|Residue|------)/);
                next unless $newline;
                my ($resi, $value) = $newline =~ /^\w{3} +(\d+).+\| +(-{0,1}\d{1,}\.\d{3}) \+\/-  0.000$/;
                if (abs($value) >= $opts{'DGTHRESHOLD'}) {
                    $resi = sprintf("R%04d", $resi);
                    $rawdata->{$dataset}->{$resi} = { } unless (exists $rawdata->{$dataset}->{$resi});
                    $rawdata->{$dataset}->{$resi}->{$sample} = $value;
                }
            } else {
                next; # skippo il file fino alla sezione che mi interessa
            }
        }
        close $fh;
    }
    print "done\n";
    
    printf("%s filtering shared probes...", clock());
    # filtro i dati per la soglia definita con $opts{'RATIO'}
    for my $dataset (keys %{$rawdata}) {
        my $howmany = scalar grep { /$dataset/ } @dat_infiles;
        $howmany *= $opts{'RATIO'};
        for my $resi (keys %{$rawdata->{$dataset}}) {
            delete $rawdata->{$dataset}->{$resi}
                if (scalar keys %{$rawdata->{$dataset}->{$resi}} < $howmany);
        }
    }
    
    # filtro i dati condivisi tra i dataset
    my @shared_probes;
    for my $resi (sort keys %{$rawdata->{'REFERENCE'}}) {
        push (@shared_probes, $resi)
            if (exists $rawdata->{'QUERY'}->{$resi});
    }
    
    # scrivo i csv di input per il Rank Product
    for my $dataset ('REFERENCE', 'QUERY') {
        my $outfile = 'enedecomp_' . $dataset . '.csv';
        open $fh, '>', $outfile;
        my $newline = 'POSE;' . join(';',@shared_probes);
        print $fh "$newline\n";
        my @samples = grep { /$dataset/ } @dat_infiles;
        for my $sample (@samples) {
            my $null;
            ($null, $sample) = $sample =~ /^(REFERENCE|QUERY)\.(.+)_DECOMP\.dat$/;
            $newline = "$sample";
            for my $probe (@shared_probes) {
                if (exists $rawdata->{$dataset}->{$probe}->{$sample}) {
                    $newline .= ';' . $rawdata->{$dataset}->{$probe}->{$sample};
                } else {
                    $newline .= ';NA';
                }
            }
            print $fh "$newline\n";
        }
        close $fh;
    }
    print "done\n";
}

RANKPROD: {
    print "\n*** RANK PRODUCT ***\n";
    
    printf("\n%s preparing input data...", clock());
    
    # preparo l'hash di input
    my $intable = { };
    my %incsv = (
        'REFERENCE'  => 'enedecomp_REFERENCE.csv',
        'QUERY'      => 'enedecomp_QUERY.csv'
    );
    for my $dataset (keys %incsv) {
        $intable->{$dataset} = { };
        open($fh, '<' . $incsv{$dataset});
        my $header = <$fh>;
        chomp $header;
        my @probe_names = split(';', $header);
        foreach my $i (1..scalar(@probe_names)-1) {
            $intable->{$dataset}->{$probe_names[$i]} = [ ];
        }
        while (my $newline = <$fh>) {
            chomp $newline;
            my @values = split(';', $newline);
            foreach my $i (1..scalar(@values)-1) {
                my $value = $values[$i];
                $value = '0.000' if ($value =~ m/NA/);
                push(@{$intable->{$dataset}->{$probe_names[$i]}}, $value);
            }
        }
        close $fh;
    }
    
    # seleziono solo i probes comuni tra reference e query
    my @A = keys %{$intable->{'REFERENCE'}};
    my @B = keys %{$intable->{'QUERY'}};
    my @shared;
    for my $A_elem (0..(scalar @A)-1) {
        for my $B_elem (0..(scalar @B)-1) {
            if ($A[$A_elem] eq $B[$B_elem]) {
                push(@shared, $A[$A_elem]);
            }
        }
    }
    
    print "done\n";
    
    # scrivo i file csv di input per lo script RankPride
    for my $dataset (keys %{$intable}) {
        my $outfile = $workdir . "/$dataset.shared.csv";
        open($fh, '>' . $outfile);
        my $string = join(';', @shared) . "\n";
        print $fh $string;
        my $replicas = scalar @{$intable->{$dataset}->{$shared[0]}};
        for my $replica (0..$replicas-1) {
            $string = '';
            for my $probe (@shared) {
                $string .= $intable->{$dataset}->{$probe}->[$replica] . ';';
            }
            $string =~ s/;$/\n/;
            print $fh $string;
        }
        close $fh;
    }
    
    # lancio RankPride
    $script = <<ROGER
#!/bin/bash

cd $workdir;
$bins{'RankPride'} QUERY.shared.csv REFERENCE.shared.csv;
mv rankprod.csv ..;
mv enedecomp_REFERENCE.csv ..;
mv enedecomp_QUERY.csv ..;
ROGER
    ;
    quelo($script, 'running RankPride');
    job_monitor($workdir);
}

CLEANSWEEP: {
    qx/rm -r $workdir/; # rimuovo la directory temporanea
}

FINE: {
    print "\n*** IPP.REBMA.edirPknaR ***\n";
    exit;
}

sub mmgbsappi { # serve per lanciare threads di MM-GBSA_PPI.pl senza occupare slot aggiuntivi su QUEST
    my ($input_file) = @_;
    
    qx/cd $workdir;echo "$opts{'LIGMASK'}" | $bins{'MM-GBSA_PPI'} $input_file/;
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
