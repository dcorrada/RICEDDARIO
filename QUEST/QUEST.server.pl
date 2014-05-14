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

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;
###################################################################
use Carp;
use IO::Socket::INET;
use threads;
use threads::shared;
use Thread::Semaphore;

## GLOBS ##
# file di congigurazione
our $conf_file = '/etc/QUEST.conf';

# configurazioni di default, vengono sovrascritte dal file $conf_file
our %confs = (
    'host'       => '127.0.0.1',        # IP address del localhost
    'port'       => '6090',             # porta
    'threads'    => '8',                # numero massimo di threads concorrenti
    'maxsub'     => '1000',             # numero massimo di submission che il server puo' sopportare
);

our $socket; # l'oggetto per gestire la comunicazione client/server

# lo script intecetta segnali di interrupt e li redirige ad una subroutine (v. sotto)our @children;
$SIG{'INT'} = \&sigIntHandler; # il tipico Ctrl+C
$SIG{'TERM'} = \&sigIntHandler; # il segnale di kill dato con top (ie SIGTERM 15)
our $poweroff; # la variabile gestita dalla suboutine &sigIntHandler

our $superuser; # definisce se usare il server come superuser

our $semaforo;
our @thr; # lista dei threads
our %killerlist;
our @children;
our (@queued, @running, @sorted) :shared; # lista dei job accodati e running

our $submitted = 0E0;

## SBLOG ##

SPLASH: {
    my $splash = <<END
********************************************************************************
QUEST - QUEue your ScripT
release 14.5.c

Copyright (c) 2011-2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

END
    ;
    print $splash;
}

INIT: {
    # verifico se esiste un file di configurazione
    unless (-e $conf_file) {
        my $ans;
        print "\nQUEST server is not yet configured, do you want to proceed? [y/N] ";
        $ans = <STDIN>; chomp $ans;
        goto FINE unless ($ans eq 'y');
        print "\n";
        open(CONF, '>' . $conf_file) or croak("E- unable to open <$conf_file>\n\t");
        print CONF "# QUEST configuration file\n\n";
        foreach my $key (sort keys %confs) {
            my $default = $confs{$key};
            printf("    %-8s [%s]: ", $key, $default);
            my $ans = <STDIN>; chomp $ans;
            if ($ans) {
                print CONF "$key = $ans\n";
            } else {
                print CONF "$key = $default\n";
            }
        }
        close CONF;
    } else {
        print "Configuration settings are stored in <$conf_file>\n\n";
    }
    
    # inizializzo il server leggendo il file di configurazione
    open(CONF, '<' . $conf_file) or croak("E- unable to open <$conf_file>\n\t");
    while (my $newline = <CONF>) {
        if ($newline =~ /^#/) {
            next; # skippo le righe di commento
        } elsif ($newline =~ / = /) {
            chomp $newline;
            my ($key, $value) = $newline =~ m/([\w\d_\.]+) = ([\w\d_\.\/]+)/;
            $confs{$key} = $value if (exists $confs{$key});
        } else {
            next;
        }
    }
    close CONF;
    
    # verifico se sono root
    my $username = $ENV{'USER'};
    if ($username eq 'root') {
        $superuser = 1;
    } else {
        undef $superuser;
        my $warn = <<END
WARNING: server has not been launched as superuser; consequently, only the local
user [$username] can submit his/her scripts

END
        ;
        print $warn;
    }
    
    # inizializzo il semaforo
    $semaforo = Thread::Semaphore->new(int($confs{'threads'}));
    
    printf("%s server initialized\n", clock());
    
}

