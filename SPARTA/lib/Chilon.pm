package SPARTA::lib::Chilon;

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
use base ( 'SPARTA::lib::Generic_class' ); # eredito la classe generica contenente il costruttore, l'AUTOLOAD ecc..
use base ( 'SPARTA::lib::DBmanager' ); # gestione del database
use base ( 'SPARTA::lib::FileIO' ); # modulo per leggere/scrivere su file

# *** ALTRI MODULI ***
use LWP::UserAgent;
use SPARTA::lib::Kabat;
use threads;
use threads::shared;
use Thread::Semaphore;
use Statistics::Descriptive;

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
);

# Unisco gli attributi della classi madri con questa
my $ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Generic_class::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::DBmanager::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::FileIO::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;

sub cadistances {
# data una lista di pdb e, per ognuno, una lista di coppie di residui, calcolo le distanze tra i Calpha
    my ($self, $pairs) = @_;
    my $dataset = $self->get_dataset();
    
    print "\n\t[Chilon] parsing coordinates";
    my $distmatrix = { };
    foreach my $pdb (keys %{$pairs}) {
        print ".";
        my $coord_CA = [ ];
        COORDS: { # recupero le coordinate spaziali dei carboni alfa di ogni residuo
            my $pdbfile = $dataset->{$pdb}->{'PDB'};
            my ($x, $y, $z);
            my $file = $self->read($pdbfile);
            while (my $newline = shift @{$file}) {
                chomp $newline;
                next unless ($newline =~ /^ATOM/);
                my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
                for (my $i = 0; $i < scalar @splitted; $i++) {
                    $splitted[$i] =~ s/\s+//g; # removing trailing spaces
                }
                my $atomname = $splitted[3];
                my $resname = $splitted[5];
                my $resID = $splitted[8];
                if ($atomname =~ /^CA$/) {
                    $x = $splitted[11];
                    $y = $splitted[12];
                    $z = $splitted[13];
                    $coord_CA->[$resID] = [ $x, $y, $z ];
                }
            }
        }
        
        my $pairlist = [ keys %{$pairs->{$pdb}} ];
        $distmatrix->{$pdb} = [ ];
        while (my $pair = shift @{$pairlist}) {
            my ($i,$j) = split(';', $pair);
            my $dx = $coord_CA->[$i][0] - $coord_CA->[$j][0];
            my $dy = $coord_CA->[$i][1] - $coord_CA->[$j][1];
            my $dz = $coord_CA->[$i][2] - $coord_CA->[$j][2];
            my $dist = sqrt($dx**2 + $dy**2 + $dz**2);
            $distmatrix->{$pdb}->[$i][$j] = $dist;
        }
    }
    
    return $distmatrix;
}

