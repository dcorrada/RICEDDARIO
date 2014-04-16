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
our %options=();
use Cwd;
use Carp;
use threads;

USAGE: {
    use Getopt::Std;no warnings;
    getopts('a:q:d:e:n:hs', \%options);
    my $usage = <<END

OPZIONI

  $0 -a ref.fasta -q reads.fastq

  -a pattern1    fastA ref file
  -q pattern2    fastQ ref file
  -d path        output directory (def: pwd)
  -e path        path dei file binari di maq (def: '/usr/local/bin/')
  -n int         numero di reads da mettere in ogni file bfq (def: 2000000)
  -s             conversione del file fastQ da formato SOLEXA a formato Sanger

  ATTENZIONE: il carattere di protezione \\ (backslash) usato nelle
  stringhe in questo caso diventa \\\\ (doppio backslash).

  es.: "\\\\d+" individua stringhe con almeno un carattere numerico
       (invece di usare "\\d+")
END
    ;
    if (($options{h})||(!$options{a})||(!$options{q})) {
        print $usage; exit;
    }
}

#######################
## VARIABILI GLOBALI ##
our $maq_bins_path = ($options{e})? $options{e} : '/usr/local/bin/'; # path dei file binari di maq
our $workdir = ($options{d})? $options{d} : getcwd(); # path della working dir
our $nreads = ($options{n})? $options{n} : 2000000; # numero di reads da mettere in ogni file bfq
our ($fastA_file, $fastQ_file) = ($options{a}, $options{q}); # nomi dei file fastA e fastQ
our ($bfa_file) = $options{a} =~ m/(.+)\.(fa|fas|fasta)$/; $bfa_file .= '.bfa'; # nomi del file bfa generato a partire dal file fastA
our $bfq_files = [ ]; # nomi dei file bfq generati a partire dal file fastQ
our $thr = [ ]; # elenco dei threads attivi (x gli step di parallelizzazione)
our $maps_threads = 10;   # massimo numero di threads che girano contemporaneamente nello STEP 2
                         # se $nreads è impostato a 2M di reads ogni thread lanciato alloca circa 1GB di memoria
our $map_files = [ ]; # nomi dei file map generati a partire dallo STEP 2
our $all_map_file = 'all.map'; # nome del file map finale (dal merge di $map_files)
#######################


FILE_CHECK: { ## Controllo che esistano directory e files
    my ($dh, @file_list);

    opendir ($dh, $maq_bins_path) or croak "\n-- ERROR path dei file binari di maq <$maq_bins_path> inesistente\n";
    @file_list = readdir($dh); closedir $dh;
    grep /^maq$/, @file_list or croak "\n-- ERROR file binario <$maq_bins_path/maq> non trovato\n";

    opendir ($dh, $workdir) or croak "\n-- ERROR path <$workdir> inesistente\n";
    @file_list = readdir($dh); closedir $dh;
    grep /$fastA_file/, @file_list or croak "\n-- ERROR fastA file <$workdir/$fastA_file> non trovato\n";
    grep /$fastQ_file/, @file_list or croak "\n-- ERROR fastQ file <$workdir/$fastQ_file> non trovato\n";
};

MONITORING: { ## monitora le risorse lanciate dallo script
# in pratica reindirizza un ps su un file di log ogni tot secondi
my $thread_mon_params = { user => 'dcorrada', sleep => '60' } ;# tempo (sec) e utente su cui monitorare i processi
my $daemon = threads->new(\&thread_mon, $thread_mon_params);
$daemon->detach(); # faccio in modo che il thread giri per i fatti suoi, indipendentemente dagli altri
}

chdir $workdir; # prima di tutto mi sposto nella working dir per lavorare

##  RIGHE DI TESTING
# goto STEP_200;
# STEP_200: { print "\n"; }
############################

STEP_0: { ## STEP 0: converto i file fastQ in formato da Solexa a Sanger
    $options{s} && do { # controllo che l'opzione -s sia stata chiamata
        print "\n[STEP 0] Conversione formato fastQ Solexa > Sanger ...";
        my ($solexa_file, $noext) = ($fastQ_file, $fastQ_file =~ m/(.+)\.fastq/);
        $fastQ_file = $noext . '.sanger.fastq.gz';

        if ($solexa_file =~ m/\.gz$/) { # file gzipped
            run_cmd("gzip -dc $solexa_file | " . $maq_bins_path . "maq sol2sanger - - | gzip -c9 > $fastQ_file");
        } else { # file plain
            run_cmd($maq_bins_path . "maq sol2sanger $solexa_file - | gzip -c9 > $fastQ_file");
        }
        print "\n[STEP 0] Completato:";
        print "\n[STEP 0] fastQ file <$fastQ_file> ";
    };
}

