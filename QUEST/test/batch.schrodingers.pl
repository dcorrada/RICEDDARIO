#!/usr/bin/perl
# -d

use strict;
use warnings;


opendir DH, '/home/dario/tmp/test';
my @scripts = grep { /mmgbsa.\d+.sh/ } readdir(DH);
closedir DH;

foreach my $script (@scripts) {
    sleep 1;
    my $log = qx/clear; \/usr\/local\/PANDORA\/QUEST\/QUEST.client.pl -s $script/;
    print "$log\n";
}

exit;