sub clust {
    my ($self, $occur, $mode) = @_; # occur contiene il path del file (.csv) della tabella delle occorrenze
    # check della modalità
    my ($log_file, $eps_file);
    if ($mode eq 'flu') {
        $log_file = 'flu_clust.log';
        $eps_file = 'flu_clust.eps';
    } elsif ($mode eq 'ene') {
        $log_file = 'ene_clust.log';
        $eps_file = 'ene_clust.eps';
    } else {
        $self->_raise_error("\nE- [Chilon] unknown mode\n\t");
    }
    
    my $R_file = 'clustering.R';
    my $dataset = $self->get_dataset();
    my $Rbin = $self->_whichR(); # R command line
    
    my $Rlog;
    CLUSTANAL: { # cluster analysis
        my $tot = int ((scalar keys %{$dataset})/2); # numero massimo di cluster 
        my $scRipt = <<END
# importo la tabella delle occorrenze
pdb <- read.csv2("$occur", header = TRUE, sep = ";", row.names = 1, stringsAsFactors = FALSE);
# calcolo la matrice di similarità
library(cluster);
distmat <- dist(pdb,  method = "euclidean");
# Clustering gerarchico con metodo di agglomerazione "complete linkage": la distanza tra due cluster viene calcolata considerando la coppia di elementi piu' dissimile
complete <- hclust(distmat, method = "complete");
library(hopach);
# questa e' una versione custom di silcheck, per stimare il numero ottimale di cluster; in pratica non prendo in considerazione un clustering con due soli gruppi
optimus <- function (data, kmax = 9, diss = FALSE, echo = FALSE, graph = FALSE) 
{
    if (!diss) {
        if (inherits(data, "dist")) 
            stop("data argument is a dist object, but diss is FALSE")
        if (is.matrix(data) && (nrow(data) == ncol(data))) 
            warning("data argument is square, could be a dissimilarity")
    }
    if (diss && is.matrix(data) && nrow(data) != ncol(data)) 
        stop("should be a dissimilarity matrix - but is not square")
    sil <- NULL
    m <- min(kmax, max((!diss) * (dim(data)[1] - 1), (diss) * 
        (0.5 * (sqrt(1 + 8 * length(data)) - 1)), na.rm = TRUE))
    if (m < 2) 
        out <- c(1, NA)
    else {
        for (i in 1:(m - 1)) sil[i] <- pam(data, k = (i + 1), 
            diss = diss)\$silinfo\$avg.width
        sil[1] <- 0 # riga aggiunta da me
        if (echo) 
            cat("best k = ", order(sil)[length(sil)] + 1, ", sil(k) = ", 
                round(max(sil), 4), "\\n")
        if (graph) {
            plot(2:m, sil, type = "n", xlab = "Number of Clusters", 
                ylab = "Average Silhouette")
            text(2:m, sil, 2:m)
        }
        out <- c(order(sil)[length(sil)] + 1, max(sil))
    }
    return(out)
}
# stimo il numero ottimale di cluster
optimum <- optimus(distmat, diss = TRUE, echo = TRUE, kmax = $tot);
clusnum <- round(optimum[1]);
# calcolo i valori di silhouette
clusters <- cutree(complete, k = clusnum);
sitest <- silhouette(clusters, distmat);
print(clusters);
print(sitest);
# stampa del dendrogramma
postscript("$eps_file")
plot(complete);
rect.hclust(complete, k = clusnum, border="blue"); # metto in evidenza i cluster sul dendrogramma
dev.off()
END
        ;
        my $filename = $self->get_workdir() . '/' . $R_file;
        $self->set_filename($filename);
        $self->set_filedata([ $scRipt ]);
        $self->write();
        $Rlog = qx/$Rbin $filename 2>&1/;
    }
    $self->_raise_warning("\nI- [Chilon] [$eps_file] written");
    
    my $results = [ ];
    RPARSE: { # parsing dell'output prodotto nel blocco precedente
        my @output = split("\n", $Rlog);
        my $header = <<END
*** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***

# Silhouettes measure how well an element belongs to its cluster, and the average
# silhouette measures the strength of cluster membership overall.
# For each observation i, the silhouette width s(i) is defined as follows:
# Put a(i) = average dissimilarity between i and all other points of the cluster
# to which i belongs. For all other clusters C, put d(i,C) = average
# dissimilarity of i to all observations of C. The smallest of these d(i,C) is
# b(i), and can be seen as the dissimilarity between i and its “neighbor” cluster.
# Finally, s(i) := ( b(i) - a(i) ) / max( a(i), b(i) ).
# The Median Split Silhouette (MSS) is a measure of cluster heterogeneity.
# Given a partitioning of elements into groups, the MSS algorithm considers each
# group separately and computes the split silhouette for that group, which
# evaluates evidence in favor of further splitting the group. If the median split 
# silhouette over all groups in the partition is low, the groups are homogeneous.

END
        ;
        push(@{$results}, $header . "\n");
        my %clust_elems; # singoli elementi dei cluster
        for (my $i = 0; $i < scalar @output; $i++) { # completo le righe vuote, altrimenti il ciclo while successivo abortisce
            $output[$i] = ' ' unless ($output[$i]);
        }
        while (my $row = shift @output ) {
            if ($row =~ /^best k/) {
                push(@{$results}, $row . "\n\n");
            } elsif ($row =~ /^> print\(clusters\);$/) {
                my $sorted_items = '';
                while (1) {
                    $row = shift @output;
                    last if ($row =~ /^> print\(sitest\);$/);
                    if ($row =~ /^\w{4}/) {
                        $sorted_items .= $row;
                    }
                }
                my @items = split(' ', $sorted_items);
                for (my $i = 1; $i <= scalar @items; $i++) {
                    $clust_elems{"[$i,]"} = $items[$i-1];
                }
            } elsif ($row =~ /neighbor\s+sil_width/) {
                push(@{$results}, $row . "\n");
                while (1) {
                    $row = shift @output;
                    last if ($row =~ /attr\(,"Ordered"\)/);
                    my ($elem,$cluster,$neighbor,$sil_width) =
                        $row =~ m/(\[\d+,\])\s+(\d+)\s+(\d+)\s+([\-\d\.]+)/g;
                    my $string = sprintf("%s       %d        %d  %.9f" , $clust_elems{$elem}, $cluster, $neighbor, $sil_width);
                    push(@{$results}, $string . "\n");
                }
            }
        }
        push(@{$results}, "\n");
        my $filename = $self->get_workdir() . '/' . $log_file;
        $self->set_filename($filename);
        $self->set_filedata($results);
        $self->write();
        $self->_raise_warning("\nI- [Chilon] [$log_file] written");
    }
    
    unlink $R_file;
    return $results;
}

