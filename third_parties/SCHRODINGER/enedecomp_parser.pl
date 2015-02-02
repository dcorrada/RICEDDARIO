#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.01.a    - initial release
#
# ##############################################################################


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
use Text::CSV;
use Carp;

## GLOBS ##

our $shell = 5.000;
our $basename;
our $fields_of_interest = {
    'atom_ndx'                          => [ 'atom_number' ],
    'r_m_x_coord'                       => [ 'coord_x' ],
    'r_m_y_coord'                       => [ 'coord_y' ],
    'r_m_z_coord'                       => [ 'coord_z' ],
    'i_m_residue_number'                => [ 'resi' ],
    's_m_mmod_res'                      => [ 'resn' ],
    'r_psp_MMGBSA_dG_Bind(NS)_Hbond'    => [ 'Hbond' ],
    'r_psp_MMGBSA_dG_Bind(NS)_Coulomb'  => [ 'Coulomb' ],
    'r_psp_MMGBSA_dG_Bind(NS)_Covalent' => [ 'Covalent' ],
    'r_psp_MMGBSA_dG_Bind(NS)_Packing'  => [ 'Packing' ],
    'r_psp_MMGBSA_dG_Bind(NS)_Lipo'     => [ 'Lipo' ],
    'r_psp_MMGBSA_dG_Bind(NS)'          => [ 'dG(NS)' ],
    'r_psp_MMGBSA_dG_Bind(NS)_Solv_GB'  => [ 'Solv_GB' ],
    'r_psp_MMGBSA_dG_Bind(NS)_vdW'      => [ 'vdW' ],
    'r_psp_MMGBSA_dG_Bind(NS)_SelfCont' => [ 'SelfCont' ],
    'i_psp_ligand_atom'                 => [ 'is_ligand' ],
};
our $parsed_mae = { };
our $distances = { };

## SBLOG ##


USAGE: {
    use Getopt::Long;no warnings;
    my $help;
    my $workflow;
    GetOptions('help|h' => \$help, 'shell|s=f' => \$shell);
    my $header = <<ROGER
********************************************************************************
enedecomp_parser.pl
release 14.12.a

Copyright (c) 2014, Dario Corrada <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

ROGER
    ;
    print $header;
    
    if ($help or !$ARGV[0]) {
        my $spiega = <<ROGER
This script parses an output Maestro file (.mae or .maegz) coming from an 
individual pose that was processed by a prime_mmgbsa job.

*** SYNOPSIS ***
    
    \$ enedecomp_parser.pl <single_pose.maegz>
    
*** OPTIONS ***
    
    -shell|s <float>    define the shell of contacts (in Angstrom)

ROGER
        ;
        print $spiega;
        goto FINE;
    }
}

