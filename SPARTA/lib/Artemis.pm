package SPARTA::lib::Artemis;

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
# *** CLASSI EREDITATE ***
use base ( 'SPARTA::lib::Generic_class' ); # classe generica contenente il costruttore, l'AUTOLOAD ecc..
use base ( 'SPARTA::lib::DBmanager' ); # gestione del database
use base ( 'SPARTA::lib::FileIO' ); # lettura/scrittura su file
use base ( 'SPARTA::lib::Menelaus' ); # scrittura di tabelle sul DB
use base ( 'SPARTA::lib::Chilon' );

# *** ALTRI MODULI ***
use LWP::UserAgent;
use SPARTA::lib::Kabat;
use threads;
use threads::shared;
use Thread::Semaphore;

## GLOBS ##
our $AUTOLOAD;
# THREADING TOOLS
#
# *** ATTENZIONE: per motivi di prestazione sarebbe opportuno liberare lo spazio
# occupato da queste variabili. In questo caso sarebbe meglio evitare di usare
# undef, quindi re-inizializzare le variabili come scritto di seguito:
#     @thr = ( );
#     @jobcontent = ( );
# 
our $thread_num = 8; # numero massimo di threads da lanciare contemporaneamente
our $semaforo = Thread::Semaphore->new(int($thread_num));
our @thr; # lista dei threads
our ($queued, $running) :shared; # numero di job in coda e che stanno girando
our (@jobcontent) :shared; # array in cui i job riversano i loro risultati;

# Definizione degli attributi della classe
# chiave        -> nome dell'attributo
# valore [0]    -> valore di default
# valore [1]    -> permessi di accesso all'attributo
#                  ('read.[write.[...]]')
# STRUTTURA DATI
our %_attribute_properties = (
    _database       => ['sparta', 'read.write'],
    _dataset        => [ { }, 'read.write' ],
    _rcsb_url       => ['http://www.rcsb.org/pdb/rest/customReport', 'read.write'],
    _pdbsum_url     => ['http://www.ebi.ac.uk/thornton-srv/databases/cgi-bin/pdbsum/GetIface.pl', 'read.write'],
);

# Unisco gli attributi della classi ereditate con questa
my $ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Generic_class::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::DBmanager::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::FileIO::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Menelaus::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Chilon::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;

sub annotation { # Annotazioni strutturali varie
    my ($self) = @_;
    
    my %list = ( # lista delle annotazioni (da espandere a piacimento)
        'HELIX' => {
            'desc' => "alfa-helices of CL domain, folding nucleus",
            'pubmedId' => "10397760; 20022755",
            'ref' => [  'CL-0014','CL-0015','CL-0016','CL-0017','CL-0018','CL-0019',
                        'CL-0075','CL-0076','CL-0077','CL-0078','CL-0079','CL-0080' ]
        },
        
        'PROLINE' => {
            'desc' => "proline, folding guidance",
            'pubmedId' => "20022755",
            'ref' => ['CL-0032']
        },
        
        'PIN_MOTIF' => {
            'desc' => "C-m-[LFYW]-n-C motif, folding guidance",
            'pubmedId' => "9417933; 20022755",
            'ref' => [  'CH-0028','CH-0042','CH-0085',
                        'CL-0025','CL-0039','CL-0085',
                        'VH-0022','VH-0036','VH-0092',
                        'VL-0023','VL-0035','VL-0088'   ]
        },
        
    );
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    foreach my $id (keys %list) {
        foreach my $ref (@{$list{$id}->{'ref'}}) {
            my $desc = $list{$id}->{'desc'};
            my $pubmedId = $list{$id}->{'pubmedId'};
            push(@{$tmp_table}, [$ref,$id,$desc,$pubmedId]);
        }
    }
    
    # ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [notes]...");
    $self->table_notes($tmp_table);
    # ==============================================================================
    
    return $tmp_table;
}

