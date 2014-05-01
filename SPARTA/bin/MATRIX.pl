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
# Questo script legge le matrici (energetiche/doinamiche) ed strapola
# comportamenti globali dei Fab

use Cwd;
use Carp;
use SPARTA::lib::FileIO; # modulo per leggere/scrivere su file
use Statistics::Basic;

## GLOBS ##
our $basepath = '/home/dario/SPARTA_RAWDATA/temp/affinity_maturation';
our $dataset = {
    '1P2C' => { 'path' => $basepath . '/1P2Colo',
        'VH' => [1..116], 'VL' => [217..325], 'CH1' => [117..216], 'CL' => [325..428], 'AG' => [429..557],
        'paratope' => [30,31,32,33,35,50,52,55,56,57,59,99,100,101,248,266,307,308,309,310]
    },
    '1MLC' => { 'path' => $basepath . '/1MLColo',
        'VH' => [1..117], 'VL' => [219..327], 'CH1' => [117..218], 'CL' => [328..432],'AG' => [433..561],
        'paratope' => [30,31,32,33,35,50,55,56,57,59,99,100,101,250,268,309,310,312]
    },
    '1NDG' => { 'path' => $basepath . '/1NDGolo',
        'VH' => [1..113], 'VL' => [211..319], 'CH1' => [114..210], 'CL' => [320..424],'AG' => [425..553],
        'paratope' => [30,31,32,33,50,52,53,54,56,58,98,99,241,242,259,260,263,301,302,304,306]
    },
    '1DQJ' => { 'path' => $basepath . '/1DQJolo',
        'VH' => [1..113], 'VL' => [211..319], 'CH1' => [114..210], 'CL' => [320..424],'AG' => [425..553],
        'paratope' => [30,31,32,33,50,52,53,54,56,58,98,240,241,242,260,263,301,302,304,306]
    },
    '1NDM' => { 'path' => $basepath . '/1NDMolo',
        'VH' => [1..113], 'VL' => [211..319], 'CH1' => [114..210], 'CL' => [320..424],'AG' => [425..553],
        'paratope' => [30,31,32,33,50,52,53,54,56,58,98,99,240,241,242,260,263,301,302,304,306]
    },
    '1BJ1' => { 'path' => $basepath . '/1BJ1olo',
        'VH' => [1..123], 'VL' => [225..334], 'CH1' => [124..224], 'CL' => [335..437],'AG' => [438..531],
        'paratope' => [30,31,32,33,50,52,53,54,59,99,100,101,102,103,104,106,108,318,320]
    },
    '1CZ8' => { 'path' => $basepath . '/1CZ8olo',
        'VH' => [1..123], 'VL' => [225..334], 'CH1' => [124..224], 'CL' => [335..437],'AG' => [438..531],
        'paratope' => [30,31,32,33,50,52,53,54,59,99,100,101,102,103,104,106,108,318,320]
    }
};
our $enematrix = '/ene/enematrix.dat'; # matrice delle energie
our $flumatrix = '/emma/emmatrix.dat'; # matrice delle distance fluctuations
our $output = { };
## SBLOG ##

FILECHECK: {
    foreach my $pdb (keys %{$dataset}) {
        my $check1 =  $dataset->{$pdb}->{'path'} . $enematrix;
        my $check2 =  $dataset->{$pdb}->{'path'} . $flumatrix;
        if ((-e $check1) && (-e $check2)) {
            $output->{$pdb} = { };
        } else {
            carp("\nE- [$pdb] missing files, amalysis skipped...\n\t");
        }
    }
}

ENERGY: {
# calcolo i contributi energetici del Fab
    foreach my $pdb (keys %{$output}) {
        print "\nI- [$pdb] processing Fab energies...";

        # individuo quali residui del complesso definisco il Fab
        my %partners;
        foreach my $domain ('VH', 'CH1', 'VL', 'CL') {
            foreach my $res (@{$dataset->{$pdb}->{$domain}}) {
                $partners{$res} = 1;
            }
        }

        # leggo la matrice delle energie
        my $enefile = SPARTA::lib::FileIO->new();
        $enefile->set_filename($dataset->{$pdb}->{'path'} . $enematrix);
        my $content = $enefile->read();

        # sommo i contributi
        my $enesum = 0E0;
        while (my $row = shift @{$content}) {
            chomp $row;
            my ($p1,$p2,$ene) = $row =~ m/(\d+)\s+(\d+)\s+([\d\-eE\.]+)/;
            next unless $ene; # righe non di interesse
            if ((exists $partners{$p1}) && (exists $partners{$p2})) {
                $enesum += $ene;
            } else {
                next;
            }
        }

        $enesum = sprintf("%d", $enesum * 4.184); # converto in kJ/mol
        $output->{$pdb}->{'Etot'} = $enesum;
    }

# calcolo i contributi energetici dell'antigene (se c'è)
    foreach my $pdb (keys %{$output}) {
        print "\nI- [$pdb] processing Ag energies...";
        # individuo quali residui del complesso definisco l'antigene
        my %partners;
        foreach my $res (@{$dataset->{$pdb}->{'AG'}}) {
            $partners{$res} = 1;
        }

        # leggo la matrice delle energie
        my $enefile = SPARTA::lib::FileIO->new();
        $enefile->set_filename($dataset->{$pdb}->{'path'} . $enematrix);
        my $content = $enefile->read();

        # sommo i contributi
        my $enesum = 0E0;
        while (my $row = shift @{$content}) {
            chomp $row;
            my ($p1,$p2,$ene) = $row =~ m/(\d+)\s+(\d+)\s+([\d\-eE\.]+)/;
            next unless $ene; # righe non di interesse
            if ((exists $partners{$p1}) && (exists $partners{$p2})) {
                $enesum += $ene;
            } else {
                next;
            }
        }

        $enesum = sprintf("%d", $enesum * 4.184); # converto in kJ/mol
        $output->{$pdb}->{'Eag'} = $enesum;
    }
}

