#!/usr/bin/perl
# -d

use strict;
use warnings;


foreach (1..1000) {
    sleep 1;
    my $log = qx/clear; \/usr\/local\/RICEDDARIO\/QUEST\/QUEST.client.pl child.sh/;
    print "$log\n";
}

exit;