CORE: {
    # apro un socket per comunicare con il client
    my $error = <<END
E- Cannot open socket, maybe the server is already running elsewhere. Otherwise,
   check the parameters in the file <$conf_file>
END
    ;
    $socket = new IO::Socket::INET (
        'LocalHost'       => $confs{'host'},
        'LocalPort'       => $confs{'port'},
        'Proto'           => 'tcp',     # protocollo di connessione
        'Listen'          => 1,         # numero di sockets in ascolto
        'Reuse'           => 1          # riciclare i socket?
    ) or croak("$error\t");
    printf("%s server is listening\n", clock());
    
    while (1) {
        # lascio girare il server fino a che non riceve un SIGTERM
        goto FINE if ($poweroff);
        
        # metto il server in ascolto
        my $client = $socket->accept();
        if ($client) {
            # raccolgo la request dal client
            my $recieved_data;
            $client->recv($recieved_data,1024);
            
            # richiesta della lista dei job
            if ($recieved_data eq 'status') {
                my $log = job_monitor();
                $client->send($log);
                
            # richiesta di uccidere job
            } elsif ($recieved_data =~ /killer/ ) {
                my ($jobid, $user_client) = $recieved_data =~ /killer\|([\w\d]+);user\|([\w\d]+)/;
                my $mess;
                
                if (exists $killerlist{$jobid}) {
                    my $job = $killerlist{$jobid};
                    if ($job->is_running) {
                        
                        # verifico le credenziali
                        unless ($superuser && ($user_client eq 'root')) {
                            my $match;
                            {
                                lock @queued; lock @running;
                                my @joblist;
                                push(@joblist, @queued, @running);
                                ($match) = grep(/$jobid/, @joblist);
                            }
                            my ($job_owner) = $match =~ /\]\s+([\w\d]+)/;
                            unless ($user_client eq $job_owner) {
                                $mess = <<END
E- the owner of job [$jobid] is $job_owner, you are not allowed to kill it
END
                                ;
                                goto ENDKILL;
                            } 
                        }
                        
                        printf("%s killing job [%s] requested by [%s]\n", clock(), $jobid, $user_client);
                        
                        # verifico se il job sta girando
                        my $is_running = 'null';
                        {
                            lock @running;
                            my ($greppo) = grep(/$jobid/, @running);
                            if ($greppo) {
                                $is_running = $greppo;
                                
                                # verifico se si tratta di un job Schrodinger
                                if ($greppo =~ /\[Schrodinger: /) {
                                    my ($schrodinger_jobid) = $greppo =~ /\[Schrodinger: (.+)\]/;
                                    $mess = <<END

killing the Schrodinger's cat is unsafe, try to use the following commad:

    \$ \$SCHRODINGER/jobcontrol -kill $schrodinger_jobid
END
                                    ;
                                    goto ENDKILL;
                                }
                            }
                        }
                        
                        # ammazzo eventuali processi figli se il job sta girando
                        unless ($is_running eq 'null') {
                            my $parent_pid;
                            {
                                lock @running;
                                my ($greppo) = grep(/$jobid/, @running);
                                ($parent_pid) = $greppo =~ /\[PID: (\d+)\]/;
                                unless ($parent_pid) {
                                    $mess = "E- unable to find PID for job [$jobid]";
                                    goto ENDKILL;
                                }
                            }
                            undef @children;
                            push (@children, $parent_pid);
                            &getcpid($parent_pid);
                            @children = sort {$b <=> $a} @children;
                            while (my $child = shift(@children)) {
                                print "\tkilling child pid $child...\n";
                                kill 15, $child;
                                sleep 1; # aspetto un poco...
                            }
                        }
                        $job->kill('TERM');
                        
                        # verifico se il job è stato ucciso
                        sleep 2;
                        if ($job->is_running) {
                            sleep 2;
                        }
                        
                        if ($job->is_running) {
                            $mess = "E- unable to kill job [$jobid]";
                        } else {
                            $mess = "job [$jobid] killed";
                        }
                        
                    } else {
                        $mess = "job [$jobid] has already accomplished";
                    }
                } else {
                    $mess = "E- job [$jobid] not found";
                }
                
                ENDKILL: { $client->send($mess); };
                
            # richiesta di sottomettere job
            } elsif ($recieved_data =~ /user/ ) {
                
                $submitted++;
                if ($submitted > $confs{'maxsub'}) {
                    my $mess = <<END
WARNING: the server has collected $confs{'maxsub'} jobs. You should restart the 
server before submitting another job.
END
                    ;
                    $client->send($mess);
                    $client->send('QUEST.over&out');
                    next;
                } else {
                    my $mess = sprintf(">>> %05d submissions to restart <<<\n\n", $confs{'maxsub'} - $submitted);
                    $client->send($mess);
                }
                
                my @params = split(';', $recieved_data);
                my %client_order;
                while (my $order = shift @params) {
                    my ($key, $value) = $order =~ /(.+)\|(.+)/;
                    $client_order{$key} = $value;
                }
                
                # verifico se il server ha le credenziali per lanciare il job
                my $username = $ENV{'USER'};
                unless ($superuser) {
                    unless ($client_order{'user'} eq $username) {
                        my $mess = <<END
JOB LAUNCH ABORTED: the server has been launched as as [$username] and only this
user can submit job (not as [$client_order{'user'}]).
END
                        ;
                        $client->send($mess);
                    }
                }
                
                # genero un jobid
                my @chars = ('A'..'Z', 0..9, , 0..9);
                my $jobid = join('', map $chars[rand @chars], 0..7);
                
                # genero un file di log in cui raccogliero' l'output del job
                my $logfile = sprintf("%s/QUEST.job.%s.log", $client_order{'workdir'}, $jobid);
                
                # sottometto il job
                my $job = threads->new(\&launch_thread,
                    $client_order{'script'},
                    $logfile,
                    $client_order{'threads'},
                    $client_order{'user'},
                    $jobid,
                    $client_order{'workdir'},
                    $client_order{'schrodinger'}
                );
                # $job->detach();
                
                # metto il job nella killerlist
                $killerlist{$jobid} = $job;
                
                printf("%s job [%s] submitted by [%s]\n", clock(), $jobid, $client_order{'user'});
                my $mess = sprintf("%s job [%s] queued,\nSTDOUT/STDERR will be written to <%s>",
                    clock(), $jobid, $logfile);
                $client->send($mess);
                
            } else {
                next;
            }
            
            # messaggio di "passo e chiudo" dal server al client
            $client->send('QUEST.over&out');
        }
    }
}

