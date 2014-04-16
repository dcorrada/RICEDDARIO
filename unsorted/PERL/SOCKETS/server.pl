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
use IO::Socket::INET;

my $socket = new IO::Socket::INET (
                                  LocalHost => '127.0.0.1',
                                  LocalPort => '5000',
                                  Proto => 'tcp',
                                  Listen => 1,
                                  Reuse => 1
                               )
or die "E- Coudn't open socket";

my $client = $socket->accept();

$client->send("READY");

my @survivors;

my $client_msg;
while (1) {
    $client->recv($client_msg,1024);
    last if($client_msg eq 'dario');
    $client->send("BUSY");
    print "Ho ricevuto [$client_msg]\n";
    sleep 2;
    $client->send("READY");
    push(@survivors, $client_msg);
}

close $socket;

print "\n*** I SOPRAVVISSUTI ***\n";
print "@survivors";


print "\n_____________\nFINE PROGRAMMA\n";
exit;
# while(1)
# {
#     $client_socket = "";
#     $client_socket = $socket->accept();
#     
#     $peer_address = $client_socket->peerhost();
#     $peer_port = $client_socket->peerport();
#     
#     print "\n I got a connection from ( $peer_address , $peer_port ) ";
#     
#     
#      while (1)
#      {
#          
#          print "\n SEND( TYPE q or Q to Quit):";
#          
#          $send_data = <STDIN>;
#          chop($send_data); 
#          
#          
#          
#          if ($send_data eq 'q' or $send_data eq 'Q')
#             {
#                 
#             $client_socket->send ($send_data);
#             close $client_socket;
#             last;
#             }
#             
#          else
#             {
#             $client_socket->send($send_data);
#             }
#             
#             $client_socket->recv($recieved_data,1024);
#             
#             if ( $recieved_data eq 'q' or $recieved_data eq 'Q')
#             {
#                 close $client_socket;
#                 last;
#             }
#             
#             else
#             {
#                 print "\n RECIEVED: $recieved_data";
#             }
#             
#     }
# }



