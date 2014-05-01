package SPARTA::lib::Theodorus;

use strict;
use warnings;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| =1;

use lib $ENV{HOME};

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;

###################################################################
use base ( 'SPARTA::lib::Generic_class' ); # eredito la classe generica contenente il costruttore, l'AUTOLOAD ecc..
use base ( 'SPARTA::lib::DBmanager' ); # gestione del database
use base ( 'SPARTA::lib::FileIO' ); # modulo per leggere/scrivere su file
our $AUTOLOAD;

# Definizione degli attributi della classe
# chiave        -> nome dell'attributo
# valore [0]    -> valore di default
# valore [1]    -> permessi di accesso all'attributo
#                  ('read.[write.[...]]')
# STRUTTURA DATI
our %_attribute_properties = (
    _database       => ['sparta', 'read.write'],
    _pdblist        => ['sparta', 'read.write'],
    
);

# Unisco gli attributi della classi madri con questa
my $ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Generic_class::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::DBmanager::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::FileIO::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;

# ================================ NOTA ========================================
# Per evitare conflitti nelle chiamate, i metodi pubblici di Theodorus avranno
# tutti un nome tipo "pml_XXXXX"
# ==============================================================================

sub pml_first {
# templato di script per PyMol, da usare in tutti gli altri metodi 
    my ($self) = @_;
    
    my $pdb_files = $self->get_pdblist();
    my @pdb_ids = sort keys %{$pdb_files};
    
    # raccolgo informazioni strutturali dal database
    $self->_raise_warning("\nI- [Theodorus] PDB dataset...");
    my @struct_feats;
    my $query = <<END
SELECT structure.pdb, structure.chain, structure.domain, structure.res, pdbsum.type, structure.cdr
FROM structure
JOIN xres
ON xres.pdb = structure.pdb
AND xres.res = structure.res
LEFT JOIN pdbsum
ON xres.pdb = pdbsum.pdb
AND xres.source_res = pdbsum.residA
AND xres.chain = pdbsum.chainA
AND pdbsum.chainB = 'A'
GROUP BY CONCAT(structure.pdb, structure.res)
END
    ;
    
    my $dbh = $self->access2db();
    my $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
    while (my $row = $sth->fetchrow_hashref()) {
        push(@struct_feats, $row);
    }
    $sth->finish();
    $dbh->disconnect;
    
    # in questo arrayref metto il contenuto dello script, da scrivere poi su file
    my $script = [ "# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***\n" ];
    
    push(@{$script}, "\n# loading pdb files\n");
    foreach my $id (@pdb_ids) {
        my $string = sprintf("load %s, %s\n", $pdb_files->{$id}, $id);
        push(@{$script}, $string);
    }
    
    push(@{$script}, "\n# removing hydrogens\n");
    push(@{$script}, "remove hydro\n");
    
    push(@{$script}, "\n# structural alignment\n");
    for (my $i = 1; $i < scalar @pdb_ids; $i++) {
        my $string = sprintf("align %s, %s\n", $pdb_ids[$i], $pdb_ids[0]);
        push(@{$script}, $string);
    }
    
    push(@{$script}, "\n# selecting chains\n");
    my $chains = { };
    for (my $i = 0; $i < scalar @struct_feats; $i++) {
        my $record = $struct_feats[$i];
        $chains->{$record->{'pdb'}} = { 'H' => [ 1000, 0 ], 'L' => [ 1000, 0 ] }
            unless (exists $chains->{$record->{'pdb'}});
        if ($record->{'chain'} eq 'H') {
            if ($record->{'res'} < $chains->{$record->{'pdb'}}->{'H'}->[0]) {
                $chains->{$record->{'pdb'}}->{'H'}->[0] = $record->{'res'};
            } elsif ($record->{'res'} > $chains->{$record->{'pdb'}}->{'H'}->[1]) {
                $chains->{$record->{'pdb'}}->{'H'}->[1] = $record->{'res'};
            } else {
                next;
            }
        } elsif ($record->{'chain'} eq 'L') {
            if ($record->{'res'} < $chains->{$record->{'pdb'}}->{'L'}->[0]) {
                $chains->{$record->{'pdb'}}->{'L'}->[0] = $record->{'res'};
            } elsif ($record->{'res'} > $chains->{$record->{'pdb'}}->{'L'}->[1]) {
                $chains->{$record->{'pdb'}}->{'L'}->[1] = $record->{'res'};
            } else {
                next;
            }
        }
    }
    my $heavy_string = "select heavy_chain,";
    my $light_string = "select light_chain,";
    foreach my $id (@pdb_ids) {
        $heavy_string .= sprintf(" (%s and resi %d-%d) or", $id, $chains->{$id}->{'H'}->[0], $chains->{$id}->{'H'}->[1]);
        $light_string .= sprintf(" (%s and resi %d-%d) or", $id, $chains->{$id}->{'L'}->[0], $chains->{$id}->{'L'}->[1]);
    }
    $heavy_string =~ s/ or$/\n/;
    $light_string =~ s/ or$/\n/;
    push(@{$script}, $heavy_string, $light_string);
    push(@{$script}, "color palegreen, heavy_chain\n");
    push(@{$script}, "color palecyan, light_chain\n");
    
    push(@{$script}, "\n# selecting antigen contact residues\n");
    my $antigen = { };
    foreach (my $i = 0; $i < scalar @struct_feats; $i++) {
        my $record = $struct_feats[$i];
        $antigen->{$record->{'pdb'}} = [ ]
            unless (exists $antigen->{$record->{'pdb'}});
        push(@{$antigen->{$record->{'pdb'}}}, $record->{'res'})
            if ($record->{'type'});
    }
    my $antigen_string = "select antigen,";
    foreach my $id (@pdb_ids) {
        $antigen_string .= sprintf(" (%s and resi %s) or", $id, join('+', @{$antigen->{$id}}));
    }
    $antigen_string =~ s/ or$/\n/;
    push(@{$script}, $antigen_string);
#     push(@{$script}, "color blue, antigen\n");
    
    push(@{$script}, "\n# selecting CDR regions\n");
    my $cdr = { };
    foreach (my $i = 0; $i < scalar @struct_feats; $i++) {
        my $record = $struct_feats[$i];
        $cdr->{$record->{'pdb'}} = [ ]
            unless (exists $cdr->{$record->{'pdb'}});
        push(@{$cdr->{$record->{'pdb'}}}, $record->{'res'})
            if ($record->{'cdr'} =~ /^CDR/);
    }
    my $cdr_string = "select cdr,";
    foreach my $id (@pdb_ids) {
        $cdr_string .= sprintf(" (%s and resi %s) or", $id, join('+', @{$cdr->{$id}}));
    }
    $cdr_string =~ s/ or$/\n/;
    push(@{$script}, $cdr_string);
    
    push(@{$script}, "\n# representations\n");
    push(@{$script}, "hide all\n");
    push(@{$script}, "show ribbon, all\n");
    
    print "done";
    return $script;
}

