#!/usr/bin/perl
# -d

use strict;
use warnings;

my $bin = qx/which QUEST.client.pl/; chomp $bin;

foreach (1..2000) {
    sleep 1;
    my $log = qx/clear; \/usr\/local\/PANDORA\/QUEST\/QUEST.client.pl sleeper.sh/;
    print "$log\n";
}

exit;
