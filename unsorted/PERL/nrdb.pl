#!/usr/bin/perl
#
# nrdb.pl   Builds non-redundant fasta format databases 
#           (peptide or nucleotide)
#
# USAGE:
#
#       nrdb.pl -p [options] file1 id1 [file2 id2 [file3 id3 ...]]
#   Or
#       nrdb.pl  [options] file1 [file2 [file3 ...]]
#
# where options are:
#
#      -h             -- print usage
#      -o filename    -- name of output file (default is nrdb.out)
#      -s filename    -- name of statistics file (default is nrdb.stats)
#      -l#            -- min. required sequence length (default is 3)
#      -p             -- use id prefixes on command line
#
# Each file# argument is the name of an input file in FASTA format.
# Each id# (identifier) argument is a character string to be prepended 
#      to each sequence name read from the corresponding input file.
#
# Example:
#
#   $ nrdb.pl -p -l3 -o protein.nrdb -s NRP.stats uniprot_sp.seq UPSP \
#   > uniprot_tr.seq UPTR uppeptgb.seq GPN peptgb.seq GP pdbseq.seq 3D
#
#    The basic idea behind this script is very simple.  Instead of having a 
# hash with entry ID and description as the key and the entry sequence as 
# the value: ( ID_desc => sequence ), just invert it so that the sequence 
# serves as the key and the ID and description as the value: 
# ( sequence => ID_desc ).
#
#    Then just read each entry into the hash.  When a sequence (key) is 
# already in the hash, the new one just overwrites with the new ID and 
# description (value).  After all the entries have been read in, the hash 
# contains a non-redundant set of sequences!
#
#    I modified this idea slightly so that if a sequence is already in the 
# hash, I don't overwrite the current ID and description with the new one, 
# just "discard" the new one.  I do it this way because of the order in 
# which the input files are read in.  That is from files with possibly better 
# annotation and longer descriptions to files with lesser annotation.
#
# NOTES: 
#      Hashes are unordered so I sort the hash on the ID before writing them
# to the output file.
#      This works for large files if you have enough memory, and you have a
# 64-bit perl.
#
#     ****************************************
#     *               © 2006                 *
#     *           Gary W. Smythers           *
#     * Advanced Biomedical Computing Center *
#     *                SAIC                  *
#     ****************************************
#
# -----------------------------------------------------------------
# | Gary W. Smythers  [Contractor]       | email: gws@ncifcrf.gov |
# | Programmer Anaylst IV                |                        |
# | Advanced Biomedical Computing Center | Phone: (301) 846-5778  |
# | SAIC NCI-Frederick                   | FAX:   (301) 846-5762  |
# | PO Box B, Bldg 430                   |                        |
# | Frederick, MD 21702-1201   USA       |                        |
# -----------------------------------------------------------------

use strict;
use integer;
use Getopt::Std;

my $Usage= "
 Usage: 

       $0 -p [options] file1 id1 [file2 id2 [file3 id3 ...]]
   Or
       $0 [options] file1 [file2 [file3 ...]]

 where options are:

      -h             -- print usage
      -o filename    -- name of output file
      -s filename    -- name of statistics file
      -l#            -- min. required sequence length
      -p             -- use id prefixes on command line

";

my %options=();

my @PFile = ();  # Input file names
my %PID = ();    # Input file name => ID prefix

my $MinL = 0;    # Minimum length of an entry sequence

my $PName = "";
my $PNameIn = "";
my $PNameOut = "";
my $StatFile = "";

my $desc = "";
my $seq = "";
my %NRDB = ();   # Hash of sequence => ID

my %SRead = ();  # Number of seqs read for each input file
my %SWrite = (); # Number of seqs written for each input file
my %SDup = ();   # Number of duplicate seqs for each input file
my %SShort = (); # Number of seqs less than min length for each input file
my $TRead = 0;   # Total seqs read
my $TWrite = 0;  # Total seqs written
my $TDup = 0;    # Total duplicate seqs
my $TShort = 0;  # Total seqs less than min length

my $Lsize = 60;  # Seq line output size
my $FullL = "";  # Number of full length seq output lines for an entry
my $LastL = "";  # Length of last seq output line for an entry
my $Lout = "";   # Line to be written out
my $i = "";


