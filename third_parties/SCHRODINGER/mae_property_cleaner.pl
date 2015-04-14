#!/usr/bin/perl
# -d

# ########################### RELEASE NOTES ####################################
#
# release 15.04.a    -  initial release
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
use Cwd;
use Carp;

## GLOBS ##

our $maebin = $ENV{RICEDDARIOHOME} . '/third_parties/SCHRODINGER' . '/delete_properties.py';
our $maepython = $ENV{SCHRODINGER} . '/run';

## SBLOG ##

USAGE: {
    my $header = <<ROGER
********************************************************************************
mae_property_cleaner
release 15.04.a

Copyright (c) 2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
ROGER
    ;
    print $header;
    
    unless ($ARGV[0]) {
        my $spiega = <<ROGER

This script reads a mae or maegz file and delete any property.

*** SYNOPSIS ***
    
    \$ mae_property_cleaner.pl input.mae
ROGER
        ;
        print $spiega;
        goto FINE;
    }
}

MAINSTREAM: {
    my ($basename) = $ARGV[0] =~ /(.*)\.(mae|maegz)$/;
    
    # rimuovo tutte le property
    my $cmdline = "$maepython $maebin $ARGV[0] $basename-tempus.mae";
    qx/$cmdline/;
    
    # rimozione manuale di s_m_title
    open(INMAE, '<' . "$basename-tempus.mae");
    my $flag = 'null';
    my $outcontent = '';
    while (my $newline = <INMAE>) {
        chomp $newline;
        if ($flag =~ /f_m_ct/) {
            if ($flag =~ /f_m_ct:::/) {
                $outcontent .= ' "" ' . "\n";
                $flag = 'null';
            } elsif ($newline =~ /^ :::/) {
                $flag .= ':::';
                $outcontent .= $newline . "\n";
            } else {
                $outcontent .= $newline . "\n";
            }
        } else {
            $flag = 'f_m_ct' if ($newline =~ /^f_m_ct/);
            $outcontent .= $newline . "\n";
        }
    }
    close INMAE;
    
    open(OUTMAE, '>' . "$basename-cleaned.mae");
    print OUTMAE $outcontent;
    close OUTMAE;
    print "[$basename-cleaned.mae] written\n";
    
    # cancello il file intermedio
    unlink "$basename-tempus.mae";
}

FINE: {
    print "\n*** renaelc_ytreporp_eam ***\n";
    exit;
}