sub flucategories {
# suddivido i valori di fluttuazione in classi
    my ($self, $fluct) = @_;
    
    print "\n\t[Chilon] fluctuation ranges";
    my $categories = { 'APO' => { }, 'HOLO' => { } };
    foreach my $form (keys %{$fluct}) {
        my $ranges = {
            '(0,20]'    => { },
            '(20,40]'   => { },
            '(40,60]'   => { },
            '(60,80]'   => { },
            '(80,100]'  => { }
        };
        foreach my $pdb (keys %{$fluct->{$form}}) {
            my %distfluct;
            foreach my $res (sort keys %{$fluct->{$form}->{$pdb}->{'others'}}) {
                $distfluct{$res} = sprintf("%.3f", $fluct->{$form}->{$pdb}->{'others'}->{$res}->{'fluct'});
            }
            # standardizzazione dei valori di distance fluctuation
            my $stat = Statistics::Descriptive::Full->new();
            $stat->add_data(values %distfluct);
            my $min = $stat->min();
            my $range = $stat->sample_range();
            foreach my $res (keys %distfluct) {
                my $value = $distfluct{$res};
                $value = ($value - $min) / $range;
                $value = $value * 100;
                $distfluct{$res} = sprintf("%.3f", $value);
            }
            # suddivisione dei valori in classi
            foreach my $res (sort keys %distfluct) {
                ($distfluct{$res} <= 20) and do {
                    $ranges->{'(0,20]'}->{$pdb} = [ ]
                        unless (exists $ranges->{'(0,20]'}->{$pdb});
                    push(@{$ranges->{'(0,20]'}->{$pdb}}, $res);
                    next;
                };
                ($distfluct{$res} <= 40) and do {
                    $ranges->{'(20,40]'}->{$pdb} = [ ]
                        unless (exists $ranges->{'(20,40]'}->{$pdb});
                    push(@{$ranges->{'(20,40]'}->{$pdb}}, $res);
                    next;
                };
                ($distfluct{$res} <= 60) and do {
                    $ranges->{'(40,60]'}->{$pdb} = [ ]
                        unless (exists $ranges->{'(40,60]'}->{$pdb});
                    push(@{$ranges->{'(40,60]'}->{$pdb}}, $res);
                    next;
                };
                ($distfluct{$res} <= 80) and do {
                    $ranges->{'(60,80]'}->{$pdb} = [ ]
                        unless (exists $ranges->{'(60,80]'}->{$pdb});
                    push(@{$ranges->{'(60,80]'}->{$pdb}}, $res);
                    next;
                };
                ($distfluct{$res} <= 100) and do {
                    $ranges->{'(80,100]'}->{$pdb} = [ ]
                        unless (exists $ranges->{'(80,100]'}->{$pdb});
                    push(@{$ranges->{'(80,100]'}->{$pdb}}, $res);
                    next;
                };
            }
            
            my @bindsite = @{$fluct->{$form}->{$pdb}->{'bindsite'}};
            push(@{$ranges->{'(80,100]'}->{$pdb}}, @bindsite);
        }
        
        $categories->{$form} = $ranges;
    }
    
    return $categories;
}

