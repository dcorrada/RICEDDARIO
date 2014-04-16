# script per trovare pattern in una sequenza
package consensus;

use strict;
use warnings;

# Leggo gli argomenti in input
$ARGV[0] and $ARGV[1]?
my ($filename, $regexp) = ($ARGV[0], $ARGV[1]) : die("SYNOPSIS: consensus.pl [input_file] [pattern_search]\n");

# Recupero la sequenza dal file FASTA
open (my $fh, $filename) or die("nome di file errato o inesistente...\n");
my @content = <$fh>; shift @content;
my $seq = join('', @content); $seq =~ s/\s//g;
close $fh;

my ($found, @positions);

print "pattern trovati:\n";
while (1) {
    $seq =~ m/$regexp/gi;
    last unless pos($seq);
    $found = pos($seq);
    # per ogni pattern individuato scrivo la sequenza estesa del
    # pattern e la sua posizione sulla sequenza
    printf("%s --> %d\n", $&, $found - length($&));
}

exit;
