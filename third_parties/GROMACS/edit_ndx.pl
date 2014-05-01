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
use RICEDDARIO::lib::FileIO;

#######################
## VARIABILI GLOBALI ##
our $working_dir = getcwd();
our $gmxrc_path = '/usr/local/GMX407/bin/GMXRC';
our $filename = { 'ndx' => 'index.ndx', 'gro' => 'conf.gro', 'csv' => 'sstruct.csv' };
our $selected_fields =  [ 2, 2 ];
our $atom_sel = [ 'b', 'c' ];
our $file_obj = RICEDDARIO::lib::FileIO->new();
our $features = { }; # hash delle annotazioni
our $map_features = { };
#######################

USAGE: {
    my $options = { };
    use Getopt::Long;no warnings;
    GetOptions($options, 'help|h', 'gro|g=s', 'csv|c=s', 'ndx|n=s', 'fields|f=s', 'atomselect|s=s');
    
    my $usage = <<END

SYNOPSYS

  $0 [-c string] [-g string] [-n string] [-f string] [-s string]

Questo script legge in input un file .csv in cui sono tabulate una lista di
annotazioni per una specifica struttura (.gro file). In output viene restituito
un index file in cui vengono definite tali annotazioni, ottenuto tramite il
comando di GROMACS "make_ndx".

OPZIONI

  -c <string>   INPUT, (def: <$filename->{'csv'}>)
                File .csv di annotazioni

  -g <string>   INPUT, (def: <$filename->{'gro'}>)
                File .gro della struttura su cui allestiro' l'index file;
                sarebbe ideale disporre del file .gro usato per la simulazione,
                quindi completo di solvente e ioni

  -n <string>   OUTPUT, (def: <$filename->{'ndx'}>)
                Index file, output di 'make_ndx'

  -f <string>   (def: [@{$selected_fields}])
                lista dei campi che definiscono le annotazioni

  -s <string>   (def: [@{$atom_sel}])
                lista delle atom selection ('a' residuo intero; 'b' backbone;
                'c' carboni alfa) associate ai campi definiti con l'opzione -f;
                la stringa deve contenere un numero di elementi uguale al numero
                dei campi selezionati

ESEMPIO:

    $0 -f '3 5'
    # seleziono le colonne 3 e 5 su cui definire i miei gruppi con 'make_ndx';
    # di default, se non viene specificata l'opzione -s, vengono presi in
    # considerazione i residui interi
    
    $0 -f '2 4 4' -s 'a b c'
    # seleziono le colonne 2 e 4; sulla colonna 2 prendo in considerazione i
    # residui interi, sulla colonna 4 voglio definire un gruppo che consideri
    # solo gli atomi del backbone e un secondo gruppo che consideri solo i CA

NOTE:

Il file .csv dovebbe avere una formattazione analoga a questa di esempio:

    RESIDUE;CHAIN;DOMAIN;ELEM;MAIN_CONF;HELIX;STRAND;LOOP
    1;;;;Loop;0;0;1
    2;;;;Loop;0;0.15;0.85
    3;HEAVY;VARIABLE;SHEET;Strand;0;0.91;0.09
    4;HEAVY;VARIABLE;SHEET;Strand;0;0.96;0.04
    [...]

Le colonne sono numerate a partire da 0. La prima riga del file e' l'header, la
prima colonna (col 0, 'RESIDUE') identifica il numero di residuo corrispondente
nel .gro file; Tutte le colonne successive sono campi selezionabili con
l'opzione -f.

END
    ;
    
    OPT_CHECK: {
        if (exists $options->{'help'}) { print $usage; exit; };
        
        $filename->{'csv'} = $options->{'csv'} if (exists $options->{'csv'});
        $filename->{'gro'} = $options->{'gro'} if (exists $options->{'gro'});
        $filename->{'ndx'} = $options->{'ndx'} if (exists $options->{'ndx'});
        
        if (exists $options->{'fields'}) { # reinizializzo $selected_fields
            croak("\nE- option '-f' must contain only integers\n\t") unless ($options->{'fields'} =~ /^[\d\s]{1,}$/);
            @{$selected_fields} = split(' ', $options->{'fields'});
#             @{$selected_fields} = map( $_ - 1, @{$selected_fields}); # perchè Perl conta a partire da 0...
            
            # reinizializzo $atom_sel
            unless (exists $options->{'atomselect'}) {
                $options->{'atomselect'} = 'a ' x scalar @{$selected_fields};
            }
            croak("\nE- unknown atom selection\n\t") unless ($options->{'atomselect'} =~ /^[abc\s]{1,}$/);
            @{$atom_sel} = split(' ', $options->{'atomselect'});
            croak("\nE- atom selection does not match with the number of selected fields\n\t") unless (scalar @{$selected_fields} == @{$atom_sel});
        }
    }
    
    FILECHECK: {
        croak("\nE- file <$filename->{'csv'}> not found\n\t") unless (-e $filename->{'csv'});
        croak("\nE- file <$filename->{'gro'}> not found\n\t") unless (-e $filename->{'gro'});
    }
    
    SUMMARIES: {
        print "\n/*";
        print "\nFIELDS   [@{$selected_fields}]";
        print "\nATOM_SEL [@{$atom_sel}]";
        print "\n*/\n";
    }
}