sub fluctvalues {
# recupero, per ogni PDB apo/holo, i valori massimi di distance fluctuation tra i residui del paratopo e quelli restanti del Fab 
    my ($self) = @_;
    
    my $dbh = $self->access2db(); # accesso al database
    
    my $contact_list = { };
    CONTACTS: { # recupero la lista dei residui in contatto con gli antigeni
        my $query = <<END
SELECT structure.pdb, structure.res, structure.cdr, structure.known, pdbsum.type
FROM structure
JOIN xres
ON structure.pdb = xres.pdb
AND structure.res = xres.res
JOIN pdbsum
ON xres.pdb = pdbsum.pdb
AND xres.source_res = pdbsum.residA
AND xres.chain = pdbsum.chainA
WHERE  pdbsum.chainB = 'A'
AND pdbsum.type != 'Non-bonded contacts'
END
        ;
        my $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
        while (my @row = $sth->fetchrow_array) {
            my ($pdb, $res) = ($row[0], $row[1]);
#             next unless ($pdb =~ /(1NDG|1AFV|2FJH)/); # RIGA DI TESTING
            $contact_list->{$pdb} = { }
                unless (exists $contact_list->{$pdb});
            $contact_list->{$pdb}->{$res} = 1
                unless (exists $contact_list->{$pdb}->{$res});
        }
        $sth->finish();
    }
    
    my $refschema = { };
    REFSCHEMA: { # carico in memoria la tabella refschema
        my $sth = $self->query_exec('dbh' => $dbh, 'query' => 'SELECT * FROM refschema');
        while (my @row = $sth->fetchrow_array) {
            my ($pdb, $resid, $ref) = ($row[1], $row[2], $row[3]);
            $refschema->{$pdb} = { }
                unless (exists $refschema->{$pdb});
            $refschema->{$pdb}->{$resid} = $ref;
        }
    }
    
    my $flucts = { 'APO' => { }, 'HOLO' => { } };
    FLUCTS: { # recupero i valori di distance fluctuation in relazione ai residui coinvolti nei contatti con l'antigene
        print "\n\t[Chilon] querying the database";
        foreach my $pdb (keys %{$contact_list}) {
            print '.';
            my $res = q/'/ . join(q/', '/, keys %{$contact_list->{$pdb}}) . q/'/;
            my $query = <<END
SELECT pdb, form, resA, resB, fluct
FROM flumatrix
WHERE (resA IN ($res)
OR resB IN ($res))
AND pdb = '$pdb'
END
            ;
            my $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
            while (my @row = $sth->fetchrow_array) {
                my ($pdb, $form, $resA, $resB, $value) = @row;
                my ($reference, $residue);
                if (exists $contact_list->{$pdb}->{$resA}) {
                    ($reference, $residue) = ($resA, $resB);
                } else {
                    ($reference, $residue) = ($resB, $resA);
                };
                unless (exists $flucts->{$form}->{$pdb}) {
                    $flucts->{$form}->{$pdb} = {
                        'bindsite'  =>  [ keys %{$contact_list->{$pdb}} ],
                        'others'    =>  { }
                    };
                };
                next    # non considero i valori di distfluct interni al gruppo di residui del binding site
                    if (exists $contact_list->{$pdb}->{$residue});
                if (exists $flucts->{$form}->{$pdb}->{'others'}->{$residue}) {
                    if ($value > $flucts->{$form}->{$pdb}->{'others'}->{$residue}->{'fluct'}) {
                        $flucts->{$form}->{$pdb}->{'others'}->{$residue}->{'paratope'} = $reference;
                        $flucts->{$form}->{$pdb}->{'others'}->{$residue}->{'fluct'} = $value;
                    } else {
                        next;
                    }
                } else {
                    my $flag = $refschema->{$pdb}->{$residue};
                    $flucts->{$form}->{$pdb}->{'others'}->{$residue} = {
                        'paratope'  =>  $reference,
                        'position'  =>  $flag,
                        'fluct'     =>  $value,
                        'distance'  =>  ''
                    }
                }
            }
        }
    }
     
    $dbh->disconnect; # disconnessione dal database
    
    return $flucts;
}

