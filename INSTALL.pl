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

# recupero i vari percorsi degli script
my $workdir = getcwd();
opendir (PATHS, $workdir) or croak("\nE- unable to open <$workdir>\n\t");
my @path_list = readdir PATHS;
closedir PATHS;
my $path_string = "\n\n# RICEDDARIO package [https://github.com/dcorrada/RICEDDARIO]\n";
$path_string .= "# main paths\nexport PATH=";
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
        $path_string .= "$workdir/$single_path:";
        system("chmod +x $workdir/$single_path/*.p? &> /dev/null");
    }
}
$path_string .= "\$PATH\n";

# adding RICEDDARIO's parent path
my ($pruned) = $workdir =~ /(.+)\/RICEDDARIO$/;
$path_string .= "export PERL5LIB=$pruned:$workdir:\$PERL5LIB\n";

# percorsi specifici per EMMA
$path_string .= "# EMMA\n";
$path_string .= "export PATH=$workdir/EMMA/EMMA/bin:$workdir/EMMA/RAGE/bin:\$PATH\n";
$path_string .= "export PERL5LIB=$workdir/EMMA:\$PERL5LIB\n";
system("chmod +x $workdir/EMMA/EMMA/bin/*.p?");
system("chmod +x $workdir/EMMA/RAGE/bin/*.p?");

# percorsi specifici per ISABEL
$path_string .= "# ISABEL\n";
$path_string .= "export PATH=$workdir/ISABEL/bin:\$PATH\n";
$path_string .= "export PERL5LIB=$workdir/ISABEL:\$PERL5LIB\n";
system("chmod +x $workdir/ISABEL/bin/*.p?");

# percorsi specifici per third_parties
$path_string .= "# third parties scripts\n";
my $path3rd = $workdir . '/third_parties';
opendir (PATHS, $path3rd) or croak("\nE- unable to open <$path3rd>\n\t");
@path_list = readdir PATHS;
closedir PATHS;
$path_string .= "export PATH=";
while (my $single_path = shift @path_list) {
    next if ($single_path =~ m/^\./);
#     print "\n[$single_path]";
    if (-d "$path3rd/$single_path") {
        $path_string .= "$path3rd/$single_path:";
        system("chmod +x $path3rd/$single_path/*.??*");
    }
}
$path_string .= "\$PATH\n";

$path_string .= "\n";

# aggiorno il file bashrc
my $bashrc_file = $ENV{HOME} . '/.bashrc';
print "Set your bashrc file [$bashrc_file]: ";
my $ans = <STDIN>; chomp $ans;
$bashrc_file = $ans if ($ans);
open (BASHRC, '>>' . $bashrc_file) or croak("\nE- unable to open <$bashrc_file>\n\t");
print BASHRC $path_string;
close BASHRC;

print "All done, please re-source <$bashrc_file>\n";
exit;