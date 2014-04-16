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
use RICEDDARIO::lib::FileIO;

#######################
## VARIABILI GLOBALI ##
our $working_dir = getcwd();
our ($pdbfile, $logfile);
our $protein = { };
our $aminoacids = { # set di amminoacidi con i tipi atomici consentiti
    'ALA' => ['N', 'CA', 'C', 'O', 'CB'],
    'ARG' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'CD', 'NE', 'CZ', 'NH1', 'NH2'],
    'ASN' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'OD1', 'ND2'],
    'ASP' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'OD1', 'OD2'],
    'CYS' => ['N', 'CA', 'C', 'O', 'CB', 'SG'],
    'GLY' => ['N', 'CA', 'C', 'O'],
    'GLN' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'CD', 'OE1', 'NE2'],
    'GLU' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'CD', 'OE1', 'OE2'],
    'HIS' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'ND1', 'CD2', 'CE1', 'NE2'],
    'ILE' => ['N', 'CA', 'C', 'O', 'CB', 'CG1', 'CG2', 'CD1'],
    'LEU' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'CD1', 'CD2'],
    'LYS' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'CD', 'CE', 'NZ'],
    'MET' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'SD', 'CE'],
    'PHE' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'CD1', 'CD2', 'CE1', 'CE2', 'CZ'],
    'PRO' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'CD'],
    'SER' => ['N', 'CA', 'C', 'O', 'CB', 'OG'],
    'THR' => ['N', 'CA', 'C', 'O', 'CB', 'OG1', 'CG2'],
    'TRP' => ['N', 'CA', 'C', 'O', 'CB', 'CD1', 'CD2', 'NE1', 'CE2', 'CE3', 'CZ2', 'CZ3', 'CH2'],
    'TYR' => ['N', 'CA', 'C', 'O', 'CB', 'CG', 'CD1', 'CD2', 'CE1', 'CE2', 'CZ', 'OH'],
    'VAL' => ['N', 'CA', 'C', 'O', 'CB', 'CG1', 'CG2']
    };

#######################


USAGE: {
    my $options = { };
    use Getopt::Long;no warnings;
    GetOptions($options, 'help|h', 'file|f=s');
    my $usage = <<END

SYNOPSYS

  $0 -f string

Questo script si occupa di parsare un file PDB e valutare eventuali
- inserzioni;
- delezioni;
- discontinuita' nella numerazione dei residui;
- missing atoms;
- residui in posizioni alternative.
Restituisce il tutto in un file di log

OPZIONI

  -f <string>       INPUT, PDB filename
END
    ;
    if (exists $options->{'help'}) { print $usage; exit; };
    
    if (exists $options->{'file'}) { $pdbfile = $options->{'file'}
    } else { print $usage; exit; }
}

FILECHECK: {
    croak("\nE- file [$pdbfile] not found\n\t") unless (-e $pdbfile);
    $logfile = $pdbfile;
    $logfile =~ s/pdb$/log/;
    
    open(LOG, '>', $logfile);
    print LOG "*** LOGFILE OF <$pdbfile> ***\n";
    close LOG;
}

PARSER: { # individuo e recupero informazioni da ogni catena
    print "\nParsing <$pdbfile>...";
    open(PDB, '<', $pdbfile);
    while (1) {
        my $record = <PDB>;
        if ($record =~ m/^ATOM /) { # leggo solo la parte inerente le coordinate atomiche
            chomp $record;
            # splitto il record "ATOM"
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $record);
            # Gli elementi del vettore da considerare sono
            # [1]   Atom serial number
            # [3]   Atom name
            # [4]   Alternate location indicator
            # [5]   Residue name
            # [7]   Chain identifier
            # [8]   Residue sequence number
            # [9]   Code for insertion of residues
            # [10-12] XYZ cpoordinates
            # [14]  Tfactor
            
            my $chain = $splitted[7];
            unless (exists $protein->{$chain}) { # definisco una nuova catena
                $protein->{$chain} = { };
            }
            my $resid = sprintf("%04d%s%s", $splitted[8], $splitted[9], $splitted[4]);
            unless (exists $protein->{$chain}->{$resid}) { # definisco un nuovo residuo
                $protein->{$chain}->{$resid} = {
                    'chain' => $splitted[7],
                    'number' => '',
                    'type' => $splitted[5],
                    'insertion' => '',
                    'alternate' => '',
                    'atoms' => { }
                };
                $protein->{$chain}->{$resid}->{'insertion'} = $splitted[9]
                    if ($splitted[9] !~ m/^ $/);
                $protein->{$chain}->{$resid}->{'alternate'} = $splitted[4]
                    if ($splitted[4] !~ m/^ $/);
                ($protein->{$chain}->{$resid}->{'number'}) = $splitted[8] =~ m/(\d+)/;
            }
            
            my ($atomname) = $splitted[3] =~ m/(\w+)/;
            $protein->{$chain}->{$resid}->{'atoms'}->{$atomname} = 1;
        }
    } continue {
        if (eof(PDB)) {close PDB; last;};
    }
    print "done";
}


