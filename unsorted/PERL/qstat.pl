#!/usr/bin/perl
#~ -d

use strict;
use warnings;

###################################################################
# Simulo il funzionamento di un qstat
# (file da copiare nella cartella /usr/bin


my $normal_output = <<END
Job id              Name             User            Time Use S Queue
------------------- ---------------- --------------- -------- - -----
17277.michelangelo  pbsjob1.pbs       pcozzi          00:01:24 R projects
17278.michelangelo  pbsjob2.pbs       pcozzi          00:01:24 R projects
17279.michelangelo  pbsjob3.pbs       pcozzi          00:01:23 R projects
17280.michelangelo  pbsjob4.pbs       pcozzi          00:01:23 R projects
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
    print $unknown_output;
} elsif ($chance < 90) {
    print $normal_output;
} else {
    print $error_output;
}


exit;
