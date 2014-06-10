#!/usr/bin/perl
# -d

use strict;
use warnings;


for my $i (1..1000) {
    
    my $prog = sprintf("%05d", $i);
    qx/cp amae.maegz mmgbsa.$prog.maegz/;
    
    my $scontent = <<END
#!/bin/sh

# export the environment vars
export SCHRODINGER=/usr/local/schrodinger_2014
export LM_LICENSE_FILE=62158\@192.168.1.4

# launch the job
\$SCHRODINGER/prime_mmgbsa mmgbsa.$prog.maegz


END
    ;
    
    open(FH, ">mmgbsa.$prog.sh");
    print FH $scontent;
    close FH;
    qx/chmod a+x mmgbsa.$prog.sh/;
}

exit;
