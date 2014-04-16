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
# questo esempio illustra come fare una richiesta ad una pagina
# con il metodo POST
use Carp;
use LWP::UserAgent; # la libreria da usare

# istanzio un oggetto UserAgent
my $bot = LWP::UserAgent->new();
$bot->agent('libwww-perl/5.805'); # nome del bot
$bot->timeout(600);

# This method will dispatch a POST request on the given $url, providing the
# key/value pairs for the fill-in form content. Additional headers and content
# options are the same as for the get() method. This method will use the POST()
# function from HTTP::Request::Common to build the request.
my $request = $bot->post(
    'http://www.bioinf.org.uk/cgi-bin/abnum/abnumpdb.pl', # $url
    
#   The POST method also supports the multipart/form-data content used for
#   Form-based File Upload as specified in RFC 1867. You trigger this content
#   format by specifying a content type of 'form-data' as one of the request
#   headers.
    Content_type => 'multipart/form-data',
    
    Content => [
#       di seguito specifico i parametri da fornire; per sapere quali sono e
#       quale contenuto richiedo si dovrebbe ravanare dentro il codice HTML
#       della pagina web che si vuole interrogare
        scheme => '-k',
        
#       If one of the values is an array reference, then it is treated as a
#       file part specification with the following interpretation:
#           
#           [ $file, $filename, Header => Value... ]
#           [ undef, $filename, Header => Value,..., Content => $content ]
#           
#       The first value in the array ($file) is the name of a file to open.
#       This file will be read and its content placed in the request.
#       The routine will croak if the file can't be opened. Use an undef as
#       $file value if you want to specify the content directly with a Content
#       header. The $filename is the filename to report in the request. If this
#       value is undefined, then the basename of the $file will be used. You can
#       specify an empty string as $filename if you want to suppress sending the
#       filename when you provide a $file value.
        pdb => [ "$ENV{HOME}/simulazioni/temp/GROMACS_numbering/1AFV.pdb" ]
    ] 
);

# $request è un oggetto di tipo HTTP::Response
$request->is_error() and do {
    croak(printf("E- %s [%s]\n\t", $request->status_line, $request->base));
};
$request->is_success() and do {
#   il metodo "content" ritorna la pagina web in risposta alla richiesta
    my $content = $request->content();
    my $count = ($content =~ tr/\n/\n/);
    my $bytes = length $content;
    printf("%s\n---\n%s\n(%d lines, %d bytes)\n", $content, $request->base, $count, $bytes);
};

print "\n---\nFINE PROGRAMMA\n";
exit;
