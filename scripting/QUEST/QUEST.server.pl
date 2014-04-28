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
    'protocol'   => 'tcp',              # protocollo di connessione
    'sockets'    => '1',                # numero di sockets in ascolto
    'reuse'      => '1',                # riutilizzare il socket dopo averlo chiuso?
    'threads'    => '8',                # numero massimo di threads concorrenti
);

our $socket; # l'oggetto per gestire la comunicazione client/server

# lo script intecetta segnali di interrupt e li redirige ad una subroutine (v. sotto)
$SIG{'INT'} = \&sigIntHandler; # il tipico Ctrl+C
$SIG{'TERM'} = \&sigIntHandler; # il segnale di kill dato con top (ie SIGTERM 15)
our $poweroff; # la variabile gestita dalla suboutine &sigIntHandler

our $superuser; # definisce se usare il server come superuser

our $semaforo;
our @thr; # lista dei threads
our (@queued, @running) :shared; # lista dei job accodati e running

## SBLOG ##

SPLASH: {
    my $splash = <<END
********************************************************************************
QUEST - QUEue your ScripT
release 14.4

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
        'Proto'           => $confs{'protocol'},
        'Listen'          => $confs{'sockets'},
        'Reuse'           => $confs{'reuse'}
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

            if ($recieved_data eq 'status') { # richiesta della lista dei job
                my $log = job_monitor();
                $client->send($log);

            } elsif ($recieved_data =~ /user/ ) { # richiesta di sottomissione job
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
                        next;
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
                    $client_order{'workdir'}
                );
                $job->detach();

                my $mess = sprintf("%s job %s queued, STDOUT/STDERR will be written to <%s>",
                    clock(), $jobid, $logfile);
                $client->send($mess);

            } else {
                next;
            }
        }
    }
}

FINE: {
    close $socket if ($socket);
    printf("%s QUEST server stopped\n", clock());
    exit;
}

sub launch_thread {
    my ($cmd_line, $logfile, $threads, $user, $jobid, $workdir) = @_;

    my $jobline;
    my $queue_time;
    my $running_time;

    $queue_time = time;

    { # metto il job nella lista dei queued
        lock @queued;
        $jobline = sprintf(
            "%s  % 8s  %s  %s  <%s>",
            clock(), $user, $threads, $jobid, $cmd_line
        );
        push (@queued, $jobline);
    }

    while (${$semaforo} < $threads) { sleep 1 }; # attendo che si liberino threads

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

    # lancio del job, redirigo STDOUT e STDERR sul file di log
    my $joblog;
    if ($superuser) {
        qx/cd $workdir; sudo -u $user touch $logfile; sudo -u $user $cmd_line >> $logfile 2>&1/;
    } else {
        qx/cd $workdir; touch $logfile; $cmd_line >> $logfile 2>&1/;
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
}

sub job_monitor {
    my $log;
    {   lock @queued; lock @running;
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
    print"\n";
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