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
# scriptino x creare un csv degli hotspots con le relative frequenze dei tipi di residuo
use SPARTA::lib::FileIO;

my $filename;
my $content = [ ];
my $row;
my $obj = SPARTA::lib::FileIO->new();
my $rpos = { 'IERP' => {}, 'RMRP' => {} };

# carico i csv degli hotspots
my %what = ('ene_hotspots.csv' => 'IERP', 'flu_hotspots.csv' => 'RMRP');
foreach $filename (keys %what) {
    $content = $obj->read($filename);
    while ($row = shift @{$content}) {
        chomp $row;
        my ($rex, $form) = split(';',$row);
        $rpos->{$what{$filename}}->{$rex} = $form;
    }
}

# carico il csv delle crossrefs
$content = $obj->read('CROSSREFS.csv');
shift @{$content};
my $occurs = { };
while ($row = shift @{$content}) {
    chomp $row;
    my @cells = split(';',$row);
    my $pos = shift @cells;
    $occurs->{$pos} = { };
    while (my $cell = shift @cells) {
        my ($res) = $cell =~ m/(\w{3})$/;
        next if ($res eq 'ull');
        if (exists $occurs->{$pos}->{$res}) {
            $occurs->{$pos}->{$res}++;
        } else {
            $occurs->{$pos}->{$res} = 1;
        }
    } 
}

# sorting delle occorrenze
foreach my $pos (keys %{$occurs}) {
    my %list = %{$occurs->{$pos}};
    my @array;
    foreach my $res (keys %list) {
        my $string = sprintf("%02d;%s",$list{$res},$res);
        push(@array,$string);
    }
    $occurs->{$pos} = [  ];
    @{$occurs->{$pos}} = sort {$b cmp $a} @array;
}

# scrivo il file di output
$obj->set_filename('HOTSPOTS.csv');
$content = [ ];
foreach my $rp (keys %{$rpos}) {
    foreach my $rex (keys %{$rpos->{$rp}}) {
        my $form = $rpos->{$rp}->{$rex};
        my @spec = @{$occurs->{$rex}};
        my $string = "$rp;$form;$rex;";
        while (my $elem = shift @spec) {
            my ($tot,$res) = split(';', $elem);
            $string .= "$res($tot),";
        }
        $string =~ s/,$/\n/;
        push(@{$content},$string);
    }
}
$obj->set_filedata($content);
$obj->write();

exit;