getopts('o:s:l:ph', \%options);

$PNameOut = $options{o} || "nrdb.out";
$StatFile = $options{s} || "nrdb.stats";
$MinL = $options{l} || 3;
 
if ( $options{h} ) { print $Usage; exit; }
 
if ( ! $options{p} )
  {
    if ($#ARGV > -1) 
      {
       while ( $#ARGV > -1 ) 
         {
            push(@PFile,shift); $PID{$PFile[$#PFile]} = ">"; 
         }
      }
    else { print $Usage; exit; }
  }
elsif ( ($#ARGV > -1) && ($#ARGV % 2 == 1) )  # An even number of arguments
  {
    while ( $#ARGV > -1 ) 
      {  push(@PFile,shift); 
         $PID{$PFile[$#PFile]} = shift;
         $PID{$PFile[$#PFile]} = ">" . $PID{$PFile[$#PFile]} . ":";
      }
  }
else { print $Usage; exit; }

foreach $PNameIn (@PFile)
  {
    open (INF,"${PNameIn}") || die "\nCan't open ${PNameIn} : $!\n\n";
    $SRead{$PNameIn} = 1;
    $SWrite{$PNameIn} = 0;
    chomp($desc = <INF>);
    $desc = $PID{$PNameIn} . substr($desc,1);
    $seq = "";

    while(<INF>)
      {
        chomp;
        if ( /^>/ )
          { 
            $SRead{$PNameIn}++;
            if (length($seq) < $MinL) { $SShort{$PNameIn}++; }
            else
              {
               if ( ! exists $NRDB{$seq} ) 
                 { 
                   $NRDB{$seq} = $desc; 
                   $SWrite{$PNameIn}++;
                 }
              }
            $seq = "";
            $desc = $PID{$PNameIn} . substr($_,1);
          }
        else { $seq .= $_ ; }
      }
    close(INF);
                    # Process the last sequence from the file
    if (length($seq) < $MinL) { $SShort{$PNameIn}++; }
    else
      {
       if ( ! exists $NRDB{$seq} )
         { 
           $NRDB{$seq} = $desc; 
           $SWrite{$PNameIn}++;
         }
      }

  }

open (OUTF, ">$PNameOut") || die "Can't open $PNameOut : $!\n";

foreach $seq ( sort {$NRDB{$a} cmp $NRDB{$b}} keys %NRDB )
  {
     print OUTF "$NRDB{$seq}\n";
        
     $FullL = length($seq) / $Lsize;
     $LastL = length($seq) % $Lsize;

     for ($i=1; $i<=$FullL; $i++)
        {
          $Lout = substr($seq,($i*$Lsize)-($Lsize),$Lsize);
          print OUTF "$Lout\n";
        }
     if ( ! $LastL == 0 )
	{
          $Lout = substr($seq,-($LastL));
          print OUTF "$Lout\n";
        }

  }

close(OUTF);

open (STATF, ">$StatFile") || die "Can't open $StatFile : $!\n";

print STATF " Progressive Statistics:\n";
print STATF "                                   Sequences\n";
print STATF "                       -------------------------------------\n";
print STATF "Database               ";
print STATF "Read  Duplicates  length<3    Written\n";
print STATF "------------------------------------------------------------\n";

foreach $PNameIn (@PFile)
  {
     $PName = substr($PNameIn,rindex($PNameIn,"/")+1);     
     printf STATF "%-18s %8d   ", $PName,$SRead{$PNameIn};

     $SDup{$PNameIn} = $SRead{$PNameIn}-$SWrite{$PNameIn}-$SShort{$PNameIn};
     printf STATF "%8d   ", $SDup{$PNameIn};
     printf STATF "%8d   ", $SShort{$PNameIn};     
     printf STATF "%8d\n", $SWrite{$PNameIn};

     $TRead += $SRead{$PNameIn}; $TWrite += $SWrite{$PNameIn};
     $TDup += $SDup{$PNameIn}; $TShort += $SShort{$PNameIn};
  }

printf STATF "\n%-18s %8d   %8d   %8d   %8d\n", 
             "Totals:",$TRead,$TDup,$TShort,$TWrite;

close(STATF);
