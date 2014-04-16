#!/usr/bin/perl
#~ -d
package ReplacePattern;

use strict;
use warnings;
use Carp;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| = 1;

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;

###################################################################
use Cwd;

our $params = { };

USAGE: {
    
    use Getopt::Long ;no warnings;
    GetOptions($params, 'help|h', 'workdir|d=s', 'exclude|e=s@');
    my $usage = <<END

SYNOPSYS

  $0 [-d <path> -e <pattern> ] <find_pattern> <replace_pattern> 

DESCRIPTION

  Questo script si occupa di cercare una determinata stringa e sostituirla con un altra in tutti i file presenti nella cartella in cui ci si trova. Lo script agisce in modo ricorsivo.

  Richiede come parametro di ingresso OBBLIGATORI un pattern che caratterizzi le tabelle che dovranno essere raccolte (es.: se desidero creare una summary table sui dati provenienti da HepG2 <table_pattern> sarà "HepG2"; per avere un idea di quale pattern usare accedere al database x ottenere una lista delle tabelle caricate con la query "mysql> show tables;" ).

OPZIONI

  -d --workdir <string>     working directory (def: pwd)
  -e --exclude <string>     exclude pattern
END
    ;
    if ((exists $params->{help})||!$ARGV[0]||!$ARGV[1]) {
        print $usage; exit;
    }

}

INIT: {
    $params->{workdir} = getcwd() # workdir default value
        unless (exists $params->{workdir});
    
    $params->{find} = $ARGV[0]; # pattern da ricercare
    $params->{replace} = $ARGV[1]; # pattern sostitutivo
    
    croak "E- workdir <", $params->{workdir}, "> not found\n" # check della workdir
        unless (chdir $params->{workdir});
}

SEEK: { # recupera la lista di file positivi al pattern matching
    my $cmd_line = 'grep -r -H -w -l';
    foreach my $term (@{$params->{exclude}}) { # aggiungo i pattern da escludere
        $cmd_line .= sprintf(" --exclude=\'%s\'", $term);
    }
    $cmd_line .= sprintf(" \'%s\' %s", $params->{find}, $params->{workdir});
    printf ("\n-- running grep...\n\t%s\n", $cmd_line);
    my $grep_output = qx/$cmd_line 2>&1/;
    $params->{greplist} = [ ];
    @{$params->{greplist}} = split("\n", $grep_output);
}

SUBSTITUTE: { # sostituisce i pattern
    $params->{skipped} = [ ]; # lista di file non processati
    print "-- replacing pattern";
    foreach my $filename (@{$params->{greplist}}) {
        printf("\n\tprocessing <%s>", $filename);
        if (-l $filename) {
            print " -- symbolic link, skipped";
            push(@{$params->{skipped}}, $filename);
            next;
        } elsif (-B $filename) {
            print " -- binary, skipped";
            push(@{$params->{skipped}}, $filename);
            next;
        } elsif (-w $filename) {
            my $matches = 0;
            open(OLD_FILE, '<', $filename) or do {
                print " -- IO error, skipped";
                push(@{$params->{skipped}}, $filename);
                next;
            };
            open(NEW_FILE, '>', 'subst.tmp');
            while (<OLD_FILE>) {
                my $newline = $_;
                $matches += $newline =~ s/$params->{find}/$params->{replace}/g;
                print NEW_FILE $newline;
            }
            print " $matches matches";
            close NEW_FILE;
            close OLD_FILE;
            rename 'subst.tmp', $filename;
        } else {
            print " -- skipped";
            push(@{$params->{skipped}}, $filename);
            next;
        }
    }
}

LOGS: {

#     print Dumper($params);
    open(LOG_FILE, '>', 'ReplacePattern.log');
    print LOG_FILE "SKIPPED FILES:\n";
    foreach my $skipped (@{$params->{skipped}}) {
        print LOG_FILE "\n\t$skipped";
    }
    close LOG_FILE;
}

print "\n_________________\nFINE PROGRAMMA\n";

exit;