INFILE: { # leggo e parso il file di input
    printf("%s parsing input file\n", clock());
    my $format;
    ($basename, $format) = $ARGV[0] =~ /(.+)\.(mae|maegz)$/;
    
    # decomprimo il file se necessario
    ($format eq 'maegz') and do {
        my $cmdline = "cp $basename.maegz $basename.mae.gz; gunzip $basename.mae.gz";
        qx/$cmdline/;
    };
    
    open(MAE, '<' . "$basename.mae");
    my $csv_obj = Text::CSV->new({
        quote_char          => '"',
        sep_char            => ' ',
        allow_whitespace    => 0
    });
    my @header;
    my $start2read = 0E0;
    while (my $newline = <MAE>) {
        chomp $newline;
        if ($newline =~ /^  m_atom\[\d+\] \{ $/) { # le righe di interesse iniziano da qui..
            $start2read++;
            next;
        } elsif ($newline =~ /^    :::$/) { # separatori di sezione
            if ($start2read == 1) {
                # valuto in quale ordine i campi sono scritti nel file
                my $i = 0E0;
                while (my $fieldname = shift @header) {
                    $fields_of_interest->{$fieldname}->[1] = $i
                        if (exists $fields_of_interest->{$fieldname});
                    $i++;
                }
                
                $start2read++;
                next;
            } elsif ($start2read == 2) {
                last;
            }
        } elsif ($start2read == 1) { # memorizzo in un array il nome dei campi
            $newline =~ s/ //g;
            $newline = 'atom_ndx' if ($newline =~ /^#/);
            push(@header, $newline);
        } elsif ($start2read == 2) {
            # ripulisco le righe di interesse di spazi inutili
            $newline =~ s/^[ ]+//;
            $newline =~ s/  / /g;
            
            # parso le righe del file mae come se fossero quelle di un file csv
            my $status = $csv_obj->parse($newline);
            $status and do {
                my @row = $csv_obj->fields();
                
                # converto la riga parsata da array ad hash
                my %hashed;
                foreach my $field (keys %{$fields_of_interest}) {
                    my ($field_label, $field_number) = @{$fields_of_interest->{$field}};
                    $hashed{$field_label} = $row[$field_number];
                }
                
                my $primary_key;
                if ($hashed{'is_ligand'}) {
                    $primary_key = sprintf("LIG_%04d", $hashed{'resi'});
                } else {
                    $primary_key = sprintf("REC_%04d", $hashed{'resi'});
                }
                
                my $atm_num = sprintf("%06d", $hashed{'atom_number'});
                unless (exists $parsed_mae->{$primary_key}) {
                    $parsed_mae->{$primary_key} = {
                        'resn'          => $hashed{'resn'},
                        'Hbond'         => $hashed{'Hbond'},
                        'Coulomb'       => $hashed{'Coulomb'},
                        'Covalent'      => $hashed{'Covalent'},
                        'Packing'       => $hashed{'Packing'},
                        'Lipo'          => $hashed{'Lipo'},
                        'dG(NS)'        => $hashed{'dG(NS)'},
                        'Solv_GB'       => $hashed{'Solv_GB'},
                        'vdW'           => $hashed{'vdW'},
                        'SelfCont'      => $hashed{'SelfCont'},
                        'atoms'         => {
                            $atm_num => [
                                $hashed{'coord_x'},
                                $hashed{'coord_y'},
                                $hashed{'coord_z'}
                            ]
                        }
                    };
                } else {
                    $parsed_mae->{$primary_key}->{'Hbond'}      += $hashed{'Hbond'};
                    $parsed_mae->{$primary_key}->{'Coulomb'}    += $hashed{'Coulomb'};
                    $parsed_mae->{$primary_key}->{'Covalent'}   += $hashed{'Covalent'};
                    $parsed_mae->{$primary_key}->{'Packing'}    += $hashed{'Packing'};
                    $parsed_mae->{$primary_key}->{'Lipo'}       += $hashed{'Lipo'};
                    $parsed_mae->{$primary_key}->{'dG(NS)'}     += $hashed{'dG(NS)'};
                    $parsed_mae->{$primary_key}->{'Solv_GB'}    += $hashed{'Solv_GB'};
                    $parsed_mae->{$primary_key}->{'vdW'}        += $hashed{'vdW'};
                    $parsed_mae->{$primary_key}->{'SelfCont'}   += $hashed{'SelfCont'};
                    $parsed_mae->{$primary_key}->{'atoms'}->{$atm_num} = [
                        $hashed{'coord_x'},
                        $hashed{'coord_y'},
                        $hashed{'coord_z'}
                    ];
                }
            };
        } else {
            next;
        }
    }
    close MAE;
}

DISTANCE: { # calcolo quanto ogni residuo è distante dal ligando
    printf("\n%s calculating distances\n", clock());
    my $lig_coords = { };
    my $rec_coords = { };
    foreach my $primary_key (keys %{$parsed_mae}) {
        my $residue = $parsed_mae->{$primary_key};
        foreach my $secondary_key (keys %{$residue->{'atoms'}}) {
            my $index = $primary_key . '_' . $secondary_key;
            if ($primary_key =~ /^REC_/) {
                $rec_coords->{$index} = [ @{$residue->{'atoms'}->{$secondary_key}} ];
            } elsif ($primary_key =~ /^LIG_/) {
                $lig_coords->{$index} = [ @{$residue->{'atoms'}->{$secondary_key}} ];
            }
        }
    }
    
    foreach my $lig_key (keys %{$lig_coords}) {
        my ($x1, $y1, $z1) = @{$lig_coords->{$lig_key}};
        foreach my $rec_key (keys %{$rec_coords}) {
            my ($x2, $y2, $z2) = @{$rec_coords->{$rec_key}};
            my $dx = ($x1-$x2)**2;
            my $dy = ($y1-$y2)**2;
            my $dz = ($z1-$z2)**2;
            my $dist = sqrt($dx + $dy + $dz);
            my ($index) = $rec_key =~ /^(REC_\d+)_\d+/;
            if (exists $distances->{$index}) {
                $distances->{$index} = $dist
                    if ($dist < $distances->{$index});
            } else {
                $distances->{$index} = $dist;
            }
        }
    }
}

OUTFILE: { # scrivo il csv filtrato sulla shell
    printf("\n%s writing output file\n", clock());
    open(CSV, '>' . "$basename.csv");
    my @cols = ('dG(NS)','Hbond','Coulomb','Packing','vdW','Lipo','Solv_GB','Covalent','SelfCont');
    my $header = sprintf("resi;resn;dist;%s\n", join(';',@cols));
    print CSV $header;
    foreach my $key (sort keys %{$distances}) {
        if ($distances->{$key} < $shell) {
            my ($resnum) = $key =~ /^REC_0*(\d+)$/;
            my $row = sprintf("%s;%s;%.3f", $resnum, $parsed_mae->{$key}->{'resn'}, $distances->{$key});
            foreach my $col (@cols) {
                my $value = $parsed_mae->{$key}->{$col};
                $value = sprintf("%.3f", $value)
                    if ($value =~ /^[e\d\-\.]+$/);
                $row .= ";$value";
            }
            $row .= "\n";
            print CSV $row;
        }
    }
    close CSV;
}

FINE: {
    print "\n*** THAT'S ALL ***\n";
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

