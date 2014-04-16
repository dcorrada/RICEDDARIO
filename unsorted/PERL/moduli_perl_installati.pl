#!/usr/bin/perl

use strict;
use warnings;

# Salva la lista in questo file
$0 =~ s/\.pl//g;
open (my $fh, ">$0.txt");

# Fornisce una lista dei moduli aggiuntivi installati.
# I core modules vengono identificati come Perl

use ExtUtils::Installed;

my $inst   = ExtUtils::Installed->new();

my @external_modules = $inst->modules();

print $fh "\n\n*** MODULI AGGIUNTIVI INSTALLATI ***\n\n";
foreach my $newline (@external_modules) {
!($newline =~ m/Perl/) and print $fh "$newline\n";
}


# Fornisce una lista dei moduli del core installati.
 
use Module::CoreList;
 
my @core_modules = Module::CoreList->find_modules(qr/.*/);
 
 
print $fh "\n\n*** MODULI CORE INSTALLATI ***\n\n";
print $fh "$_\n" foreach @core_modules;


close $fh;

exit;
