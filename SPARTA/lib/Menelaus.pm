package SPARTA::lib::Menelaus;

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
);

# Unisco gli attributi della classi madri con questa
my $ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Generic_class::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::DBmanager::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::FileIO::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;

sub table_abnum {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `chain` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `kabat` varchar(255) NOT NULL DEFAULT '', `chothia` varchar(255) NOT NULL DEFAULT '', `abnum` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `pdb` (`pdb`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'abnum',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `abnum` SET pdb = ?, chain = ?, res = ?, kabat = ?, chothia = ?, abnum = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$chain,$res,$kabat,$chotia,$chotiax) = @{$row};
            $sth->execute($pdb,$chain,$res,$kabat,$chotia,$chotiax)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_cluster {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `form` varchar(255) NOT NULL DEFAULT '', `id` int NOT NULL DEFAULT '0', `items` int NOT NULL DEFAULT '0'";
    my $keys = "KEY `pdb` (`pdb`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'cluster',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `cluster` SET pdb = ?, form = ?, id = ?, items = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$form,$id, $items) = @{$row};
            $sth->execute($pdb,$form,$id, $items)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_hinges {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `form` varchar(255) NOT NULL DEFAULT '', `frame` int NOT NULL DEFAULT '0', `heavy` float NOT NULL DEFAULT '0', `light` float NOT NULL DEFAULT '0'";
    my $keys = "KEY `pdb` (`pdb`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'hinges',
        'args' => $args,
        'keys' => $keys
    );
    
    
    # upload dei dati
    my $query_string = "INSERT INTO `hinges` SET pdb = ?, form = ?, frame = ?,  heavy = ?, light = ?";
    
    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift @{$data}) {
            my ($pdb,$form,$frame,$heavy,$light) = @{$row};
            $sth->execute($pdb,$form,$frame,$heavy,$light)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_enedecomp {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `ref` varchar(255) NOT NULL DEFAULT '', `form` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `pdb` (`pdb`), KEY `res` (`res`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'enedecomp',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `enedecomp` SET pdb = ?, res = ?, ref = ?, form = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$res,$ref,$form) = @{$row};
            $sth->execute($pdb,$res,$ref,$form)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_enedist {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `enapo` float NOT NULL DEFAULT '0', `enolo` float NOT NULL DEFAULT '0'";
    my $keys = "KEY `pdb` (`pdb`), KEY `res` (`res`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'enedist',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `enedist` SET pdb = ?, res = ?, enapo = ?, enolo = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb, $res, $enapo, $enolo) = @{$row};
            $sth->execute($pdb, $res, $enapo, $enolo)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_enematrix {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `form` varchar(255) NOT NULL DEFAULT '', `resA` int NOT NULL DEFAULT '0', `resB` int NOT NULL DEFAULT '0', `ene` float NOT NULL DEFAULT '0'";
    my $keys = "KEY `pdb` (`pdb`), KEY `resA` (`resA`), KEY `resB` (`resB`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'enematrix',
        'args' => $args,
        'keys' => $keys
    );
    
    
    # upload dei dati
    my $query_string = "INSERT INTO `enematrix` SET pdb = ?, form = ?, resA = ?,  resB = ?, ene = ?";
    
    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    # ATTENZIONE:   questo ciclo è leggermente diverso dagli altri metodi
    #               "table_xxx", perchè la mole di dati da caricare è tanta
    print "\n";
    my $tot = scalar @{$data};
    my $progress = $tot; my $percent = 100;
    my ($pdb,$form,$resA,$resB,$ene);
    while (my $string = shift @{$data}) {
            $progress = scalar @{$data};
            $percent = ($progress/$tot)*100;
            unless ($percent % 5) {
                printf("\r\t%03d%% to go...", $percent);
            }
            ($pdb,$form,$resA,$resB,$ene) = split("\t", $string);
            $sth->execute($pdb,$form,$resA,$resB,$ene)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_fludecomp {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `ref` varchar(255) NOT NULL DEFAULT '', `form` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `pdb` (`pdb`), KEY `res` (`res`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'fludecomp',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `fludecomp` SET pdb = ?, res = ?, ref = ?, form = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$res,$ref,$form) = @{$row};
            $sth->execute($pdb,$res,$ref,$form)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_fludist {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `dfapo` float NOT NULL DEFAULT '0', `dfolo` float NOT NULL DEFAULT '0'";
    my $keys = "KEY `pdb` (`pdb`), KEY `res` (`res`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'fludist',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `fludist` SET pdb = ?, res = ?, dfapo = ?, dfolo = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb, $res, $dfapo, $dfolo) = @{$row};
            $sth->execute($pdb, $res, $dfapo, $dfolo)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_flumatrix {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `form` varchar(255) NOT NULL DEFAULT '', `resA` int NOT NULL DEFAULT '0', `resB` int NOT NULL DEFAULT '0', `fluct` float NOT NULL DEFAULT '0'";
    my $keys = "KEY `pdb` (`pdb`), KEY `resA` (`resA`), KEY `resB` (`resB`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'flumatrix',
        'args' => $args,
        'keys' => $keys
    );
    
    
    # upload dei dati
    my $query_string = "INSERT INTO `flumatrix` SET pdb = ?, form = ?, resA = ?,  resB = ?, fluct = ?";
    
    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    # ATTENZIONE:   questo ciclo è leggermente diverso dagli altri metodi
    #               "table_xxx", perchè la mole di dati da caricare è tanta
    print "\n";
    my $tot = scalar @{$data};
    my $progress = $tot; my $percent = 100;
    my ($pdb,$form,$resA,$resB,$fluct);
    while (my $string = shift @{$data}) {
            $progress = scalar @{$data};
            $percent = ($progress/$tot)*100;
            unless ($percent % 5) {
                printf("\r\t%03d%% to go...", $percent);
            }
            ($pdb,$form,$resA,$resB,$fluct) = split("\t", $string);
            $sth->execute($pdb,$form,$resA,$resB,$fluct)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_notes {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`ref` varchar(255) NOT NULL DEFAULT '', `id` varchar(255) NOT NULL DEFAULT '', `desc` varchar(255) NOT NULL DEFAULT '', `pubmedID` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `ref` (`ref`), KEY `id` (`id`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'notes',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `notes` SET ref = ?, id = ?, `desc` = ?,  pubmedID = ?";

    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($ref,$id,$desc,$pubmedID) = @{$row};
            $sth->execute($ref,$id,$desc,$pubmedID)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_refschema {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `ref` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `pdb` (`pdb`), KEY `res` (`res`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'refschema',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `refschema` SET pdb = ?, res = ?, ref = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$res,$ref) = @{$row};
            $sth->execute($pdb,$res,$ref)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_pdbsum {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `type` varchar(255) NOT NULL DEFAULT '', `chainA` varchar(255) NOT NULL DEFAULT '', `resA` varchar(255) NOT NULL DEFAULT '', `residA` varchar(255) NOT NULL DEFAULT '', `chainB` varchar(255) NOT NULL DEFAULT '', `resB` varchar(255) NOT NULL DEFAULT '', `residB` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `pdb` (`pdb`), KEY `type` (`type`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'pdbsum',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `pdbsum` SET pdb = ?, type = ?, chainA = ?, resA = ?, residA = ?, chainB = ?, resB = ?, residB = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$type,$chainA,$resA,$residA,$chainB,$resB,$residB) = @{$row};
            $sth->execute($pdb,$type,$chainA,$resA,$residA,$chainB,$resB,$residB)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_rmsd {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `form` varchar(255) NOT NULL DEFAULT '', `rmsd` float NOT NULL DEFAULT '0', `au` float NOT NULL DEFAULT '0'";
    my $keys = "KEY `pdb` (`pdb`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'rmsd',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `rmsd` SET pdb = ?, form = ?, rmsd = ?, au = ?";

    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$form,$rmsd,$au) = @{$row};
            $sth->execute($pdb,$form,$rmsd,$au)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_rmsf {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `rmsfapo` float NOT NULL DEFAULT '0', `rmsfolo` float NOT NULL DEFAULT '0'";
    my $keys = "KEY `pdb` (`pdb`), KEY `res` (`res`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'rmsf',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `rmsf` SET pdb = ?, res = ?, rmsfapo = ?, rmsfolo = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$res,$rmsfapo, $rmsfolo) = @{$row};
            $sth->execute($pdb,$res, $rmsfapo, $rmsfolo)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_sequence {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `chain` varchar(255) NOT NULL DEFAULT '', `seq` longtext NOT NULL DEFAULT ''";
    my $keys = "KEY `pdb` (`pdb`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'sequence',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `sequence` SET pdb = ?, chain = ?, seq = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb, $chain, $seq) = @{$row};
            $sth->execute($pdb, $chain, $seq)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_structure {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `chain` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `resname` varchar(255) NOT NULL DEFAULT '', `domain` varchar(255) NOT NULL DEFAULT '', `cdr` varchar(255) NOT NULL DEFAULT '', `dssp` varchar(255) NOT NULL DEFAULT '', `known` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `resid` (`pdb`, `res`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'structure',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `structure` SET pdb = ?, chain = ?, res = ?, resname = ?,domain = ?, cdr = ?, dssp = ?, known = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$chain,$res,$resname,$domain,$cdr,$dssp,$known) = @{$row};
            $sth->execute($pdb,$chain,$res,$resname,$domain,$cdr,$dssp,$known)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_summary {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `chain` varchar(255) NOT NULL DEFAULT '', `seqID` varchar(255) NOT NULL DEFAULT '', `seqDB` varchar(255) NOT NULL DEFAULT '',  `pubmedID` varchar(255) NOT NULL DEFAULT '', `resolution` float(5,2) NOT NULL DEFAULT '0', `desc` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `pdb` (`pdb`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'summary',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    my $nr_filter = 'helloworld';
    foreach my $row (@{$data}) {
        # elimino righe ridondanti, se non c'è una pubblicazione di riferimento può capitare che ci siano dati ridondanti ad un inserimento pre-release
        my $nr_match = join('|', $row->[0], $row->[1], $row->[2], $row->[3], $row->[5], $row->[6]);
        next if ($nr_match eq $nr_filter);
        $nr_filter = $nr_match;
        
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `summary` SET pdb = ?, chain = ?, seqID = ?, seqDB = ?, pubmedID = ?, resolution = ?, `desc` = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb, $chain, $seqID, $seqDB, $pubmedID, $res, $desc) = @{$row};
            $sth->execute($pdb, $chain, $seqID, $seqDB, $pubmedID, $res, $desc)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

sub table_xres {
    my ($self, $data) = @_;
    
    my $dbh = $self->access2db();
    
    # creo una nuova tabella
    my $args = "`pdb` varchar(255) NOT NULL DEFAULT '', `chain` varchar(255) NOT NULL DEFAULT '', `res` varchar(255) NOT NULL DEFAULT '', `source_chain` varchar(255) NOT NULL DEFAULT '', `source_res` varchar(255) NOT NULL DEFAULT ''";
    my $keys = "KEY `pdb` (`pdb`), KEY `res` (`res`)";
    $self->new_table(
        'dbh' => $dbh,
        'table' => 'xres',
        'args' => $args,
        'keys' => $keys
    );
    
    # pre-processing
    my @tmp_table;
    foreach my $row (@{$data}) {
        # righe x eventuale pre-processamento dei record
        push(@tmp_table, $row);
    }
    
    # upload dei dati
    my $query_string = "INSERT INTO `xres` SET pdb = ?, chain = ?, res = ?, source_chain = ?, source_res = ?";


    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    
    while (my $row = shift(@tmp_table)) {
            my ($pdb,$chain,$res,$source_chain,$source_res) = @{$row};
            $sth->execute($pdb,$chain,$res,$source_chain,$source_res)
                or $self->_raise_error(sprintf("\nE- [Menelaus] mysql statement error: %s\n\t", $dbh->errstr));
    }
    
    $sth->finish();
    $dbh->disconnect;
}

1;

=head1 SPARTA::lib::Menelaus

=head1 MENELAUS: the first king of Sparta
    
    Menelaus was a legendary king of Sparta, the husband of Helen of Troy. He 
    was the brother of Agamemnon king of Mycenae and, according to the Iliad, 
    leader of the Spartan contingent of the Greek army during the War. 
    
    Menelaus class is composed of methods aimed to the maintenance of the SPARTA 
    database.
    
=head1 METHODS

=head2 db_dump([$string])
    
    my $filename = $self->new_database('sparta');
    
    Makes a dump of an existing database. It returns the full-path of the tar
    gzipped SQL file.
    
    DEFAULTS:
        $string    = $self->get_database

=head2 new_database([$string])
    
    $self->new_database('sparta');
    
    Creates a new SPARTA database, overwriting the existing one.
    
    DEFAULTS:
        $string    = $self->get_database


=head2 table_[tablename]([$arrayref])
    
        $self->table_summary($data);
    
    Table methods overwrite existing tables in database and fill them with data.
    Data must be submitted as an array reference of arrays, without header 
    lines. A typical structure of $data should be as follows:
    
    $data = [
        [ 'A1' , 'B1' , 'C1', ... ],
        [ 'A2' , 'B2' , 'C2', ... ],
        ...
    ];

=head1 UPDATES

=cut