FINE: {
    close $socket if ($socket);
    printf("\n%s QUEST server stopped\n\n", clock());
    exit;
}

sub launch_thread {
    my ($cmd_line, $logfile, $threads, $user, $jobid, $workdir, $schrodinger) = @_;
    
    # Thread 'cancellation' signal handler
    $SIG{'TERM'} = sub {
        {
            lock @queued; lock @running; lock @sorted;
            @queued = grep(!/$jobid/, @queued);
            @running = grep(!/$jobid/, @running);
            @sorted = grep(!/$jobid/, @sorted);
        }
        printf("%s job [%s] killed\n", clock(), $jobid);
        threads->exit();
    };
    
    my $jobline;
    my $queue_time;
    my $running_time;
    
    $queue_time = time;
    
    { # metto il job nella lista dei queued
        lock @queued; lock @sorted;
        $jobline = sprintf(
            "%s  % 8s  %s  %s  <%s>",
            clock(), $user, $threads, $jobid, $cmd_line
        );
        push (@queued, $jobline);
        
        # metto il job nella scaletta dei job che dovranno partire
        my $position = sprintf("%04d%012d-%s", $threads, time, $jobid);
        push(@sorted,$position);
        @sorted = sort {$a cmp $b} @sorted;
    }
    
    # attendo che si liberino threads e che, contestualmente, il job in coda sia in cima alla scaletta
    my $waitasecond = 1;
    while ($waitasecond) { 
        if (${$semaforo} >= $threads) {
            {
                lock @sorted;
                my $ontop = $sorted[0];
                if ($ontop =~ /$jobid/) {
                    shift @sorted;
                    undef $waitasecond;
                }
            }
        }
        sleep 1;
    }
    
    $queue_time = time - $queue_time;
    $running_time = time;
    
    for (1..$threads) { $semaforo->down() }; # occupo tanti threads quanti richiesti
#     print "$threads taken (${$semaforo} available)\n";
    
    { # metto il job nella lista dei running e lo tolgo dai queued
        lock @queued; lock @running;
        @queued = grep(!/$jobid/, @queued);
        $jobline = sprintf(
            "%s  % 8s  %s  %s  <%s>", 
            clock(), $user, $threads, $jobid, $cmd_line
        );
        push (@running, $jobline);
    }
    
    printf("%s job [%s] started\n", clock(), $jobid);
    
    # lancio del job, redirigo STDOUT e STDERR sul file di log
    my $joblog;
    if ($superuser) {
        qx/cd $workdir; sudo -u $user touch $logfile; sudo su $user -c "$cmd_line >> $logfile 2>&1"/;
    } else {
        qx/cd $workdir; touch $logfile; $cmd_line >> $logfile 2>&1/;
    }
    
    if ($schrodinger eq 'true') { # blocco ad-hoc per i job della Schrodinger
        
        my $signature;
        
        # leggo il logfile per catturare il JobID assegnato da Schrodinger
        my $waitforjobid = 1;
        while ($waitforjobid) {
            my $string = qx/grep "JobId:" $logfile/;
            chomp $string;
            if ($string) {
                ($signature) = $string =~ /JobId: (.+)/;
                undef $waitforjobid;
                # una volta che ottengo il JobID aspetto ancora un po' (se facessi partire subito un top cercando un processo contenente il JobID come stringa non troverei nulla)
                sleep 5;
            } else {
                sleep 1; # continuo a ciclare fino a quando non ottengo un JobID
            }
        }
        
        {
            lock @running;
            @running = grep(!/$jobid/, @running);
            $jobline = sprintf(
                "%s  % 8s  %s  %s [Schrodinger: %s]  <%s>", 
                clock(), $user, $threads, $jobid, $signature, $cmd_line
            );
            push (@running, $jobline);
        }
        
        # i job della Schrodinger fanno da se' un detach una volta partiti e lo script finirebbe, genero un loop che guarda se il monitor di Schrodinger controlla il JobID specifico
        my $is_running = 1;
        while ($is_running) {
            my $pslog = qx/ps aux | grep "$signature"/;
            my @procs = split("\n", $pslog);
            @procs = grep(!/ps aux/, @procs);
            @procs = grep(!/grep/, @procs);
#             print Dumper \@procs;
            if (@procs) {
                sleep 5;
            } else {
                undef $is_running;
            }
        }
    }
    
    $running_time = time - $running_time;
    open (LOGFILE, '>>' . $logfile);
    my @timex = localtime($queue_time);
    $queue_time = sprintf("%02d:%02d:%02d", $timex[2]-1, $timex[1], $timex[0]);
    @timex = localtime($running_time);
    $running_time = sprintf("%02d:%02d:%02d", $timex[2]-1, $timex[1], $timex[0]);
    my $summary = <<END
*** QUEST SUMMARY ***
EXECUTABLE.....: $cmd_line
WORKING DIR....: $workdir
THREADS USED...: $threads
QUEUED TIME....: $queue_time
RUNNING TIME...: $running_time

END
    ;
    print LOGFILE $summary;
    close LOGFILE;
    
    for (1..$threads) { $semaforo->up() }; # libero tanti threads quanti richiesti
#     print "$threads released (${$semaforo} available)\n";
    
    { # rimuovo il job dalla lista dei running
        lock @running;
        @running = grep(!/$jobid/, @running);
    }
    
    printf("%s job [%s] finished\n", clock(), $jobid);
}

