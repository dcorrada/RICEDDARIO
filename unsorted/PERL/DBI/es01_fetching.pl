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
             database    => 'mm9',    # nome del database
             host        => 'localhost',  # indirizzo IP (es. 'localhost')
             port        => '3306',       # porta
             user        => 'dario',
             password    => '',

             # attributi del database handle
             attribute   => {  PrintError => 0, # riporta gli eventuali errori con warn( )
                               RaiseError => 0, # riporta gli eventuali errori con die( )
                            }

          );

my $datasource = join(':','DBI','mysql',$acc{database},$acc{host},$acc{port});

# Connessione al DB
my $dbh = DBI->connect($datasource, $acc{user}, $acc{password}, $acc{attribute})
    or die "\n--- non riesco a connettermi:\n" . DBI->errstr;

# faccio un tracing di tutte le operazioni effettuate e le scrivo su un log file
my $fh_dbilog; open($fh_dbilog, ">dbi.log"); DBI->trace(1,$fh_dbilog);




my $query_string = "SELECT miranda.mirID AS paperino, rnahybrid.mirID AS topolino, miranda.kgID, miranda.score
                    FROM mm9.miranda, mm9.rnahybrid
                    LIMIT 20";


my $sth = $dbh->prepare($query_string)
    or die "\n--- non riesco a preparare lo statement:\n" . $dbh->errstr;

$sth->execute()
    or die "\n--- non riesco a eseguire lo statement:\n" . $sth->errstr;



# con fetchrow_hashref ogni record viene salvato in un hash in cui le chiavi
# vengono definite in base a quanto è specificato in SELECT.
#
# ATTENZIONE: in questo es. ho due campi chiamati mirID (miranda.mirID e
#             rnahybrid.mirID): se non li distinguo con un ALIAS ('paperino'
#             e 'topolino' ad es.) fetchrow_hashref mi ritornera' una sola
#             chiave chiamata 'mirID', ma non si sa a quale dei due campi si riferisca!
while (my $ref_row = $sth->fetchrow_hashref()) {
    print Dumper $ref_row;
}
warn "\n--- errore durante il fetching:\n" . $sth->errstr if $sth->err;
# I metodi di fetching ritornano come undef sia nel caso siano quando non ci sono piu'
# record da recuperare, sia in caso di errore durante il fetch; per cautelarmi da
# questa seconda evenienza uso un warn che mi avverte dell'errore





# Disconnessione
$dbh->disconnect();

# Chiusura del file di log
close $fh_dbilog;

exit;
