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
use Cwd; 
use DBI;

# dati di input
my %inputs_data = ( records   => 0,  # numero records
                    tablename => $ARGV[0], # nome tabella sul DB
                    mapfile   => getcwd.'/output.map', # nome map file
                    logfile   => getcwd.'/run.log' ); # nome log file

# attributi da reperire dal map file di bowtie
my %record = ( targetID => '', # nome del target su cui mappa la read
               readID   => '', # nome della read
               strand   => '', # +/- indica se è stato allineata la read (+) o il suo complemento inverso)
               sequence => '', # sequenza della read, o del suo complemento inverso se strand è "-"
               start    => '', # posizione di inizio allineamento (a partire dall'estremita sinistra della sequenza di riferimento)
               end      => '', # posizione di fine allineamento
               mmatch   => '' ); # elenco dei mismatch$sth->finish();

# Configurazioni DBI
my %acc = (  driver      => 'mysql',
             database    => 'database=RGASP',    # nome del database
             host        => 'host=localhost',  # indirizzo IP (es. 'localhost')
             port        => 'port=3306',       # porta
             user        => 'rgasp',
             password    => 'rgaspers',
             attribute   => {  PrintError => 0, RaiseError => 0, } # riporta gli eventuali errori con wanr o die
          );
my $datasource = "DBI:$acc{driver}:$acc{database};$acc{host};$acc{port}";


USAGE: {
    use Getopt::Long;no warnings;
    GetOptions(\%inputs_data, 'help|h', 'mapfile|m=s', 'logfile|l=s'); 
    my $usage = <<END

SYNOPSYS

  $0 <tablename> [-m map_filename] [-l log_filename]

END
    ;
    if ((exists $inputs_data{help})||!$ARGV[0]) {
        print $usage; exit;
        }
}


# Apro il file run log per cercare il numero di allienamenti effettuati
if (-e $inputs_data{logfile}) {
    open(LOGFILE, $inputs_data{logfile}) or croak ("\nImpossibile aprire il file <$inputs_data{logfile}>");
    while (<LOGFILE>) {
            my $newline = $_; chomp $newline;
            $newline =~ m/^Reported (\d+) .*alignments/g && do {
                     $inputs_data{records} = $1; # mi segno il numero di allieneamenti da trovare
            }
    } 
    close LOGFILE;
} else {$inputs_data{records} = 'unknown' }

############### CREAZIONE TABELLA sul DB
my $dbh = DBI->connect($datasource, $acc{user}, $acc{password}, $acc{attribute})
    or die "\n--- non riesco a connettermi:\n" . DBI->errstr;

$dbh->do("DROP TABLE IF EXISTS $inputs_data{tablename}")  # elimino la tabella se pre-esistente
        or die "\n--- non riesco a eseguire lo statement:\n" . $dbh->errstr;

my $query_string = <<END
CREATE TABLE IF NOT EXISTS $inputs_data{tablename} (
  `PID` INT NOT NULL PRIMARY KEY AUTO_INCREMENT,
  `targetID` varchar(255) NOT NULL DEFAULT '',
  `readID` varchar(255) NOT NULL DEFAULT '',
  `strand` set("-","+") NOT NULL DEFAULT '+',
  `sequence` varchar(255) NOT NULL DEFAULT '',
  `start` int NOT NULL DEFAULT '0',
  `end` int NOT NULL DEFAULT '0',
  `mmatch` varchar(255) NOT NULL DEFAULT '0',
  KEY `targetID` (`targetID`),
  KEY `readID` (`readID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
END
;
my $sth = $dbh->prepare($query_string)
        or die "\n--- non riesco a preparare lo statement:\n" . $dbh->errstr;
$sth->execute()
        or die "\n--- non riesco a eseguire lo statement:\n" . $sth->errstr;
$sth->finish();
$dbh->disconnect; 
printf ("\nTABLE\t<%s>...CREATED\n", $inputs_data{tablename});





############### POPOLAMENTO TABELLA
$dbh = DBI->connect($datasource, $acc{user}, $acc{password}, $acc{attribute})
    or die "\n--- non riesco a connettermi:\n" . DBI->errstr;

# query per l'inserimento dei dati
$query_string = <<END
INSERT INTO $inputs_data{tablename} 
SET targetID = ?, readID = ?, strand = ?, 
sequence = ?, start = ?, end = ?, mmatch = ?
END
;
$sth = $dbh->prepare($query_string)
        or die "\n--- non riesco a preparare lo statement:\n" . $dbh->errstr;


# Apro il file contenente le info di mapping
open(MAPFILE, $inputs_data{mapfile}) or croak ("\nImpossibile aprire il file <$inputs_data{mapfile}>");;
my $count = 0;
while (<MAPFILE>) {
        $count++;
        
        
        ### leggo il record dal file di mapping...
        my $newline = $_;chomp($newline); 
        my @field  = split(/\t/, $newline); # splitto i diversi campi
        # prendo solo quelli che mi interessano
        $record{targetID} = $field[2];
        $record{readID} = $field[0];
        $record{strand} = $field[1];
        $record{start} = $field[3];
        $record{sequence} = $field[4];
        $record{end} = $field[3]+length($record{sequence})-1;
        if ($field[7]) {
                $record{mmatch} = $field[7];
        } else {
                $record{mmatch} = "NULL";
        }
        
        
### e lo ricaccio nella tabella del database
        $sth->execute($record{targetID}, $record{readID}, $record{strand},
                $record{sequence}, $record{start}, $record{end}, $record{mmatch} )
                or die "\n--- non riesco a eseguire lo statement:\n" . $sth->errstr;
        print "\n[$count/$inputs_data{records}]"
            if (($count%10000) == 0);
}

print "...record inseriti";
close MAPFILE;
$sth->finish();
$dbh->disconnect;

# print Dumper($inputs_data);

exit;

