#!/usr/bin/perl
#~ -d

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



our %options=();
use Cwd;
use Carp;
use threads;

USAGE: {
    use Getopt::Std;no warnings;
    getopts('n:d:h', \%options);
    my $usage = <<END

OPZIONI

  $0 [-d path] [-n int]

  -n int         numero massimo di threads da lanciare contemporaneamente
  -d path        working directory (def: pwd)

  ATTENZIONE: il carattere di protezione \\ (backslash) usato nelle
  stringhe in questo caso diventa \\\\ (doppio backslash).

  es.: "\\\\d+" individua stringhe con almeno un carattere numerico
       (invece di usare "\\d+")
END
    ;
    if ($options{h}) {
        print $usage; exit;
    }
}

#######################
## VARIABILI GLOBALI ##
our $workdir = ($options{d})? $options{d} : getcwd(); # path della working dir
our $sh_job_list = [ ]; # lista dei file shell script 'launch_pipeline.sh' da lanciare
our $thread_num = ($options{n})? $options{n} : 2; # numero massimo di job threads da lanciare contemporaneamente
#######################

chdir $workdir;

my $dh; opendir ($dh, $workdir) or croak "path <$workdir> inesistente\n";
my @all_file_list = readdir($dh);
closedir $dh;

@all_file_list = grep(!/^\./, @all_file_list);  # spazzo via i file nascosti dalla lista ('.', '..', '.filename')

# creo una lista di files <launch_pipeline.sh> con la seguente sintassi:
# [pwd path]/[$_ path]/launch_pipeline.sh
@all_file_list = map { getcwd() . '/' . $_ . '/launch_pipeline.sh' } @all_file_list;

foreach my $file_exists (@all_file_list) {
    if (-e $file_exists) { # esiste il file <[pwd path]/[$_ path]/launch_pipeline.sh> ?
        push @{$sh_job_list}, $file_exists;
    } else {
        carp "--WARN file <$file_exists> non trovato!";
    }
}


use Thread::Semaphore;
our $semaforo = Thread::Semaphore->new(int($thread_num));
our @thr;

foreach my $sh_file (@{$sh_job_list}) { # lancio i threads
    push @thr, threads->new(\&launch_sh_script, $sh_file);
}

for (@thr) { $_->join() }

print "\n--END tutti i threads lanciati sono conclusi\n";

exit;

sub launch_sh_script {
    my ($sh_file) = @_;
    my ($jobname) = $sh_file =~ m/([\w\-\+\.]+\-\-[\w\-\+\.]+)\/launch_pipeline\.sh$/;
    unless (${$semaforo}) { print "\n", &date, "-- THREAD <$jobname> queued..." };
    $semaforo->down();
    print "\n", &date, "-- THREAD <$jobname> partito!";
    my @args = ('/bin/sh', '-c', $sh_file);
    system(@args) && do { $semaforo->up(); die ("** fail to run <$sh_file>"); };
    $semaforo->up();
}

# ritorna l'ora locale
sub date {
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    my $date = '['.($anno+1900).'/'.($mese+1).'/'."$giom - $ore:$min:$sec] ";

    return $date;
}
