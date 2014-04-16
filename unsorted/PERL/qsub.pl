#!/usr/bin/perl
#~ -d

use strict;
use warnings;

###################################################################
# Simulo il funzionamento di un qsub
# (file da copiare nella cartella /usr/bin


my $normal_output = <<END
22083.michelangelo.cilea.it
END
;

my $error_output = <<END
No Permission.qsub: cannot connect to server michelangelo (errno=15007)
END
;

my $unknown_output = <<END
blablabla...
END
;


srand (time ^ $$ ^ unpack "%L*", `ps axww | gzip`);
my $chance = int(rand(100)) + 1;

if ($chance < 2) {
    print "[".$ARGV[0]."]".$unknown_output;
} elsif ($chance < 90) {
    print $normal_output;
} else {
    print "[".$ARGV[0]."]".$error_output;
}


exit;
