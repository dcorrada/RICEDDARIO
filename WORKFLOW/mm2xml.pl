#!/usr/bin/perl

# Questo script converte un file di FreeMind (.mm) in un file XML.
# L'idea è di costruire con FreeMind la struttura (e il contenuto) di un hash, 
# quindi convertirlo in un file XML dove i singoli nodi sono le chiavi. Se un nodo
# non ha figli lo considero come un valore di un nodo parent.
# Una regola base è che ogni nodo deve contenere solo stringhe plain text; per 
# evitare di creare mappe con contenuti pre-formattati aprire le impostazioni in 
# FreeMind (Tools|Preferences...) e nella sezione Behaviour selezionare "No" alla 
# voce "Use formatting for all nodes".
# Testato su FreeMind v0.9.0

use strict;
use warnings;
use Data::Dumper;
use XML::Simple;

# importo il file di FreeMind in un hash
my $mm2hash = XMLin(
    $ARGV[0],
    ForceArray => 1,
    KeyAttr => 'TEXT'
);

# rappresento la mappa di FreeMind con un array, dove ogni elemento/stringa
# stabilisce le relazioni tra nodi ad un definito livello gerarchico
# le foglie presentano un '@' a fine stringa
my @tree;
&build_tree($mm2hash->{'node'},0,'');
@tree = sort {$a cmp $b} @tree;

# ricostruisco un nuovo hash a partire dall'array
# le stringhe/foglie verranno parsate cosi:
# - se c'è un '=' saranno interpretate come "chiave:valore"
# - altrimenti saranno interpretate come "chiave:1"
my $tree2hash = { };
while (my $relationship = shift @tree) {
    my $elems = [ ];
    @{$elems} = split('::',$relationship);
#     printf("\nBranching <%s> at level %s\n",$elems->[scalar @{$elems} - 1],$elems->[0]);
    shift @{$elems};
    &brancher($elems,$tree2hash);
#     print Dumper $tree2hash;
}

# esporto l'hash come codice XML sullo STDOUT
my $XML = XMLout(
    $tree2hash,
    NoAttr => 1,
);
print "\n$XML\n";

exit;

sub build_tree {
    my ($obj,$level,$parents) = @_;
    
    foreach my $child (keys %{$obj}) {
        if (exists $obj->{$child}->{'node'}) { # il nodo ha figli
            push(@tree, sprintf("<%03d>%s::%s", $level, $parents, $child));
            my $new_parents = sprintf("%s::%s", $parents, $child);
            my $new_level = $level + 1;
            my $new_obj = $obj->{$child}->{'node'};
            &build_tree($new_obj,$new_level,$new_parents);
        } else { # il nodo è una foglia
            push(@tree, sprintf("<%03d>%s::%s@", $level, $parents, $child));
        }
    }
}

sub brancher {
    my ($nodes,$hash) = @_;
    
    return if (scalar @{$nodes} < 1); # non ci sono altri nodi da esplorare
    
    my $first = shift @{$nodes};
    
    if ($first =~ m/\@$/) { # sono arrivato ad una foglia
        $first =~ s/\@$//;
        my ($key,$value);
        if ($first =~ m/=/) {
            ($key,$value) = $first =~ m/([^=]+)=([^=]+)/;
        } else {
            $key = $first;
            $value = 1;
        }
        $hash->{$key} = $value;
    } elsif (exists $hash->{$first}) { # ho trovato un nodo pre-esistente
        &brancher($nodes,$hash->{$first});
    } else { # ho trovato un nodo nuovo
        $hash->{$first} = { };
        &brancher($nodes,$hash->{$first});
    }
}
