#!/usr/bin/perl

#Tristan Lefebure, Feb12 2009, Licenced under the GPL

use warnings;
use strict;
use Bio::AlignIO;
use Bio::SeqIO;
use Getopt::Long;

my $list;
my $ext = '.fasta';
my $format = 'phylip';

GetOptions (	'l' => \$list,
		'ext=s' => \$ext,
		'format=s' => \$format,
	);


if($#ARGV<0) {
	print "Usage $0 <file to convert>
Options:
\t-l, the file is a list of file to be processed [False]
\t-ext .xxx, gives the extension added to the output files [.fasta]\n
\t-format xxx, gives the format of the alignment [phylip]\n";
	exit;
}


###file or list of files
my @files;
if($list) {
	open IN, $ARGV[0];
	@files = <IN>;}
else {
	$files[0] = $ARGV[0];
}

###open the alignment(s) print the fasta files

foreach (@files) {
	chomp;
	my $in  = Bio::AlignIO->new(-file => $_, -format => $format);
	my $out = Bio::SeqIO->new(-file => ">$_${ext}", -format => 'fasta');
	while ( my $aln = $in->next_aln() ) {
		#foreach seq in the aln, write it in the output
		foreach my $seq ( $aln->each_seq() ) {
			$out->write_seq($seq);
		}
	}
}




