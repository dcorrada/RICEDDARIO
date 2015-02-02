#!/usr/bin/perl

use strict;
use warnings;
use Carp;

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
use Cwd;
use threads;

## GLOBS ##
our $bins = { # file binari
    'trjconv'   => qx/which trjconv/,
    'trjcat'    => qx/which trjcat/,
    'makendx'   => qx/which make_ndx/,
    'editconf'   => qx/which editconf/,
};
our @input_pdbs; # la lista dei pdb di input da concatenare
our $refpdb; # la struttura di riferimento
our $selected; # il gruppo di atomi selezionato per la traiettoria
our @thr;
our $workdir = getcwd();
## SBLOG ##

INIT: {
    my $splash = <<END
********************************************************************************
PDB2XTC
release 14.11.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
END
    ;
    print $splash;
    
    # verifico che i binari ci siano tutti
    foreach my $key (keys %{$bins}) {
        chomp $bins->{$key};
        if (-e $bins->{$key}) {
            next;
        } else {
            croak "\nE- file <$bins->{$key}> not found\n\t";
        }
    }
    
    # raccolgo la lista dei pdb e li ordino per nome
    opendir(PWD, $workdir);
    @input_pdbs = grep { /\.pdb$/ } readdir PWD;
    closedir PWD;
    @input_pdbs = sort {$a cmp $b} @input_pdbs;
    
    # il primo pdb della lista sarà anche la struttura di riferimento
    $refpdb = $input_pdbs[0];
}

NDX: {
    # cerco i gruppi disponibili e seleziono quello da importare nella traiettoria
    printf("\n*** %s creating index file ***\n\n", clock());
    my @log = qx/echo "q" | $bins->{'makendx'} -f $refpdb 2>&1/;
    while (my $newline = shift @log) {
        chomp $newline;
        if ($newline =~ /:\s+\d+ atoms$/) {
            print "$newline\n";
        }
    }
    
    my @groups = ( '1' );
    print "\nWhich of these groups you would retain? [@groups] ";
    my $ans = <STDIN>; chomp $ans;
    @groups = split(" ", $ans) if ($ans);
    my $joined = join(' | ', @groups);
    
    my $cmd = "$bins->{'makendx'} -f $refpdb <<EOF";
    $cmd .= "\n$joined\nq\nEOF";
    system("$cmd");
    
    undef @groups;
    @log = qx/echo "q" | $bins->{'makendx'} -f $refpdb -n index.ndx 2>&1/;
    while (my $newline = shift @log) {
        chomp $newline;
        if ($newline =~ /:\s+\d+ atoms$/) {
            push(@groups, $newline);
        }
    }
    my $newgroup = pop @groups;
    ($selected) = $newgroup =~ /^\s*(\d+)/;
}

TRJCONV: {
    printf("\n*** %s running trjconv ***\n\n", clock());
    
    my @structlist = @input_pdbs;
    my $remnants = scalar @structlist;
    my $threadnum = 16; # lancio trjconv a blocchi di $threadnum per volta
    my $num = 1;
    while ($remnants) {
        for (my $i = 0; $i < $threadnum; $i++) {
            my $filename = shift @structlist;
            if ($filename) {
                print "converting $filename\n";
                push @thr, threads->new(\&pdb2xtc, $filename, $num);
                $num++;
            }
            $remnants = scalar @structlist;
        }
        for (@thr) { $_->join() };
        undef @thr;
    }
}

TRJCAT: {
    printf("\n*** %s concatenating snapshots ***\n\n", clock());
    system("$bins->{'trjcat'} -f traj_?????.xtc -o catted.xtc");
    system("echo $selected | $bins->{'editconf'} -f $refpdb -o refstruct.gro -n index.ndx");
    system("echo $selected | $bins->{'trjconv'} -f catted.xtc -s refstruct.gro -timestep 1 -o trajout.xtc -n index.ndx");
}

CLEANSWEEP: {
    printf("\n*** %s cleaning temporary files ***\n\n", clock());
    my $cmd = <<END
rm traj_?????.xtc
rm catted.xtc
rm index.ndx
rm \\#*
END
    ;
    qx/$cmd/;
}

FINE: {
    print "\n\n*** CTX2BDP ***\n";
    exit;
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

sub pdb2xtc {
    my ($filename, $num) = @_;
    my $cmdline = sprintf("echo 0 | $bins->{'trjconv'} -s %s -f %s -o traj_%05i.xtc -t0 %i", $filename, $filename, $num, $num);
    qx/$cmdline 2>&1/;
}