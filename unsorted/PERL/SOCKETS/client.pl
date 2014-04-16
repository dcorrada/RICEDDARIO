#!/usr/bin/perl
# -d

use strict;
use warnings;

# to make STDOUT/opt/perl51 flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| = 1;

# paths di librerie personali
use lib $ENV{HOME};
###################################################################
# questo script dovrebbe spedire al server un array di elementi
# ogni elemento singolo dovrebbe essere mandato al server.
# L'elemento successivo non viene spedito al fintanto che non riceve
# via libera dal server

use IO::Socket::INET;

# la mia lista di msg
my @settenani = ('dotto', 'pisolo', 'mammolo', 'eolo', 'cucciolo', 'brontolo', 'gongolo', 'truciolo', 'gianni', 'pinotto', 'pluto', 'paperino', 'qui', 'quo', 'qua', 'dario');


my $socket = new IO::Socket::INET (
                                  PeerAddr  => '127.0.0.1',
                                  PeerPort  =>  '5000',
                                  Proto => 'tcp',
                               )
or die "E- Couldn't connect to Server\n";

while (my $nano = shift(@settenani)) {
    my $server_response;
    $socket->recv($server_response,1024);
    print "SERVER $server_response\n";
    if ($server_response eq 'READY') {
        $socket->send($nano);
        print ":-) nano $nano spedito\n";
        next;
    } elsif ($server_response eq 'BUSY') {
        unshift(@settenani, $nano);
        print "T_T il nano $nano deve attendere...\n";
        next;
    }
}

close $socket;

print "\n_____________\nFINE PROGRAMMA\n";
exit;
# while (1)
# {
#     
#     $socket->recv($recv_data,1024);
#     
#     if ($recv_data eq 'q' or $recv_data eq 'Q')
#     {
#         close $socket;
#         last;
#     }
#     else
#     {
#         print "RECIEVED: $recv_data"; 
#         print "\nSEND( TYPE q or Q to Quit):";
#         
#         $send_data = <STDIN>;
#         chop($send_data);
#               
#         
#         if ($send_data ne 'q' and $send_data ne 'Q')
#         {
#             $socket->send($send_data);
#         }    
#         else
#         {
#             $socket->send($send_data);
#             close $socket;
#             last;
#         }
#         
#     }
# }
