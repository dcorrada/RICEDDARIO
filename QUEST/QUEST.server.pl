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
use RICEDDARIO::lib::SQLite;
use RICEDDARIO::lib::FileIO;
use Carp;
use IO::Socket::INET;
use threads;
use threads::shared;
use Thread::Semaphore;

## GLOBS ##

# COMUNICAZIONE CLIENT/SERVER
our $conf_file = '/etc/QUEST.conf'; # file di configurazione
our %confs = ( # valori di default
    'host'      => '127.0.0.1',        # IP address del localhost
    'port'      => '6090',             # porta
    'threads'   => '8',                # numero massimo di threads concorrenti
);
our $socket; # oggetto IO::Socket::INET

# DATABASE
our $database = '/etc/QUEST.db'; # file del database
our $db_obj; # oggetto RICEDDARIO::lib::SQLite
our $dbh; # database handler
our $sth; # statement handler

# SHUTDOWN
# lo script sigIntHandler intecetta segnali di interrupt
$SIG{'INT'} = \&sigIntHandler; # segnale dato da Ctrl+C
$SIG{'TERM'} = \&sigIntHandler; # segnale di kill (SIGTERM 15)
our $poweroff; # la variabile gestita dalla suboutine &sigIntHandler

# THREADING
our $semaforo; # semaforo basato per il blocco dei threads 
our $dbaccess :shared; # accesso esclusivo al database

# OTHERS
our $superuser; # il server è stato lanciato come superuser?
our $fileobj = RICEDDARIO::lib::FileIO->new(); # oggetto RICEDDARIO::lib::FileIO
our @children; # elenco dei PID di processi figli di un job

## SBLOG ##

SPLASH: {
    my $splash = <<END
********************************************************************************
QUEST - QUEue your ScripT
release 14.6.a

Copyright (c) 2011-2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

END
    ;
    print $splash;
}

