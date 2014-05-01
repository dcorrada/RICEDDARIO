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

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;

###################################################################
# Questo script crea le cartelle dove verrano lanciati  job di maq.
# In ogni cartella creata vengono inseriti i link simbolici dei files
# fastA e fastQ coinvolti; viene inoltre creato il file <launch_pipeline.sh>
# uno shell script che chiama maq_pipeline.pl con i parametri necessari
use Carp;

our $paths = { # path dove risiedono i file fastA/Q
               fasta => '/home/share/dario/maptest/inputs',
               fastq => '/home/share/dario/maptest/inputs' };

our $file_list = { # lista dei nomi dei file fastA/Q
               fasta => [ 'hg18.fa', ],
## K562_single_rep2 fastQ file list
               fastq => [ 'reads.fastq', ] };

our $working_dir = '/home/share/dario/maptest'; # path di output

our $maq_pipeline = '/home/share/dario/maptest/maq_script/maq_pipeline.pl'; # path dello script maq_pipeline.pl

chdir $working_dir;

foreach my $fastq_file (@{$file_list->{fastq}}) {
    foreach my $fasta_file (@{$file_list->{fasta}}) {
        my ($fa) = $fasta_file =~ m/(.+)\.(fa|fas|fasta)$/;
        my ($fq) = $fastq_file =~ m/(.+)\.fastq(\.gz)*$/;
        my $output_dir = "$fa--$fq";
        mkdir $output_dir;
        chdir "$working_dir/$output_dir";
        system "ln -s $paths->{fasta}/$fasta_file";
        system "ln -s $paths->{fastq}/$fastq_file";
        sh_builder("$working_dir/$output_dir", $fasta_file, $fastq_file );
        chdir "$working_dir";
    }
}


exit;
sub sh_builder {
    my ($path, $fa_file, $fq_file) = @_; # output directory, fastA filename, fastQ filename

    # array contenente le singole righe del file maq_pipeline.sh
    my @file_content = ('#!/bin/sh', "");
    push @file_content, "date > $path/maq_pipeline.log";
    push @file_content, "echo \"MAQ pipeline avviata...\" >> $path/maq_pipeline.log";
    push @file_content, "time $maq_pipeline -n 2000000 -a \"$fa_file\" -q \"$fq_file\" -s -d \"$path\" >> $path/maq_pipeline.log 2>> $path/maq_pipeline.log";
    push @file_content, "date >> $path/maq_pipeline.log";
    push @file_content, "echo \"MAQ pipeline terminata\" >> $path/maq_pipeline.log";
    @file_content = map "$_\n", @file_content;

    my $fh;open($fh, ">launch_pipeline.sh") or croak ("\nImpossibile aprire il file <launch_pipeline.sh>");
    print $fh @file_content;
    system "chmod +x launch_pipeline.sh";
    close $fh;

}