STEP_1: { ## STEP 1: creazione dei file binari .bfa e .bfq
    print "\n[STEP 1] Conversione input files in formato binario ...";

    push @$thr, threads->new(\&plain2binary, 'bfa'); # thread x la creazione del file di input bfa
    push @$thr, threads->new(\&plain2binary, 'bfq'); # thread x la creazione dei file di input bfq

    for (@$thr) { $_->join() } # attendo che i threads lanciati siano terminati
    $thr = [ ]; # svuoto la lista dei threads x riciclarla in futuro

    BFQ_FILELIST: { # genero una lista dei file bfq appena creati
        my $dh; opendir ($dh, $workdir) or croak "\n-- ERROR path <$workdir> inesistente\n";
        my @file_list = readdir($dh);
        closedir $dh;
        @$bfq_files = grep /.bfq$/, @file_list;
    }
    print "\n[STEP 1] Completato ";
    print "\n[STEP 1] bfa file <$bfa_file>\n[STEP 1] bfq file(s)";
    print " <$_>" for (@$bfq_files);
}

# Prima di procedere con lo STEP 2 imposto un semaforo: se il numero di threads che verranno
# lanciati supera il valore impostato da $maps_threads quelli eccedenti vengono messi in queue
use Thread::Semaphore;
our $semaforo = Thread::Semaphore->new(int($maps_threads));
STEP_2: { ## STEP 2: run di allineamento (multipli e parallelizzati se i file .bfq sono più di uno)
    print "\n[STEP 2] Run di allineamento ...";
    foreach my $single_bfq (@{$bfq_files}) {
        my $params = { bfa => $bfa_file, bfq => $single_bfq }; # parametri x la subroutine run_map
        push @$thr, threads->new(\&run_map, $params); # thread x map
    }

    for (@$thr) { $_->join() } # attendo che i threads lanciati siano terminati
    $thr = [ ]; # svuoto la lista dei threads x riciclarla in futuro

    MAP_FILELIST: { # genero una lista dei file map appena creati
        my $dh; opendir ($dh, $workdir) or croak "\n-- ERROR path <$workdir> inesistente\n";
        my @file_list = readdir($dh);
        closedir $dh;
        @$map_files = grep /.map$/, @file_list;
    }
    print "\n[STEP 2] Completato";
    print "\n[STEP 2] map file(s)";
    print " <$_>" for (@$map_files)
}

STEP_3: { ## STEP 3: merge dei file map (se sono più di uno)
    print "\n[STEP 3] merge dei file map...";
    print "\n-- MAP files trovati [", scalar @$map_files, "]";
    if (scalar @$map_files == 1) { # se il map file e uno solo creo semplicemente un link simbolico
        symlink ($map_files->[0], $all_map_file);
    } elsif (scalar @$map_files > 1) {
        run_cmd($maq_bins_path . "maq mapmerge $all_map_file @$map_files 2>> STEP3.error.log");
    } else {
        croak "-- ERROR map files non trovati";
    }

    print "\n[STEP 3] Completato";
    print "\n[STEP 3] map file <$all_map_file> generato";
}

STEP_4: { ## STEP 4: map check e map assembly
    print "\n[STEP 4] map check e map assembly...";
    push @$thr, threads->new(\&check_n_assembly, 'check'); # thread check
    push @$thr, threads->new(\&check_n_assembly, 'assembly'); # thread assembly

    for (@$thr) { $_->join() } # attendo che i threads lanciati siano terminati
    $thr = [ ]; # svuoto la lista dei threads x riciclarla in futuro
    print "\n[STEP 4] Completato";
}


STEP_5: { ## STEP 5: output summaries
    print "\n[STEP 5] output summary files...";

    foreach my $single_thr ('cns2fq', 'cns2snp', 'cns2win', 'mapview') { # lista dei thread
        push @$thr, threads->new(\&output_summaries, $single_thr);
    }

    for (@$thr) { $_->join() } # attendo che i threads lanciati siano terminati
    $thr = [ ]; # svuoto la lista dei threads x riciclarla in futuro
    print "\n[STEP 5] Completato";
}

print "\n-- FINE PIPELINE --\n";
exit;