sub list {
    my ($self, $mode) = @_;
    
    my ($dist_table, $prefixapo, $prefixholo); # tabella che dovrò interrogare sul DB
    if ($mode eq 'flu') {
        $dist_table = 'fludist';
        $prefixapo = 'dfapo';
        $prefixholo = 'dfolo';
    } elsif ($mode eq 'ene') {
        $dist_table = 'enedist';
        $prefixapo = 'enapo';
        $prefixholo = 'enolo';
    } else {
        $self->_raise_error("\nE- [Chilon] unknown mode\n\t")
    }
    
    my $pdblist = { }; # lista dei pdb del dataset (key), con il rispettivo numero totale di residui (value)
    my $dist; # contributi (in apo e in holo) di ogni residuo del dataset
    QUERY: { # interrogo il database
        $self->_raise_warning("\nI- [Chilon] querying the database...");
        my $dbh = $self->access2db(); # accesso al database
        
        PDBLIST: { # inizializzo $pdblist
            my $query = <<END
SELECT pdb, count(*) AS tot
FROM $dist_table
GROUP BY pdb
END
            ;
            my $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
            while (my @row = $sth->fetchrow_array) {
                $pdblist->{$row[0]} = $row[1];
            }
            $sth->finish();
        };
        
        DIST: { # inizializzo $dist
            my $query = <<END
SELECT $dist_table.pdb, $dist_table.res, refschema.ref, $dist_table.$prefixapo, $dist_table.$prefixholo
FROM $dist_table
JOIN refschema
ON $dist_table.pdb = refschema.pdb
AND $dist_table.res = refschema.res
ORDER BY $dist_table.res + 0 ASC
END
            ;
            my $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
            $dist = $sth->fetchall_arrayref;
            $sth->finish();
        }
        
        print "done";
        $dbh->disconnect; # disconnessione dal database
    }
    
    my $selection = { 'APO' => { }, 'HOLO' => { },  'BOTH' => { },}; # allestisco tre liste di residui il cui contributo flurgetico è rilevante nelle forme apo, olo o in entrambe
    SELECT: {
        while (my $record = shift @{$dist}) {
            my ($pdbID, $res, $ref, $apo, $olo) = @{$record};
            
            # definisco la soglia entro cui il contrbuto è rilevante
            my $threshold = 1 / sqrt($pdblist->{$pdbID});
            
            # classifico il record letto
            if ((abs($apo) > $threshold)&&(abs($olo) > $threshold)) {
                unless (exists $selection->{'BOTH'}->{$ref}) {
                    $selection->{'BOTH'}->{$ref} = [ ];
                }
                push(@{$selection->{'BOTH'}->{$ref}}, $pdbID.'-'.$res);
            } elsif (abs($apo) > $threshold) {
                unless (exists $selection->{'APO'}->{$ref}) {
                    $selection->{'APO'}->{$ref} = [ ];
                }
                push(@{$selection->{'APO'}->{$ref}}, $pdbID.'-'.$res);
            } elsif (abs($olo) > $threshold) {
                unless (exists $selection->{'HOLO'}->{$ref}) {
                    $selection->{'HOLO'}->{$ref} = [ ];
                }
                push(@{$selection->{'HOLO'}->{$ref}}, $pdbID.'-'.$res);
            } else {
                next;
            }
        }
    }
    
    return $selection;
}

