#!/usr/bin/perl
#~ -d

use strict;
use warnings;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| = 1;

# paths di librerie personali
use lib $ENV{HOME};

###################################################################

use RICEDDARIO::lib::FileIO;
my $file_obj = RICEDDARIO::lib::FileIO->new();


my $path = '/home/korda/Scrivania/Profili_exp_mouse/';
my $ref_array = $file_obj->read($path.'exp_values.csv');

my @non_zeros;

foreach my $newline (@$ref_array) {
    chomp $newline;
    my @values = split (';', $newline);
    foreach (@values) {
        push (@non_zeros, $_."\n") unless ($_ == 0);
    }
}

my $sorted = [ ];
@$sorted = sort {$a <=> $b} @non_zeros;


print @$sorted;

$file_obj->write(filedata => $sorted, filename => $path.'exp_values_sorted.csv');

exit;
