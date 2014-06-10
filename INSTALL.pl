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
use Cwd;
use Carp;

my $workdir = getcwd();
my ($pruned) = $workdir =~ /(.+)\/RICEDDARIO$/;
my $path_string = <<END

# RICEDDARIO package [https://github.com/dcorrada/RICEDDARIO]
export RICEDDARIOHOME=$workdir
export PERL5LIB=$pruned:\$PERL5LIB
source $workdir/.paths.sh

END
;

# aggiorno il file bashrc
my $bashrc_file = $ENV{HOME} . '/.bashrc';
print "Set your bashrc file [$bashrc_file]: ";
my $ans = <STDIN>; chomp $ans;
$bashrc_file = $ans if ($ans);
open (BASHRC, '>>' . $bashrc_file) or croak("\nE- unable to open <$bashrc_file>\n\t");
print BASHRC $path_string;
close BASHRC;

# recupero esesguibili i vari script
opendir (PATHS, $workdir) or croak("\nE- unable to open <$workdir>\n\t");
my @path_list = readdir PATHS;
closedir PATHS;
while (my $single_path = shift @path_list) {
    
    # paths dedicati
    next if ($single_path eq 'EMMA');
    next if ($single_path eq 'ISABEL');
    next if ($single_path eq 'third_parties');
    
    # paths da escludere
    next if ($single_path eq 'unsorted');
    next if ($single_path eq 'LICENSES');
    next if ($single_path =~ m/^\./);
    
    # paths ancora da sistemare
    next if ($single_path eq 'BRENDA');
    next if ($single_path eq 'MyMir');
    next if ($single_path eq 'SPARTA');
    
#     print "\n[$single_path]";
    if (-d "$workdir/$single_path") {
        system("chmod +x $workdir/$single_path/*.p? &> /dev/null");
    }
}

system("chmod +x $workdir/EMMA/EMMA/bin/*.p?");
system("chmod +x $workdir/EMMA/RAGE/bin/*.p?");
system("chmod +x $workdir/ISABEL/bin/*.p?");
my $path3rd = "$workdir/third_parties";
opendir (PATHS, $path3rd) or croak("\nE- unable to open <$path3rd>\n\t");
@path_list = readdir PATHS;
closedir PATHS;
while (my $single_path = shift @path_list) {
    next if ($single_path =~ m/^\./);
#     print "\n[$single_path]";
    if (-d "$path3rd/$single_path") {
        system("chmod +x $path3rd/$single_path/*.??*");
    }
}

print "All done, please re-source <$bashrc_file>\n";
exit;
