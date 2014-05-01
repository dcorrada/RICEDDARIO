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
use Cwd;
use Carp;
use SPARTA::lib::FileIO;
use SPARTA::lib::DBmanager;
use threads;
use threads::shared;
use Thread::Semaphore;
use Math::Trig;

# =================================== GLOBS ====================================
# PATHS
our $home = $ENV{HOME};
our $gnuplot = $home.'/opt/gnuplot44';
our $spartadb = $home.'/script/SPARTA/data/db_connect.txt';
our $pdb;
our $path;
# INTERNALS
our @db_settings;
our $regions = { }; # trovo residui che definiscono i due domini (variabile e coatante) e la regione cerniera
our $blacklist = { 'VH' => [ ], 'VL' => [ ], 'CH' => [ ], 'CL' => [ ] }; # lista di residui da non considerare
our $hinges = { }; # lista degli angoli per ogni frame
# =================================== SBLOG ====================================

USAGE: {
    print "\n*** BENDER ***\n";
    my $options = { };
    use Getopt::Long;no warnings;
    GetOptions($options, 'help|h');
    my $usage = <<END
BENDER:"bite my shiny metal a**!"
He calculates the hinge bending angles of a Fab structure along an entire trajectory.

SYNOPSYS
    
    $0 1BJ1 ~/simulazioni/DUSCENTO/1BJ1olo/bender
END
    ;
    if (exists $options->{'help'}) { print $usage; goto FINE; }
}