INIT: {
    
    # verifico se sono root
    my $username = $ENV{'USER'};
    if ($username eq 'root') {
        printf("%s access as superuser\n", clock());
        $superuser = 1;
    } else {
        printf("%s access as <$username>\n", clock());
        undef $superuser;
        $conf_file = "$ENV{'HOME'}/.QUEST.conf";
        $database = "$ENV{'HOME'}/.QUEST.db";
    }
    
    # verifico se esiste un file di configurazione
    unless (-e $conf_file) {
        my $ans;
        print "\nQUEST server is not yet configured, do you want to proceed? [Y/n] ";
        $ans = <STDIN>; chomp $ans;
        $ans = 'y' unless ($ans);
        goto FINE if ($ans !~ /[yY]/);
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
        print "\n";
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
    
    # inizializzo il database
    $db_obj = RICEDDARIO::lib::SQLite->new('database' => $database, 'log' => 0);
    $dbh = $db_obj->access2db();
    $sth = $db_obj->query_exec( 'dbh' => $dbh, 
        'query' => 'SELECT name FROM sqlite_master WHERE type = "table"'
    );
    my $table_list = $sth->fetchall_arrayref();
    $sth->finish();
    init_database() if (scalar @{$table_list} == 0);
    
    # inizializzo il semaforo
    $semaforo = Thread::Semaphore->new(int($confs{'threads'}));
    
    printf("%s server initialized\n\n", clock());
    print "    CONFIGS...: $conf_file\n";
    print "    DATABASE..: $database\n\n";
}

goto FINE;

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
                        sleep 4.6;
                        
                        if ($job->is_running) {
                            $mess = "W- job [$jobid] is still alive, try to check it later";
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
                    $client_order{'schrodinger'},
                    $client_order{'queue'}
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
    $dbh->disconnect;
    printf("%s server stopped\n\n", clock());
    exit;
}

sub superslot {
    my $jobid;
    my $ref_row;
    my $threads; 
    
    while (1) {
        {
            # con questo blocco la sub sta in standby fintanto che non trova un job disponibile a partire
            
            lock $dbaccess;
            
            # estraggo il primo job dalla lista degli accodati
            $sth = $db_obj->query_exec( 'dbh' => $dbh, 
                'query' => 'SELECT * FROM queuelist'
            );
            my %queued;
            while ($ref_row = $sth->fetchrow_hashref()) {
                my $key = $ref_row->{'score'};
                my $value = $ref_row->{'jobid'};
                $queued{$key} = $value;
            }
            $sth->finish();
            my @sorted = sort {$a cmp $b} keys %queued;
            $jobid = $queued{$sorted[0]};
            
            # verifico il numero di threads che richiede il job
            $sth = $db_obj->query_exec( 'dbh' => $dbh, 
                'query' => 'SELECT jobid, threads FROM subdetails WHERE jobid = ?',
                'bindings' => [ $jobid ]
            );
            $ref_row = $sth->fetchrow_hashref();
            $sth->finish();
            $threads = $ref_row->{'threads'};
            if ($threads > ${$semaforo}) {
                sleep 1;
                next;
            } else {
                # rimuovo il job dalla queuelist se può partire
                $sth = $db_obj->query_exec( 'dbh' => $dbh, 
                    'query' => 'DELETE FROM queuelist WHERE jobid =?',
                    'bindings' => [ $jobid ]
                );
                $sth->finish();
            }
        }
        
        my $start_time = time;
        for (1..$threads) { $semaforo->down() }; # occupo tanti threads quanti richiesti
        {
            # aggiorno il database
            
            lock $dbaccess;
            
            $sth = $db_obj->query_exec( 'dbh' => $dbh, 
                'query' => 'UPDATE jobstatus SET status = "running" WHERE jobid =?',
                'bindings' => [ $jobid ]
            );
            $sth->finish();
            
            # i campi 'pid' e 'schroid' li aggiornerò con il monitor
            $sth = $db_obj->query_exec( 'dbh' => $dbh, 
                'query' => 'INSERT INTO runlist (jobid, rundate) VALUES (?, ?)',
                'bindings' => [ $jobid,  $start_time ]
            );
            $sth->finish();
        }
        
        
        # *** DAFFARE ***
    }
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

sub init_database {
    # status dei job ('queued', 'running' o 'finished')
    $db_obj->new_table(
        'dbh' => $dbh,
        'table' => 'jobstatus',
        'args' => "`jobid` TEXT PRIMARY KEY NOT NULL, `status` TEXT NOT NULL"
    );
    # scriptfile associati ai job
    $db_obj->new_table(
        'dbh' => $dbh,
        'table' => 'jobfiles',
        'args' => "`jobid` TEXT PRIMARY KEY NOT NULL, `filename` TEXT NOT NULL, `content` TEXT NOT NULL"
    );
    # parametri di sottomissione
    $db_obj->new_table(
        'dbh' => $dbh,
        'table' => 'subdetails',
        'args' => "`jobid` TEXT PRIMARY KEY NOT NULL, `threads` INT NOT NULL, `queue` TEXT NOT NULL, `user` TEXT NOT NULL, `subdate` TEXT NOT NULL, `schrodinger` INT NOT NULL DEFAULT `0`" # la data va convertita con la funzione localtime
    );
    # parametri di running
    $db_obj->new_table(
        'dbh' => $dbh,
        'table' => 'runlist',
        'args' => "`jobid` TEXT PRIMARY KEY NOT NULL, `pid` INT, `schroid` TEXT, `rundate` TEXT NOT NULL" # la data va convertita con la funzione localtime
    );
    # lista dei job accodati, score è un valore su cui si valuta la priorità dei job
    $db_obj->new_table(
        'dbh' => $dbh,
        'table' => 'queuelist',
        'args' => "`jobid` TEXT PRIMARY KEY NOT NULL, `score` TEXT NOT NULL" # la data va convertita con la funzione localtime
    );
}
