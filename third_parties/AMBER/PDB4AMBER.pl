#!/usr/bin/perl
# -d

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


INIT: {
    my $splash = <<END
********************************************************************************
PDB4AMBER
release 14.5.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
END
    ;
    print $splash;
    my $usage = <<END

This script convert a generic PDB file in a format compliant to AMBER software.
Only the lines with flag "ATOM" will be parsed by this script

SYNOPSIS
    
    \$ PDB4AMBER.pl <protein.pdb>
END
    ;
    unless ($ARGV[0]) {
        print $usage;
        goto FINE;
    }
}

CORE: {
    
    # leggo il file pdb in input
    my $pdb_content = [ ];
    my $header;
    open (PDBIN, '<' . $ARGV[0]) or
        croak "E- unable to read [$ARGV[0]]\n\t";
    while (my $newline = <PDBIN>) {
        chomp $newline;
        if ($newline =~ /^(TITLE|MODEL)/) {
            $header .= "$newline\n";
        } elsif ($newline =~ /^ATOM/) { # parso solo le linee dei residui proteici (flag "ATOM")
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            # le righe "ATOM" sono strutturate così:
            #   [1]     Atom serial number
            #   [3]     Atom name
            #   [4]     Alternate location indicator
            #   [5]     Residue name
            #   [7]     Chain identifier
            #   [8]     Residue sequence number
            #   [9]     Code for insertion of residues
            #   [11-13] XYZ coordinates
            #   [14]    Occupancy volume
            #   [15]    T-factor
            push(@{$pdb_content}, [ @splitted ]);
        } else {
            next;
        }
    }
    close PDBIN;
    
    print "\nSearching terminal residues";
    my @Nterms; my @Cterms;
    my $chain = 'null';
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        if ($pdb_content->[$i][7] eq $chain) { 
            next;
        } else {
            push(@Nterms, $pdb_content->[$i][7] . $pdb_content->[$i][8]);
            push(@Cterms, $pdb_content->[$i-1][7] . $pdb_content->[$i-1][8]);
            $chain = $pdb_content->[$i][7];
        }
    }
    
    print "\n\nFixing histidines";
    my $is_protonated;
    foreach my $newatm (@{$pdb_content}) {
        if ($newatm->[3] =~ /^\sH/) {
            $is_protonated = 1;
            last;
        }
    }
    if ($is_protonated) {
        my %histidine_list;
        for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
            if ($pdb_content->[$i][5] =~ /^HIS$/) {
                my $id_tag = $pdb_content->[$i][7] . $pdb_content->[$i][8];
                if ($pdb_content->[$i][3] =~ /HD1/) {
                    $histidine_list{$id_tag} .= 'HD1';
                } elsif ($pdb_content->[$i][3] =~ /HE2/) {
                    $histidine_list{$id_tag} .= 'HE2';
                }
            }
        }
        my $newtag = 'null';
        for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
            if ($pdb_content->[$i][5] =~ /^HIS$/) {
                my $id_tag = $pdb_content->[$i][7] . $pdb_content->[$i][8];
                if (exists $histidine_list{$id_tag}) {
                    if ($histidine_list{$id_tag} =~ /HD1HE2/) {
                        $pdb_content->[$i][5] = 'HIP';
                        printf("\n\tHIS %s -> HIP", $id_tag)
                            unless ($id_tag eq $newtag);
                    } elsif ($histidine_list{$id_tag} =~ /HE2/) {
                        $pdb_content->[$i][5] = 'HIE';
                        printf("\n\tHIS %s -> HIE", $id_tag)
                            unless ($id_tag eq $newtag);
                    } else {
                        $pdb_content->[$i][5] = 'HID';
                        printf("\n\tHIS %s -> HID", $id_tag)
                            unless ($id_tag eq $newtag);
                    }
                    $newtag = $id_tag;
                }
            }
        }
    } else {
        print "\n\tW- all histidines will be treated as HIE\n";
        for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
            if ($pdb_content->[$i][5] =~ /^HIS$/) {
                $pdb_content->[$i][5] = 'HIE';
            }
        }
    }
    
    print "\n\nFixing isoleucines"; # per i pdb di GROMACS
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        if ($pdb_content->[$i][5] =~ /^ILE$/ && $pdb_content->[$i][3] =~ /^ CD $/) {
            $pdb_content->[$i][3] = ' CD1';
        }
    }
    
    print "\n\nChecking disulfides";
    my $SG = [ ];
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        if ($pdb_content->[$i][5] =~ /^CYS$/ && $pdb_content->[$i][3] =~ /^ SG $/) {
            push(@{$SG}, $pdb_content->[$i]);
        }
    }
    my %bridge;
    for (my $i = 0; $i < scalar @{$SG}; $i++) {
        for (my $j = $i + 1; $j < scalar @{$SG}; $j++) {
            my $xa = $SG->[$i][11]; $xa =~ s/\s//g; my $xb = $SG->[$j][11]; $xb =~ s/\s//g;
            my $ya = $SG->[$i][12]; $ya =~ s/\s//g; my $yb = $SG->[$j][12]; $yb =~ s/\s//g;
            my $za = $SG->[$i][13]; $za =~ s/\s//g; my $zb = $SG->[$j][13]; $zb =~ s/\s//g;
            my $distance = ($xa - $xb)**2 + ($ya - $yb)**2 + ($za - $zb)**2;
            $distance = sqrt $distance;
            if ($distance < 2.1) {
                my $key1 = $SG->[$i][7].$SG->[$i][8];
                my $key2 = $SG->[$i][7].$SG->[$i][8];
                $bridge{$key1} = 1 unless (exists $bridge{$key1});
                $bridge{$key2} = 1 unless (exists $bridge{$key2});
            }
        }
    }
    my $newbridge = 'null';
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        my $pattern = $pdb_content->[$i][7] . $pdb_content->[$i]->[8];
        if (exists $bridge{$pattern}) {
            $pdb_content->[$i][5] = 'CYX';
            printf("\n\tCYS %s -> CYX", $pattern)
                unless ($pattern eq $newbridge);
        }
        $newbridge = $pattern;
    }
    
    print "\n\nC-term fix"; # per i pdb di GROMACS
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        my $pattern = $pdb_content->[$i][7] . $pdb_content->[$i]->[8];
        foreach my $ref (@Cterms) {
            if ($pattern =~ /$ref/ && $pdb_content->[$i][3] =~ /^ (O1 |OC1)$/) {
                $pdb_content->[$i][3] = ' O  ';
            } elsif ($pattern =~ /$ref/ && $pdb_content->[$i][3] =~ /^ (O2 |OC2)$/) {
                $pdb_content->[$i][3] = ' OXT';
            }
        }
    }
    
    print "\n\nRemoving hydrogens"; 
    my $pdb_noH = [ ];
    while (my $newline = shift @{$pdb_content}) {
        if ($newline->[3] =~ /^H/ ) {
            next;
        } elsif ($newline->[3] =~ /^.H/ ) {
            next;
        } else {
            push(@{$pdb_noH}, $newline);
        }
    }
    
    # Riformattazione del PDB. Il nuovo file risistemato per AMBER avra' atom
    # number, residue number e chain ID riordinati in modo progressivo. Inoltre
    # vengono aggiunti nuovi flag TER.
    print "\n\nRenumbering";
    my @letters = ('A'..'Z');
    my $inc_chain = shift @letters;
    my ($inc_atom, $inc_resi) = (1, 1);
    my $current_chain = $pdb_noH->[0][7];
    my $current_res = $pdb_noH->[0][8];
    my ($prev_resn, $prev_ins);
    my $pdb_sorted = [ ];
    my @deepcopy;
    foreach my $newline (@{$pdb_noH}) {
        # faccio una deep copy dell'array giusto per non fare confusione
        @deepcopy = @{$newline}; 
        
        # aggiorno il residue number
        my $newer_res = $newline->[8];
        unless ($newer_res eq $current_res) {
            $inc_resi++;
            $current_res = $newer_res;
        }
        
        # aggiorno la chain ID
        my $newer_chain = $newline->[7];
        unless ($newer_chain eq $current_chain) {
            
            # inserisco un TER
            my $TER = sprintf("TER   % 5d     % 4s %s% 4d%s", 
                $inc_atom, $prev_resn, $inc_chain, $inc_resi-1, $prev_ins);
            
            $inc_atom++;
            $inc_chain = shift @letters;
            $current_chain = $newer_chain;
            push(@{$pdb_sorted}, $TER);
        }
        
        $deepcopy[1] = sprintf("% 5d",$inc_atom); # right justified format
        $deepcopy[8] = sprintf("% 4d",$inc_resi); # right justified format
        $deepcopy[7] = sprintf("%s",$inc_chain);
        
        push(@{$pdb_sorted}, join('', @deepcopy));
        ($prev_resn, $prev_ins) = ($deepcopy[5], $deepcopy[9]);
        
        $inc_atom++; # aggiorno l'atom number
    }
    my $TER = sprintf("TER   % 5d     % 4s %s% 4d%s", 
                $inc_atom, $prev_resn, $inc_chain, $inc_resi, $prev_ins);
    push(@{$pdb_sorted}, $TER);
    
    # scrivo il file pdb processato
    my $filename = $ARGV[0];
    $filename =~ s/\.pdb$/.amber.pdb/;
    open (PDBOUT, ">$filename");
    my $string = <<END
REMARK   4 COMPLIANT WITH AMBER FORMAT
REMARK 888 WRITTEN BY PDB4AMBER.pl
REMARK 888 Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>
END
    ;
    print PDBOUT $string;
    print PDBOUT $header;
    while (my $newline = shift @{$pdb_sorted}) {
        print PDBOUT $newline . "\n";
    }
    print PDBOUT "ENDMDL\n";
    close PDBOUT;
    print "\n\nOuput PDB written to <$filename>";
}


FINE: {
    print "\n\n*** REBMA4BDP ***\n";
    exit;
}