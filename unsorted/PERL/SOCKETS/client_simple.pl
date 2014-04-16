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
use IO::Socket::INET;

my $sock = new IO::Socket::INET (   PeerAddr => '127.0.0.1',
                                    PeerPort => '7070',
                                    Proto => 'tcp',);
die "Could not create socket: $!\n" unless $sock;


print $sock "Tutto a posto?\n";

close($sock);


