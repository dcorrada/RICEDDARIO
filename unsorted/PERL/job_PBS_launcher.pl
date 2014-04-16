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

use Carp;

USAGE: {
    no warnings;
    my $usage = <<END

Lancia con qsub una lista di job PBS individuato con pattern

  $0 pattern
    
  ATTENZIONE: il carattere di protezione \\ (backslash) usato nelle
  stringhe in questo caso diventa \\\\ (doppio backslash).
  
  es.: "\\\\d+" individua stringhe con almeno un carattere numerico
       (invece di usare "\\d+")
END
    ;

    unless ($ARGV[0]) {
        print $usage; exit;
    }
}


use Cwd;
my $dh;
my $workdir = getcwd;



opendir ($dh, $workdir) or croak "path <$workdir> inesistente\n";
my @all_file_list = readdir($dh);
closedir $dh;

my ($queue_list, $done_list) = ([ ], [ ]);
@$queue_list = grep /$ARGV[0]/, @all_file_list;

# esco se una delle liste di file è vuota
croak "\n---\nfile non trovati, impossibile lanciare i jobs\n" unless (@$queue_list);

use my_PERL::PBS_manager::Scheduler;
my $obj = 'my_PERL::PBS_manager::Scheduler';
my $launch_obj = $obj->new();
my $total_job = scalar @$queue_list;
my $job_number = 0;

while (@$queue_list)  {
    if (($launch_obj->qstat_status) eq '1') {
        my $single_job = shift @$queue_list;
        push @$done_list, $single_job;
        $launch_obj->submit_job($single_job);
        $job_number++;
        system "clear"; print "[$job_number/$total_job] job sottomessi...";
        sleep 20; # attendo tot secondi prima che qstat si accorga che ho sottomesso un job
        status_monitor(queue => $queue_list, done => $done_list);
    } else {
        sleep 60; # attendo tot secondi prima di ri-sottomettere il job se la coda è piena
        next;
    }
    
}

exit;


# scrive un file di log in cui butta dentro man mano la lista di job
# eseguiti e di job in coda
#
# %opzioni = ( queue => \@arg1, OBBLIGATORIO lista dei job in coda
#              done  => \@arg2, OBBLIGATORIO lista dei job lanciati
#            );
sub status_monitor {
    my (%arg) = @_;
    use my_PERL::misc::Clock;
    my $clock = 'my_PERL::misc::Clock';
    
    my $newline = pack("A32A32", "JOB_LANCIATI", "JOB_DA_LANCIARE")."\n".
                  pack("A32A32", "------------", "---------------")."\n";
    my $log_content = ["\n".$clock->date."\n", $newline ];
    
    # definisco il numero massimo di linee da scrivere in ogni tabella di log
    my $max_num_line;
    if ((scalar @{$arg{queue}}) >= (scalar @{$arg{done}})) {
        $max_num_line = scalar @{$arg{queue}};
    } else {
        $max_num_line = scalar @{$arg{done}};
    }
    
    for (my $counter = 0; $counter < $max_num_line; $counter++) {
        no warnings;
        $newline = pack("A32A32", ${$arg{done}}[$counter], ${$arg{queue}}[$counter])."\n";
        push @$log_content, $newline;
    }
    
    use my_PERL::misc::FileIO;
    my $fileio = 'my_PERL::misc::FileIO';
    my $logfile = $fileio->new();
    
    $logfile->write(filename => 'job_PBS_launcher.log', filedata => $log_content, mode => '>>');


}