sub pml_flucts {
    my ($self, $selected) = @_;
    my $pml_content; # contenuto dello script per PyMol
    
    $pml_content = $self->pml_first(); # inizializzo con il templato di base
    
    push(@{$pml_content}, "\n# selecting distfluct categories\n");
    my $string;
#     my @color_ramp = ('density', 'deepblue', 'skyblue', 'lightblue', 'lightorange', 'brightorange', 'deepsalmon', 'firebrick');
    foreach my $range (sort keys %{$selected}) {
        $string = "select $range,";
        foreach my $pdb (sort keys %{$selected->{$range}}) {
            $string .= sprintf(" (%s and resi %s) or", $pdb, join('+', @{$selected->{$range}->{$pdb}}));
        }
        $string =~ s/ or$/\n/;
        push(@{$pml_content}, $string);
#         my $color = shift @color_ramp;
#         push(@{$pml_content}, "color $color, $range\n");
    }
    
#     push(@{$pml_content}, "color firebrick, antigen\n");
    return $pml_content;
}

sub pml_hotspot {
    my ($self, $nrg_res) = @_;
    my $pml_content; # contenuto dello script per PyMol
    
    $pml_content = $self->pml_notes(); # inizializzo con il templato di base
    
    $self->_raise_warning("\nI- [Theodorus] hotspots list...");
    my $sel_apo = { };
    my $sel_holo = { };
    my $sel_both = { };
    foreach my $form (keys %{$nrg_res}) {
        foreach my $pdb (keys %{$nrg_res->{$form}}) {
            foreach my $res (@{$nrg_res->{$form}->{$pdb}}) {
                if ($form eq 'APO') {
                    $sel_apo->{$pdb} = [ ]
                        unless (exists $sel_apo->{$pdb});
                    push(@{$sel_apo->{$pdb}}, $res);
                } elsif ($form eq 'HOLO') {
                    $sel_holo->{$pdb} = [ ]
                        unless (exists $sel_holo->{$pdb});
                    push(@{$sel_holo->{$pdb}}, $res);
                } elsif ($form eq 'BOTH') {
                    $sel_both->{$pdb} = [ ]
                        unless (exists $sel_both->{$pdb});
                    push(@{$sel_both->{$pdb}}, $res);
                }
            }
        }
    }
#     # smoothing function (se c'e' un gap di un solo residuo nelle selezioni lo includo)
#     foreach my $pdb (keys %{$selected_res}) {
#         @{$selected_res->{$pdb}} = sort {$a <=> $b} @{$selected_res->{$pdb}};
#         my $pre = scalar @{$selected_res->{$pdb}};
#         for (my $i = 1; $i < $pre; $i++) {
#             if ($selected_res->{$pdb}->[$i] - $selected_res->{$pdb}->[$i-1] == 2) {
#                 push(@{$selected_res->{$pdb}}, $selected_res->{$pdb}->[$i] - 1);
#             }
#         }
#     }
    push(@{$pml_content}, "\n# selecting hotspots\n");
    my $energy_string;
    $energy_string = "select APO,";
    foreach my $id (keys %{$sel_apo}) {
        $energy_string .= sprintf(" (%s and resi %s) or", $id, join('+', @{$sel_apo->{$id}}));
    }
    $energy_string =~ s/ or$/\n/;
    push(@{$pml_content}, $energy_string);
    push(@{$pml_content}, "color blue, APO\n");
    
    $energy_string = "select BOTH,";
    foreach my $id (keys %{$sel_both}) {
        $energy_string .= sprintf(" (%s and resi %s) or", $id, join('+', @{$sel_both->{$id}}));
    }
    $energy_string =~ s/ or$/\n/;
    push(@{$pml_content}, $energy_string);
    push(@{$pml_content}, "color green, BOTH\n");
    
    $energy_string = "select HOLO,";
    foreach my $id (keys %{$sel_holo}) {
        $energy_string .= sprintf(" (%s and resi %s) or", $id, join('+', @{$sel_holo->{$id}}));
    }
    $energy_string =~ s/ or$/\n/;
    push(@{$pml_content}, $energy_string);
    push(@{$pml_content}, "color red, HOLO\n");
    
    print "done";
    return $pml_content;
}

