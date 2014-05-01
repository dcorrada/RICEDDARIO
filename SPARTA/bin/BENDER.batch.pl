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
# script per lanciare in batch EMMA su più cartelle
use Cwd;
use Carp;
use SPARTA::lib::FileIO;
use threads;
use threads::shared;
use Thread::Semaphore;

# =================================== GLOBS ====================================
our $bender = qx/which BENDER.pl 2> \/dev\/null/; # dov'è BENDER?
our $dataset = { # elenco dei percorsi di ogni simulazione
# *** APO 50ns ***
'/home/dario/simulazioni/APO_MD/1AFV/bender' => '1AFV', '/home/dario/simulazioni/APO_MD/1AHW/bender' => '1AHW', '/home/dario/simulazioni/APO_MD/1BGX/bender' => '1BGX', '/home/dario/simulazioni/APO_MD/1FDL/bender' => '1FDL', '/home/dario/simulazioni/APO_MD/1FE8/bender' => '1FE8', '/home/dario/simulazioni/APO_MD/1FSK/bender' => '1FSK', '/home/dario/simulazioni/APO_MD/1H0D/bender' => '1H0D', '/home/dario/simulazioni/APO_MD/1IQD/bender' => '1IQD', '/home/dario/simulazioni/APO_MD/1MHP/bender' => '1MHP', '/home/dario/simulazioni/APO_MD/1NCA/bender' => '1NCA', '/home/dario/simulazioni/APO_MD/1NSN/bender' => '1NSN', '/home/dario/simulazioni/APO_MD/1OAK/bender' => '1OAK', '/home/dario/simulazioni/APO_MD/1PKQ/bender' => '1PKQ', '/home/dario/simulazioni/APO_MD/1RJL/bender' => '1RJL', '/home/dario/simulazioni/APO_MD/1TPX/bender' => '1TPX', '/home/dario/simulazioni/APO_MD/1TZH/bender' => '1TZH', '/home/dario/simulazioni/APO_MD/1YNT/bender' => '1YNT', '/home/dario/simulazioni/APO_MD/1YQV/bender' => '1YQV', '/home/dario/simulazioni/APO_MD/2ADF/bender' => '2ADF', '/home/dario/simulazioni/APO_MD/2FJH/bender' => '2FJH', '/home/dario/simulazioni/APO_MD/2JEL/bender' => '2JEL', 
# *** APO 200ns ***
'/home/dario/simulazioni/DUSCENTO/1NDGapo/bender' => '1NDG', '/home/dario/simulazioni/DUSCENTO/1DQJapo/bender' => '1DQJ', '/home/dario/simulazioni/DUSCENTO/1NDMapo/bender' => '1NDM', '/home/dario/simulazioni/DUSCENTO/1P2Capo/bender' => '1P2C', '/home/dario/simulazioni/DUSCENTO/1MLCapo/bender' => '1MLC', '/home/dario/simulazioni/DUSCENTO/1CZ8apo/bender' => '1CZ8', '/home/dario/simulazioni/DUSCENTO/1BJ1apo/bender' => '1BJ1', 
# *** OLO 50ns ***
'/home/dario/simulazioni/OLO_MD/1AFV/bender' => '1AFV', '/home/dario/simulazioni/OLO_MD/1AHW/bender' => '1AHW', '/home/dario/simulazioni/OLO_MD/1BGX/bender' => '1BGX', '/home/dario/simulazioni/OLO_MD/1FDL/bender' => '1FDL', '/home/dario/simulazioni/OLO_MD/1FE8/bender' => '1FE8', '/home/dario/simulazioni/OLO_MD/1FSK/bender' => '1FSK', '/home/dario/simulazioni/OLO_MD/1H0D/bender' => '1H0D', '/home/dario/simulazioni/OLO_MD/1IQD/bender' => '1IQD', '/home/dario/simulazioni/OLO_MD/1MHP_Mg/bender' => '1MHP', '/home/dario/simulazioni/OLO_MD/1NCA/bender' => '1NCA', '/home/dario/simulazioni/OLO_MD/1NSN/bender' => '1NSN', '/home/dario/simulazioni/OLO_MD/1OAK/bender' => '1OAK', '/home/dario/simulazioni/OLO_MD/1PKQ/bender' => '1PKQ', '/home/dario/simulazioni/OLO_MD/1RJL/bender' => '1RJL', '/home/dario/simulazioni/OLO_MD/1TPX/bender' => '1TPX', '/home/dario/simulazioni/OLO_MD/1TZH/bender' => '1TZH', '/home/dario/simulazioni/OLO_MD/1YNT/bender' => '1YNT', '/home/dario/simulazioni/OLO_MD/1YQV/bender' => '1YQV', '/home/dario/simulazioni/OLO_MD/2ADF/bender' => '2ADF', '/home/dario/simulazioni/OLO_MD/2FJH/bender' => '2FJH', '/home/dario/simulazioni/OLO_MD/2JEL/bender' => '2JEL', 
# *** OLO 200ns ***
'/home/dario/simulazioni/DUSCENTO/1NDGolo/bender' => '1NDG', '/home/dario/simulazioni/DUSCENTO/1DQJolo/bender' => '1DQJ', '/home/dario/simulazioni/DUSCENTO/1NDMolo/bender' => '1NDM', '/home/dario/simulazioni/DUSCENTO/1P2Colo/bender' => '1P2C', '/home/dario/simulazioni/DUSCENTO/1CZ8olo/bender' => '1CZ8', '/home/dario/simulazioni/DUSCENTO/1MLColo/bender' => '1MLC', '/home/dario/simulazioni/DUSCENTO/1BJ1olo/bender' => '1BJ1'
};
# THREADING
our $thread_num = 8; # numero massimo di threads contemporanei (dipende dal numero di nodi/processori disponibili)
our $semaforo = Thread::Semaphore->new(int($thread_num));
our @thr; # lista dei threads
our ($queued, $running) :shared; 
# =================================== SBLOG ====================================

FILECHECK: {
    print "\n*** BENDER in batch mode ***\n";
    chomp $bender;
    croak("\nE- BENDER.pl script not found\n\t")
        unless (-e $bender);
}

CORE: {
    $queued = 0E0;
    $running = 0E0;
    my ($pdb, $path);
    foreach my $key (keys %{$dataset}) {
        $path = $key;
        $pdb = $dataset->{$key};
        push @thr, threads->new(\&submit, $pdb, $path);
    }
    for (@thr) { $_->join() };
    @thr = ( );
}

FINE: {
    print "\n\n*** REDNEB ***\n";
    exit;
}

sub submit { # sottomissione dei job di EMMA
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        lock $queued; $queued = $queued + 1;
        thread_monitor();
    }
    $semaforo->down(); # occupo uno slot
    { lock $running; $running = $running + 1; }
    thread_monitor();
    
    my ($pdb, $path) = @_;
    my $logfile = $path . '/bender.log';
    my $cmdline = "$bender $pdb $path > $logfile";
    qx/$cmdline/;
    
    {
        lock $running; $running = $running - 1;
        lock $queued; $queued = $queued - 1;
        $queued = 0E0 if ($queued <= 0);
        $running = 0E0 if ($running <= 0);
    }
    thread_monitor();
    $semaforo->up(); # libero uno slot
}

sub thread_monitor {
    printf("\r\tRUNNING [%03d] QUEUED [%03d]", $running, $queued);
}