# post-processing features
sub output_summaries {
    my ($mode) = @_;

    my $dh; opendir ($dh, $workdir) or croak "\n-- ERROR impossibile aprire <$workdir>";
    my @file_list = readdir($dh); closedir $dh;
    grep /^consensus\.cns$/, @file_list or croak "\n-- ERROR file <consensus.cns> non trovato\n";
    grep $all_map_file, @file_list or croak "\n-- ERROR file <$all_map_file> non trovato\n";

    print "\n-- THREAD $mode lanciato...";
    CASEOF: {
        ($mode = m/^cns2fq$/) && do {
            run_cmd($maq_bins_path . "maq cns2fq consensus.cns > cns.fq");
            last CASEOF;
        };
        ($mode = m/^cns2snp$/) && do {
            run_cmd($maq_bins_path . "maq cns2snp consensus.cns > cns.snp");
            last CASEOF;
        };
        ($mode = m/^cns2win$/) && do {
            run_cmd($maq_bins_path . "maq cns2win consensus.cns > cns.win");
            last CASEOF;
        };
        ($mode = m/^mapview$/) && do {
            run_cmd($maq_bins_path . "maq mapview $all_map_file > mapview.log");
            last CASEOF;
        };
        croak "\n--ERROR thread $_ non previsto";
    }
}

# verifica il file map e fa l'assembly
sub check_n_assembly {
    my ($mode) = @_;
    if ($mode eq 'check') {
        print "\n-- THREAD check avviato...";
        run_cmd($maq_bins_path . "maq mapcheck $bfa_file $all_map_file > mapcheck.txt 2>> mapcheck.log");
    } elsif ($mode eq 'assembly') {
        print "\n-- THREAD assembly avviato...";
        run_cmd($maq_bins_path . "maq assemble consensus.cns $bfa_file $all_map_file 2>> assemble.log");
    } else {
        my $exception = <<END

-- ERROR Parametri mancanti o errati:
check_n_assembly('check'|'assembly')

END
        ;
        croak $exception;
    }
}

# lancia i threads per il mappaggio delle reads
sub run_map {
    my ($hash_ref) = @_; my %arg = %{$hash_ref};
    unless ($arg{bfa} && $arg{bfq}) {
        my $exception = <<END

-- ERROR Parametri mancanti
run_map(bfa => arg1, bfq => arg2)

END
            ;
        croak $exception;
    }
    unless (${$semaforo}) { print "\n-- THREAD su <$arg{bfq}> queued..." };
    $semaforo->down();
    print "\n-- THREAD su <$arg{bfq}> partito!";
    my ($map_file) = $arg{bfq} =~ m/(.+)\.bfq/;
    $map_file .= '.map';
    run_cmd($maq_bins_path . "maq map $map_file $arg{bfa} $arg{bfq} 2>> $map_file.log");
    $semaforo->up();
}

# converte i file fastA e fastQ nei rispettivi file binari .bfa e .bfq
sub plain2binary {
    my ($which_bin) = @_;
    CASEOF: {
        ($which_bin =~ m/^bfa$/) && do {
            print "\n-- CONVERSIONE di <$fastA_file> in corso...";
            run_cmd($maq_bins_path . "maq fasta2bfa $fastA_file $bfa_file 2>> STEP1.bfa_error.log");
            last CASEOF;
        };
        ($which_bin =~ m/^bfq$/) && do {
            print "\n-- CONVERSIONE <$fastQ_file> in corso...";
            my ($bfq_filename) = $fastQ_file =~ m/(.+)\.fastq\.gz$/; $bfq_filename .= '.bfq';
            run_cmd("gzip -dc $fastQ_file | " . $maq_bins_path . "maq fastq2bfq -n $nreads - $bfq_filename 2>> STEP1.bfq_error.log");
            last CASEOF;
        };
        croak "\n-- ERROR metodo di conversione in formato \"\.$which_bin\" non previsto\n";
    }
}

# routine che lancia comandi da shell
sub run_cmd {
    my ($cmd) = @_;
    warn("\n-- CMD: $cmd\n");
    my $benchmark = 'time -o "benchlogs.txt" -a -f "--CMD %C\n%E real %U user %S sys \nexit status %x\n"';
    # my $benchmark = 'time '; # variante ridotta quando time esiste solo come variante "shell builtin" e non come binario
    system("$benchmark $cmd") && die("** fail to run command '$cmd'");
}

# monitor x valutare le risorse usate dallo script man mano procede
sub thread_mon {
    my ($hash_ref) = @_; my %arg = %{$hash_ref};
    unless ($arg{user} && $arg{sleep}) {
        my $exception = <<END

-- ERROR Parametri mancanti
run_map(user => arg1, sleep => arg2)

END
            ;
        croak $exception;
    }
    print "\n-- THREAD monitor avviato...";
    while (1) {
        system('ps -u ' . $arg{user} . ' -o pid,tty,%cpu,%mem,comm >> thread_mon.log 2> /dev/null')
            && croak "-- ERROR username errato, thread monitor interrotto";
        qx/echo "\n\n--" >> thread_mon.log/;
        sleep $arg{sleep};
    }
}