sub refine {
    my ($self, $list, $cutoff) = @_;
    
    my $dataset = $self->get_dataset();
    
    # valore di default
    $cutoff = 6.5
        unless ($cutoff && $cutoff =~ /^[\d\-\.Ee]+$/);
    $self->_raise_warning(sprintf("\nI- [Chilon] Contact map cutoff: %.1f A", $cutoff));
    
    # lista dei residui candidati per le forme apo e holo
    my $candidate_apo = { };
    my $candidate_olo = { };
    RESLIST: {
        foreach my $cat ( 'APO', 'BOTH' ) {
            foreach my $ref (keys %{$list->{$cat}}) {
                my @matches = @{$list->{$cat}->{$ref}};
                $candidate_apo->{$ref} = [ ]
                    unless (exists $candidate_apo->{$ref});
                push(@{$candidate_apo->{$ref}}, @matches);
            }
        }
        foreach my $cat ( 'HOLO', 'BOTH' ) {
            foreach my $ref (keys %{$list->{$cat}}) {
                my @matches = @{$list->{$cat}->{$ref}};
                $candidate_olo->{$ref} = [ ]
                    unless (exists $candidate_olo->{$ref});
                push(@{$candidate_olo->{$ref}}, @matches);
            }
        }
        # tengo buoni solo quei residui che sono condivisi da almeno due strutture
        foreach my $ref (keys %{$candidate_apo}) {
            if (scalar @{$candidate_apo->{$ref}} <= 1) {
                delete $candidate_apo->{$ref};
            }
        }
        foreach my $ref (keys %{$candidate_olo}) {
            if (scalar @{$candidate_olo->{$ref}} <= 1) {
                delete $candidate_olo->{$ref};
            }
        }
    }
    
    # raffinamento delle liste
    $self->_raise_warning("\nI- [Chilon] data refinement...");
    $running = 0E0; $queued = 0E0;
    print "\n";
    foreach my $pdbID (keys %{$dataset}) { # lancio i thread
        my $label = $pdbID.'[APO]';
        my $pdbfile = $dataset->{$pdbID}->{'CLUSTER_PDB_APO'};
        push @thr, threads->new(\&_contact_matrix, $self, $candidate_apo, $label, $pdbfile, $cutoff);
        $label = $pdbID.'[HOLO]';
        $pdbfile = $dataset->{$pdbID}->{'CLUSTER_PDB_HOLO'};
        push @thr, threads->new(\&_contact_matrix, $self, $candidate_olo, $label, $pdbfile, $cutoff);
    }
    for (@thr) { $_->join() }; # aspetto che tutti i thread siano terminati
    
    # interseco i residui trovati nelle forme apo e holo
    my %nr_list;
    while (my $record = shift @jobcontent) {
        my @array = split(';', $record);
        my $pdbID = shift @array;
        my $form = shift @array;
        while (my $res = shift @array) {
            my $label = $pdbID.'-'.$res;
            if (exists $nr_list{$label}) { # se il residuo appare sia in apo che in olo è "BOTH"
                $nr_list{$label} = 'BOTH';
            } else { # altrimenti sarà "APO" o "HOLO"
                $nr_list{$label} = $form;
            }
        }
    }
    
    # formatto l'hash da ritornare in uscita
    my $hashref = { };
    my $dbh = $self->access2db();
    my $sth = $dbh->prepare("SELECT ref FROM refschema WHERE pdb = ? AND res = ?")
        or $self->_raise_error(sprintf("\nE- [Chilon] statement handle error [%s]\n\t", $dbh->errstr));
    foreach my $record (keys %nr_list) {
        my ($pdbID, $res) = $record =~ m/(\w{4})-(\d+)/g;
        my $form = $nr_list{$record};
        $sth->execute($pdbID, $res)
            or $self->_raise_error(sprintf("\nE- [Chilon] statement handle error [%s]\n\t", $sth->errstr));
        my @row = $sth->fetchrow_array;
        my $ref = $row[0];
        $hashref->{$ref} = [ ]
            unless (exists $hashref->{$ref});
        push(@{$hashref->{$ref}}, $pdbID.'-'.$form.'-'.$res)
    }
    
    $sth->finish();
    $dbh->disconnect;
    
    @thr = ( );
    @jobcontent = ( ); # libero memoria, non consigliabile usare undef in questo frangente
    
    return $hashref;
}

