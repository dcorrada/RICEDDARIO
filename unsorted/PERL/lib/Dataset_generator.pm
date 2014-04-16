# *** GENERATORE SEQUENZE RANDOM ***

package my_PERL::misc::Dataset_generator;

use warnings;
use strict;

# Array contenente la lista degli elementi casuali che andranno a
# comporre le sequenze generate (ad es. basi nucleotidiche)
@Dataset_generator::list_elements = ('A', 'T', 'G', 'C');


# store (\@sequences)
#
# Archivia il dataset in un file

sub store {

    my ($ref) = @_;
    my @inputarray = @$ref;

    open (NEWFILE, ">dataset.txt");
    for (my $i=0; $i<scalar @inputarray; $i++) {
        print NEWFILE $inputarray[$i]."\n";
    }
    close NEWFILE;

}

# dataset ($min, $max, $num_seqs)
#
# Genera un set di sequenze di DNA casuali, a partire da un range
# di dimensioni di sequenza prefissato.

sub dataset {
    
    my ($min, $max, $num_seqs) = @_;
    my @dataset;
    
    for (my $i=0; $i<$num_seqs; $i++) {
        my $seq_length = int(rand($max-$min+1)) + $min;
        push(@dataset, sequence($seq_length));
    }
    
    return @dataset;

}


# sequence ($seq_length)
#
# Genera una sequenza random di una lunghezza stabilita

sub sequence {
   
   my ($seq_length) = @_;
   my $sequence;
   
   for (my $i=0; $i<$seq_length; $i++) {
       $sequence .= element(\@Dataset_generator::list_elements);
   }
   
   return $sequence;
   
}


# element(\@list)
#
# Genera una elemento casuale dalla lista @Dataset_generator::list_elements

sub element {
    
    my ($ref) = @_;
    my @elements_list = @$ref;
    
    my $newelement = $elements_list[int(rand(scalar(@elements_list)))];
    
    return $newelement;

}


1;