FLUCTUATION: {
# calcolo i contributi dinamici del Fab
    foreach my $pdb (keys %{$output}) {
        print "\nI- [$pdb] processing fluctuations...";

        # individuo i residui del complesso per cui calcolare i contributi
        my $partners = { 'paratope' => {}, 'heavy' => { }, 'light' => { }, 'constant' => { }, 'variable' => { } };
        foreach my $res (@{$dataset->{$pdb}->{'paratope'}}) {
            $partners->{'paratope'}->{$res} = 1;
        }
        foreach my $domain ('VH', 'CH1') {
            foreach my $res (@{$dataset->{$pdb}->{$domain}}) {
                $partners->{'heavy'}->{$res} = 1;
            }
        }
        foreach my $domain ('VL', 'CL') {
            foreach my $res (@{$dataset->{$pdb}->{$domain}}) {
                $partners->{'light'}->{$res} = 1;
            }
        }
        foreach my $domain ('CH1', 'CL') {
            foreach my $res (@{$dataset->{$pdb}->{$domain}}) {
                $partners->{'constant'}->{$res} = 1;
            }
        }
        foreach my $domain ('VH', 'VL') {
            foreach my $res (@{$dataset->{$pdb}->{$domain}}) {
                $partners->{'variable'}->{$res} = 1;
            }
        }

        # leggo la matrice delle fluttuazioni
        my $enefile = SPARTA::lib::FileIO->new();
        $enefile->set_filename($dataset->{$pdb}->{'path'} . $flumatrix);
        my $content = $enefile->read();

        my (@heavy,@light,@constant,@variable);
        while (my $row = shift @{$content}) {
            chomp $row;
            my ($p1,$p2,$flu) = $row =~ m/(\d+)\s+(\d+)\s+([\d\-eE\.]+)/;
            next unless $flu; # righe non di interesse

            my ($paratope,$counterpart);
            if (exists $partners->{'paratope'}->{$p1}) {
                ($paratope,$counterpart) = ($p1,$p2);
            } elsif (exists $partners->{'paratope'}->{$p2}) {
                ($paratope,$counterpart) = ($p2,$p1);
            } else {
                next;
            }

            push(@heavy, $flu) if (exists $partners->{'heavy'}->{$counterpart});
            push(@light, $flu) if (exists $partners->{'light'}->{$counterpart});
            push(@constant, $flu) if (exists $partners->{'constant'}->{$counterpart});
            push(@variable, $flu) if (exists $partners->{'variable'}->{$counterpart});
        }

        $output->{$pdb}->{'heavy'} = sprintf("%.3f", Statistics::Basic::mean(@heavy));
        $output->{$pdb}->{'light'} = sprintf("%.3f", Statistics::Basic::mean(@light));
        $output->{$pdb}->{'constant'} = sprintf("%.3f", Statistics::Basic::mean(@constant));
        $output->{$pdb}->{'variable'} = sprintf("%.3f", Statistics::Basic::mean(@variable));

        $output->{$pdb}->{'h'} = [ @heavy ];
        $output->{$pdb}->{'l'} = [ @light ];
        $output->{$pdb}->{'c'} = [ @constant ];
        $output->{$pdb}->{'v'} = [ @variable ];
    }
}

OUTPUT: {
    print "\n\nPDB\t\tEtot\t\tEag\t\theavy\t\tlight\t\tconstant\tvariable\n";
    print "---\t\t----\t\t-----\t\t-----\t\t-----\t\t--------\t--------\n";
    foreach my $pdb (keys %{$output}) {
        printf("%s\t\t%d\t\t%d\t\t%.2f\t\t%.2f\t\t%.2f\t\t%.2f\n",
            $pdb,
            $output->{$pdb}->{'Etot'},
            $output->{$pdb}->{'Eag'},
            $output->{$pdb}->{'heavy'},
            $output->{$pdb}->{'light'},
            $output->{$pdb}->{'constant'},
            $output->{$pdb}->{'variable'}
        );
    }
}

FINE: {
    print "\n\n*** FINE ***\n";
    exit;
}