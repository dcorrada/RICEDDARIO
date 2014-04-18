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
use BRENDA::lib::FileIO;
use BRENDA::lib::Rambo;
use Cwd;
use Carp;
use threads;
use threads::shared;
use Thread::Semaphore;

## GLOBS ##
our $frame_num; # numero di frames da collezionare
our $list_file =  '/home/dario/script/BRENDA/data/BRENDA_list.csv'; # lista dei path che descrivono i complessi recettore/ligando
## SBLOG ##

## THREADING ##
our $thread_num; # numero massimo di threads contemporanei (dipende dal numero di nodi/processori disponibili)
our $semaforo;
our @thr; # lista dei threads
our ($queued, $running) :shared;
## GNIDAERHT ##

USAGE: {
    printf("\n*** BRENDA %s ***\n", clock());
    
    my $help;
    use Getopt::Long;no warnings;
    GetOptions('help|h' => \$help, 'snapshot|s=i' => \$frame_num, 'threads|t=i' => \$thread_num);
    my $usage = <<END

*** BRENDA - BRing the ENergy, ya damned DAemon! ***
This script is voted to perform an MM-GBSA energy analysis from a sample of 
(protein-protein) complexes.

She needs that you have previously run (with GROMACS) MD simulations and the 
subsequent cluster analyses for every ligand, receptor and complex you need to 
take into account.

Brenda samples, from each trajectory, an amount of snapshots and then she 
minimize them with AMBER sander tool. She performs MM-GBSA with the AMBER 
mm_pbsa.pl script.

OPTIONS
    
    -snapshot|s     number of snapshots to be sampled (default: 3)
    
    -threads|t      concurrent threads for parallel computing (default: 8)
END
    ;
    
    $help and do { print $usage; goto FINE; };
}

DUMPER: {
# serve per saltare ad un determinato blocco, evitare se non si conosce il codice
#     $frame_num = 3 unless ($frame_num);
#     $thread_num = 8 unless ($thread_num);
#     $semaforo = Thread::Semaphore->new(int($thread_num));
#     $queued = 0E0; $running = 0E0; 
    goto INIT;
}

INIT: {
# inizializzazioni
    
    $frame_num = 3 unless ($frame_num);
    $thread_num = 8 unless ($thread_num);
    $semaforo = Thread::Semaphore->new(int($thread_num));
    
    # inizializzo il numero di code e di job che girano attualmente
    $queued = 0E0; $running = 0E0; 
    
    # verifico se ci sono già dei dati esistenti e ne faccio una copia di backup
    foreach my $folder (@{folders($list_file)}) {
        $folder = $folder . '/BRENDA';
        if (-e $folder) {
            my @info = stat($folder);
            my $mtime = $info[9];
            system("mv $folder $folder.$mtime");
        }
        mkdir $folder;
    }
}

SAMPLECLUSTER: {
# campionamento dei frames a partire dalla cluster analysis precedentemente condotta
    
    printf("\nI- %s sampling snapshots from trajectories...\n", clock());
    my $path_list = folders($list_file);
    
    my $sample = { }; # elenco dei percorsi
    
    foreach my $path (@{$path_list}) {
        
        # leggo il log file della cluster analysis
        my $fileobj = BRENDA::lib::FileIO->new();
        my $content = $fileobj->read($path . '/cluster/cluster.log');
        
        # raccolgo la lista dei frames che appartengono al primo cluster
        my @framelist; my $mode; my $ref_struct;
        while (my $newline = shift @{$content}) {
            chomp $newline;
            if ($newline =~ m/^  1 \|/) {
                # mi appunto la struttura rappresentativa del cluster
                ($ref_struct) = $newline =~ m/^  1 \|[ \.\d]+\| *(\d+)/;
                
                $mode = 1;
            } elsif ($newline =~ m/^  2 \|/) {
                undef $mode;
            }
            next unless $mode;
            $newline =~ s/([ \.\d]+\|){3}//;
            push(@framelist, split(/\s+/, $newline));
        }
        
        @framelist = grep { /^\d+$/ } @framelist;
        @framelist = sort {$a <=> $b} @framelist;
        
        # aggiungo anche il frame rappresentativo del cluster
        my $workdir = $path . "/BRENDA/$ref_struct";
        $sample->{$workdir} = [ $path, $ref_struct ];
        
        # e raccolgo un campione di frames distribuito lungo tutto il cluster
        my $step = int(scalar @framelist / $frame_num);
        my $sampled = 1;
        while ($sampled < $frame_num) {
            my $seed = $sampled * $step;
            $workdir = $path . "/BRENDA/$framelist[$seed]";
            $sampled++ unless (exists $sample->{$workdir});
            $sample->{$workdir} = [ $path, $framelist[$seed] ];
        }
        
        
#         # raccolgo un campione casuale di frames
#         my $sampled = 0E0;
#         while ($sampled < $frame_num) {
#             my $seed = int(rand(scalar @framelist));
#             my $workdir = $path . "/BRENDA/$framelist[$seed]";
#             $sampled++ unless (exists $sample->{$workdir});
#             $sample->{$workdir} = [ $path, $framelist[$seed] ];
#         }
        
    }
    
    foreach my $workdir (keys %{$sample}) {
        my $xtc_file = $sample->{$workdir}->[0] . '/simulazione/MD_50ns.xtc';
        my $tpr_file = $sample->{$workdir}->[0] . '/simulazione/MD_50ns.tpr';
        foreach my $file ($xtc_file, $tpr_file) {
            croak "\nE- file <$file> not found\n\t" unless (-e $xtc_file);
        }
        my $frame = $sample->{$workdir}->[1];
        my $trjconv_opt = {
            'xtc'       =>  $xtc_file,
            'tpr'       =>  $tpr_file,
            'frame'     =>  $frame,
            'workdir'   =>  $workdir
        };
        push @thr, threads->new(\&trjconv, $trjconv_opt);
    }
    for (@thr) { $_->join() }; # aspetto che tutti i thread siano terminati
    @thr = ( ); # ripulisco la lista dei threads
}