sub pml_notes { # aggiungo al templato di base annotazioni strutturali
    my ($self) = @_;
    my $pml_content; # contenuto dello script per PyMol
    
    $pml_content = $self->pml_first(); # inizializzo con il templato di base
    
    # raccolgo informazioni strutturali dal database
    $self->_raise_warning("\nI- [Theodorus] structural annotation...");
    my $struct_feats = { };
    my $query = <<END
SELECT structure.pdb, structure.res, notes.id
FROM structure
JOIN refschema
ON refschema.pdb = structure.pdb
AND refschema.res = structure.res
JOIN notes
ON refschema.ref = notes.ref
ORDER BY notes.id
END
    ;
    
    my $dbh = $self->access2db();
    my $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
    while (my ($pdb, $res, $id) = $sth->fetchrow_array()) {
        $struct_feats->{$id} = { }
            unless (exists $struct_feats->{$id});
        $struct_feats->{$id}->{$pdb} = [ ]
            unless (exists $struct_feats->{$id}->{$pdb});
        push(@{$struct_feats->{$id}->{$pdb}}, $res);
    }
    $sth->finish();
    $dbh->disconnect;
    
    foreach my $id (keys %{$struct_feats}) {
        my $string = "\n# selecting $id";
        $string .= "\nselect $id,";
        foreach my $pdb (keys %{$struct_feats->{$id}}) {
            $string .= sprintf(" (%s and resi %s) or", $pdb, join('+', @{$struct_feats->{$id}->{$pdb}}));
        }
        $string =~ s/ or$/\n/;
        push(@{$pml_content}, $string);
    }
    
    print "done";
    return $pml_content;
}

1;

=head1 SPARTA::lib::Theodorus

=head1 THEODORUS of Samos: a sculptor and architect.
    
    The ancient historian Herodotus credits Theodorus with improving the process 
    of mixing copper and tin to form bronze, as well as being the first to use 
    it in casting. He credits Theodorus alone for discovering the art of fusing 
    iron. He is also credited with inventing a water level, a carpenter's 
    square, a lock and key and the turning lathe.
    
    The methods of this class produce PyMol script in order to get a graphical 
    visualization of the data stored in the database.

=cut
