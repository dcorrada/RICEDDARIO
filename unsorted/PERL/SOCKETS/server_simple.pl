#!/usr/bin/perl
# -d

# use strict;
use warnings;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| = 1;

# paths di librerie personali
use lib $ENV{HOME};
###################################################################
use IO::Socket::INET;

# creo un socket
my $sock = new IO::Socket::INET (   LocalHost => '127.0.0.1',
                                    LocalPort => '7070',
                                    Proto => 'tcp',
                                    Listen => 1, # definisco quante connessioni accettare su questo socket
                                    Reuse => 1, ); # rendo disponibile la porta una volta chiuso il server
die "Could not create socket: $!\n" unless $sock;
# accetto le connessioni in ingresso
my $client = $sock->accept();

# stampo tutto quello che arriva dal client
while (my $line = <$client>) {
        print $line;
}

close($sock);