ANALISYS: { # analizzo ogni catena
    open(LOG, '>>', $logfile);
    
    foreach my $chain (keys %{$protein}) {
        print LOG "\n-- CHAIN [$chain]\n\n";
        print "\n-- CHAIN [$chain]";
        GAPS: { # cerco i gaps
            print "\nSearching gaps...";
            my $found = 0;
            my @sequence = sort(keys %{$protein->{$chain}});
            
            my $counter = shift(@sequence);
            while (my $resid = shift(@sequence)) {
                my %prev = %{$protein->{$chain}->{$counter}};
                my %next = %{$protein->{$chain}->{$resid}};
                next if ($next{'insertion'});
                next if ($next{'alternate'} && $next{'alternate'} !~ m/^A$/);
                unless ($next{'number'} == $prev{'number'} + 1) {
                    print LOG "-W GAP BETWEEN [$prev{type}$prev{'number'}]<-->[$next{type}$next{'number'}]\n";
                    $found = 1;
                }
                $counter = $resid;
            }
            $found and print LOG "\n";
            print "done";
        }
        
        my %peptide = %{$protein->{$chain}};
        INSERTIONS: { # cerco i residui con numerazione alternativa
            print "\nSearching insertions...";
            my $found = 0;
            foreach my $resid (sort(keys %peptide)) {
                if ($peptide{$resid}->{'insertion'}) {
                    my $resname = $peptide{$resid}->{'type'} . $peptide{$resid}->{'number'} . $peptide{$resid}->{'insertion'};
                    print LOG "-W INSERTION [$resname]\n";
                    $found = 1;
                }
            }
            $found and print LOG "\n";
            print "done";
        }
        
        ALTERNATES: { # cerco i residui con conformazioni alternative
            print "\nSearching alternates...";
            my $found = 0;
            my %alternate_list;
            foreach my $resid (sort(keys %peptide)) {
                if ($peptide{$resid}->{'alternate'}) {
                    my $resname = $peptide{$resid}->{'type'} . $peptide{$resid}->{'number'} . $peptide{$resid}->{'insertion'};
                    next if (exists $alternate_list{$resname});
                    print LOG "-W ALTERNATIVE CONF [$resname]\n";
                    $alternate_list{$resname} = 1;
                    $found = 1;
                }
            }
            $found and print LOG "\n";
            print "done";
        }
        
        MISSING: { # cerco i missing atoms
            print "\nSearching missing atoms...";
            foreach my $resid (sort(keys %peptide)) {
                my $found = 0;
                my $resname = $peptide{$resid}->{'type'} . $peptide{$resid}->{'number'} . $peptide{$resid}->{'insertion'};
                my $restype = $peptide{$resid}->{'type'};
                my %atoms = %{$peptide{$resid}->{'atoms'}};
                foreach my $check (@{$aminoacids->{$restype}}) {
                    unless (exists $atoms{$check}) {
                        print LOG "-W MISSING ATOM [$check] FOR [$resname]\n";
                        $found = 1;
                    }
                }
                $found and print LOG "\n"; 
            }
            print "done";
        }
    }
    
    close LOG;
}


# print Dumper $protein;

FINE: {
    print "\n---\nFINE PROGRAMMA\n";
    exit;
}