TOPOLOGY: {
# preparazione dei file di topologia per AMBER
    
    printf("\nI- %s preparing topologies...\n", clock());
    
    # raccolgo una lista dei paths di dove ho campionato gli snapshot
    my $snapshot_paths = [ ];
    my $system_paths = folders($list_file);
    while (my $path = shift @{$system_paths}) {
        $path .= '/BRENDA';
        opendir(DIR, $path);
        my @snaps = grep { !/^\./ && -d "$path/$_" } readdir(DIR);
        closedir DIR;
        while (my $snap = shift @snaps) {
            my $complete_path = $path . '/' . $snap;
            push(@{$snapshot_paths}, $complete_path);
        }
    }
    
    while (my $path = shift @{$snapshot_paths}) {
        push @thr, threads->new(\&tleap, $path);
    }
    for (@thr) { $_->join() }; # aspetto che tutti i thread siano terminati
    @thr = ( ); # ripulisco la lista dei threads
}


MINIMIZATION: {
# minimizzazione
    
    printf("\nI- %s performing minimizations...\n", clock());
    
    # raccolgo una lista dei paths di dove ho campionato gli snapshot
    my $snapshot_paths = [ ];
    my $system_paths = folders($list_file);
    while (my $path = shift @{$system_paths}) {
        $path .= '/BRENDA';
        opendir(DIR, $path);
        my @snaps = grep { !/^\./ && -d "$path/$_" } readdir(DIR);
        closedir DIR;
        while (my $snap = shift @snaps) {
            my $complete_path = $path . '/' . $snap;
            push(@{$snapshot_paths}, $complete_path);
        }
    }
    
    while (my $path = shift @{$snapshot_paths}) {
        push @thr, threads->new(\&sander, $path);
    }
    for (@thr) { $_->join() }; # aspetto che tutti i thread siano terminati
    @thr = ( ); # ripulisco la lista dei threads
}

MMPBSA: {
# lancio MM-PBSA
    
    printf("\nI- %s performing MM-GBSA...\n", clock());
    
    my $fileobj = BRENDA::lib::FileIO->new('filename' => $list_file);
    my $content = $fileobj->read();
    my $mmpbsa_opt = { };
    shift @{$content}; # rimuovo la prima riga del file
    while (my $record = shift @{$content}) {
        chomp $record;
        my @fields = split(';',$record);
        $mmpbsa_opt = {
            'receptor'      => $fields[1],
            'ligand'        => $fields[2],
            'complex'       => $fields[3]
        };
        push @thr, threads->new(\&mmpbsa, $mmpbsa_opt);
    }
    for (@thr) { $_->join() }; # aspetto che tutti i thread siano terminati
    @thr = ( ); # ripulisco la lista dei threads
}

# Il blocco COLLECT raccoglie in un file csv le energie ele e VdW (escluse le
# interazioni di tipo 1-4) e la ASA calcolata per ogni snapshot di ogni
# recettore, ligando e complesso di ogni sistema
#
# Per il momento non uso questo pezzo di codice e salto direttamente alla fine.
#
# in quanto mmpbsa.pl produce già da sè per ogni sistema il file
# "prot-min_statistics.out" con le medie e le stdev dei parametri energetici
# (inoltre il file "prot-min_statistics.out.snap" fornisce i valori singoli per
# ogni snapshot campionato)

