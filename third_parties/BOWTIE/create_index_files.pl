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
# Crea gli index files per bowtie (.ebwt files)

use Cwd;
use Carp;
use threads;
our %options=();

USAGE: {
    use Getopt::Std;no warnings;
    getopts('n:i:o:f:e:h', \%options);
    my $usage = <<END

OPZIONI

  $0 [options] -f <filename>

  -f filename    OBBLIGATORIO pattern di ricerca dei file da indicizzare
  -n int         numero massimo di threads da lanciare contemporaneamente; se non è specificato
                 lancia un numero di thread pari al numero di input files che trova
  -i path        path in cui risiedono i file di input (def: pwd)
  -o path        path di output (def: pwd)
  -e path        path di dove risiedono i binari di bowtie (def: '/usr/local/bin/')

  ATTENZIONE: il carattere di protezione \\ (backslash) usato nelle
  stringhe in questo caso diventa \\\\ (doppio backslash).

  es.: "\\\\d+" individua stringhe con almeno un carattere numerico
       (invece di usare "\\d+")
END
    ;
    if (($options{h})||!($options{f})) {
        print $usage; exit;
    }
}

#######################
## VARIABILI GLOBALI ##
our $bowtie_path = ($options{e})? $options{e} : '/usr/local/bin/'; # path dei file binari di bowtie
our $bowtie_build = 'bowtie-build';
our $input_dir = ($options{i})? $options{i} : getcwd(); # path della dir in cui risiedono i file di input
our $output_dir = ($options{o})? $options{o} : getcwd(); # path della dir in cui verra' salvato l'output
our $fasta_file_list = [ ]; # lista dei file di input
our $thr = [ ]; # elenco dei threads attivi (x gli step di parallelizzazione)
our $thread_num = $options{n}; # numero massimo di job threads 
#######################


FILE_CHECK: { ## Controllo che esistano directory e files
    my ($dh, @file_list);

    # prima controllo che bowtie sia installato...
    opendir ($dh, $bowtie_path) or croak "\n-- ERROR path dei file binari di bowtie <$bowtie_path> inesistente\n";
    @file_list = readdir($dh); closedir $dh;
    if (grep /^bowtie-build$/, @file_list) {
        chdir $bowtie_path;
        $bowtie_build = getcwd().'/'.$bowtie_build;
    } else {
        croak "\n-- ERROR file binario <$bowtie_path/$bowtie_build> non trovato\n";
    }
    
    # poi controllo la dir in cui risedono i file multi-fasta
    opendir ($dh, $input_dir) or croak "\n-- ERROR path dei file fasta <$input_dir> non trovato\n";
    @file_list = readdir($dh); closedir $dh;
    @file_list = grep /$options{f}$/, @file_list or croak "\n-- ERROR pattern dei file fasta <$input_dir/$options{f}> non trovato\n";
    chdir $input_dir;
    @{$fasta_file_list} = map { getcwd().'/'.$_} @file_list;
    
    # poi controllo la output dir
    opendir ($dh, $output_dir) or do {
        mkdir $output_dir; # se non esiste la creo
        chdir $output_dir;
        $output_dir = getcwd();
    }
    
};


# Prima di procedere imposto un semaforo: se il numero di threads che verranno lanciati
# supera il valore impostato da $thread_num quelli eccedenti vengono messi in queue
# se $thread_num nn è def lo setto pari al numero di file di input trovati
$thread_num = scalar @{$fasta_file_list} unless ($thread_num);


use Thread::Semaphore;
our $semaforo = Thread::Semaphore->new(int($thread_num));

foreach my $single_fasta (@{$fasta_file_list}) {
    my $params = { ref_file => $single_fasta, options => '-f'}; # parametri x la subroutine run_bowtie_index
    push @$thr, threads->new(\&run_bowtie_index, $params);
}

for (@$thr) { $_->join() } # attendo che i threads lanciati siano terminati
print "\n--END tutti i threads lanciati sono conclusi\n";

exit;



sub run_bowtie_index {
    my ($hash_ref) = @_; my %arg = %{$hash_ref};
    
    unless ($arg{ref_file}) {
        my $exception = <<END

-- ERROR Parametri mancanti
run_bowtie_index(ref_file => arg1, [options => arg2], [index_basename => arg3])

ref_file        nome del reference
options         stringa contenente opzioni aggiuntive di bowtie-index (v. documentazione)
index_basename  basename degli index files che verranno generati
END
            ;
        croak $exception;
    }
    
    my $reference_in = $arg{ref_file}; # ref file da indicizzare
    my $options = ($arg{options})? $arg{options} : '';
    # se nn specificato estraggo il basename dal nome del ref_file
    my ($index_basename) = ($arg{index_basename})? $arg{index_basename} : $reference_in =~ /\/([\w\-\+\.]+)\.\w+$/;
    
    unless (${$semaforo}) { print "\n", &date, "-- INDICIZZAZZIONE DI <$reference_in> [queued]" };
    $semaforo->down();
    print "\n", &date, "-- INDICIZZAZZIONE DI <$reference_in> [started]";
    
    chdir $output_dir;
    my $cmd_line = "$bowtie_build $options $reference_in $index_basename >> $index_basename.log 2>&1";
    run_cmd($cmd_line);
    print "\n-- REF FILE <$reference_in> indicizzato!\n";
    $semaforo->up();
}

# routine che lancia comandi da shell
sub run_cmd {
    my ($cmd) = @_;
    warn("\n-- CMD: $cmd\n");
    # my $benchmark = 'time -o "benchlogs.txt" -a -f "--CMD %C\n%E real %U user %S sys \nexit status %x\n"';
    my $benchmark = 'time '; # variante ridotta quando time esiste solo come variante "shell builtin" e non come binario
    system("$benchmark $cmd") && die("** fail to run command '$cmd'");
}

# ritorna l'ora locale
sub date {
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    my $date = '['.($anno+1900).'/'.($mese+1).'/'."$giom - $ore:$min:$sec] ";

    return $date;
}