sub _contact_matrix {
    my ($self, $candidate, $label, $pdbfile, $cutoff) = @_;
    
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        lock $queued; $queued = $queued + 1;
        $self->_thread_monitor();
    }
    $semaforo->down(); # occupo uno slot
    { lock $running; $running = $running + 1; }
    $self->_thread_monitor();
    
    my $cmatrix = [ ];
    CONTACT: { # matrici dei contatti
        my $coord_CB = [ ];
        my ($x, $y, $z);
        my $file = $self->read($pdbfile);
        # recupero le coordinate spaziali dei carboni beta di ogni residuo
        while (my $newline = shift @{$file}) {
            chomp $newline;
            next unless ($newline =~ /^ATOM/);
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            for (my $i = 0; $i < scalar @splitted; $i++) {
                $splitted[$i] =~ s/\s+//g; # removing trailing spaces
            }
            my $atomname = $splitted[3];
            my $resname = $splitted[5];
            my $resID = $splitted[8];
            if ($atomname =~ /^CB$/ && $resname !~ /^GLY$/) {
                $x = $splitted[11];
                $y = $splitted[12];
                $z = $splitted[13];
                $coord_CB->[$resID] = [ $x, $y, $z ];
            } elsif ($resname =~ /^GLY$/ && $atomname =~ /^H$/) {
                $x = $splitted[11];
                $y = $splitted[12];
                $z = $splitted[13];
                $coord_CB->[$resID] = [ $x, $y, $z ];
            }
        }
        # calcolo la matrice dei contatti
        for (my $i=1; $i < scalar @{$coord_CB}; $i++) {
            for (my $j=1; $j < scalar @{$coord_CB}; $j++) {
                if ($i == $j) { # metto a 0 il contatto con il medesimo residuo
                    $cmatrix->[$i][$j] = 0;
                } elsif (abs($i - $j) == 1) { # metto a 0 il contatto con reisdui contigui
                    $cmatrix->[$i][$j] = 0;
                    $cmatrix->[$j][$i] = 0;
                } else { # calcolo la distanza tra i CB
                    my $dx = $coord_CB->[$i][0] - $coord_CB->[$j][0];
                    my $dy = $coord_CB->[$i][1] - $coord_CB->[$j][1];
                    my $dz = $coord_CB->[$i][2] - $coord_CB->[$j][2];
                    my $dist = sqrt($dx**2 + $dy**2 + $dz**2);
                    if ($dist < $cutoff) {
                        $cmatrix->[$i][$j] = 1;
                        $cmatrix->[$j][$i] = 1;
                    } else {
                        $cmatrix->[$i][$j] = 0;
                        $cmatrix->[$j][$i] = 0;
                    }
                }
            }
        }
    }
    
    REFINEMENT: {
        my ($pdbID, $form) = $label =~ m/^(\w{4})\[(APO|HOLO)\]$/g;
        my @reslist;
        # recupero dall'hashref $candidate i resID relativi al file pdb che sto considerando
        foreach my $ref (keys %{$candidate}) {
            foreach my $match (@{$candidate->{$ref}}) {
                if ($match =~ m/$pdbID/g) {
                    my ($res) = $match =~ m/\d+$/g;
                    push(@reslist, $res);
                }
            }
        }
        my @recover;
        foreach my $i (@reslist) {
            my $keep = 0;
            my $which = $i;
            foreach my $j (@reslist) {
                if ($cmatrix->[$i][$j] == 1) {
                    $keep++;
                }
            }
            if ($keep != 0) {
                push(@recover, $which);
            }
        }

        my $string = "$pdbID;$form;" . join(';',  @recover);
        {
            lock @jobcontent;
            push(@jobcontent, $string);
        }
    }
    undef $cmatrix; # libero memoria
    
    {
        lock $running; $running = $running - 1;
        lock $queued; $queued = $queued - 1;
        $queued = 0E0 if ($queued <= 0);
        $running = 0E0 if ($running <= 0);
    }
    $self->_thread_monitor();
    $semaforo->up(); # libero uno slot
}

