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

our $infile_csv;
our $infile_pdb;
our $outfile_pdb;

our %csv_content;

INIT: {
    my $splash = <<END
********************************************************************************
PDB_colorize
release 15.10.a

Copyright (c) 2015, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
END
    ;
    print $splash;
    my $usage = <<END

This script overwrite the b-factor column of a PDB file using the values 
tabulated in a CSV file.

SYNOPSIS
    
    \$ PDB_colorize.pl <pdb_file> <csv_file>
END
    ;
    
    unless ($ARGV[0] and $ARGV[1]) {
        print $usage;
        goto FINE;
    }
    
    for my $filename ($ARGV[0], $ARGV[1]) {
        if ($filename =~ /\.pdb$/) {
            $infile_pdb = $filename;
            $filename =~ s/\.pdb$/\.colorized\.pdb/;
        $outfile_pdb = $filename;
        } elsif ($filename =~ /\.csv$/) {
            $infile_csv = $filename;
        } else {
            croak("\nE- [$filename] unknown file format\n\t");
        }
    }
    
}

READCSV: {
    open (CSVIN, '<' . $infile_csv) or
        croak "E- unable to read [infile_csv]\n\t";
    
    while (my $newline = <CSVIN>) {
        chomp $newline;
        my @fields = split(';', $newline);
        $csv_content{ $fields[0] . $fields[1] } = $fields[2];
    }
    
    close CSVIN;
}

IOPDB: {
    open (PDBIN, '<' . $infile_pdb) or
        croak "E- unable to read [$infile_pdb]\n\t";
    open (PDBOUT, '>' . $outfile_pdb) or
        croak "E- unable to read [$outfile_pdb]\n\t";
        
    while (my $newline = <PDBIN>) {
        chomp $newline;
        if ($newline =~ /^ATOM/) {
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
            
            my $key = $splitted[7] . $splitted[8];
            $key =~ s/\s//g;
            
            if (exists $csv_content{$key}) {
                my $svalue = sprintf("%.2f", $csv_content{$key});
                $splitted[15] = sprintf("% 6s", $svalue);
            }
            
            $newline = join('', @splitted);
        }
        
        print PDBOUT "$newline\n";
    }
    
    close PDBIN;
    close PDBOUT;
    
    print "\nI- file [$outfile_pdb] written";
}

FINE: {
    print "\n\n*** eziroloc_BDP ***\n";
    exit;
}