INIT: {
    ($pdb, $path) = ($ARGV[0],$ARGV[1]);
    
    # verifico la presenza dei file traiettoria
    my $trajfile = $path . '/traj.ca.pdb';
    croak("\nE- file [$trajfile] not found\n\t") unless (-e $trajfile);
    
    # reperisco le credenziali di accesso al DB
    my $file_obj = SPARTA::lib::FileIO->new('filename' => $spartadb);
    my $content = $file_obj->read();
    while (my $row = shift @{$content}) {
        chomp $row;
        next unless ($row =~ /^\[/);
        my ($key, $value) = $row =~ m/^\[(\w+)\] ([\w\.]+)/;
        push(@db_settings, $key, $value);
    }
}

print "\nI- querying SPARTA database...";

REGIONS: { # interrogo il DB di SPARTA x capire dove mappano i domini e le regioni cerniera
    my $db_obj = SPARTA::lib::DBmanager->new(@db_settings);
    my $dbh = $db_obj->access2db();
    my ($query, $sth);
    $query = <<END
SELECT MIN(res+0), MAX(res+0), chain
FROM structure
WHERE cdr LIKE 'HINGE'
AND pdb LIKE '$pdb'
GROUP BY CONCAT(pdb,chain)
END
    ;
    $sth = $db_obj->query_exec('dbh' => $dbh, 'query' => $query);
    while (my ($start, $stop, $chain) = $sth->fetchrow_array()) {
        $regions->{$chain} = [ ];
        push(@{$regions->{$chain}}, $start, $stop);
    }
    $sth->finish();
    $query = <<END
SELECT MIN(res+0), MAX(res+0), chain
FROM structure
WHERE pdb LIKE '$pdb'
GROUP BY CONCAT(pdb,chain)
END
    ;
    $sth = $db_obj->query_exec('dbh' => $dbh, 'query' => $query);
    while (my ($start, $stop, $chain) = $sth->fetchrow_array()) {
        unshift(@{$regions->{$chain}}, $start);
        push(@{$regions->{$chain}}, $stop);
    }
    $sth->finish();
    $dbh->disconnect();
}

BLACKLIST: { # considero per il calcolo del baricentro solo i residui appartenenti al beta-sandwich
    my $db_obj = SPARTA::lib::DBmanager->new(@db_settings);
    my $dbh = $db_obj->access2db();
    my ($query, $sth, $fetch);
    foreach my $dom (keys %{$blacklist}) {
        $query = <<END
SELECT res
FROM structure
WHERE pdb LIKE '$pdb'
AND CONCAT(domain,chain) LIKE '$dom'
AND dssp NOT LIKE 'E'
AND cdr NOT LIKE 'HINGE'
END
        ;
        $sth = $db_obj->query_exec('dbh' => $dbh, 'query' => $query);
        while (my ($res) = $sth->fetchrow_array()) {
            push(@{$blacklist->{$dom}}, $res);
        }
        $sth->finish();
    }
    $dbh->disconnect();
}

print "done";

CORE: {
    my $centres = { }; # elenco dei baricentri per ogni frame
    BARYCENTRE: { # calcolo i baricentri di ogni timeframe
        my $trajfile = $path . '/traj.ca.pdb';
        my $obj = SPARTA::lib::FileIO->new();
        my $content = $obj->read($trajfile);
        my $wc = qx/wc -l $trajfile/;
        my ($tot_lines) = $wc =~ /^(\d+)/;
        print "\nI- parsing [$trajfile] file\n";
        my $model_num;
        my %skip;
        foreach my $dom (keys %{$blacklist}) {
            foreach my $res (@{$blacklist->{$dom}}) {
                $skip{$res} = 1;
            }
        }
        while (my $newline = shift @{$content}) {
            $tot_lines--;
            printf("\r  [%04dE04] steps to go...", $tot_lines/10000) if ($tot_lines % 10000 == 0);
            chomp $newline;
            $newline =~ /^MODEL/ and do { # leggo il frame della traiettoria
                ($model_num) =  $newline =~ /^MODEL\s+(\d+)/;
                $model_num = sprintf("MODEL_%05d", $model_num);
                $centres->{$model_num} = { 
                    'Hvar' => [0E0,0E0,0E0], 'Hconst' => [0E0,0E0,0E0], 'Hhinge' => [0E0,0E0,0E0],
                    'Lvar' => [0E0,0E0,0E0], 'Lconst' => [0E0,0E0,0E0], 'Lhinge' => [0E0,0E0,0E0]
                };
                next;
            };
            $newline =~ /^ATOM/ and do { # leggo le coordinate atomiche associate al frame
                my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
                # Gli elementi del vettore @splitted da considerare sono:
                #   [3]   atom name
                #   [8]   residue number
                #   [11-13] XYZ coordinates
                my ($x, $y, $z, $resnum, $atom) = ($splitted[11], $splitted[12], $splitted[13], $splitted[8], $splitted[3]);
                ($resnum) = $resnum =~ /(\d+)/;
                next unless ($atom eq ' CA '); # x il momento considero solo le coord dei C-alpha
                next if (exists $skip{$resnum});
                if ($resnum < $regions->{'H'}[1]) {
                    $centres->{$model_num}->{'Hvar'}[0] += $x;
                    $centres->{$model_num}->{'Hvar'}[1] += $y;
                    $centres->{$model_num}->{'Hvar'}[2] += $z;
                } elsif ($resnum <= $regions->{'H'}[2]) {
                    $centres->{$model_num}->{'Hhinge'}[0] += $x;
                    $centres->{$model_num}->{'Hhinge'}[1] += $y;
                    $centres->{$model_num}->{'Hhinge'}[2] += $z;
                } elsif ($resnum < $regions->{'H'}[3]) {
                    $centres->{$model_num}->{'Hconst'}[0] += $x;
                    $centres->{$model_num}->{'Hconst'}[1] += $y;
                    $centres->{$model_num}->{'Hconst'}[2] += $z;
                } elsif ($resnum < $regions->{'L'}[1]) {
                    $centres->{$model_num}->{'Lvar'}[0] += $x;
                    $centres->{$model_num}->{'Lvar'}[1] += $y;
                    $centres->{$model_num}->{'Lvar'}[2] += $z;
                } elsif ($resnum <= $regions->{'L'}[2]) {
                    $centres->{$model_num}->{'Lhinge'}[0] += $x;
                    $centres->{$model_num}->{'Lhinge'}[1] += $y;
                    $centres->{$model_num}->{'Lhinge'}[2] += $z;
                } elsif ($resnum < $regions->{'L'}[3]) {
                    $centres->{$model_num}->{'Lconst'}[0] += $x;
                    $centres->{$model_num}->{'Lconst'}[1] += $y;
                    $centres->{$model_num}->{'Lconst'}[2] += $z;
                };
                next;
            };
            $newline =~ /^ENDMDL/ and do { # calcolo il baricentri di ogni frame
                foreach my $tag (keys %{$centres->{$model_num}}) {
                    my $totres;
                    my $coords = $centres->{$model_num}->{$tag};
                    if ($tag eq 'Hvar') {
                        $totres = $regions->{'H'}[1] - $regions->{'H'}[0] - scalar(@{$blacklist->{'VH'}});
                    } elsif ($tag eq 'Hhinge') {
                        $totres = $regions->{'H'}[2] - $regions->{'H'}[1] + 1;
                    } elsif ($tag eq 'Hconst') {
                        $totres = $regions->{'H'}[3] - $regions->{'H'}[2] - scalar(@{$blacklist->{'CH'}});
                    } elsif ($tag eq 'Lvar') {
                        $totres = $regions->{'L'}[1] - $regions->{'L'}[0] - scalar(@{$blacklist->{'VL'}});
                    } elsif ($tag eq 'Lhinge') {
                        $totres = $regions->{'L'}[2] - $regions->{'L'}[1] + 1;
                    } elsif ($tag eq 'Lconst') {
                        $totres = $regions->{'L'}[3] - $regions->{'L'}[2] - scalar(@{$blacklist->{'CL'}});
                    }
                    $coords->[0] = $coords->[0]/$totres;
                    $coords->[1] = $coords->[1]/$totres;
                    $coords->[2] = $coords->[2]/$totres;
                }
                next;
            };
        }
    }
    ANGLE: { # calcolo gli angoli
        print "\nI- calculating angles...";
        foreach my $frame (sort keys %{$centres}) {
            my %pairs = ( # riferimenti x coppie di punti 
                'Hdom_hinge'    => [ 'Hhinge',  'Hconst' ],
                'Hdom_dom'      => [ 'Hvar',    'Hconst' ],
                'Hhinge_dom'    => [ 'Hhinge',  'Hvar'   ],
                'Ldom_hinge'    => [ 'Lhinge',  'Lconst' ],
                'Ldom_dom'      => [ 'Lvar',    'Lconst' ],
                'Lhinge_dom'    => [ 'Lhinge',  'Lvar'   ]
            );
            my %distances = ( # distanze per coppie di punti
                'Hdom_hinge' => 0E0, 'Hdom_dom' => 0E0, 'Hhinge_dom' => 0E0,
                'Ldom_hinge' => 0E0, 'Ldom_dom' => 0E0, 'Lhinge_dom' => 0E0
            );
            my ($Hangle, $Langle);
            foreach my $couple (keys %pairs) {
                my ($xi, $yi, $zi) = @{$centres->{$frame}->{$pairs{$couple}->[0]}};
                my ($xj, $yj, $zj) = @{$centres->{$frame}->{$pairs{$couple}->[1]}};
                my $dist = sqrt( ($xi-$xj)**2 + ($yi-$yj)**2 + ($zi-$zj)**2 );
                $distances{$couple} = $dist;
            };
            $Hangle = $distances{'Hdom_hinge'}**2 + $distances{'Hhinge_dom'}**2 - $distances{'Hdom_dom'}**2;
            $Hangle = $Hangle / (2*$distances{'Hdom_hinge'}*$distances{'Hhinge_dom'});
            $Hangle = (acos($Hangle)*180)/3.141592654;
            $Langle = $distances{'Ldom_hinge'}**2 + $distances{'Lhinge_dom'}**2 - $distances{'Ldom_dom'}**2;
            $Langle = $Langle / (2*$distances{'Ldom_hinge'}*$distances{'Lhinge_dom'});
            $Langle = (acos($Langle)*180)/3.141592654;
            $hinges->{$frame} = [$Hangle,$Langle];
        }
        print "done";
    }
    DATFILE: {
        my $header = "FRAME  HEAVY_CHAIN  LIGHT_CHAIN\n";
        my $content = [ $header ];
        foreach my $frame (sort keys %{$hinges}) {
            my ($flag) = $frame =~ /^MODEL_0*(\d+)$/;
            $flag++;
            my $string = sprintf("%d  %.2f  %.2f\n", $flag, $hinges->{$frame}->[0], $hinges->{$frame}->[1]);
            push(@{$content}, $string);
        }
        my $datfile = $path . '/hinges.dat';
        my $obj = SPARTA::lib::FileIO->new();
        $obj->set_filename($datfile);
        $obj->set_filedata($content);
        $obj->write();
        print "\nI- [$datfile] written";
    }
    GNUPLOT: {
        my $datfile = $path . '/hinges.dat';
        my $pngfile = $path . '/hinges.png';
        my $gnufile = $path . '/script.gnu';
        my $gnuscript = <<END
set terminal png size 2400, 800
set size ratio 0.33
set output "$pngfile"
set key
set tics out
set ylabel "degree"
set xlabel "frame"
set grid y
set yrange [0:180]
set ytics 10
set mxtics 20
show mxtics
plot '$datfile' using 2 with line title col lt 1, \\
        '' using 3 with line title col lt 3 
unset output
quit
END
        ;
        my $obj = SPARTA::lib::FileIO->new();
        $obj->set_filename($gnufile);
        $obj->set_filedata([ $gnuscript ]);
        $obj->write();
        my $gplot_log = qx/$gnuplot $gnufile 2>&1/;
        $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
        # print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
        unlink $gnufile;
        print "\nI- [$pngfile] written";
    }
}

FINE: {
    print "\n\n*** REDNEB ***\n";
    exit;
}