PARSE_CSV: {
    printf("\nI- parsing <%s/%s>...", getcwd(), $filename->{'csv'});
    
    # leggo il file, me lo slurpo e me lo choppo
    $file_obj->set_filename($filename->{'csv'});
    my $content = $file_obj->read();
    chomp(@{$content});
    
    # creo una lista non ridondante dei campi selezionati
    my %nr_fields;
    foreach my $column (@{$selected_fields}) {
        $nr_fields{$column} = 1;
    }
    
    # leggo la prima riga del file (header) e mi appunto la lista delle annotazioni da considerare
    my $header = shift(@{$content});
    my @field_names = split(';', $header);
    foreach my $sel_feat (keys %nr_fields) {
        $map_features->{$sel_feat} = $field_names[$sel_feat];
        $features->{$field_names[$sel_feat]} = { };
    }
    
#     foreach my $map (sort keys %{$map_features}) { printf("\nla colonna [%03d] mappa il campo [%s]", $map, $map_features->{$map}); }
    
    # leggo le righe restanti riempiendo l'hash delle annotazioni
    while (my $new_entry = shift(@{$content})) {
        my @all_feats = split(';', $new_entry);
        my $resid = $all_feats[0];
        foreach my $sel_feat (keys %nr_fields) {
            my $value = $all_feats[$sel_feat];
            next unless $value;
            $features->{$map_features->{$sel_feat}}->{$value} = [ ]
                unless (exists($features->{$map_features->{$sel_feat}}->{$value}));
            push(@{$features->{$map_features->{$sel_feat}}->{$value}}, $resid);
        }
    }
    
#     # come è strutturato il mio hash???
#     foreach my $parent (sort keys %{$features}) {
#         foreach my $child (sort keys %{$features->{$parent}}) {
#             print "\n\n[$parent|$child] -> [@{$features->{$parent}->{$child}}]";
#         }
#         print "\n\n***";
#     }
    
    print "done\n";
}

MAKE_NDX_CMD: { # qui dentro edito le linee di comando che dovrò passare a "make_ndx"
    print "\nI- editing 'make_ndx' commands...";
    
    # valuto quanti sono i gruppi di default definiti per il .gro file
    my $def_groups;
    my $syscmd = <<END
source $gmxrc_path;
echo q | make_ndx -f $filename->{'gro'} 2>&1;
END
    ;
    qx/$syscmd/;
    $file_obj->set_filename('index.ndx');
    my $content = $file_obj->read();
    unlink 'index.ndx';
    $def_groups = grep(/^\[/, @{$content}); # anche "make_ndx" conta a partire da 0
    
    
    my $cmdlines = [ ];
    my $pos = 0;
    my ($string, $label_sel);
    my $group_id = $def_groups + $pos;
    foreach my $sel_feat (@{$selected_fields}) {
        
        # valuto le tipologie di atom select ed edito in modo differente
        $_ = $atom_sel->[$pos];
        CASEOF: {
            /^a$/ && do {
                $string = qq/r /;
                $label_sel = "";
                last CASEOF;
            };
            /^b$/ && do {
                $string = qq/"backb" & r /;
                $label_sel = "_and_Backbone";
                last CASEOF;
            };
            /^c$/ && do {
                $string = qq/a CA & r /;
                $label_sel = "_and_C-alpha";
                last CASEOF;
            };
            # qui aggiungere altri metodi di selezione...
            # ricordarsi però di aggiornare anche il blocco "USAGE"
        }
        
        my $group = $map_features->{$sel_feat};
        foreach my $subgroup (keys %{$features->{$group}}) {
            my $group_name = "$group($subgroup)$label_sel";
            $group_name =~ s/\s/_/g;
            push(@{$cmdlines}, $string . join(' ', @{$features->{$group}->{$subgroup}}));
            push(@{$cmdlines}, qq/name $group_id '$group_name'/);
            $group_id ++;
        }
        
        $pos ++;
    }
    
    push(@{$cmdlines}, 'q');
    @{$cmdlines} = map( $_ . "\n", @{$cmdlines});
    
    
    # scrivo tutti i comandi su file
    $file_obj->set_filename('elenco_comandi.txt');
    $file_obj->set_filedata($cmdlines);
    $file_obj->write();
    
    print "done\n";
}


GMX_LAUNCH: { # lancio il comando 'make_ndx'
    print "\nI- running 'make_ndx'...";
    
    my $cmdlines =<<END
source $gmxrc_path;
make_ndx -f $filename->{'gro'} -o $filename->{'ndx'} < elenco_comandi.txt 2>&1
END
    ;

    qx/$cmdlines/;
    
    unlink 'elenco_comandi.txt'; # elimino il file, non mi serve più
    
    print "done\n";
}

FINE: {
    print "\n---\nFINE PROGRAMMA\n";
    exit;
}
