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

###################################################################

use Carp;

# leggo le opzioni passate allo script
use Getopt::Std;
my %options=();
getopts('m:u:p:a:h', \%options);


USAGE: {
    no warnings;
    my $usage = <<END

Genera automaticamente script per PITA

  $0 -a [pita|miranda] -m pattern1 -u pattern2 [-p path]
  
  -a [pita|      scegliere l'algoritmo di predizione da usare (default pita)
      miranda|
      rnahybrid] 
  -m pattern1    stringa per riconoscere i FASTA contenenti miRNA seqs
  -u pattern2    stringa per riconoscere i FASTA contenenti UTR seqs
  -p path        percorso in cui cercare i file (di default è pwd)
  -h             help
  
  ATTENZIONE: il carattere di protezione \\ (backslash) usato nelle
  stringhe in questo caso diventa \\\\ (doppio backslash).
  
  es.: "\\\\d+" individua stringhe con almeno un carattere numerico
       (invece di usare "\\d+")
END
    ;

    if (($options{h})||(!$options{m})||(!$options{u})) {
        print $usage; exit;
    }
}


use Cwd;
my $dh;

# imposto le opzioni di default
my $workdir = getcwd; my $method = 'pita';
# cambio working dir se viene specificato
$workdir = $options{p} if $options{p};
# cambio metodo di predizione se viene specificato
$method = $options{a} if $options{a};

opendir ($dh, $workdir) or croak "path <$workdir> inesistente\n";
my @all_file_list = readdir($dh);
closedir $dh;

my @utr_file_list = grep /$options{u}/, @all_file_list;
my @mir_file_list = grep /$options{m}/, @all_file_list;

print "MIR files: @mir_file_list\nUTR files: "."@utr_file_list"."\n";
# esco se una delle liste di file è vuota
croak "\n---\nfile non trovati, impossibile creare i jobs\n" unless (@mir_file_list and @utr_file_list);


use RICEDDARIO::lib::PBS_manager::Scheduler;
my $job_obj = RICEDDARIO::lib::PBS_manager::Scheduler->new();

foreach my $mir_file (@mir_file_list) {
    foreach my $utr_file (@utr_file_list) {
        # ********************************************************************************
        # allestisco un case_of per valutare quale metodo di predizione inserire nei job
        # 
        # il blocco CASEOF dovrà essere implementato man mano che sviluppo nuovi metodi
        # per la classe <RICEDDARIO::lib::PBS_manager::Scheduler> per scrivere job file contenenti
        # nuovi metodi di predizione; ricordarsi di aggiornare pure la variabile $usage
        # ********************************************************************************
        $_ = $method;
        CASEOF: {
            /^pita$/ && do {
                $job_obj->write_pita_job( utr => $workdir.'/'.$utr_file,
                                          mir => $workdir.'/'.$mir_file);
                last CASEOF;
            };
            /^miranda$/ && do {
                $job_obj->write_miranda_job( utr => $workdir.'/'.$utr_file,
                                             mir => $workdir.'/'.$mir_file);
                last CASEOF;
            };
            /^rnahybrid$/ && do {
                $job_obj->write_rnahybrid_job( utr => $workdir.'/'.$utr_file,
                                               mir => $workdir.'/'.$mir_file);
                last CASEOF;               
            };
            croak "\n---\nmetodo di predizione $_ non ancora implementato\n";
        }
    }
}

exit;
