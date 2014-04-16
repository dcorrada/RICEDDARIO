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

use Cwd;
use Carp;
###################################################################
use LWP::Simple qw( $ua );



my $organism_name = 'nipah';
my $XML_query = qq(
<?xml version="1.0" encoding="UTF-8"?>

<orgPdbQuery>
 <version>B0905</version>
 <queryType>org.pdb.query.simple.OrganismQuery</queryType>
 <description>Organism Search : Organism Name=$organism_name </description>

 <organismName>$organism_name</organismName>
</orgPdbQuery>
);
print "\nquery:", $XML_query;

# you can configure a proxy...                                                                          
#$ua->proxy( http => 'http://yourproxy:8080' );

# Create a request                                                                                  

my $request = HTTP::Request->new( POST => 'http://www.rcsb.org/pdb/rest/search/');


$request->content_type( 'application/x-www-form-urlencoded' );

$request->content( $XML_query );

# Post the XML query                                                                                
print "\n querying PDB...";
print "\n";

print $XML_query;
my $response = $ua->request( $request );


# Check to see if there is an error
unless( $response->is_success ) {
    print "\n an error occurred: ", $response->status_line, "\n";

}

# Print response content in either case

print "\n response content:\n", $response->content;
