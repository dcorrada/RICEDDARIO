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
our %options= ( );
use Cwd;
use Carp;

USAGE: {
    use Getopt::Std;no warnings;
    getopts('i:r:p:h', \%options);
    my $usage = <<END
SYNOPSYS
  $0 <-i pattern> <-r pattern> [-p pattern]

  Questo script crea le cartelle dove verrano lanciati job di bowtie.
  In ogni cartella  viene inoltre creato shell script per il lancio
  di bowtie con i parametri necessari

OPTIONS
  -i pattern    pattern di ricerca per gli index file
  -r pattern    pattern di ricerca per il primo set di reads file
  -p pattern    pattern di ricerca per il secondo set di reads file, nel caso di paired reads
  
  ATTENZIONE: il carattere di protezione \\ (backslash) usato nelle
  stringhe in questo caso diventa \\\\ (doppio backslash).

  es.: "\\\\d+" individua stringhe con almeno un carattere numerico
       (invece di usare "\\d+")
END
    ;
    if (($options{h})||(!$options{i})||(!$options{r})) { print $usage; exit; }
}

#######################
## VARIABILI GLOBALI ##
our $inputs = { index_basenames => [], # lista degli index_basename di bowtie
                fastq_reads_A => [], # lista di file contenente le reads
                fastq_reads_B => [], # seconda lista di file (nel caso di paired reads)
                bowtie_bin => '', # path del file binario bowtie (cerca automaticamente il file se non specificato)
              };
our $working_dir = getcwd();
#######################

FILE_CHECK: {
    my ($dh, @file_list, $path, $pattern);
    
    # prima controllo che il path di bowtie sia corretto...
    chomp($inputs->{bowtie_bin} = qx/which bowtie/) unless ($inputs->{bowtie_bin});
    croak ("\n-- ERROR bowtie binary file <$inputs->{bowtie_bin}> non trovato\n") unless (-e $inputs->{bowtie_bin});
    
    READS_A: { # poi controllo il pattern dei file delle reads_A 
        if ($options{r} =~ /\//) {
            ($path) = $options{r} =~ /(.*)\/.*$/g;
            croak ("\n-- ERROR path <$path> non trovato\n") unless (chdir $path);
        };
        $path = getcwd; chdir $working_dir;
        opendir ($dh, $path);
        @file_list = readdir($dh);
        closedir $dh;
        ($pattern) = $options{r} =~ /([^\/]*)$/g;
        @file_list = grep /$pattern/, @file_list or croak "\n-- ERROR pattern dei file delle reads_A <$options{r}> non trovato\n";
        @{$inputs->{fastq_reads_A}} = map { $path.'/'.$_} @file_list;
    }
    
    READS_B: { # poi controllo il pattern dei file delle reads_B (caso paired reads)
        ($options{p}) and do {
            if ($options{p} =~ /\//) {
                ($path) = $options{p} =~ /(.*)\/.*$/g;
                croak ("\n-- ERROR path <$path> non trovato\n") unless (chdir $path);
            };
            $path = getcwd; chdir $working_dir;
            opendir ($dh, $path);
            @file_list = readdir($dh);
            closedir $dh;
            ($pattern) = $options{p} =~ /([^\/]*)$/g;
            @file_list = grep /$pattern/, @file_list or croak "\n-- ERROR pattern dei file delle reads_B <$options{p}> non trovato\n";
            @{$inputs->{fastq_reads_B}} = map { $path.'/'.$_} @file_list;
        }
    }
    
    INDEX: {# poi controllo il pattern degli index file
        if ($options{i} =~ /\//) {
            ($path) = $options{i} =~ /(.*)\/.*$/g;
            croak ("\n-- ERROR path <$path> non trovato\n") unless (chdir $path);
        };
        $path = getcwd; chdir $working_dir;
        opendir ($dh, $path);
        @file_list = readdir($dh);
        closedir $dh;
        ($pattern) = $options{i} =~ /([^\/]*)$/g;
        @file_list = grep /$pattern\.rev\.1\.ebwt$/, @file_list # cerco una caratteristica dell'index set, ad es. il file che termina come .rev.1.ebwt
                or croak "\n-- ERROR pattern degli index file <$options{i}> non trovato\n";
        @{$inputs->{index_basenames}} = map { my ($a) = $_ =~ /([\w\+\-\.]+)\.rev\.1\.ebwt$/;
                                              $a = $path.'/'.$a} @file_list;
    }
}



chdir $working_dir;

if (@{$inputs->{fastq_reads_B}}) {
    print "Paired read job\n";
} else {
    foreach my $index_ebwt  (@{$inputs->{index_basenames}}) {
        my $reads = join(',', @{$inputs->{fastq_reads_A}});
        my ($output_dir) = $index_ebwt =~ m/([\w\-\+\.]+)$/;
        mkdir $output_dir;
        chdir "$working_dir/$output_dir";
        sh_builder("$working_dir/$output_dir", $index_ebwt, $reads );
        chdir "$working_dir";
        print "-- JOB <$output_dir> creato\n";
    }
}

#~ print Dumper ($inputs);

exit;

sub sh_builder {
    my ($path, $index_ebwt, $reads_A, $reads_B) = @_; # working_dir, index_basename, reads_A filename, reads_B filename
    
    # array contenente le singole righe del file launch_bowtie.sh
    my @file_content = ('#!/bin/sh', "");
    push @file_content, "echo \"\n-------------------------------------\" >> $path/run.log";
    push @file_content, "date >> $path/run.log";
    push @file_content, "echo \"BOWTIE mapping avviato...\" >> $path/run.log";
    push @file_content, "echo \"-------------------------------------\n\" >> $path/run.log";
    if ($reads_B) {
        print "Paired read job\n";
    } else {
        ################ command line di bowtie, da modificare all'occorrenza...
        push @file_content, "$inputs->{bowtie_bin} -t -n2 -q -p4 --best -B1 --al '$path/aligned.fastq' --un '$path/unaligned.fastq' '$index_ebwt' '$reads_A' '$path/output.map' >> $path/run.log 2>&1";
    }
    push @file_content, "echo \"\n-------------------------------------\" >> $path/run.log";
    push @file_content, "date >> $path/run.log";
    push @file_content, "echo \"BOWTIE mapping terminato\" >> $path/run.log";
    push @file_content, "echo \"-------------------------------------\n\" >> $path/run.log";
    @file_content = map "$_\n", @file_content;

    my $fh;open($fh, ">launch_bowtie.sh") or croak ("\nImpossibile aprire il file <launch_bowtie.sh>");
    print $fh @file_content;
    system "chmod +x launch_bowtie.sh";
    close $fh;

}
