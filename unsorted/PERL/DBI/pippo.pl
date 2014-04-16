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

print "DBI->available_drivers()";

exit;