goto FINE;

COLLECT: {
# colleziono gli output dei calcoli
    
    printf("\nI- %s collecting <mm_pbsa.pl> outputs...\n", clock());
    
    my $fileobj = BRENDA::lib::FileIO->new('filename' => $list_file);
    my $content = $fileobj->read();
    my $parser_opt = { };
    shift @{$content}; # rimuovo la prima riga del file
    while (my $record = shift @{$content}) {
        chomp $record;
        my @fields = split(';',$record);
        $parser_opt->{$fields[0]} = $fields[3];
    }
    
    my $rambo_obj = BRENDA::lib::Rambo->new(
        'workdir'       => getcwd(),
        'parser_opt'    => $parser_opt
    );
    $rambo_obj->parser();
}

FINE: {
    printf("\n*** ADNERB %s ***\n", clock());
    exit;
}


sub folders {
# ritorna una lista di path dal file csv contenente l'elenco dei sistemi
    my ($filename) = @_;
    
    my $fileobj = BRENDA::lib::FileIO->new('filename' => $filename);
    my $content = $fileobj->read();
    shift @{$content}; # rimuovo la prima riga
    
    my %folders;
    while (my $newline = shift @{$content}) {
        chomp $newline;
        my @fields = split(';', $newline);
        shift @fields; # rimuovo la prima colonna
        while (my $folder = shift @fields) {
            $folders{$folder} = 1;
        }
    }
    
    my $list = [ keys %folders ];
    return $list;
}

sub mmpbsa {
# lancio il calcolo delle energie
    
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        lock $queued; $queued = $queued + 1;
        thread_monitor();
    }
    $semaforo->down(); # occupo uno slot
    { lock $running; $running = $running + 1; }
    thread_monitor();
    
    my ($mmpbsa_opt) = @_;
    
    my $rambo_obj = BRENDA::lib::Rambo->new('mmpbsa_opt' => $mmpbsa_opt);
    $rambo_obj->gbsa();
    
    {
        lock $running; $running = $running - 1;
        lock $queued; $queued = $queued - 1;
        $queued = 0E0 if ($queued <= 0);
        $running = 0E0 if ($running <= 0);
    }
    thread_monitor();
    $semaforo->up(); # libero uno slot
}


sub sander {
# lancio le minimizzazioni
    
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        lock $queued; $queued = $queued + 1;
        thread_monitor();
    }
    $semaforo->down(); # occupo uno slot
    { lock $running; $running = $running + 1; }
    thread_monitor();
    
    my ($path) = @_;
    my $rambo_obj = BRENDA::lib::Rambo->new('workdir' => $path);
    $rambo_obj->minimize();
    
    {
        lock $running; $running = $running - 1;
        lock $queued; $queued = $queued - 1;
        $queued = 0E0 if ($queued <= 0);
        $running = 0E0 if ($running <= 0);
    }
    thread_monitor();
    $semaforo->up(); # libero uno slot
}

sub tleap {
# preparo i file delle topologie
    
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        lock $queued; $queued = $queued + 1;
        thread_monitor();
    }
    $semaforo->down(); # occupo uno slot
    { lock $running; $running = $running + 1; }
    thread_monitor();
    
    my ($path) = @_;
    my $rambo_obj = BRENDA::lib::Rambo->new('workdir' => $path);
    $rambo_obj->topology();
    
    {
        lock $running; $running = $running - 1;
        lock $queued; $queued = $queued - 1;
        $queued = 0E0 if ($queued <= 0);
        $running = 0E0 if ($running <= 0);
    }
    thread_monitor();
    $semaforo->up(); # libero uno slot
}

sub trjconv {
# campiona uno snapshot a partire da una traiettoria fatta con GROMACS
    
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        lock $queued; $queued = $queued + 1;
        thread_monitor();
    }
    $semaforo->down(); # occupo uno slot
    { lock $running; $running = $running + 1; }
    thread_monitor();
    
    my ($trjconv_opt) = @_;
    
    mkdir $trjconv_opt->{'workdir'}; # creo una cartella di lavoro
    
    my $rambo_obj = BRENDA::lib::Rambo->new('gmxsnapshot_opt' => $trjconv_opt);
    $rambo_obj->gmxsnapshot();
    
    {
        lock $running; $running = $running - 1;
        lock $queued; $queued = $queued - 1;
        $queued = 0E0 if ($queued <= 0);
        $running = 0E0 if ($running <= 0);
    }
    thread_monitor();
    $semaforo->up(); # libero uno slot
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

sub thread_monitor {
    printf("\r\tRUNNING [%03d] QUEUED [%03d]", $running, $queued);
}