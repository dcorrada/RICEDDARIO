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
use lib $ENV{HOME},
        #~ '/opt/BioPerl-live/trunk/',     # BioPerl aggiornato via SVN
        #~ '/opt/PerlAPI/bioperl-live',    # BioPerl 1.2.3 fornito con Ensembl
        #~ '/opt/PerlAPI/ensembl_core_v50/modules', # Ensembl Core API
        #~ '/opt/PerlAPI/ensembl_core_v47/modules',
        ;

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;

###################################################################

use DBI;

my %acc = (  driver      => 'mysql',
             database    => 'database=mm9',    # nome del database
             host        => 'host=localhost',  # indirizzo IP (es. 'localhost')
             port        => 'port=3306',       # porta
             user        => 'dario',
             password    => '',

             # attributi del database handle
             attribute   => {  PrintError => 0, # riporta gli eventuali errori con warn( )
                               RaiseError => 0, # riporta gli eventuali errori con die( )
                            }

          );

my $datasource = "DBI:$acc{driver}:$acc{database};$acc{host};$acc{port}";

# Connessione al DB
my $dbh = DBI->connect($datasource, $acc{user}, $acc{password}, $acc{attribute})
    or die "\n--- non riesco a connettermi:\n" . DBI->errstr;

# faccio un tracing di tutte le operazioni effettuate e le scrivo su un log file
my $fh_dbilog; open($fh_dbilog, ">dbi.log"); DBI->trace(1,$fh_dbilog);




my $query_string = "SELECT miranda.mirID AS ?, rnahybrid.mirID AS ?, miranda.kgID, miranda.score
                    FROM mm9.miranda, mm9.rnahybrid
                    LIMIT 20";


my $sth = $dbh->prepare($query_string)
    or die "\n--- non riesco a preparare lo statement:\n" . $dbh->errstr;

# imposto gli alias per 'miranda.mirID' e 'rnahybrid.mirID' usando il carattere di binding;
# i punti di domanda '?' nella stringa della query sono come dei segnalibri che vanno a
# completare lo statement handle dopo aver lanciato il metodo 'prepare'.
# Si distinguono numerandoli da 1 per il primo ?, 2 per il secondo e cosi via...
# Con il metodo bind_param specifico cosa inserire al posto dei segnalibri
$sth->bind_param(1, 'miranda_mir');
$sth->bind_param(2, 'rnahybrid_mir');

$sth->execute()
    or die "\n--- non riesco a eseguire lo statement:\n" . $sth->errstr;




while (my $ref_row = $sth->fetchrow_hashref()) {
    print Dumper $ref_row;
}
warn "\n--- errore durante il fetching:\n" . $sth->errstr if $sth->err;



# Disconnessione
$dbh->disconnect();

# Chiusura del file di log
close $fh_dbilog;

exit;