sub _thread_monitor {
    printf("\r\tRUNNING [%03d] QUEUED [%03d]", $running, $queued);
}

sub _whichR { # verifico che R sia installato
    my ($self) = @_;
    
    my $Rbin = qx/which R 2> \/dev\/null/;
    chomp $Rbin;
    $self->_raise_error("\nE- [Chilon] R software not found\n\t")
        unless $Rbin;
    $Rbin .= ' --vanilla <'; # opzione per farlo girare in batch
    return $Rbin;
}

1;

=head1 SPARTA::lib::Chilon

=head1 CHILON: one of the Seven Sages of Greece.
    
    He was an ephor in Sparta and was a member of the Spartan assembly. Chilon 
    was also the first person who introduced the custom of joining the ephors to 
    the kings as their counselors. He is credited with the change in Spartan 
    policy leading to the development of the Peloponnesian League in the sixth 
    century BC.
    
    Chilon's methods are devoted to find the pattern of residues mainly involved 
    in the stabilization of a Fab::antigen complex.

=head1 METHODS

=head2 clust($csv, $mode)
    
        $arrayref = $self->clust("xxx_distmat.csv", 'flu');
    
    Performs a hierarchical cluster analysis, submitting a script to R software. 
    This method takes as input the filename of the occurencies table in csv format.
    
    NOTES:
    In this release Chilon::clust is developed in order to be called by 
    Leonidas::hotspot_cluster method

=head2 list($mode)
    
        $hasref = $self->list('flu');
    
    This method is a classifier of residues whose contributes may be relevant in 
    a structure (from fluctuation|energy point of view). Data are extracted from 
    the component values of the most representative eigenvectors; afterwards, 
    those data lower than a threshold value K are discarded 
    (K = sqrt(1/TOT_residues)). The method returns an hashref in which residues 
    are classified:
    
    $VAR1 = {
        'BOTH' => {
            'CH-0089' => ['1AHW-202','1PKQ-203'],
            'VH-0021' => ['1BGX-17','1TZH-21','1IQD-21','1MHP-21','1FSK-21']
        },
        'HOLO' => {
            'CH-0089' => ['1BGX-194','1NDM-198','1FDL-201','2ADF-203'],
            'VH-0021' => ['2JEL-20','1FDL-21','1H0D-21','1RJL-21']
        },
        'APO' => {
            'CH-0089' => ['1DQJ-198','1TPX-198','1NSN-198','1IQD-203'],
            'VH-0021' => ['1PKQ-20','1AFV-21','1FE8-21','1YNT-21','1TPX-21']
        }
    }
    
    The keys 'APO', 'HOLO' and 'BOTH' indicate in which form the residues appear 
    relevant. Subkeys identify the residue according to the standard numbering 
    schema of SPARTA. Values are lists of pdb structures of the dataset in which 
    the related residues are shared as relevant (accompained by the numbering 
    schema as they appear in the related pdb files).
    
=head2 refine($hasref, $hasref, [$string])
    
        $hasref = $self->refine($list, $cutoff);
    
    This method reads relevant contribution, stored in $list (see Chilon::list). 
    Then, it filters the most relevant residues applying a contact 
    matrix mask. The threshold to match a contact is defined by $cutoff 
    variable (in Angstrom). The methods returns a list of the residues as 
    important for the stabilization of the structure.
    
    DEFAULTS:
        $cutoff = 6.5;

=cut
