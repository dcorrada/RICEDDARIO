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
# ATTENZIONE: la definizione del numero di job threads da lanciare (opzione -n dello script)
# rappresenta un compromesso col numero di map threads lanciati dallo script <maq_pipeline.pl>
# I job threads sono delle singole chiamate allo script <maq_pipeline.pl>.
# Di default lancio 4 map threads da 2M di reads ognuno (x un totale di 4.48G di mem allocati)
# su 2 job threads (4.48 X 2 = 8.96G di mem allocati).
# OKKIO quindi a bilanciare bene map threads e job threads: il rischio è di saturare
# tutta la RAM e imballare completamente la macchina su cui stanno girando i calcoli

our $options= { };
use Cwd;
use Carp;
use threads;
use threads::shared;
use Thread::Semaphore;

USAGE: {
    use Getopt::Long;no warnings;
    GetOptions($options, 'help|h', 'threads|n=i', 'workdir|d=s', 'sleep|s=i');
    my $usage = <<END

SYNOPSYS

  $0 [-d path] [-n int] [-s sec] <shell_script_filename>

Cerca nella working directory tutti gli shell-script aventi come nome
<shell_script_filename> (es. "script.sh", solitamente localizzati in
diverse subdirs) e li lancia simultaneamente su threads separati.

OPZIONI

  -n --threads <int>        numero massimo di threads da lanciare
                            contemporaneamente (def: 6)
  -d --workdir <string>     working directory (def: pwd)
  -s --sleep <int>          intervallo di tempo (in secondi) entro cui
                            vengono monitorati i threads (def: 1800)

  ATTENZIONE: il carattere di protezione \\ (backslash) usato nelle
  stringhe in questo caso diventa \\\\ (doppio backslash).

  es.: "\\\\d+" individua stringhe con almeno un carattere numerico
       (invece di usare "\\d+")
END
    ;
    if ((exists $options->{help})||!$ARGV[0]) {
        print $usage; exit;
    }
}

#######################
## VARIABILI GLOBALI ##
our $working_dir = getcwd(); # path della working dir
our $sh_job_list = [ ]; # lista dei job
our $thread_num = ($options->{threads})? $options->{threads} : 6; # numero massimo di job threads da lanciare contemporaneamente
our $semaforo = Thread::Semaphore->new(int($thread_num));
our $sh_file = $ARGV[0]; # nome del file shell-script da lanciare come thread singolo
our @thr; # lista dei threads
our (@q_list, @r_list, @f_list) :shared; # lista dei job accodati, running e terminati
our $daemon; # demone che gestice il monitoring
#######################

CHECKDIR: { # check della working dir
    ($options->{workdir}) and do {
        if (chdir $options->{workdir}) {
            $working_dir = getcwd();
            print "\n-- WORKDIR changed to <$working_dir>\n"
        } else {
            croak "pattern <$options->{workdir}> non trovato\n";
        }
    };
}

JOBLIST: {# allestisco la lista dei jobs (l'ID è il nome della cartella trovata)
    my $dh; opendir ($dh, $working_dir) or croak "\n-- ERROR <$working_dir> non aperta\n";
    my @file_list = readdir($dh); closedir $dh;
    @file_list = map (/([^\/]*)$/, @file_list);  
    foreach my $identifier (@file_list) {
        $identifier =~ /^\./ and next;
        # se trovo lo shell-script aggiungo $identifier alla lista dei jobs
        if (-d ($working_dir . '/' . $identifier)) {
            if (-e ($working_dir . '/' . $identifier . '/' . $sh_file)) {
                push(@{$sh_job_list}, $identifier);
            } else {
                print "\n--WARN <$working_dir/$identifier/$sh_file> non trovato...";
            }
        }
    }
    #~ print "FILE LIST:\n"; foreach (@file_list) { print "<$_>\n"; }
    #~ print "JOB LIST:\n"; foreach (@{$sh_job_list}) { print "<$_>\n"; }
    
}

MONITORING: { ## monitora i lo status dei job
my $thread_mon_params = { sleep => ($options->{sleep})? $options->{sleep} : 1800 };# tempo (sec) su cui monitorare i processi
$daemon = threads->new(\&thread_mon, $thread_mon_params);
$daemon->detach(); # faccio in modo che il thread giri per i fatti suoi, indipendentemente dagli altri
}

JOB_LAUNCH: {
    foreach my $job_name (@{$sh_job_list}) { # lancio i threads
        push @thr, threads->new(\&launch_thread, $job_name);
    }
    for (@thr) { $_->join() }
    print "\n--END tutti i threads lanciati sono conclusi\n"
}

exit;

sub launch_thread {
    my ($job_name) = @_;
    
    
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        { lock @q_list;
          push (@q_list, $job_name); }
    }
    
    $semaforo->down(); #occupo uno slot
    { lock @q_list; lock @r_list;
      @q_list = grep(!/^$job_name$/, @q_list);
      push (@r_list, $job_name); }
    
    my $sh_path = $working_dir . '/' . $job_name . '/' . $sh_file; # lancio il lo shell script associato al job
    my @args = ('/bin/sh', '-c', $sh_path);
    system(@args) && do { $semaforo->up(); die ("** fail to run <$sh_path>"); };
    
    { lock @r_list; lock @f_list;
      @r_list = grep(!/^$job_name$/, @r_list);
      push (@f_list, $job_name); }
    $semaforo->up(); # libero lo slot
}


sub date { # ritorna l'ora locale
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    my $date = '['.($anno+1900).'/'.($mese+1).'/'."$giom - $ore:$min:$sec] ";

    return $date;
}


sub thread_mon { # monitor x valutare lo status dei thread lanciati
    my ($hash_ref) = @_; my %arg = %{$hash_ref};
    print "\n-- THREAD monitor avviato...";
    while (1) {
        foreach my $line (@{&status_monitor()}) { print $line; }
        sleep $arg{sleep};
    }
}


# scrive un file di log in cui butta dentro man mano la lista di job
# eseguiti e di job in coda
#
sub status_monitor {
    my $newline = pack("A40A40A40", "QUEUED", "RUNNING", "FINISHED")."\n".
                  pack("A40A40A40", "------------", "---------------", "---------------")."\n";
    my $log_content = ["\n" . date . "\n", $newline ];
    
    # definisco il numero massimo di linee da scrivere in ogni tabella di log
    my $max_num_line;
    {   lock @q_list; lock @r_list; lock @f_list; 
        if ((scalar @q_list) >= (scalar @r_list) && (scalar @q_list) >= (scalar @f_list)) {
            $max_num_line = scalar @q_list;
        } elsif ((scalar @r_list) >= (scalar @f_list)) {
            $max_num_line = scalar @r_list;
        } else {
            $max_num_line = scalar @f_list;
        }
        
        for (my $counter = 0; $counter < $max_num_line; $counter++) {
            no warnings;
            $newline = pack("A40A40A40", $q_list[$counter], $r_list[$counter], $f_list[$counter])."\n";
            push @$log_content, $newline;
        }
    }
    
    return $log_content;
}