sub job_monitor {
    my $log;
    {   lock @queued; lock @running;
        
        # modifico la lista dei running fornendo il PID invece del path dello script lanciato
        for (my $i = 0; $i < scalar @running; $i++) {
            my $newline = $running[$i];
            if ($newline =~ /\[Schrodinger:/) {
                next; # sono job della Schrodinger, non troverei il PID
            } elsif ($newline =~ /\[PID:/) {
                next; # sono job gia' flaggati, passo oltre
            } else {
                my ($jobid, $script) = $newline =~ /(\w{8})  <(.+)>/;
                my $string = "QUEST.job.$jobid.log";
                my $psaux = qx/ps aux \| grep -P " $script >> .*$string"/;
                my @procs = split("\n", $psaux);
                my ($match) = grep(!/grep/, @procs);
                if ($match) {
                    my ($pid) = $match =~ /\w+\s*(\d+)/;
                    $newline =~ s/<.+>/[PID: $pid]  <$script>/;
                    $running[$i] = $newline;
                }
            }
        }
        
        $log = sprintf("\nAvalaible threads %d of %d\n", ${$semaforo}, $confs{'threads'});
        $log .= "\n--- JOB RUNNING ---\n";
        foreach my $jobid (@running) {
            $log .= "$jobid\n";
        }
        $log .= "\n--- JOB QUEUED ---\n";
        foreach my $jobid (@queued) {
            $log .= "$jobid\n";
        }
    }
    return $log
}


# questa subroutine serve per intercettare un segnale di interrupt e comunicarlo
# allo script inizializzando il valore della variabile globale $poweroff
sub sigIntHandler {
    print "\n";
    {
        lock @running;
        foreach my $jobid (keys %killerlist) {
            my $job = $killerlist{$jobid};
            if ($job->is_running) {
                my ($match) = grep(/$jobid/, @running);
                $match && do {
                    my ($pid) = $match =~ /(\[PID: \d+\])/;
                    my $warn = <<END

W- job [$jobid] was running while KILL signal arrived, check for accidental 
orphans generated from $pid
END
                    ;
                    print $warn;
                }
            }
        }
    }
    $poweroff = 1;
}

sub clock {
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    $mese = $mese+1;
    $mese = sprintf("%02d", $mese);
    $giom = sprintf("%02d", $giom);
    $ore = sprintf("%02d", $ore);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    my $date = '[' . ($anno+1900)."/$mese/$giom $ore:$min:$sec]";
    return $date;
}

sub getcpid {
    my ($pid) = @_;
    my $log = qx/pgrep -P $pid/;
    my @cpids = split("\n", $log);
    foreach my $child (@cpids) {
        push(@children, $child);
        &getcpid($child);
    }
}
