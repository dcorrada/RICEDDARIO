#!/usr/bin/perl
# -d

use strict;
use warnings;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| = 1;

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;
use Carp;
###################################################################

USAGE: {
    my $usage = <<END
*** GROMACS2AMBER ***
This script is a PDB format converter for parsing output file coming
from GROMACS to input file for AMBER.
GROMACS2AMBER is the standalone version of a ISABEL module.

SYNOPSYS

  $0 <filename.pdb>
END
    ;
    
    unless ($ARGV[0]) {
        print $usage;
        goto FINE;
    }
}

CORE: {
    my $fh; # filehandle
    
    # leggo il file pdb generato da GROMACS
    my $in_file = $ARGV[0];
    open($fh, '<'.$in_file) or croak("\nE- unable to open [$in_file]\n\t");
    my $in_content = [ <$fh> ];
    close $fh;
    
    # importazione del pdb originale
    print "\nI- importing data from [$in_file]...";
    my $pdb = [ ];
    while (my $newline = shift @{$in_content}) {
        chomp $newline;
        if ($newline !~ /^ATOM/) {
            next;
        }
        
        # se le righe contengo le coordinate atomiche le parso...
        my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
        # Gli elementi del vettore @splitted da considerare sono:
        #   [1]   Atom serial number
        #   [3]   Atom name
        #   [4]   Alternate location indicator
        #   [5]   Residue name
        #   [7]   Chain identifier
        #   [8]   Residue sequence number
        #   [9]   Code for insertion of residues
        #   [11-13] XYZ coordinates
        #   [14]  Occupancy volume
        #   [15]  T-factor
        push(@{$pdb}, [ @splitted ]);
    }
    
    # pre-processamento del pdb
    print "\nI- data pre-processing...";
    my @Nterms; # res N-terminali
    my @Cterms; # res C-terminali
    for (my $i = 0; $i < scalar @{$pdb}; $i++) {
        if ($pdb->[$i][3] =~ /\sN\s{2}/) { # individui gli N-term
            if ($pdb->[$i+1][3] =~ /\sH1\s{1}/) {
                push(@Nterms, $pdb->[$i][7].$pdb->[$i][8]); # mi appunto catena+resID 
            }
        } elsif ($pdb->[$i][3] =~ /\sC\s{2}/) { # individui i C-term
            if ($pdb->[$i+1][3] =~ /\sO1\s{1}/) {
                push(@Cterms, $pdb->[$i][7].$pdb->[$i][8]);
            }
        }
    }
    
    
    # fix per le istidine
    print "\nI- histidine fix...";
    my $fixc = 0E0; my $fixn = 0E0;
    for (my $i = 0; $i < scalar @{$pdb}; $i++) {
        if ($pdb->[$i][5] =~ /^HIS$/) {
            my $pattern = $pdb->[$i][7].$pdb->[$i][8];
            
            foreach my $ref (@Cterms) { # correzione per residui C-terminali
                if ( $pattern =~ /$ref/) {
                    $fixc = 1;
                }
            }
            foreach my $ref (@Nterms) { # correzione per residui N-terminali
                if ( $pattern =~ /$ref/) {
                    $fixn = 2;
                }
            }
            
            if ($pdb->[$i + 6 + $fixn][3] !~ /HD1/ && $pdb->[$i + 9 + $fixn][3] =~ /HE2/) {
                for (my $a = $i; $a <= $i + 11 + $fixc + $fixn; $a++) {
                    $pdb->[$a][5] = 'HIE';
                }
            } elsif ($pdb->[$i + 6 + $fixn][3] =~ /HD1/ && $pdb->[$i + 10 + $fixn][3] =~ /C/) {
                for (my $a = $i; $a <= $i + 11 + $fixc + $fixn; $a++) {
                    $pdb->[$a][5] = 'HID';
                }
            } else {
                for (my $a = $i; $a <= $i + 12 + $fixc + $fixn; $a++) {
                    $pdb->[$a][5] = 'HIP';
                }
            }
            $fixc = 0E0;
            $fixn = 0E0;
        }
    }
    
    # fix per le isoleucine
    print "\nI- isoleucine fix...";
    for (my $i = 0; $i < scalar @{$pdb}; $i++) {
        if ($pdb->[$i][5] =~ /^ILE$/ && $pdb->[$i][3] =~ /^ CD $/) {
            $pdb->[$i][3] = ' CD1';
        }
    }
    
    # fix per le cisteine
    print "\nI- cysteine fix...";
    # raccolgo le info sugli atomi di zolfo delle cisteine
    my $SG = [ ];
    for (my $i = 0; $i < scalar @{$pdb}; $i++) {
        if ($pdb->[$i][5] =~ /^CYS$/ && $pdb->[$i][3] =~ /^ SG $/) {
            push(@{$SG}, $pdb->[$i]);
        }
    }
    # verifico la presenza di ponti disolfuro
    my %bridge;
    for (my $i = 0; $i < scalar @{$SG}; $i++) {
        for (my $j = $i + 1; $j < scalar @{$SG}; $j++) {
            my $xa = $SG->[$i][11]; $xa =~ s/\s//g; my $xb = $SG->[$j][11]; $xb =~ s/\s//g;
            my $ya = $SG->[$i][12]; $ya =~ s/\s//g; my $yb = $SG->[$j][12]; $yb =~ s/\s//g;
            my $za = $SG->[$i][13]; $za =~ s/\s//g; my $zb = $SG->[$j][13]; $zb =~ s/\s//g;
            my $distance = ($xa - $xb)**2 + ($ya - $yb)**2 + ($za - $zb)**2;
            $distance = sqrt $distance;
            # print "\n Distanza di legame: [$distance]";
            if ($distance < 2.1) { # se c'è il disuolfuro metto le cisteine in lista
                my $key1 = $SG->[$i][7].$SG->[$i][8];
                my $key2 = $SG->[$i][7].$SG->[$i][8];
                $bridge{$key1} = 1 unless (exists $bridge{$key1});
                $bridge{$key2} = 1 unless (exists $bridge{$key2});
            }
        }
    }
    # print "\n cisteine coinvolte in ponti disolfuro:";
    # print Dumper \%bridge;
    for (my $i = 0; $i < scalar @{$pdb}; $i++) { # il fix vero e proprio
        my $pattern = $pdb->[$i][7].$pdb->[$i]->[8];
        if (exists $bridge{$pattern}) {
            $pdb->[$i][5] = 'CYX';
        }
    }
    
    # fix per i carbossili C-term
    print "\nI- C-term fix...";
    for (my $i = 0; $i < scalar @{$pdb}; $i++) {
        my $pattern = $pdb->[$i][7].$pdb->[$i]->[8];
        foreach my $ref (@Cterms) { # aggiungo un "TER" ad ogni fine catena
            if ($pattern =~ /$ref/ && $pdb->[$i][3] =~ /^ O1 $/) {
                $pdb->[$i][3] = ' O  ';
            } elsif ($pattern =~ /$ref/ && $pdb->[$i][3] =~ /^ O2 $/) {
                $pdb->[$i][3] = ' OXT';
            }
        }
    }
    
    # rimozione degli idrogeni
    print "\nI- removing hydorgens...";
    my $pdb_noH = [ ];
    while (my $newline = shift @{$pdb}) {
        if ($newline->[3] =~ /^H/ ) {
            next;
        } elsif ($newline->[3] =~ /^.H/ ) {
            next;
        } else {
            push(@{$pdb_noH}, $newline);
        }
    }
    
    # rinumero gli atomi
    my $i = 1;
    foreach my $newline (@{$pdb_noH}) {
        $newline->[1] = sprintf('%*d', 5, $i); # riempio a sinistra con degli spazi
        $i++;
    }
    
    # rinomino le catene
    my @letters = ('A'..'Z');
    my @newNterms;
    my $next_change = shift @Nterms;
    my $actual_chain;
    foreach my $newline (@{$pdb_noH}) {
        if ($newline->[7].$newline->[8] eq $next_change) {
            $actual_chain = shift @letters;
            push(@newNterms, $actual_chain.$newline->[8]);
            if (@Nterms) {
                $next_change = shift @Nterms;
            } else {
                $next_change = "goto_EOF"; # non ci sono altre catene rimanenti
            }
        }
        $newline->[7] = $actual_chain;
    }
    
    # scrittura del pdb processato
    my $out_content = [ "TITLE     ISabel is Another BEppe Layer\n", "MODEL        1\n" ];
    shift @newNterms;
    while (my $newline = shift @{$pdb_noH}) {
        my $pattern = $newline->[7].$newline->[8];
        foreach my $ref (@newNterms) { # aggiungo un "TER" ad ogni fine catena
            if ( $pattern =~ /$ref/) {
                push(@{$out_content}, "TER\n");
                shift @newNterms;
            }
        }
        my $joined = pack('A6A5A1A4A1A3A1A1A4A1A3A8A8A8A6A6A4A2A2', @{$newline});
        push(@{$out_content}, $joined."\n");
    }
    push(@{$out_content}, "TER\n");
    push(@{$out_content}, "ENDMDL\n");
    my $out_file = $in_file;
    $out_file =~ s/(\.pdb)?$/\.amber\.pdb/;
    open ($fh, '>'.$out_file) or croak("\nE- unable to open [$out_file]\n\t");
    print $fh @{$out_content};
    close $fh;
    
    print "\nI- data written to [$out_file]";
}

FINE: {
    print "\n*** REBMA2SCAMORG ***\n";
    exit;
}