sub abnumpdb {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
   $self->_raise_warning("\nI- [Artemis] fetching data from [http://www.bioinf.org.uk]...");
    foreach my $key (keys %{$dataset}) {
        my $pdbID = $key;
        my $pdbfile = $dataset->{$key}->{'PDB'};
        
        # patch per il file 1YQV, c'è una MET in N-term della catena L e abnum va in panico
        if ($pdbID eq "1YQV") {$pdbfile = '/home/dario/simulazioni/dataset/PDBapo/1YQV_patched.pdb'; }
        
        print "\n\tsubmitting [$pdbID]...";
        my $logfile = $self->get_errfile();
        my $kabat = SPARTA::lib::Kabat->new('errfile' => $logfile);
        my $rawdata = $kabat->numbers($pdbfile);
        shift @{$rawdata}; # rimuovo l'header
        foreach my $record (@{$rawdata}) {
            chomp $record;
            my ($chain,$res,$kabat,$chotia,$chotiaxp) = 
                $record =~ m/^\w{3}\s(\w)\s+(\d+);\s*(\w+)\s*;\s*(\w+)\s*;\s*(\w+)\s*;$/g;
            push(@{$tmp_table}, [$pdbID,$chain,$res,$kabat,$chotia,$chotiaxp]);
            
            # patch x il pdb 1YQV (vedi sopra)
            if (($pdbID eq "1YQV") && ($res == 116)) {
                push(@{$tmp_table}, ["1YQV","L","216","0","0","0"]);
            }
            
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [abnum]...");
    $self->table_abnum($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub clusters {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    $self->_raise_warning("\nI- [Artemis] collecting structural clusters...");
    
    foreach my $key (keys %{$dataset}) {
        my $pdbID = $key;
        
        my $apo_xvg = $self->_xvg_parser($dataset->{$key}->{'CLUSTER_APO'});
        while (my $values = shift @{$apo_xvg}) {
            my $clustID = $values->[0];
            my $items = $values->[1];
            my $record = [ $key, 'APO', $clustID, $items ];
            push(@{$tmp_table}, $record);
        }
        
        my $olo_xvg = $self->_xvg_parser($dataset->{$key}->{'CLUSTER_HOLO'});
        while (my $values = shift @{$olo_xvg}) {
            my $clustID = $values->[0];
            my $items = $values->[1];
            my $record = [ $key, 'HOLO', $clustID, $items ];
            push(@{$tmp_table}, $record);
        }
        
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [cluster]...");
    $self->table_cluster($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub hinges { # reperisco gli angoli inter-dominio per le catene pesante e leggera, per ogni frame della dinamica campionato da BENDER
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    $self->_raise_warning("\nI- [Artemis] parsing angles distribution...");
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    my ($frame, $heavy, $light);
    foreach my $pdb (keys %{$dataset}) {
        foreach my $form ('APO', 'HOLO') {
            my $data = $self->_xvg_parser($dataset->{$pdb}->{'HINGE_'.$form});
            foreach my $newline (@{$data}) {
                ($frame, $heavy, $light) = @{$newline};
                my $row = [$pdb, $form, $frame, $heavy, $light];
                push(@{$tmp_table}, $row);
            }
        }
    }
    
#     foreach my $line (@{$tmp_table}) {
#         my $content = join(';', @$line);
#         print "\n[$content]";
#     }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [hinges]...");
    $self->table_hinges($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}


sub enedecomp {
    my ($self, $cutoff) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    # valore di default
    $cutoff = 6.5
        unless ($cutoff && $cutoff =~ /^[\d\-\.Ee]+$/);
    
# ***************************** ATTENZIONE *************************************
# I metodi e gli attributi di Chilon sono ereditati nella classe Artemis.
# D'altro canto, se voglio sfruttare le capacita' multithread di Chilon devo
# instanziare e usare un oggetto Chilon indipendente.
# ******************************************************************************
    my $chilon = SPARTA::lib::Chilon->new(
        'host'      => $self->get_host(),
        'database'  => $self->get_database(),
        'user'      => $self->get_user(),
        'password'  => $self->get_password(),
        'errfile'   => $self->get_errfile(),
        'dataset'   => $self->get_dataset()
    );
    
    # raccolgo i profili dei contributi energetici dati dagli autovettori più rappresentativi di ogni sistema 
    $self->_raise_warning("\nI- [Artemis] parsing energy distribution");
    my $selected = $chilon->list('ene');
    
    # raffino i profili usando una matrice dei contatti
    $self->_raise_warning("\nI- [Artemis] refining energy list");
    my $refined = $chilon->refine($selected, $cutoff);
    
    foreach my $ref (keys %{$refined}) {
        my @records = @{$refined->{$ref}};
        foreach my $triplet (@records) {
            my ($pdb,$form,$res) = $triplet =~ m/^(\w{4})-(APO|HOLO|BOTH)-(\d+)$/;
            push(@{$tmp_table}, [ $pdb, $res, $ref, $form ]);
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [enedecomp]...");
    $self->table_enedecomp($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub enedist {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    $self->_raise_warning("\nI- [Artemis] collecting energy distribution data...");
    foreach my $key (keys %{$dataset}) {
        my $pdbID = $key;
        my $apo_en_data = $self->_xvg_parser($dataset->{$pdbID}->{'EN_APO'});
        my $olo_en_data = $self->_xvg_parser($dataset->{$pdbID}->{'EN_HOLO'});
        for (my $i = 0; $i < scalar @{$apo_en_data}; $i++) {
            my $apo_en = $apo_en_data->[$i][1];
            my $olo_en = $olo_en_data->[$i][1];
            my $row = [ $pdbID, $i+1, $apo_en, $olo_en ];
            push(@{$tmp_table}, $row);
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [enedist]...");
    $self->table_enedist($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub enematrix {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    # interrogo il database
    my $dbh = $self->access2db();
    $self->set_query_string("SELECT pdb, count(*) FROM structure GROUP BY pdb");
    my $sth = $self->query_exec('dbh' => $dbh);
    my $table = $sth->fetchall_arrayref()
        or $self->_raise_error("\nE- [Artemis] Perl DBI fetching error\n\t");
    $sth->finish();
    $dbh->disconnect;
    my %limits; # numero di residui di ogni sistema
    foreach my $item (@{$table}) {
        $limits{$item->[0]} = $item->[1];
    }
    
    # lista di parametri per l'allestimento della tabella finale
    my %param;
    foreach my $pdbID (keys %limits) {
        $param{$pdbID.'APO'} = [$pdbID, 'APO', $dataset->{$pdbID}->{'EN_MATRIX_APO'}, $limits{$pdbID}];
        $param{$pdbID.'HOLO'} = [$pdbID, 'HOLO', $dataset->{$pdbID}->{'EN_MATRIX_HOLO'}, $limits{$pdbID}];
    }
#     foreach (sort keys %param) { print "\n[@{$param{$_}}]"; }
    
    # recupero dei dati sulle matrici
    $self->_raise_warning("\nI- [Artemis] parsing ED matrix file...");
    $running = 0E0; $queued = 0E0;
    print "\n";
    foreach my $jobname (sort keys %param) { # lancio i thread
        push @thr, threads->new(\&_matrix_import, $self, $jobname, $param{$jobname}->[0],  $param{$jobname}->[1],  $param{$jobname}->[2],  $param{$jobname}->[3]);
    }
    for (@thr) { $_->join() }; # aspetto che tutti i thread siano terminati
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [enematrix]...");
    $self->table_enematrix(\@jobcontent);
# ==============================================================================
    
    @thr = ( );
    @jobcontent = ( ); # libero memoria, non consigliabile usare undef in questo frangente
    
    return 1;
}

sub fluctuations {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    $self->_raise_warning("\nI- [Artemis] collecting fluctuations data...");
    foreach my $key (keys %{$dataset}) {
        my $pdbID = $key;
        my $apo_rmsf_data = $self->_xvg_parser($dataset->{$pdbID}->{'RMSF_APO'});
        my $olo_rmsf_data = $self->_xvg_parser($dataset->{$pdbID}->{'RMSF_HOLO'});
        
        for (my $i = 0; $i < scalar @{$apo_rmsf_data}; $i++) {
            my $apo_rmsf = $apo_rmsf_data->[$i][1];
            my $olo_rmsf = $olo_rmsf_data->[$i][1];
            my $row = [ $pdbID, $i+1, $apo_rmsf, $olo_rmsf ];
            push(@{$tmp_table}, $row);
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [rmsf]...");
    $self->table_rmsf($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub fludecomp {
    my ($self, $cutoff) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    # valore di default
    $cutoff = 6.5
        unless ($cutoff && $cutoff =~ /^[\d\-\.Ee]+$/);
    
# ***************************** ATTENZIONE *************************************
# I metodi e gli attributi di Chilon sono ereditati nella classe Artemis.
# D'altro canto, se voglio sfruttare le capacita' multithread di Chilon devo
# instanziare e usare un oggetto Chilon indipendente.
# ******************************************************************************
    my $chilon = SPARTA::lib::Chilon->new(
        'host'      => $self->get_host(),
        'database'  => $self->get_database(),
        'user'      => $self->get_user(),
        'password'  => $self->get_password(),
        'errfile'   => $self->get_errfile(),
        'dataset'   => $self->get_dataset()
    );
    
    # raccolgo i profili dei contributi energetici dati dagli autovettori più rappresentativi di ogni sistema 
    $self->_raise_warning("\nI- [Artemis] parsing fluctuations distribution");
    my $selected = $chilon->list('flu');
    
    # raffino i profili usando una matrice dei contatti
    $self->_raise_warning("\nI- [Artemis] refining fluctuations list");
    my $refined = $chilon->refine($selected, $cutoff);
    
    foreach my $ref (keys %{$refined}) {
        my @records = @{$refined->{$ref}};
        foreach my $triplet (@records) {
            my ($pdb,$form,$res) = $triplet =~ m/^(\w{4})-(APO|HOLO|BOTH)-(\d+)$/;
            push(@{$tmp_table}, [ $pdb, $res, $ref, $form ]);
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [fludecomp]...");
    $self->table_fludecomp($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub fludist {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    $self->_raise_warning("\nI- [Artemis] collecting energy distribution data...");
    foreach my $key (keys %{$dataset}) {
        my $pdbID = $key;
        my $apo_df_data = $self->_xvg_parser($dataset->{$pdbID}->{'DF_APO'});
        my $olo_df_data = $self->_xvg_parser($dataset->{$pdbID}->{'DF_HOLO'});
        for (my $i = 0; $i < scalar @{$apo_df_data}; $i++) {
            my $apo_df = $apo_df_data->[$i][1];
            my $olo_df = $olo_df_data->[$i][1];
            my $row = [ $pdbID, $i+1, $apo_df, $olo_df ];
            push(@{$tmp_table}, $row);
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [fludist]...");
    $self->table_fludist($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub flumatrix {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    # interrogo il database
    my $dbh = $self->access2db();
    $self->set_query_string("SELECT pdb, count(*) FROM structure GROUP BY pdb");
    my $sth = $self->query_exec('dbh' => $dbh);
    my $table = $sth->fetchall_arrayref()
        or $self->_raise_error("\nE- [Artemis] Perl DBI fetching error\n\t");
    $sth->finish();
    $dbh->disconnect;
    my %limits; # numero di residui di ogni sistema
    foreach my $item (@{$table}) {
        $limits{$item->[0]} = $item->[1];
    }
    
    # lista di parametri per l'allestimento della tabella finale
    my %param;
    foreach my $pdbID (keys %limits) {
        $param{$pdbID.'APO'} = [$pdbID, 'APO', $dataset->{$pdbID}->{'DF_MATRIX_APO'}, $limits{$pdbID}];
        $param{$pdbID.'HOLO'} = [$pdbID, 'HOLO', $dataset->{$pdbID}->{'DF_MATRIX_HOLO'}, $limits{$pdbID}];
    }
#     foreach (sort keys %param) { print "\n[@{$param{$_}}]"; }
    
    # recupero dei dati sulle matrici
    $self->_raise_warning("\nI- [Artemis] parsing DF matrix file...");
    $running = 0E0; $queued = 0E0;
    print "\n";
    foreach my $jobname (sort keys %param) { # lancio i thread
        push @thr, threads->new(\&_matrix_import, $self, $jobname, $param{$jobname}->[0],  $param{$jobname}->[1],  $param{$jobname}->[2],  $param{$jobname}->[3]);
    }
    for (@thr) { $_->join() }; # aspetto che tutti i thread siano terminati
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [flumatrix]...");
    $self->table_flumatrix(\@jobcontent);
# ==============================================================================
    
    @thr = ( );
    @jobcontent = ( ); # libero memoria, non consigliabile usare undef in questo frangente
    
    return 1;
}

sub pdbsum {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    $self->_raise_warning("\nI- [Artemis] gathering contact info at [http://www.ebi.ac.uk/]...");
    foreach my $pdbID (keys %{$dataset}) {
        print("\n\tsubmitting [$pdbID]...");
        my $heavy = $dataset->{$pdbID}->{'HEAVY_CHAIN'},
        my $light = $dataset->{$pdbID}->{'LIGHT_CHAIN'},
        my $ligand = $dataset->{$pdbID}->{'LIGAND_CHAIN'},
        my $arrayref = [ ];
        PDBSUM: { # interrogo il PDBsum dell'ebi e recupero una lista di contatti tra le catene dei fab e l'antigene
            my %hash_table; # tabella dei contatti
            
            { # CONTATTI tra heavy chain e light chain
                # richiesta del servizio web
                my $bot = LWP::UserAgent->new();
                $bot->agent('libwww-perl/5.805');
                my $pdb = lc $pdbID;
                my $request = $bot->post(
                    $self->get_pdbsum_url(),
                    # Content_type => 'multipart/form-data',
                    Content => [ 
                        pdb     => $pdb,
                        chain1  => $heavy,
                        chain2  => $light
                    ]
                );
                unless ( $request->is_success ) {
                    $self->_raise_error(sprintf("\nE- [Artemis] %s [%s]\n\t", $request->status_line, $request->base));
                };
                my $rawdata = $request->content();
                
                # parsing del risultato
                my @content = split(/\n/, $rawdata);
                shift @content; # la prima riga è un tag html credo
                my $header = shift @content;
                unless ( $header eq 'List of atom-atom interactions across protein-protein interface' ) {
                    # non ho reperito la pagina giusta dal web
                    $self->_raise_error(sprintf("\nE- [Artemis] bad retrieval at [%s]\n\t", $self->get_pdbsum_url()));
                };
                my $type;
                foreach my $row (@content) {
                    chomp $row;
                    if ($row =~ /^(Hydrogen bonds|Non-bonded contacts|Disulphide bonds|Salt bridges)$/) {
                        # definisco il tipo di contatti che verranno elencati a seguire
                        $type = $row;
                        next;
                    } elsif ($row =~ /^\s*\d+\./){
                        # dettaglio del contatto; aggiungere alla riga seguente eventuali residui non convenzionali
                        my ($resA, $idA, $resB, $idB) = $row =~ /(VAL|LEU|ILE|MET|PHE|ASN|GLU|GLN|ASP|HIS|LYS|ARG|GLY|ALA|CYS|SER|PRO|THR|TYR|TRP)\s+(\w+)\s+\w+\s+<-->[\s\w]+(VAL|LEU|ILE|MET|PHE|ASN|GLU|GLN|ASP|HIS|LYS|ARG|GLY|ALA|CYS|SER|PRO|THR|TYR|TRP)\s+(\w+)/;
                        next unless $resA;
                        next unless $resB;
                        # definisco un id univoco per il contatto trovato
                        my $unique_id = $type . 'H' . $resA . $idA . 'L' . $resB . $idB;
                        # by-passo le ridondanze
                        next if (exists $hash_table{$unique_id});
                        $hash_table{$unique_id} = [ $type, 'H', $resA, $idA, 'L', $resB, $idB];
                        next;
                    } elsif ($row =~ /^Number of /) {
                        # sono le righe finali della pagina, smetto di parsare
                        last;
                    } else {
                        # sono righe che non mi interessa parsare
                        next;
                    }
                }
            }
            
            { # CONTATTI tra light chain e heavy chain
                # richiesta del servizio web
                my $bot = LWP::UserAgent->new();
                $bot->agent('libwww-perl/5.805');
                my $pdb = lc $pdbID;
                my $request = $bot->post(
                    $self->get_pdbsum_url(),
                    # Content_type => 'multipart/form-data',
                    Content => [ 
                        pdb     => $pdb,
                        chain1  => $light,
                        chain2  => $heavy
                    ]
                );
                unless ( $request->is_success ) {
                    $self->_raise_error(sprintf("\nE- [Artemis] %s [%s]\n\t", $request->status_line, $request->base));
                };
                my $rawdata = $request->content();
                
                # parsing del risultato
                my @content = split(/\n/, $rawdata);
                shift @content; # la prima riga è un tag html credo
                my $header = shift @content;
                unless ( $header eq 'List of atom-atom interactions across protein-protein interface' ) {
                    # non ho reperito la pagina giusta dal web
                    $self->_raise_error(sprintf("\nE- [Artemis] bad retrieval at [%s]\n\t", $self->get_pdbsum_url()));
                };
                my $type;
                foreach my $row (@content) {
                    chomp $row;
                    if ($row =~ /^(Hydrogen bonds|Non-bonded contacts|Disulphide bonds|Salt bridges)$/) {
                        # definisco il tipo di contatti che verranno elencati a seguire
                        $type = $row;
                        next;
                    } elsif ($row =~ /^\s*\d+\./){
                        # dettaglio del contatto; aggiungere alla riga seguente eventuali residui non convenzionali
                        my ($resA, $idA, $resB, $idB) = $row =~ /(VAL|LEU|ILE|MET|PHE|ASN|GLU|GLN|ASP|HIS|LYS|ARG|GLY|ALA|CYS|SER|PRO|THR|TYR|TRP)\s+(\w+)\s+\w+\s+<-->[\s\w]+(VAL|LEU|ILE|MET|PHE|ASN|GLU|GLN|ASP|HIS|LYS|ARG|GLY|ALA|CYS|SER|PRO|THR|TYR|TRP)\s+(\w+)/;
                        next unless $resA;
                        next unless $resB;
                        # definisco un id univoco per il contatto trovato
                        my $unique_id = $type . 'L' . $resA . $idA . 'H' . $resB . $idB;
                        # by-passo le ridondanze
                        next if (exists $hash_table{$unique_id});
                        $hash_table{$unique_id} = [ $type, 'L', $resA, $idA, 'H', $resB, $idB];
                        next;
                    } elsif ($row =~ /^Number of /) {
                        # sono le righe finali della pagina, smetto di parsare
                        last;
                    } else {
                        # sono righe che non mi interessa parsare
                        next;
                    }
                }
            }
            
            { # CONTATTI tra heavy chain e antigene
                # richiesta del servizio web
                my $bot = LWP::UserAgent->new();
                $bot->agent('libwww-perl/5.805');
                my $pdb = lc $pdbID;
                my $request = $bot->post(
                    $self->get_pdbsum_url(),
                    # Content_type => 'multipart/form-data',
                    Content => [ 
                        pdb     => $pdb,
                        chain1  => $heavy,
                        chain2  => $ligand
                    ]
                );
                unless ( $request->is_success ) {
                    $self->_raise_error(sprintf("\nE- [Artemis] %s [%s]\n\t", $request->status_line, $request->base));
                };
                my $rawdata = $request->content();
                
                # parsing del risultato
                my @content = split(/\n/, $rawdata);
                shift @content; # la prima riga è un tag html credo
                my $header = shift @content;
                unless ( $header eq 'List of atom-atom interactions across protein-protein interface' ) {
                    # non ho reperito la pagina giusta dal web
                    $self->_raise_error(sprintf("\nE- [Artemis] bad retrieval at [%s]\n\t", $self->get_pdbsum_url()));
                };
                my $type;
                foreach my $row (@content) {
                    chomp $row;
                    if ($row =~ /^(Hydrogen bonds|Non-bonded contacts|Disulphide bonds|Salt bridges)$/) {
                        # definisco il tipo di contatti che verranno elencati a seguire
                        $type = $row;
                        next;
                    } elsif ($row =~ /^\s*\d+\./){
                        # dettaglio del contatto; aggiungere alla riga seguente eventuali residui non convenzionali
                        my ($resA, $idA, $resB, $idB) = $row =~ /(VAL|LEU|ILE|MET|PHE|ASN|GLU|GLN|ASP|HIS|LYS|ARG|GLY|ALA|CYS|SER|PRO|THR|TYR|TRP)\s+(\w+)\s+\w+\s+<-->[\s\w]+(VAL|LEU|ILE|MET|PHE|ASN|GLU|GLN|ASP|HIS|LYS|ARG|GLY|ALA|CYS|SER|PRO|THR|TYR|TRP)\s+(\w+)/;
                        next unless $resA;
                        next unless $resB;
                        # definisco un id univoco per il contatto trovato
                        my $unique_id = $type . 'H' . $resA . $idA . 'A' . $resB . $idB;
                        # by-passo le ridondanze
                        next if (exists $hash_table{$unique_id});
                        $hash_table{$unique_id} = [ $type, 'H', $resA, $idA, 'A', $resB, $idB];
                        next;
                    } elsif ($row =~ /^Number of /) {
                        # sono le righe finali della pagina, smetto di parsare
                        last;
                    } else {
                        # sono righe che non mi interessa parsare
                        next;
                    }
                }
            }
            
            { # CONTATTI tra light chain e antigene
                # richiesta del servizio web
                my $bot = LWP::UserAgent->new();
                $bot->agent('libwww-perl/5.805');
                my $pdb = lc $pdbID;
                my $request = $bot->post(
                    $self->get_pdbsum_url(),
                    # Content_type => 'multipart/form-data',
                    Content => [ 
                        pdb     => $pdb,
                        chain1  => $light,
                        chain2  => $ligand
                    ]
                );
                unless ( $request->is_success ) {
                    $self->_raise_error(sprintf("\nE- [Artemis] %s [%s]\n\t", $request->status_line, $request->base));
                };
                my $rawdata = $request->content();
                
                # parsing del risultato
                my @content = split(/\n/, $rawdata);
                shift @content; # la prima riga è un tag html credo
                my $header = shift @content;
                unless ( $header eq 'List of atom-atom interactions across protein-protein interface' ) {
                    # non ho reperito la pagina giusta dal web
                    $self->_raise_error(sprintf("\nE- [Artemis] bad retrieval at [%s]\n\t", $self->get_pdbsum_url()));
                };
                my $type;
                foreach my $row (@content) {
                    chomp $row;
                    if ($row =~ /^(Hydrogen bonds|Non-bonded contacts|Disulphide bonds|Salt bridges)$/) {
                        # definisco il tipo di contatti che verranno elencati a seguire
                        $type = $row;
                        next;
                    } elsif ($row =~ /^\s*\d+\./){
                        # dettaglio del contatto, aggiungere alla riga seguente eventuali residui non convenzionali
                        my ($resA, $idA, $resB, $idB) = $row =~ /(VAL|LEU|ILE|MET|PHE|ASN|GLU|GLN|ASP|HIS|LYS|ARG|GLY|ALA|CYS|SER|PRO|THR|TYR|TRP)\s+(\w+)\s+\w+\s+<-->[\s\w]+(VAL|LEU|ILE|MET|PHE|ASN|GLU|GLN|ASP|HIS|LYS|ARG|GLY|ALA|CYS|SER|PRO|THR|TYR|TRP)\s+(\w+)/;
                        next unless $resA;
                        next unless $resB;
                        # definisco un id univoco per il contatto trovato
                        my $unique_id = $type . 'L' .  $resA . $idA . 'A' . $resB . $idB;
                        # by-passo le ridondanze
                        next if (exists $hash_table{$unique_id});
                        $hash_table{$unique_id} = [ $type, 'L', $resA, $idA, 'A', $resB, $idB];
                        next;
                    } elsif ($row =~ /^Number of /) {
                        # sono le righe finali della pagina, smetto di parsare
                        last;
                    } else {
                        # sono righe che non mi interessa parsare
                        next;
                    }
                }
            }
            
            # filtro di non-ridondanza: le interazioni le classifico secondo la gerarchia ponte disolfuro | ponte salino > legame idrogeno > contatto x prossimità
            foreach my $key (keys %hash_table) {
                next unless (exists $hash_table{$key});
                my @record = @{$hash_table{$key}};
                my $generic_key = $record[1] . $record[2] . $record[3] . $record[4] . $record[5] . $record[6];
                if (exists $hash_table{'Disulphide bonds'.$generic_key}) {
                    delete $hash_table{'Non-bonded contacts'.$generic_key}
                        if (exists $hash_table{'Non-bonded contacts'.$generic_key});
                
                } elsif (exists $hash_table{'Salt bridges'.$generic_key}) {
                    delete $hash_table{'Non-bonded contacts'.$generic_key}
                        if (exists $hash_table{'Non-bonded contacts'.$generic_key});
                    delete $hash_table{'Hydrogen bonds'.$generic_key}
                        if (exists $hash_table{'Hydrogen bonds'.$generic_key});
                
                } elsif (exists $hash_table{'Hydrogen bonds'.$generic_key}) {
                    delete $hash_table{'Non-bonded contacts'.$generic_key}
                        if (exists $hash_table{'Non-bonded contacts'.$generic_key});
                
                } else {
                    next;
                }
            }
            
            # formatto l'output da ritornare
            foreach my $key (sort keys %hash_table) {
                unshift(@{$hash_table{$key}}, $pdbID);
                push (@{$arrayref}, $hash_table{$key})
            }
        }
        
        push(@{$tmp_table}, @{$arrayref});
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [pdbsum]...");
    $self->table_pdbsum($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub rcsb {
    my ($self) = @_;
    my $dataset = $self->get_dataset();

    $self->_raise_warning(sprintf("\nI- [Artemis] fetching data from [%s]...", $self->get_rcsb_url()));
    
# === recupero la lista dei PDB del dataset ====================================
    my @pdbID = sort keys %{$dataset};
    my $pdbstring = join(',' , @pdbID);
# ==============================================================================
    
# === scelgo quali informazioni reperire dal Protein Data Bank ================= 
    my $fields = { # lista dei campi selezionabili, con 1 spunto quelli che mi interessano
        'structureId' => 1, # PDB ID
        # *** Structure Summary
        'classification' => 0, # Classification of molecule types
        'ndbId' => 0, # Cross reference to Nucleic Acid Database
        'resolution' => 1, # level of detail present in the diffraction pattern
        'structureTitle' => 1, # Title assigned by authors
        
        # *** Sequence
        'chainId' => 1, # ID of the chain
        'db_id' => 1, # sequence id in external database
        'db_name' => 1, # name of external sequence database
        'secondaryStructure' => 0, # sequence and secondary structure accortding to Kabsch and Sander (ie DSSP)
        'sequence' => 0, # one-letter sequence
        
        # *** Biologica details
        'biologicalProcess' => 0, # GO BP list
        'cellularComponent' => 0, # GO CC list
        'compound' => 0, # macromolecule name
        'molecularFunction' => 0, # GO MF list
        'source' => 0, # the origin of the gene from which the macromolecule was expressed or isolated
        'taxonomyId' => 0, # NCBI taxonomy id
        
        # *** Domain details
        'cathId' => 0,
        'cathDescription' => 0,
        'scopId' => 0,
        'scopDomain' => 0,
        'scopFold' => 0,
        'pfamAccession' => 0,
        'pfamId' => 0,
        'pfamDescription' => 0,
        
        # *** Primary citation
        'citationAuthor' => 0,
        'firstPage' => 0,
        'lastPage' => 0,
        'journalName' => 0,
        'title' => 0,
        'volumeId' => 0,
        'publicationYear' => 0,
        'pubmedId' => 1,
    };
    my @fieldlist;
    my @sorted = sort keys %{$fields};
    foreach my $id (@sorted) {
        push (@fieldlist, $id)
            if ($fields->{$id} == 1);
    };
    my $fieldstring = join(',' , @fieldlist);
# ==============================================================================

# === lancio il servizio web ===================================================
    my $getString = $self->get_rcsb_url() . '?pdbids=' . $pdbstring . '&customReportColumns=' . $fieldstring . '&service=wsdisplay&format=csv';
    
    # invio richiesta al servizio web
    my $bot = LWP::UserAgent->new();
    $bot->agent('libwww-perl/5.805');
    my $request = $bot->get($getString);
    unless ( $request->is_success ) {
        $self->raise_error(sprintf("\nE- [Artemis] %s [%s]\n\t", $request->status_line, $request->base));
    };
# ==============================================================================

# === formattazione dell'output ================================================
    my $raw = $request->content(); # contenuto grezzo
    my @rows = split('<br />', $raw); # ...suddiviso per righe
    my $content = [ ];
    shift @rows; # rimuovo la prima riga, header
    while (my $row = shift @rows) {
        $row =~ s/"$//;
        $row =~ s/^"//;
        my $record; 
        @{$record} = split('","', $row);
        push(@{$content}, $record);
    }
# ==============================================================================
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [summary]...");
    $self->table_summary($content);
# ==============================================================================
    
    return $content;
}

sub refschema {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    my $pdblist = { }; # lista dei file pdb da considerare
    foreach my $key (keys %{$dataset}) {
        $pdblist->{$key} = $dataset->{$key}->{'PDB'};
    }
    
    $self->_raise_warning("\nI- [Artemis] performing structural alignments...");
    my $tmp_dir = $ENV{HOME} . '/.SPARTA';;
    my $aligned = $self->_pdbsplitter($pdblist, $tmp_dir); # creo dei pdb contenenti solo le catene costanti
    
    $self->_raise_warning("\nI- [Artemis] defining numbering schema");
    my $chain;
    
    # SCHEMA X I DOMINI COSTANTI
    my $domain = 'C';
    foreach my $key (keys %{$aligned}) {
        $chain = 'H' if ($key eq 'HEAVY');
        $chain = 'L' if ($key eq 'LIGHT');
        foreach my $pdbID (keys %{$aligned->{$key}}) {
            my $string = $aligned->{$key}->{$pdbID};
            my ($real, $seq) = $string =~ m/^(\d+)\|([A-Za-z\-]+)\*$/;
            my @res = split('', $seq);
            my $ref = 1;
            while (my $letter = shift @res) {
                my $label = sprintf("%04s", $ref);
                if ($letter =~ /[A-Z]{1}/) {
                    push(@{$tmp_table}, [ $pdbID, $real, $domain.$chain.'-'.$label ]);
                    $real++;
                    $ref++;
                } elsif ($letter =~ /\-{1}/) {
                    $ref++;
                }
            }
        }
    }
    
    # SCHEMA X I DOMINI VARIABILI
    my $query = <<END
SELECT structure.pdb, structure.res, structure.domain, structure.chain, abnum.abnum
FROM structure
JOIN abnum
ON structure.pdb = abnum.pdb
AND structure.res = abnum.res
WHERE structure.domain = 'V';
END
    ;
    my $dbh = $self->access2db(); # accedo al database di SPARTA
    my $sth; # statement handle
    $self->set_query_string($query);
    $sth = $self->query_exec(dbh => $dbh);
    while (my @row = $sth->fetchrow_array()) {
        my ($number,$letter) = $row[4] =~ /(\d+)(\w*)/;
        my $label = sprintf("%04d%s", $number, $letter);
        push(@{$tmp_table}, [ $row[0], $row[1], $row[2].$row[3].'-'.$label ]);
    }
    $sth->finish;
    $dbh->disconnect; # mi disconnetto dal database di SPARTA
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [refschema]...");
    $self->table_refschema($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub resdiff {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $arrayref = [ ]; # tabella temporanea da uploadare sul DB
    
    $self->_raise_warning(sprintf("\nI- [Artemis] searching crossrefs among residues...", $self->get_rcsb_url()));
    foreach my $key (keys %{$dataset}) {
        # HEAVY CHAIN
        my $pdb1 = $dataset->{$key}->{'PDB'};
        my $chain1 = 'H';
        my $pdb2 = $dataset->{$key}->{'PDB_SOURCE'};
        my $chain2 = $dataset->{$key}->{'HEAVY_CHAIN'};
        my $diff = $self->_pdbdiff($pdb1, $chain1, $pdb2, $chain2);
        foreach my $row (@{$diff}) {
            push(@{$arrayref}, [ $key, $chain1, $row->[0], $chain2, $row->[1] ]);
        }
        
        # LIGHT CHAIN
        $pdb1 = $dataset->{$key}->{'PDB'};
        $chain1 = 'L';
        $pdb2 = $dataset->{$key}->{'PDB_SOURCE'};
        $chain2 = $dataset->{$key}->{'LIGHT_CHAIN'};
        $diff = $self->_pdbdiff($pdb1, $chain1, $pdb2, $chain2);
        foreach my $row (@{$diff}) {
            push(@{$arrayref}, [ $key, $chain1, $row->[0], $chain2, $row->[1] ]);
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [xres]...");
    $self->table_xres($arrayref);
# ==============================================================================
    
    return $arrayref;
}

sub rmsd {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    $self->_raise_warning("\nI- [Artemis] collecting RMSD profiles...");
    foreach my $key (keys %{$dataset}) {
        my $pdbID = $key;
        
        # leggo il file xvg del profilo RMSD x la forma APO
        my $rmsd = $self->_xvg_parser($dataset->{$key}->{'RMSD_APO'});
        while (my $values = shift @{$rmsd}) {
            my $rmsd = sprintf("%.8f", $values->[0]);
            my $samples = sprintf("%d", $values->[1]);
            my $record = [ $key, 'APO', $rmsd, $samples ];
            push(@{$tmp_table}, $record);
        }
        
        # faccio la stessa menata per la HOLO
        $rmsd = $self->_xvg_parser($dataset->{$key}->{'RMSD_HOLO'});
        while (my $values = shift @{$rmsd}) {
            my $rmsd = sprintf("%.8f", $values->[0]);
            my $samples = sprintf("%d", $values->[1]);
            my $record = [ $key, 'HOLO', $rmsd, $samples ];
            push(@{$tmp_table}, $record);
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [rmsd]...");
    $self->table_rmsd($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub upload_seqs {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    foreach my $key (keys %{$dataset}) {
        my $pdbID = $key;
        my $pdbfile = $dataset->{$key}->{'PDB'};
        my $hash_table = { };
        PDB2SEQ: { # da ogni PDB estraggo la sequenza one-letter code
            my %aa = (
                'VAL' => 'V', 'LEU' => 'L', 'ILE' => 'I', 'MET' => 'M', 'PHE' => 'F',
                'ASN' => 'N', 'GLU' => 'E', 'GLN' => 'Q', 'ASP' => 'D', 'HIS' => 'H',
                'LYS' => 'K', 'ARG' => 'R', 'GLY' => 'G', 'ALA' => 'A', 'SER' => 'S',
                'CYS' => 'C', 'PRO' => 'P', 'THR' => 'T', 'TYR' => 'Y', 'TRP' => 'W' 
            );
            $self->set_filename($pdbfile);
            my $pdb_content = $self->read();
            while (my $row = shift @{$pdb_content}) {
                next if ($row !~ /^ATOM\s+\d+\s+CA\s+/);
                my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $row);
                my ($chain, $res) = ($splitted[7], $splitted[5]);
                if (exists $hash_table->{$chain}) {
                    push(@{$hash_table->{$chain}}, $aa{$res});
                } else {
                    $hash_table->{$chain} = [ ];
                    push(@{$hash_table->{$chain}}, $aa{$res});
                }
            }
            foreach my $chain (keys %{$hash_table}) {
                my @value = @{$hash_table->{$chain}};
                $hash_table->{$chain} = join('', @value);
            }
        }
        foreach my $chain (keys %{$hash_table}) {
            my $record = [ $pdbID, $chain, $hash_table->{$chain} ];
            push(@{$tmp_table}, $record);
        }
    }
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [sequence]...");
    $self->table_sequence($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub upload_structure {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    my $tmp_table = [ ]; # tabella temporanea da uploadare sul DB
    
    $self->_raise_warning("\nI- [Artemis] gahering structural info...");
    my $dbh = $self->access2db(); # accedo al database di SPARTA
    foreach my $pdbID (keys %{$dataset}) {
        my $arrayref =  [ ];
        STRUCTURE: { # Interroga il database e reperisce informazioni dall'addressbook su una serie di annotazioni strutturali relative ad un pdb.
            my %aa = (
                'V' => 'VAL', 'L' => 'LEU', 'I' => 'ILE', 'M' => 'MET', 'F' => 'PHE',
                'N' => 'ASN', 'E' => 'GLU', 'Q' => 'GLN', 'D' => 'ASP', 'H' => 'HIS',
                'K' => 'LYS', 'R' => 'ARG', 'G' => 'GLY', 'A' => 'ALA', 'S' => 'SER',
                'C' => 'CYS', 'P' => 'PRO', 'T' => 'THR', 'Y' => 'TYR', 'W' => 'TRP' 
            );
            my $sth; # statement handle
            my %fetch; # tabella temporanea in cui salvo i risultati delle query
            # recupero le sequenze primarie dal database e, per ogni residuo, annoto la catena
            $self->set_query_string('SELECT chain, seq FROM sequence WHERE pdb = ?');
            $sth = $self->query_exec(dbh => $dbh, bindings => [ $pdbID ]);
            while (my @row = $sth->fetchrow_array()) {
                # key = chain; value = sequence
                $fetch{$row[0]} = $row[1];
            }
            # dal momento che i gro file di GROMACS indicizzano tutti i residui delle catene in maniera continua assumo che la prima catena sia la H e la seconda sia la L
            my $resID = 1;
            foreach my $chain ('H','L') {
                my @sequence = split('',$fetch{$chain});
                foreach my $res (@sequence) {
                    my $resname = $aa{$res};
                    my $record = [ $pdbID, $chain, $resID, $resname];
                    push(@{$arrayref}, $record);
                    $resID++;
                }
            }
            
            # per ogni residuo annoto la sua appartenenza ad un dominio ed eventualmente ad una regione ipervariabile
            $self->set_query_string('SELECT res, chain, kabat, chothia FROM abnum WHERE pdb = ?');
            $sth = $self->query_exec(dbh => $dbh, bindings => [ $pdbID ]);
            undef %fetch;
            my %kabat;
            while (my @row = $sth->fetchrow_array()) {
                $fetch{$row[0]} = [ $row[1], $row[2],$row[3] ];
                $kabat{$row[1] . $row[2]} = 1;
            }
            foreach my $record (@{$arrayref}) {
                my $resID = $record->[2]; # numero ufficiale del residuo nel file PDB
                if (exists $fetch{$resID}) {
                    # il residuo appartiene ad un dominio variabile
                    push(@{$record}, 'V');
                    my $chain = $fetch{$resID}->[0];
                    my ($chothia) = $fetch{$resID}->[2] =~ m/(\d+)/g;
                    if ($chain eq 'H') { # regioni iper-variabili della catena pesante
                        my $end; # la parte terminale di CDR H1 è variabile
                        if (exists $kabat{'H35A'}) {
                            if (exists $kabat{'H35B'}) {
                                $end = 34;
                            } else {
                                $end = 33;
                            }
                        } else {
                            $end = 32;
                        }
                        if ($chothia < 26) {
                            push(@{$record}, 'HFR1');
                        } elsif (($chothia >= 26) && ($chothia <= $end)) {
                            push(@{$record}, 'CDR-H1');
                        } elsif (($chothia > $end) && ($chothia < 52)) {
                            push(@{$record}, 'HFR2');
                        } elsif (($chothia >= 52) && ($chothia <= 56)) {
                            push(@{$record}, 'CDR-H2');
                        } elsif (($chothia > 56) && ($chothia < 95)) {
                            push(@{$record}, 'HFR3');
                        } elsif (($chothia >= 95) && ($chothia <= 102)) {
                            push(@{$record}, 'CDR-H3');
                        } elsif ($chothia > 102) { 
                            push(@{$record}, 'HFR4');
                        } else {
                            push(@{$record}, '???');
                        }
                    } elsif ($chain eq 'L') { # regioni iper-variabili della catena leggera
                        if ($chothia < 24) {
                            push(@{$record}, 'LFR1');
                        } elsif (($chothia >= 24) && ($chothia <= 34)) {
                            push(@{$record}, 'CDR-L1');
                        } elsif (($chothia > 34) && ($chothia < 50)) {
                            push(@{$record}, 'LFR2');
                        } elsif (($chothia >= 50) && ($chothia <= 56)) {
                            push(@{$record}, 'CDR-L2');
                        } elsif (($chothia > 56) && ($chothia < 89)) {
                            push(@{$record}, 'LFR3');
                        } elsif (($chothia >= 89) && ($chothia <= 97)) {
                            push(@{$record}, 'CDR-L3');
                        } elsif ($chothia > 97) {
                            push(@{$record}, 'LFR4');
                        } else {
                            push(@{$record}, '???');
                        }
                    } else {
                        $self->_raise_error("\nE- [Artemis] residue indexing error\n\t");
                    }
                } else {
                    # il residuo appartiene ad un dominio costante
                    push(@{$record}, 'C');
                    # non ci sono regioni iper-variabili qui
                    push(@{$record}, '');
                }
            }
            
            # per ogni residuo definisco l'appartenenza ad un elemento di struttura secondaria
            my $dssp_file = $dataset->{$pdbID}->{'DSSP'};
            my $dssp_profile = [ ];
            DSSP: { # leggo un profilo DSSP creato con il comando di GROMACS "do_dssp -s topol_file.tpr -f traj_file.xtc -ssdump". Il file di output 'ssdump.dat' contiene una stringa con il profilo di struttura secondaria della sequenza amminoacidica full-chains.
                
                # LEGENDA SIMBOLI:
                # "~" Coil, "E" B-Sheet, "B" B-Bridge, "S" Bend, "T" Turn, "H" A-Helix,
                # "I" 5-Helix, "G" 3-Helix
                # (x motivi tecnici sostituisco i caratteri "~" con "C")
                
                # leggo il profilo di struttura secondaria
                my $dat_content = $self->read($dssp_file);
                my $profile = $dat_content->[1];
                chomp $profile;
                
                # formattazione
                $profile =~ tr/\~/C/;
                @{$dssp_profile} = split('', $profile);
            }
            $resID = 0;
            while (my $sec = shift @{$dssp_profile}) {
                push(@{$arrayref->[$resID]}, $sec);
                $resID++;
            }
            
            # per ogni residuo annoto se in quel PDB è noto da letteratura che sia in contatto con l'antigene
            my $rawdata = $dataset->{$pdbID}->{'KNOWN_CONTACTS'};
            my %blacklist;
            unless ($rawdata eq 'null') { # verifico che ci sia qualcosa di noto
                foreach my $resID (split(',',$rawdata)) {
                    $blacklist{$resID} = 1;
                }
            }
            foreach my $record (@{$arrayref}) {
                my $resID = $record->[2];
                if (exists $blacklist{$resID}) {
                    push(@{$record}, '1');
                } else {
                    push(@{$record}, '');
                }
            }
        
            # definisco la regione cerniera tra i domini costanti e variabili
            for (my $i = 0; $i < scalar(@{$arrayref}); $i++ ){
                my $prev = ${$arrayref}[$i];
                my $next = ${$arrayref}[$i+1];
                if (($prev->[4] eq 'V') && ($next->[4] eq 'C')) {
                    # se siamo al confine tra dominio variabile e costante...
        #             print join('|',@{$prev}), "\n";
        #             print join('|',@{$next}), "\n";
        #             print "\n"
                    for (my $j = $i - 4; $j < $i + 8; $j++ ){
                        my $record = ${$arrayref}[$j];
                        $record->[5] = 'HINGE'
                            unless ($record->[6] eq 'E');
                    }
                }
            }
            
            # definisco il C-terminale
            for (my $i = 0; $i < scalar(@{$arrayref}); $i++ ) {
                my $record = ${$arrayref}[$i];
                my $next_chain = '%';
                $next_chain = $arrayref->[$i+1]->[1]
                    if ($arrayref->[$i+1]);
                unless ($record->[1] eq $next_chain) {
                    for (my $j = $i - 4; $j <= $i; $j++ ){
                        $arrayref->[$j]->[5] = 'CTER';
                    }
                }
            }
        }
        
        push(@{$tmp_table}, @{$arrayref});
    }
    $dbh->disconnect; # mi disconnetto dal database di SPARTA
    
# ===  carico i risultati sul database =========================================
    $self->_raise_warning("\nI- [Artemis] creating table [structure]...");
    $self->table_structure($tmp_table);
# ==============================================================================
    
    return $tmp_table;
}

sub _matrix_import {
# parsing dei .dat file relativi alle matrici
    my ($self, $jobname, $pdbID, $form, $datfile, $limit) = @_; # $limit definisce l'ultimo residuo entro cui reperire i valori
    
    
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        lock $queued; $queued = $queued + 1;
        $self->_thread_monitor();
    }
    $semaforo->down(); # occupo uno slot
    { lock $running; $running = $running + 1; }
    $self->_thread_monitor();
    
    my $table = $self->_xvg_parser($datfile);
    
    my $matrix = [ ]; my $item;
    while ($item = shift @{$table}) {
        $matrix->[$item->[0]][$item->[1]] = $item->[2];
    }
    # printf("\n\tmatrix dims %d x %d", scalar @{$matrix}, scalar @{$matrix->[1]});
    
    # RIDONDANZA: dal momento che ho a che fare con una matrice simmetrica i cui valori sulla diagonale sono pari a zero posso ridurre il numero di dati che mi serve tenere
    my $nr_data = [ ];
    $limit = scalar @{$matrix} - 1 unless $limit;
    my ($i, $j, $row);
    for ($i = 1; $i <= $limit; $i++) {
        for ($j = $i + 1; $j <= $limit; $j++) {
            $row = [ $i, $j, $matrix->[$i][$j] ];
            push(@{$nr_data}, $row);
        }
    }
    undef $matrix; # libero memoria
#     foreach (@$nr_data) { print "\n". join("\t", @$_); };
    
    {
        lock @jobcontent;
        my ($value, $record);
        while ($value = shift @{$nr_data}) {
            $record = "$pdbID\t$form\t";
            $record .= join("\t", @{$value});
            $record .= "\n";
            push(@jobcontent, $record);
        }
    }
    undef $nr_data; # libero memoria
    
    {
        lock $running; $running = $running - 1;
        lock $queued; $queued = $queued - 1;
        $queued = 0E0 if ($queued <= 0);
        $running = 0E0 if ($running <= 0);
    }
    $self->_thread_monitor();
    $semaforo->up(); # libero uno slot
}

sub _NeedlmanWunsch {
# Metodo privato x l'allineamento globale di due sequenze
# Ritorna un arrayref con le due sequenze fittate con spacer '-'

    my ($self, $seqA, $seqB) = @_;
    
    $self->_raise_error("\nE- [Menelaus] no sequence to align...\n\t")
        unless ($seqA && $seqB);
    
    #Parameters:
    my $match=10;
    my $mismatch=-10;
    my $gop=-10;
    my $gep=-10;
    
    # split the sequences
    my @res0;
    $res0[0] = [ $seqA =~ /([a-zA-Z-]{1})/g ];
    my @res1;
    $res1[0] = [ $seqB =~ /([a-zA-Z-]{1})/g ];
    
    # evaluate substitutions
    my $len0 = length $seqA;
    my $len1 = length $seqB;
    
    my ($i, $j);
    my @smat;
    my @tb;
    for ($i=0; $i <= $len0; $i++) {
        $smat[$i][0] = $i * $gep;
        $tb[$i][0 ] = 1;
    }
    for ($j=0; $j <= $len1; $j++) {
        $smat[0][$j] = $j * $gep;
        $tb[0 ][$j] = -1;
    }
    
    my $s;
    for ($i=1; $i <= $len0; $i++) {
        for ($j=1; $j <= $len1; $j++) {
            #calcolo dello score
            if ($res0[0][$i-1] eq $res1[0][$j-1]) {
                $s = $match;
            } else {
                $s = $mismatch;
            }
            
            my $sub = $smat[$i-1][$j-1] + $s;
            my $del = $smat[$i  ][$j-1] + $gep;
            my $ins = $smat[$i-1][$j  ] + $gep;
            
            if ($sub > $del && $sub > $ins) {
                $smat[$i][$j] = $sub;
                $tb[$i][$j] = 0;
            } elsif($del > $ins) {
                $smat[$i][$j] = $del;
                $tb[$i][$j] = -1;
            } else {
                $smat[$i][$j] = $ins;
                $tb[$i][$j] = 1;
            }
        }
    }
    
    $i = $len0;
    $j = $len1;
    my $aln_len = 0;
    my @aln0;
    my @aln1;
    while (!($i == 0 && $j == 0)) {
        if ($tb[$i][$j] == 0) {
            $aln0[$aln_len] = $res0[0][--$i];
            $aln1[$aln_len] = $res1[0][--$j];
        } elsif ($tb[$i][$j] == -1) {
            $aln0[$aln_len] = '-';
            $aln1[$aln_len] = $res1[0][--$j];
        } elsif ($tb[$i][$j] == 1) {
            $aln0[$aln_len] = $res0[0][--$i];
            $aln1[$aln_len] = '-';
        }
        $aln_len++;
    }
    
    # Output
    my $string; my $arrayref = [ ];
    for ($i = $aln_len - 1; $i >= 0; $i--) { 
        $string .= $aln0[$i];
    }
    $arrayref->[0] = $string;
    undef $string;;
    for ($j = $aln_len - 1; $j >= 0; $j--) {
        $string .= $aln1[$j];
    }
    $arrayref->[1] = $string;
    
    return $arrayref;
}

sub _pdbdiff {
# Confronta due catene di due file PDB, li allinea, e ritorna i match in forma tabulata 
    my ($self, $pdb1, $chain1, $pdb2, $chain2) = @_;
    my %aa = (
        'VAL' => 'V', 'LEU' => 'L', 'ILE' => 'I', 'MET' => 'M', 'PHE' => 'F',
        'ASN' => 'N', 'GLU' => 'E', 'GLN' => 'Q', 'ASP' => 'D', 'HIS' => 'H',
        'LYS' => 'K', 'ARG' => 'R', 'GLY' => 'G', 'ALA' => 'A', 'SER' => 'S',
        'CYS' => 'C', 'PRO' => 'P', 'THR' => 'T', 'TYR' => 'Y', 'TRP' => 'W' 
    );
    
    # Parso il PDB1
    $self->set_filename($pdb1);
    my $pdb_content = $self->read();
    
    my @index1; my $seq1;
    while (my $row = shift @{$pdb_content}) {
        next if ($row !~ /^ATOM\s+\d+\s+CA\s+/);
        my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $row);
        next if ($splitted[7] !~ /^$chain1$/);
        my $resname = $splitted[5];
        my $resid = $splitted[8] . $splitted[9];
        $resid =~ s/\s//g;
        if (exists $aa{$resname}) {
            push(@index1, $resid);
            $seq1 .= $aa{$resname};
        }
    }
    
    # Parso il PDB2
    $self->set_filename($pdb2);
    $pdb_content = $self->read();
    
    my @index2; my $seq2;
    while (my $row = shift @{$pdb_content}) {
        next if ($row !~ /^ATOM\s+\d+\s+CA\s+/);
        my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $row);
        next if ($splitted[7] !~ /^$chain2$/);
        my $resname = $splitted[5];
        my $resid = $splitted[8] . $splitted[9];
        $resid =~ s/\s//g;
        if (exists $aa{$resname}) {
            push(@index2, $resid);
            $seq2 .= $aa{$resname};
        }
    }
    
    my $arrayref;
    
    # confronto allineamento globale delle sequenze
    my $globalign = $self->_NeedlmanWunsch($seq1,$seq2);
    my @fit1 = split('', $globalign->[0]);
    my @fit2 = split('', $globalign->[1]);
    my ($progress1, $progress2);
    my $max = scalar(@fit1);
    for (my $i = 0; $i <= $max - 1; $i++) {
        my $token1 = shift @fit1;
        if ($token1 !~ /^-$/) {
            $progress1 ++;
        }
        my $token2 = shift @fit2;
        if ($token2 !~ /^-$/) {
            $progress2 ++;
        }
        
        if ($token1 !~ /^-$/ && $token2 !~ /^-$/) {
            my ($id1, $id2) = ($index1[$progress1 - 1], $index2[$progress2 - 1]);
            my $row = [ $id1, $id2 ];
            push(@{$arrayref}, $row);
        } 
    }

    return $arrayref;
}

sub _pdbsplitter {
# Legge i pdb dei Fab ed estrapola i domini costanti delle catene leggere e pasanti.
# Quindi lancia gli allinemanti strutturali dei domini CH e CL.
# Ritorna una numerazione di riferimento derivata dall'allineamento. 
    
    my ($self, $pdblist, $path) = @_;
    
    # allestisco i path di destinazione
    my $CH_path = $path . '/CH';
    system("rm -rf $CH_path") if (-e $CH_path);
    mkdir $CH_path;
    my $CL_path = $path . '/CL';
    system("rm -rf $CL_path") if (-e $CL_path);
    mkdir $CL_path;
    
    # definisco il range dei domini costanti di ogni catena
    my $limits = { };
    my $dbh = $self->access2db();
    foreach my $pdbID (keys %{$pdblist}) {
        # interrogo il database
        my $sth = $self->query_exec(
            'dbh' => $dbh,
            'query' => "SELECT chain, res FROM structure WHERE domain LIKE 'C' AND pdb LIKE ? ORDER BY res + 0 ASC;",
            'bindings' => [ $pdbID ]
        );
        
        #recupero la query e la parso
        $limits->{$pdbID} = { 'H' => [ 10000 , 0E0 ], 'L' => [ 10000 , 0E0] };
        my ($min, $max);
        while (my @row = $sth->fetchrow_array) {
            if ($row[0] eq 'H') {
                $min = $limits->{$pdbID}->{'H'}->[0];
                $max = $limits->{$pdbID}->{'H'}->[1];
                if ($row[1] < $min) {
                    $limits->{$pdbID}->{'H'}->[0] = $row[1];
                } elsif ($row[1] > $max) {
                    $limits->{$pdbID}->{'H'}->[1] = $row[1];
                }
                
            } elsif ($row[0] eq 'L') {
                $min = $limits->{$pdbID}->{'L'}->[0];
                $max = $limits->{$pdbID}->{'L'}->[1];
                if ($row[1] < $min) {
                    $limits->{$pdbID}->{'L'}->[0] = $row[1];
                } elsif ($row[1] > $max) {
                    $limits->{$pdbID}->{'L'}->[1] = $row[1];
                }
            } else {
                next;
            }
        }
        $sth->finish();
    }
    $dbh->disconnect;
    
    # creo i file pdb
    my $filename;
    my $in_content = [ ];
    my $out_content_L = [ ];
    my $out_content_H = [ ];
    foreach my $pdbID (keys %{$pdblist}) {
        $filename = $pdblist->{$pdbID};
        $in_content = $self->read($filename);
        while (my $newline = shift @{$in_content}) {
            chomp $newline;
            next unless ($newline =~ /^ATOM/);
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            my ($res) = $splitted[8] =~ /(\d+)/;
            if ($res >= $limits->{$pdbID}->{'H'}->[0] && $res <= $limits->{$pdbID}->{'H'}->[1]) {
                push(@{$out_content_H}, $newline."\n");
            } elsif ($res >= $limits->{$pdbID}->{'L'}->[0] && $res <= $limits->{$pdbID}->{'L'}->[1]) {
                push(@{$out_content_L}, $newline."\n");
            } else {
                next;
            }
        }
        push(@{$out_content_H}, "END\n");
        $self->write(
            'filename' => $CH_path."/$pdbID.pdb",
            'filedata' => $out_content_H
        );
        $out_content_H = [ ];
        push(@{$out_content_L}, "END\n");
        $self->write(
            'filename' => $CL_path."/$pdbID.pdb",
            'filedata' => $out_content_L
        );
        $out_content_L = [ ];
    }
    
    # lancio Mustang per i domini CH e CL
    my $mustang_bin = qx/which mustang-3.2.1 2> \/dev\/null/;
    $self->_raise_error("\nE- [Menelaus] MUSTANG software not found\n\t")
        unless ($mustang_bin);
    chomp $mustang_bin;
    my $pdbfiles = join('.pdb ', keys %{$pdblist}) . '.pdb';
    qx/cd $path; $mustang_bin -p $CL_path\/ -i $pdbfiles -F pir -o light;/;
    qx/cd $path; $mustang_bin -p $CH_path\/ -i $pdbfiles -F pir -o heavy;/;
    
    # recupero le sequenze allineate dai rispettivi file di output di Mustang
    my $flag;
    # LIGHT CHAINS
    my $CL_aligned = $path . '/light.pir';
    my $CL_seqs = { };
    my $CL_content = $self->read($CL_aligned);
    while (my $newline = shift @{$CL_content}) {
        chomp $newline;
        if ($newline =~ m/^>/g) { # mi appunto il codice del pdb
            ($flag) = $newline =~ m/(\w{4})\.pdb/g;
            $CL_seqs->{$flag} = $limits->{$flag}->{'L'}->[0].'|';
        } elsif ($newline =~ m/^[A-Za-z\*\-]+$/g) {
            $CL_seqs->{$flag} .= $newline;
        } else {
            next;
        }
    }
    
    # HEAVY CHAINS
    my $CH_aligned = $path . '/heavy.pir';
    my $CH_seqs = { };
    my $CH_content = $self->read($CH_aligned);
    while (my $newline = shift @{$CH_content}) {
        chomp $newline;
        if ($newline =~ m/^>/g) { # mi appunto il codice del pdb
            ($flag) = $newline =~ m/(\w{4})\.pdb/g;
            $CH_seqs->{$flag} = $limits->{$flag}->{'H'}->[0].'|';
        } elsif ($newline =~ m/^[A-Za-z\*\-]+$/g) {
            $CH_seqs->{$flag} .= $newline;
        } else {
            next;
        }
    }
    
    my $tmp_table = { 'HEAVY' => $CH_seqs, 'LIGHT' => $CL_seqs };
    return $tmp_table;
}

sub _thread_monitor {
    printf("\r\tRUNNING [%03d] QUEUED [%03d]", $running, $queued);
}

sub _xvg_parser { # generic parser for XVG files; returns an arrayref:
#     $VAR1 = [
#         ..field0..field1..field2..fieldx...
#         [  321,    136,    206,    15     ],
#         [...]
#     ];
    my ($self, $filename) = @_;
    
    $filename and do {
        $self->set_filename($filename);
    };
    
    my $content = $self->read();
    
    my $table = [ ];
    
    while (my $newline = shift @{$content}) {
        chomp $newline;
        
        # salto tutte le intestazioni
        next unless ($newline =~ m/^\s*\d/g);
        
        $newline = ' ' . $newline;
        
        my @record = split(/\s+/, $newline);
        shift @record;
        push(@{$table}, \@record); 
    }
    
    return $table;
}

1;

=head1 SPARTA::lib::Artemis

=head1 ARTEMIS: one of the most widely venerated of the Ancient Greek deities.
    
    Artemis was often described as the daughter of Zeus and Leto, and the twin 
    sister of Apollo. She was the Hellenic goddess of the hunt, wild animals, 
    wilderness, childbirth, virginity and young girls, bringing and relieving 
    disease in women; she often was depicted as a huntress carrying a bow and 
    arrows.
    
    The methods of this class retrieve and parse raw data from local sources 
    and/or the web. Artemis' methods should be used to initialize the contents 
    of SPARTA database.

=head1 SYNOPSIS

    use SPARTA::lib::Artemis;
    
    my $obj = SPARTA::lib::Artemis->new(); # create an object
    
    # configuring main attributes
    $obj->set_errfile("log.txt") # log file 2 write warnings/error messages
    $obj->set_dataset($dataset); # set the dataset (see SPARTA::addressbook subroutine) 
    $obj->set_host('127.0.0.1'); # database credentials
    $obj->set_database('sparta'); # database credentials
    $obj->set_user('foo'); # database credentials
    $obj->set_password('bar'); # database credentials

=head1 METHODS

=head2 abnumpdb()
    
        $arrayref = $self->abnumpdb();
    
    Foreach pdb structure of the dataset this method find the variable domains 
    and it assign, for each residue, the correct id according to the Kabat or 
    Chothia numbering schema [1]. This method call a web service known as 
    "abnumpdb" hosted by http://www.bioinf.org.uk . 
    
    [1] Abhinandan KR, Martin AC. - Mol Immunol. 2008 Aug;45(14):3832-9 

 # Annoto il numero e la dimensione dei cluster ottenuti con la funzione g_cluster
    
=head2 cluster()
    
        $arrayref = $self->cluster();
    
    This method records the number and size of the clusters obtained with the 
    GROMACS g_cluster command. It returns an arrayref containing the results table.
    
=head2 enedecomp([$string])
    
        $arrayref = $self->enedecomp(7.0);
    
    This method retrieve a list of the most relevant residues whose energetic 
    contributes may be critical in the stabilization of the structures of the 
    dataset. The procedure relies on the energy decompostion analysis previously 
    performed with ISABEL script. Data are processed from the component values 
    of the most representative eigenvectors - of interactions energy matrix - of 
    each system deposited in the database. This method reads these energetic 
    contributions and, then, filters the most relevant residues applying a 
    contact matrix mask. The threshold to match a contact is defined by $cutoff 
    variable (in Angstrom). It returns an arrayref containing the results table.
    
    DEFAULTS:
        $cutoff = 6.5;
    
=head2 enedist()
    
        $arrayref = $self->enedist();
    
    This method retrieves the distribution of internal interaction energies of 
    the structures of the dataset. It returns an arrayref containing the results 
    table.
    
=head2 enematrix()
    
        $self->enematrix();
    
    This method collects the interaction energy matrices for each system 
    (APO and HOLO).
    
=head2 fluctuations()
    
        $arrayref = $self->fluctuations();
    
    This method collects the values ​​of fluctuations (RMSF) for each system (APO and HOLO). It returns an arrayref 
    containing the results table.
    
=head2 fludist()
    
        $arrayref = $self->enedist();
    
    This method retrieves the distribution of local distance fluctuations among 
    the structures of the dataset. It returns an arrayref containing the results 
    table.
    
=head2 flumatrix()
    
        $self->flumatrix();
    
    This method collects the local distance fluctuations matrices for each 
    system (APO and HOLO).
    
=head2 fludecomp([$string])
    
        $arrayref = $self->enedecomp(7.0);
    
    This method retrieve a list of the most relevant residues whose contributes 
    may be relevant in the analysis of global distance fluctuations. 
    The procedure relies on the decompostion analysis previously performed with 
    EMMA script. Data are processed from the component values of the most 
    representative eigenvectors - of distance fluctuation energy matrix - of 
    each system deposited in the database. This method reads these energetic 
    contributions and, then, filters the most relevant residues applying a 
    contact matrix mask. The threshold to match a contact is defined by $cutoff 
    variable (in Angstrom). It returns an arrayref containing the results table.
    
    DEFAULTS:
        $cutoff = 6.5;
    
=head2 pdbsum()
    
        $arrayref = $self->pdbsum();
    
    This method provide a list of every contact between the variable chains of a
    Fab and the related antigen by which is complexed. This method relies on the
    automated annotation deposited on PDBsum database at http://www.ebi.ac.uk.
    It returns an arrayref containing the results table.
    
=head2 rcsb()
    
        $arrayref = $self->rcsb();
    
    This method relies on the fetch services of the RCSB PDB RESTful Web Service 
    interface (see http://www.rcsb.org/pdb/rest). It returns an arrayref 
    containing the results table.
    
=head2 refschema()
    
        $arrayref = $self->refschema();
    
    Through this method every structure of the dataset is mapped against a 
    unique numbering schema. For the variable domains abnum numbering schema 
    is adopted; for the constant domains structural alignments are performed, 
    using Mustang software. It returns an arrayref containing the results table.
    
=head2 resdiff()
    
        $arrayref = $self->resdiff();
    
    This method provide a cross reference numbering schema between the source 
    pdb file deposited at RCSB and the custom processed ones. It returns an 
    arrayref containing the results table.
    
=head2 rmsd()
    
        $arrayref = $self->rmsd();
    
    This method collects RMSD profiles obtained from the MD simulations 
    of the dataset. It returns an arrayref containing the results table.
    
=head2 upload_seqs()
    
        $arrayref = $self->upload_seqs();
    
    Reads a pdb file and returns a one letter code sequence(s) for each chain.
    It returns an arrayref, whose fields are pdbID, chain name and sequence.

=head2 upload_structure()
    
        $arrayref = $self->upload_structure();
    
    Foreach residue of every structure of the dataset this method finds all 
    relevant structural annotation features such as their membership to any 
    known region or secondary structure. It returns an arrayref containing the 
    results table.

=cut
