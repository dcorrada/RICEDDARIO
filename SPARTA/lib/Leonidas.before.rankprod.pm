package SPARTA::lib::Leonidas;

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
use base ( 'SPARTA::lib::FileIO' ); # classe per leggere/scrivere su file
use base ( 'SPARTA::lib::Theodorus'); # classe per scrivere script per PyMol
use base ( 'SPARTA::lib::Chilon' );

# *** ALTRI MODULI ***
use Statistics::Basic;
use Statistics::TTest; # libreria x test t di Student
use Statistics::Normality; # libreria x test t di Student

## GLOBS ##
our $AUTOLOAD;

# Definizione degli attributi della classe
# chiave        -> nome dell'attributo
# valore [0]    -> valore di default
# valore [1]    -> permessi di accesso all'attributo
#                  ('read.[write.[...]]')
# STRUTTURA DATI
our %_attribute_properties = (
    _database       => ['sparta', 'read.write'],
    _dataset        => [ { }, 'read.write'],
    
);

# Unisco gli attributi della classi madri con questa
my $ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Generic_class::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::DBmanager::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::FileIO::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Theodorus::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = SPARTA::lib::Generic_class::_hash_joiner(\%SPARTA::lib::Chilon::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;

sub cluster {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    $self->_raise_warning(sprintf("\nI- processing fluctuations data..."));
    # verifico che gnuplot sia installato
    my $gnuplot = qx/which gnuplot44  2> \/dev\/null/; # in realtà il comando è "gnuplot", siccome ho bisogno della versione 4.4 uso questo link ("gnuplot44") per distinguerlo dal Gnuplot installato di default
    chomp $gnuplot;
    $self->_raise_error("\nE- [Leonidas] Gnuplot software not found\n\t") unless $gnuplot;
    
    COUNT: { # conta dei cluster
        my $dat_filename = $self->get_workdir . '/clust.count.dat';
        my $gnu_filename = $self->get_workdir . '/clust.count.gnu';
        my $png_filename = $self->get_workdir . '/clust.count.png';
        DATFILE: { # .dat file che dovrà essere letto da GnuPlot
            # noiosissimi cicli per raggruppare i PDB secondo la durata delle simulazioni, quindi per odrine alfabetico
            my %sorted;
            foreach my $label (keys %{$dataset}) {
                $sorted{$dataset->{$label}->{'DURATION'}.$label} = $label;
            }
            my @pdblist;
            foreach my $key (sort keys %sorted) {
                push(@pdblist, $sorted{$key});
            }
            # interrogo il database
            my $dbh = $self->access2db();
            $self->set_query_string("SELECT pdb, form, count(*) FROM cluster GROUP BY CONCAT(pdb, form)");
            my $sth = $self->query_exec('dbh' => $dbh);
            my $table = $sth->fetchall_arrayref()
                or $self->_raise_error("\nE- [Leonidas] Perl DBI fetching error\n\t");
            $sth->finish();
            $dbh->disconnect;
            my %table_bis;
            foreach my $item (@{$table}) {
                unless (exists $table_bis{$item->[0]}) {
                    $table_bis{$item->[0]} = [ ];
                }
                if ($item->[1] eq "APO") {
                    $table_bis{$item->[0]}->[0] = $item->[2];
                } elsif ($item->[1] eq "HOLO") {
                    $table_bis{$item->[0]}->[1] = $item->[2];
                }
            }
            # allestisco il contenuto del datfile
            my $header = "SYSTEM\tAPO\tHOLO\n";
            my $content = [ $header ];
            foreach my $item (@pdblist) {
                my $newline = sprintf("%s\t%d\t%d\n", $item, $table_bis{$item}->[0], $table_bis{$item}->[1]);
                push(@{$content}, $newline);
            }
            $self->set_filename($dat_filename);
            $self->set_filedata($content);
            $self->write();
        }
        GNUPLOT: { # faccio l'istogramma
            $self->_raise_warning("\nI- [Leonidas] generating histogram [$png_filename]...");
            my $gnuscript = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw histogram of clusters found from g_cluster
# 
set size ratio 0.55
set terminal png size 1280, 800
set output "$png_filename"
set style data histogram
set style histogram cluster gap 1
set style fill solid border rgb "black"
set auto x
set xtics rotate
set xtics nomirror
set ylabel "# clusters"
set yrange [0:*]
set mytics 5
show mytics
plot '$dat_filename' using 2:xtic(1) title col lt 1, \\
        '' using 3:xtic(1) title col lt 3 

unset output
quit
END
            ;
            $self->set_filename($gnu_filename);
            $self->set_filedata([ $gnuscript ]);
            $self->write();
            # creo il mio file .png
            my $gplot_log = qx/$gnuplot $gnu_filename 2>&1/;
            $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
            # print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
            unlink $gnu_filename;
        }
    }
    SAMPLING: { # numerosità dei cluster
        my $dat_filename = $self->get_workdir . '/clust.num.dat';
        my $gnu_filename = $self->get_workdir . '/clust.num.gnu';
        my $png_filename = $self->get_workdir . '/clust.num.png';
        DATFILE: { # .dat file che dovrà essere letto da GnuPlot
            my %rawdata;
            # interrogo il database
            my $dbh = $self->access2db();
            $self->set_query_string("SELECT CONCAT(pdb, form), id, items FROM cluster");
            my $sth = $self->query_exec('dbh' => $dbh);
            while (my @row = $sth->fetchrow_array()) {
                unless (exists $rawdata{$row[0]}) {
                    $rawdata{$row[0]} = [ ];
                    $rawdata{$row[0]}->[0] = 0E0; # l'elemento '0' di ogny array sarà usato per contare il numero totale di struttutre campionate
                }
                $rawdata{$row[0]}->[0] += $row[2];
                $rawdata{$row[0]}->[$row[1]] = $row[2];
            }
            $sth->finish();
            $dbh->disconnect;
            # calcolo la numerosità di ogni cluster di ogni struttura del dataset (in %)
            my %percent;
            foreach my $key (keys %rawdata) {
                my @array = @{$rawdata{$key}};
                my $abs = $array[0];
                for (my $i=1; $i < scalar @array; $i++) {
                    my $index = sprintf("%03d", $i);
                    $percent{$index} = [ ]
                        unless (exists $percent{$index});
                    my $value = ($array[$i]/$abs)*100;
                    push(@{$percent{$index}}, $value);
                }
            }
            # calcolo media e deviazione standard
            my %avestd;
            foreach my $index (sort keys %percent) {
                my $array = $percent{$index};
                my $ave = sprintf("%.3f", Statistics::Basic::mean($array));
                my $std = sprintf("%.3f", Statistics::Basic::stddev($array));
                $avestd{$index} = [ $ave, $std ];
            }
            # allestisco il contenuto del datfile
            my $header = "CLUSTER\tMEAN\tSTDDEV\n";
            my $content = [ $header ];
            foreach my $index (sort keys %avestd) {
                my $indice = $index;
                $indice =~ s/^0+//;
                my $newline = sprintf("%d\t%.3f\t%.3f\n", $indice, $avestd{$index}->[0], $avestd{$index}->[1]);
                push(@{$content}, $newline);
            }
            $self->set_filename($dat_filename);
            $self->set_filedata($content);
            $self->write();
        }
        GNUPLOT: { # faccio il grafico
            $self->_raise_warning("\nI- [Leonidas] generating graph [$png_filename]...");
            my $wclog = qx/wc -l $dat_filename/;
            my ($lines) = $wclog =~ /^(\d+)/;
            my $gnuscript = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw sample size of the clusters found from g_cluster
# 
unset key
set size ratio 0.55
set terminal png size 1280, 800
set output "$png_filename"
set xlabel "# cluster"
set ylabel "percentage"
set grid y
set yrange [-1:100]
set xrange [0:$lines]
set xtics nomirror
set ytics nomirror
set ytics out
set xtics out
set ytics 10
set xtics 1
set mytics 10
show mytics
plot "$dat_filename" using 1:2:3 with errorbars lt rgb "red", \\
    "" using 1:2 smooth cspline lt rgb "blue"
unset output
quit
END
            ;
            $self->set_filename($gnu_filename);
            $self->set_filedata([ $gnuscript ]);
            $self->write();
            # creo il mio file .png
            my $gplot_log = qx/$gnuplot $gnu_filename 2>&1/;
            $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
#             print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
            unlink $gnu_filename;
        }
    }
    return 1;
}

sub hotspot_diffmatrix {
# questa sub produce un file .csv delle componenti dell'autovettore combinato di ogni sistema apo/holo di ogni struttura
    my ($self, $mode) = @_;
    my $dataset = $self->get_dataset();
    my $dbh = $self->access2db();
    my ($xdecomp, $xdist, $csv_file);
    if ($mode eq 'flu') {
        $xdecomp = 'fludecomp';
        $xdist = 'fludist';
        $csv_file = 'flu_diffmat.csv';
    } elsif ($mode eq 'ene') {
        $xdecomp = 'enedecomp';
        $xdist = 'enedist';
        $csv_file = 'nrg_diffmat.csv';
    } else {
        $self->_raise_error("\nI- [Leonidas] unknown mode");
    }
    
    my %reflist;
    my @pdbs = sort (keys %{$dataset});
    HOTSPOT_LIST: { # recupero la lista degli hotspot comuni a tutti i PDB
        $self->_raise_warning("\nI- [Leonidas] retrieving hotspot list...");
        my $sth;
        $sth = $self->query_exec('dbh' => $dbh, 'query' => "SELECT * FROM $xdecomp GROUP BY ref");
        while (my @row = $sth->fetchrow_array) {
            $reflist{$row[3]} = 1;
        }
        $sth->finish();
        my $totpdb = scalar @pdbs;
        $sth = $self->query_exec('dbh' => $dbh, 'query' => "SELECT count(*), ref FROM refschema GROUP BY ref");
        while (my @row = $sth->fetchrow_array) { # scarto quelle posizioni che non sono condivise da tutti i pdb
            if ($row[0] < $totpdb) {
                if (exists $reflist{$row[1]}) {
#                     print "\n  discarding $row[1]";
                    delete $reflist{$row[1]};
                };
            }
        }
        $sth->finish();
    };
    
    my $hotspots = { };
    COMPONENTS: { # recupero i valori delle singole componenti per ogni hotspot selezionato
        $self->_raise_warning("\nI- [Leonidas] retrieving component values...");
        my $sth;
        my $refs = join(q/', '/, keys %reflist);
        $sth = $self->query_exec('dbh' => $dbh, 'query' => "SELECT * FROM refschema WHERE ref IN ('$refs')");
        my $refschema = $sth->fetchall_arrayref();
        $sth->finish();
        $sth = $self->query_exec('dbh' => $dbh, 'query' => "SELECT * FROM $xdist");
        my %dist_table;
        while (my @row = $sth->fetchrow_array) {
            my ($pdb, $res, $apoval, $oloval) = ($row[1], $row[2], $row[3], $row[4]);
            $dist_table{"$pdb\_$res"} = [$apoval, $oloval];
        }
        $sth->finish();
        foreach my $i (0..$#{$refschema}) {
            my ($pdb, $res, $ref) = ($refschema->[$i][1], $refschema->[$i][2], $refschema->[$i][3]);
            $hotspots->{$ref} = { } unless (exists $hotspots->{$ref});
            $hotspots->{$ref}->{$pdb} = [ ];
            @{$hotspots->{$ref}->{$pdb}} = @{$dist_table{"$pdb\_$res"}};
        }
    }
    $dbh->disconnect;
    my $filename = $self->get_workdir(). '/' . $csv_file;
    CSVFILE: {
        my $content = [ ];
        my $header;
        for my $label (@pdbs) {
            $header .= ";$label\_apo";
        };
        for my $label (@pdbs) {
            $header .= ";$label\_holo";
        };
        $header .= "\n";
        push(@{$content}, $header);
        foreach my $ref (sort(keys %{$hotspots})) {
            my $newline = $ref . ';';
            foreach my $pdb (@pdbs) { # carico i valori delle forme APO
                my @pair = @{$hotspots->{$ref}->{$pdb}};
                $newline .= $hotspots->{$ref}->{$pdb}[0] . ';';
            }
            foreach my $pdb (@pdbs) { # carico i valori delle forme HOLO
                $newline .= $hotspots->{$ref}->{$pdb}[1] . ';';
            }
            $newline =~ s/;$/\n/;
            push(@{$content}, $newline);
        }
        $self->set_filename($filename);
        $self->set_filedata($content);
        $self->write();
    }
    
    $self->_raise_warning("\nI- [Leonidas] [$csv_file] written...");
    return $filename;
}

sub rankproducts {
# Two-sample rank products [Koziol, FEBS letters, 2010, 584: 4481-4484]
    
    my $timer = time();
    
    my ($self, $mode, $random_permutations) = @_;
    $random_permutations = 100 unless ($random_permutations);
    
    my ($infile, $outfile);
    if ($mode eq 'flu') {
        $infile = 'flu_diffmat.csv';
        $outfile = 'flu_rankprod.csv';
    } elsif ($mode eq 'ene') {
        $infile = 'nrg_diffmat.csv';
        $outfile = 'nrg_rankprod.csv';
    } else {
        $self->_raise_error("\nI- [Leonidas] unknown mode");
    }
    
    # leggo il file .csv di input
    my $filename = $self->get_workdir(). '/' . $infile;
    $self->set_filename($filename);
    my $content = $self->read();
    
    $self->_raise_warning("\nI- [Leonidas] hotspot rank products...");
    # stabilisco quali colonne appartengono alla prima classe e quali alla seconda (es. @A = (1,2,3,4); @B = (5,6,7,8))
    my $row = shift @{$content};
    chomp $row;
    my @classes = split /;/, $row; # riga per definire le classi
    my (@A, @B);
    foreach my $i (0..scalar(@classes)-1) {
        if ($classes[$i] =~ '_apo') {
            push @A, $i-1;
        } elsif ($classes[$i] =~ '_holo') {
            push @B, $i-1;
        };
    }
    
    # leggo il resto del file .csv
    my $count = 0; # numero di probes
    my @probes; # lista dei nomi delle probes
    my $data = [ ]; # valori delle probes
    while (my $row = shift @{$content}) {
        chomp $row;
        my @line = split(';', $row);
        $probes[$count] = shift @line;
        foreach my $col (0..scalar(@line)-1) {
            $data->[$col][$count] = $line[$col];
        }
        $count++;
    }
    
    # assegno i rank ad ogni colonna
    foreach my $exp (@{$data}) {
        my @sortdata = sort {$exp->[$b] <=> $exp->[$a]} (0..$count-1);
        my $rank = 1;
        foreach my $i (@sortdata) {
            $exp->[$i] = $rank;
            $rank ++;
        }
    }
    
    # calcolo i valori di rank products
    my @RP;
    foreach my $probe (0..$count-1) {
        my ($rp_A, $rp_B) = (1, 1);
        foreach my $col (@A) {
            $rp_A *= $data->[$col][$probe];
        }
        $rp_A = $rp_A**(1/(scalar @A));
        foreach my $col (@B) {
            $rp_B *= $data->[$col][$probe];
        }
        $rp_B = $rp_B**(1/(scalar @B));
        push(@RP, [$rp_A, $rp_B]);
    }
    
    # permutazioni
    my $rand_RP = { };
    my $tot_cols = scalar @A + scalar @B;
    print "\n";
    for my $run (1..$random_permutations) {
        $rand_RP->{sprintf("R%06d", $run)} = [ ];
        my $rand_data = [ ];
        for my $probe (0..$count-1) {
            for my $col (0..$tot_cols-1) {
                $rand_data->[$col][$probe] = rand ();
            }
        }
        foreach my $exp (@{$rand_data}) {
            my @sortdata = sort {$exp->[$b] <=> $exp->[$a]} (0..$count-1);
            my $rank = 1;
            foreach my $i (@sortdata) {
                $exp->[$i] = $rank;
                $rank ++;
            }
        }
        foreach my $probe (0..$count-1) {
            my ($rp_A, $rp_B) = (1, 1);
            foreach my $col (@A) {
                $rp_A *= $rand_data->[$col][$probe];
            }
            $rp_A = $rp_A**(1/(scalar @A));
            foreach my $col (@B) {
                $rp_B *= $rand_data->[$col][$probe];
            }
            $rp_B = $rp_B**(1/(scalar @B));
            push(@{$rand_RP->{sprintf("R%06d", $run)}}, [$rp_A, $rp_B]);
        }
        printf("\r  [%05d/%05d] permutations...", $run, $random_permutations)
            if (($random_permutations-$run) % 21 == 0);
    }

    # evalue e fdr per la classe A
    my @sort_RP = sort {$RP[$a]->[0] <=> $RP[$b]->[0]} (0..$count-1);
    my (@e_A, @f_A);
    foreach my $probe (@sort_RP) {
        my $x = 0;
        foreach my $key (sort keys %{$rand_RP}) {
            $x++ if ($rand_RP->{$key}->[$probe]->[0] <= $RP[$probe]->[0]);
        }
        $e_A[$probe] = $x/$random_permutations;
        $f_A[$probe] = $e_A[$probe]/($probe+1);
    }
    
    # evalue e fdr per la classe B
    @sort_RP = sort {$RP[$a]->[1] <=> $RP[$b]->[1]} (0..$count-1);
    my (@e_B, @f_B);
    foreach my $probe (@sort_RP) {
        my $x = 0;
        foreach my $key (sort keys %{$rand_RP}) {
            $x++ if ($rand_RP->{$key}->[$probe]->[1] <= $RP[$probe]->[1]);
        }
        $e_B[$probe] = $x/$random_permutations;
        $f_B[$probe] = $e_B[$probe]/($probe+1);
    }
    
    # scrivo il file .csv
    $content = [ ];
    push(@{$content}, "PROBE;LOG(RP);RANKa;EVALa;FDRa;RANKb;EVALb;FDRb\n");
    foreach my $i (0..$count-1) {
        my $diff = log($RP[$i]->[0]/$RP[$i]->[1])/log(10);
        my $string = sprintf("%s;%.02f;%.02f;%.02e;%.02f;%.02f;%.02e;%.02f\n", $probes[$i], $diff, $RP[$i]->[0], $e_A[$i], $f_A[$i]*100, $RP[$i]->[1], $e_B[$i], $f_B[$i]*100);
        push(@{$content}, $string);
    }
    $filename = $self->get_workdir(). '/' . $outfile;
    $self->set_filename($filename);
    $self->set_filedata($content);
    $self->write();
    $self->_raise_warning("\nI- [Leonidas] [$outfile] written...");
    return $outfile;
    
    
    my $timerend = time();
    printf("\nI- run time %d secs",$timerend - $timer);
    
}

sub hotspot_cluster {
    my ($self, $mode) = @_;
    my $dataset = $self->get_dataset();
    my $dbh = $self->access2db();
    
    my ($db_table, $dismat);
    if ($mode eq 'flu') {
        $db_table = 'fludecomp';
        $dismat = 'flu_clust.dismat.csv';
    } elsif ($mode eq 'ene') {
        $db_table = 'enedecomp';
        $dismat = 'nrg_clust.dismat.csv';
    } else {
        $self->_raise_error("\nI- [Leonidas] unknown mode");
    }
    
    my %refs; # lista dei residui da selezionare
    MYSQL: {
        $self->_raise_warning("\nI- [Leonidas] querying database...");
        my ($sth, $fetch);
        
        $sth = $self->query_exec('dbh' => $dbh, 
            'query' => "SELECT ref, count(*) FROM $db_table WHERE form LIKE 'APO' GROUP BY ref");
        $fetch = $sth->fetchall_arrayref();
        $sth->finish();
        my $tot = scalar @{$fetch}; # numero di record estratti dal database
        my $ave = 0E0; # media delle occorrenze per ogni record
        foreach my $record (@{$fetch}) {
            $ave += $record->[1];
        }
        $ave = $ave / $tot;
        $refs{'APO'} = { };
        foreach my $record (@{$fetch}) {
            if ($record->[1] > $ave) {
                $refs{'APO'}->{$record->[0]} = 1;
            }
        }
        
        $sth = $self->query_exec('dbh' => $dbh, 
            'query' => "SELECT ref, count(*) FROM $db_table WHERE form LIKE 'HOLO' GROUP BY ref");
        $fetch = $sth->fetchall_arrayref();
        $tot = scalar @{$fetch}; # numero di record estratti dal database
        $ave = 0E0; # media delle occorrenze per ogni record
        foreach my $record (@{$fetch}) {
            $ave += $record->[1];
        }
        $ave = $ave / $tot;
        $refs{'HOLO'} = { };
        foreach my $record (@{$fetch}) {
            if ($record->[1] > $ave) {
                $refs{'HOLO'}->{$record->[0]} = 1;
            }
        }
    }
    my $occur = $self->get_workdir() . '/' . $dismat;
    OCCURRENCIES: { # costruisco la tabella delle occorrenze
        $self->_raise_warning("\nI- [Leonidas] creating distance matrix...");
        my ($sth, $fetch);
        
        my %ress;
        my $allrefs = [ ];
        APO: {
            my $string = q/'/ . sprintf("\n[%s]", join(q/', '/, keys %{$refs{'APO'}})) . q/'/;
            $sth = $self->query_exec('dbh' => $dbh, 
                'query' => "SELECT pdb, ref, form FROM $db_table WHERE ref IN ($string) AND form = 'APO'");
            $fetch = $sth->fetchall_arrayref();
            push(@{$allrefs}, @{$fetch});
            $sth->finish();
        }
        HOLO: {
            my $string = q/'/ . sprintf("\n[%s]", join(q/', '/, keys %{$refs{'HOLO'}})) . q/'/;
            $sth = $self->query_exec('dbh' => $dbh, 
                'query' => "SELECT pdb, ref, form FROM $db_table WHERE ref IN ($string) AND form = 'HOLO'");
            $fetch = $sth->fetchall_arrayref();
            push(@{$allrefs}, @{$fetch});
            $sth->finish();
        }
        while (my $row = shift @{$allrefs}) {
            my ($pdb, $ref, $form) = @{$row};
            if ($ref =~ /^VH/) {
                $ref = 'A-' . $ref;
            } elsif ($ref =~ /^CH/) {
                $ref = 'B-' . $ref;
            } elsif ($ref =~ /^VL/) {
                $ref = 'C-' . $ref;
            } elsif ($ref =~ /^CL/) {
                $ref = 'D-' . $ref;
            }
            $ress{$ref} = { } 
                unless (exists $ress{$ref});
            if ($form =~ /APO/) {
                $ress{$ref}->{$pdb} = -1;
            } elsif ($form =~ /HOLO/) {
                $ress{$ref}->{$pdb} = 1;
            }
        }
        my @reflist = sort keys %ress;
        my @header = @reflist; map { $a = $_; $a =~ s/^[ABCD]-//; $_ = $a; } @header;
        my @pdblist = sort keys %{$self->get_dataset()};
        my $file_content = [ ];
        push(@{$file_content}, 'pdb;' . join(';', @header) . "\n");
        while (my $pdb = shift @pdblist) {
            my $record = "$pdb;";
            foreach my $ref (@reflist) {
                my $value = 0;
                $value = $ress{$ref}->{$pdb}
                    if (exists $ress{$ref}->{$pdb});
                $value .= ';';
                $record .= $value;
            }
            $record =~ s/;$/\n/;
            push(@{$file_content}, $record);
        }
        $self->set_filename($occur);
        $self->set_filedata($file_content);
        $self->write();
    }
    $dbh->disconnect;
    
    $self->_raise_warning("\nI- [Leonidas] performing cluster analysis...");
    my $silhouette = $self->clust($occur, $mode);
    
    return $silhouette;
}

sub hotspot_decomp {
    my ($self, $mode) = @_;
    my $dataset = $self->get_dataset();
    
    my ($db_table, $heavydat, $lightdat, $heavypng, $lightpng, $heavygnu, $lightgnu, $pml_file);
    if ($mode eq 'flu') {
        $db_table = 'fludecomp';
        $heavydat = 'flu_dist.heavy.dat';
        $lightdat = 'flu_dist.light.dat';
        $heavypng = 'flu_dist.heavy.png';
        $lightpng = 'flu_dist.light.png';
        $heavygnu = 'flu_dist.heavy.gnu';
        $lightgnu = 'flu_dist.light.gnu';
        $pml_file = 'flu_dist.pml';
    } elsif ($mode eq 'ene') {
        $db_table = 'enedecomp';
        $heavydat = 'nrg_dist.heavy.dat';
        $lightdat = 'nrg_dist.light.dat';
        $heavypng = 'nrg_dist.heavy.png';
        $lightpng = 'nrg_dist.light.png';
        $heavygnu = 'nrg_dist.heavy.gnu';
        $lightgnu = 'nrg_dist.light.gnu';
        $pml_file = 'nrg_dist.pml';
    } else {
        $self->_raise_error("\nI- [Leonidas] unknown mode");
    }
    
    # lista dei file pdb che mi serviranno
    my $filelist = { };
    foreach my $pdbID (keys %{$dataset}) {
        $filelist->{$pdbID} = $dataset->{$pdbID}->{'PDB'};
    }
    
    my %ref_apo; my %ref_holo; my %ref_both; # percentuali di pdb che condividono gli stessi residui di riferimento (es. VH0025)
    my %res_apo; my %res_holo; my %res_both; # liste di residui coinvolti per ogni pdb
    MYSQL: { # recupero la lista dei residui interessanti interrogando il database
        $self->_raise_warning("\nI- [Leonidas] querying database...");
        my $dbh = $self->access2db();
        my ($sth, $fetch);
        APO_FORM: {
            $sth = $self->query_exec('dbh' => $dbh, 
                'query' => "SELECT ref, count(*) FROM $db_table WHERE form LIKE 'APO' GROUP BY ref");
            $fetch = $sth->fetchall_arrayref();
            my $tot = scalar @{$fetch}; # numero di record estratti dal database
            my $ave = 0E0; # media delle occorrenze per ogni record
            foreach my $record (@{$fetch}) {
                $ave += $record->[1];
            }
            $ave = $ave / $tot;
            foreach my $record (@{$fetch}) {
                if ($record->[1] > $ave) {
                    $ref_apo{$record->[0]} = sprintf("%.3f", ($record->[1]/scalar keys %{$dataset})*100);
                }
            }
            my $string = q/'/ . join(q/', '/, keys %ref_apo) . q/'/;
            $sth = $self->query_exec('dbh' => $dbh, 
                'query' => "SELECT pdb, res FROM $db_table WHERE ref IN ($string) AND form LIKE 'APO'");
            while (my @row = $sth->fetchrow_array) {
                my $pdb = $row[0];
                my $res = $row[1];
                $res_apo{$pdb} = [ ]
                    unless (exists $res_apo{$pdb});
                push(@{$res_apo{$pdb}}, $res);
            }
        }
        HOLO_FORM: {
            $sth = $self->query_exec('dbh' => $dbh, 
                'query' => "SELECT ref, count(*) FROM $db_table WHERE form LIKE 'HOLO' GROUP BY ref");
            $fetch = $sth->fetchall_arrayref();
            my $tot = scalar @{$fetch}; # numero di record estratti dal database
            my $ave = 0E0; # media delle occorrenze per ogni record
            foreach my $record (@{$fetch}) {
                $ave += $record->[1];
            }
            $ave = $ave / $tot;
            foreach my $record (@{$fetch}) {
                if ($record->[1] > $ave) {
                    $ref_holo{$record->[0]} = sprintf("%.3f", ($record->[1]/scalar keys %{$dataset})*100);
                }
            }
            my $string = q/'/ . join(q/', '/, keys %ref_apo) . q/'/;
            $sth = $self->query_exec('dbh' => $dbh, 
                'query' => "SELECT pdb, res FROM $db_table WHERE ref IN ($string) AND form LIKE 'HOLO'");
            while (my @row = $sth->fetchrow_array) {
                my $pdb = $row[0];
                my $res = $row[1];
                $res_holo{$pdb} = [ ]
                    unless (exists $res_holo{$pdb});
                push(@{$res_holo{$pdb}}, $res);
            }
        }
        BOTH_FORM: {
            $sth = $self->query_exec('dbh' => $dbh, 
                'query' => "SELECT ref, count(*) FROM $db_table WHERE form LIKE 'BOTH' GROUP BY ref");
            $fetch = $sth->fetchall_arrayref();
            my $tot = scalar @{$fetch}; # numero di record estratti dal database
            my $ave = 0E0; # media delle occorrenze per ogni record
            foreach my $record (@{$fetch}) {
                $ave += $record->[1];
            }
            $ave = $ave / $tot;
            foreach my $record (@{$fetch}) {
                if ($record->[1] > $ave) {
                    $ref_both{$record->[0]} = sprintf("%.3f", ($record->[1]/scalar keys %{$dataset})*100);
                }
            }
            my $string = q/'/ . join(q/', '/, keys %ref_apo) . q/'/;
            $sth = $self->query_exec('dbh' => $dbh, 
                'query' => "SELECT pdb, res FROM $db_table WHERE ref IN ($string) AND form LIKE 'BOTH'");
            while (my @row = $sth->fetchrow_array) {
                my $pdb = $row[0];
                my $res = $row[1];
                $res_both{$pdb} = [ ]
                    unless (exists $res_both{$pdb});
                push(@{$res_both{$pdb}}, $res);
            }
        }
        $sth->finish();
        $dbh->disconnect;
    }
    
    STACKED: { # produco uno stacked histogram per mostrare la distribuzione dei residui
        $self->_raise_warning("\nI- [Leonidas] calculating distributions...");
        my %refs;
        foreach my $key (keys %ref_apo) {
            $refs{$key} = []
                unless (exists $refs{$key});
        }
        foreach my $key (keys %ref_holo) {
            $refs{$key} = []
                unless (exists $refs{$key});
        }
        foreach my $key (keys %ref_both) {
            $refs{$key} = []
                unless (exists $refs{$key});
        }
        foreach my $key (keys %refs) {
            my ($apo, $holo, $both) = (0E0, 0E0, 0E0);
            $apo = $ref_apo{$key}
                if (exists $ref_apo{$key});
            $holo = $ref_holo{$key}
                if (exists $ref_holo{$key});
            $both = $ref_both{$key}
                if (exists $ref_both{$key});
            my $tot = $apo + $holo + $both;
            $apo = sprintf("%.3f", $apo/$tot);
            $holo = sprintf("%.3f", $holo/$tot);
            $both = sprintf("%.3f", $both/$tot);
            $refs{$key} = [ $apo, $both, $holo];
        }
        # siccome i dati sono tanti splitto %refs per la catena pesante e per la leggera
        my %heavy_refs;
        my %light_refs;
        foreach my $key (keys %refs) { # uso dei flag "A-" e "B-" per ordinare i residui correttamente da N-term a C-term
            my $label;
            if ($key =~ /^V/) {
                $label = 'A-'.$key;
            } elsif ($key =~ /^C/) {
                $label = 'B-'.$key;
            }
            if ($key =~ /H/) {
                $heavy_refs{$label} = $refs{$key};
            } elsif ($key =~ /L/) {
                $light_refs{$label} = $refs{$key};
            }
        }
        DATFILE: { # parsing dei .dat file per gnuplot
            my $dat_content = [ ];
            my $header = "RESIDUE  APO  BOTH  HOLO\n";
            push(@{$dat_content}, $header);
            foreach my $ref (sort keys %heavy_refs){
                my $label = $ref;
                $label =~ s/[AB]-//;
                push(@{$dat_content}, sprintf("%s  %s\n", $label, join('  ', @{$heavy_refs{$ref}})));
            }
            $self->set_filename($self->get_workdir() . '/' . $heavydat);
            $self->set_filedata($dat_content);
            $self->write();
            $dat_content = [ ];
            push(@{$dat_content}, $header);
            foreach my $ref (sort keys %light_refs){
                my $label = $ref;
                $label =~ s/[AB]-//;
                push(@{$dat_content}, sprintf("%s  %s\n", $label, join('  ', @{$light_refs{$ref}})));
            }
            $self->set_filename($self->get_workdir() . '/' . $lightdat);
            $self->set_filedata($dat_content);
            $self->write();
        }
        GNUPLOT: {
            my $destpath = $self->get_workdir();
            my $gnuscript_heavy = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw the ditribution of the most relevant residues according to energy decomposition analysis
# 
set terminal png size 4000, 600
set size ratio 0.10
set output "$heavypng"
set title "HEAVY CHAIN"
set key under nobox
set yrange [0:1]
set ylabel "% of total"
unset ytics
set xtics rotate
set grid y
set border 3
set style data histograms
set style histogram rowstacked
set style fill solid border -1
set boxwidth 0.75
plot '$heavydat' using 4:xtic(1) t column(4) lt rgb "red", \\
        '' using 3 t column(3) lt rgb "orange", \\
        '' using 2 t column(2) lt rgb "yellow"
END
            ;
            $self->set_filename($self->get_workdir() . '/' . $heavygnu);
            $self->set_filedata([ $gnuscript_heavy ]);
            $self->write();
            my $gnuscript_light = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw the ditribution of the most relevant residues according to energy decomposition analysis
# 
set terminal png size 4000, 600
set size ratio 0.10
set output "$lightpng"
set title "LIGHT CHAIN"
set key under nobox
set yrange [0:1]
set ylabel "% of total"
unset ytics
set xtics rotate
set grid y
set border 3
set style data histograms
set style histogram rowstacked
set style fill solid border -1
set boxwidth 0.75
plot 'lightdat' using 4:xtic(1) t column(4) lt rgb "red", \\
        '' using 3 t column(3) lt rgb "orange", \\
        '' using 2 t column(2) lt rgb "yellow"
END
            ;
            $self->set_filename($self->get_workdir() . '/' . $lightgnu);
            $self->set_filedata([ $gnuscript_light ]);
            $self->write();
            
            # verifico che gnuplot sia installato
            my $gnuplot = qx/which gnuplot44  2> \/dev\/null/; # in realtà il comando è "gnuplot", siccome ho bisogno della versione 4.4 uso questo link ("gnuplot44") per distinguerlo dal Gnuplot installato di default
            chomp $gnuplot;
            $self->_raise_error("\nE- [Leonidas] Gnuplot software not found\n\t")
                unless $gnuplot;
            
            # creo i miei file .png
            my $gplot_log = qx/$gnuplot  $lightgnu 2>&1/;
                $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
            # print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
            $gplot_log = qx/$gnuplot  $heavygnu 2>&1/;
                $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
            # print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
        }
    }
    my $refined = { # hashref che ritorno
        'APO' => \%res_apo, 'HOLO' => \%res_holo, 'BOTH' => \%res_both
    };
    PYMOL: {
        my $destpath = $self->get_workdir();
        $self->_raise_warning("\nI- [Leonidas] generating PyMol script [$destpath/$pml_file]...");
        $self->set_pdblist($filelist); # pdblist è un attributo della classe Theodorus che eredito
        my $content = $self->pml_hotspot($refined);
        
        # scrivo su file lo script
        $self->set_filename($destpath . '/' . $pml_file);
        $self->set_filedata($content);
        $self->write();
    }
    
    return $refined;
}

sub hotspot_stats {
    my ($self,$pvalue,$mode) = @_;
    my $dataset = $self->get_dataset();
    my $dbh = $self->access2db();
    
    my ($db_table, $apo_csv, $holo_csv, $ttest_dat, $apognu, $holognu, $apo_png, $holo_png);
    if ($mode eq 'flu') {
        $db_table = 'fludecomp';
        $apo_csv = 'flu_stats.apo.csv';
        $holo_csv = 'flu_stats.holo.csv';
        $ttest_dat = 'flu_stats.ttest.dat';
        $apognu = 'flu_stats.apo.gnu';
        $holognu = 'flu_stats.holo.gnu';
        $apo_png = 'flu_stats.apo.png';
        $holo_png = 'flu_stats.holo.png';
    } elsif ($mode eq 'ene') {
        $db_table = 'enedecomp';
        $apo_csv = 'nrg_stats.apo.csv';
        $holo_csv = 'nrg_stats.holo.csv';
        $ttest_dat = 'nrg_stats.ttest.dat';
        $apognu = 'nrg_stats.apo.gnu';
        $holognu = 'nrg_stats.holo.gnu';
        $apo_png = 'nrg_stats.apo.png';
        $holo_png = 'nrg_stats.holo.png';
    } else {
        $self->_raise_error("\nI- [Leonidas] unknown mode");
    }
    
    my $hotspots = { 'APO' => [ ], 'HOLO' => [ ] }; # lista degli hotspots
    SEARCH: {
        $self->_raise_warning("\nI- [Leonidas] retrieving hotspots...");
        my ($sth, $fetch);
        $sth = $self->query_exec('dbh' => $dbh, 
            'query' => "SELECT ref, count(*) FROM $db_table WHERE form LIKE 'APO' GROUP BY ref");
        $fetch = $sth->fetchall_arrayref();
        $sth->finish();
        my $tot = scalar @{$fetch}; # numero di record estratti dal database
        my $ave = 0E0; # media delle occorrenze per ogni record
        foreach my $record (@{$fetch}) {
            $ave += $record->[1];
        }
        $ave = $ave / $tot;
        foreach my $record (@{$fetch}) {
            if ($record->[1] > $ave) {
                push(@{$hotspots->{'APO'}}, $record->[0]);
            }
        }
        $sth->finish();
        $sth = $self->query_exec('dbh' => $dbh, 
            'query' => "SELECT ref, count(*) FROM $db_table WHERE form LIKE 'HOLO' GROUP BY ref");
        $fetch = $sth->fetchall_arrayref();
        $tot = scalar @{$fetch}; # numero di record estratti dal database
        $ave = 0E0; # media delle occorrenze per ogni record
        foreach my $record (@{$fetch}) {
            $ave += $record->[1];
        }
        $ave = $ave / $tot;
        foreach my $record (@{$fetch}) {
            if ($record->[1] > $ave) {
                push(@{$hotspots->{'HOLO'}}, $record->[0]);
            }
        }
        $sth->finish();
    }
    
    # distribuzione di hotspots nei singoli PDB
    my $pdb_counts = { }; # inizializzazione del mio hashref
    foreach my $pdb (sort keys %{$dataset}) {
        foreach my $form ('APO', 'HOLO') {
            $pdb_counts->{$form} = { }
                unless (exists $pdb_counts->{$form});
            unless (exists $pdb_counts->{$form}->{$pdb}) {
                $pdb_counts->{$form}->{$pdb} = {
                    'VH' => [0,0], 'VL' => [0,0], 'CH' => [0,0], 'CL' => [0,0]
# ogni array si riferisce al numero di hotspots che mappano su contatti intercatena contro quelli "interni"
                };
            }
        }
    }
    SEEK: {
        $self->_raise_warning("\nI- [Leonidas] classifying hotspots...");
        my ($sth, $fetch);
        foreach my $key ('APO', 'HOLO') {
            my $refs = "'" . join("', '", @{$hotspots->{$key}}) . "'";
            my $query = <<END
SELECT $db_table.pdb, $db_table.ref, $db_table.form, pdbsum.chainB
FROM $db_table
JOIN xres
ON xres.pdb = $db_table.pdb
AND xres.res = $db_table.res
LEFT JOIN pdbsum
ON pdbsum.pdb = xres.pdb
AND pdbsum.residA = xres.source_res
WHERE $db_table.ref IN ( $refs )
AND $db_table.form LIKE "$key"
GROUP BY CONCAT($db_table.pdb, $db_table.res)
END
            ;
            $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
            while (my @row = $sth->fetchrow_array) {
                $row[3] = ' '  unless ($row[3]);
                my $pdb = $row[0];
                my ($domain) = $row[1] =~ /(VH|VL|CH|CL)/;
                my $form = $row[2];
                my $inter = $row[3];
                $pdb_counts->{$form}->{$pdb}->{$domain}->[1]++;
                if ($inter =~ /[HL]/) {
                    $pdb_counts->{$form}->{$pdb}->{$domain}->[0]++;
                    $pdb_counts->{$form}->{$pdb}->{$domain}->[1]--;
                } else {
                    next;
                }
            }
        }
    }
    $dbh->disconnect;
    my $csvfile_apo =  $self->get_workdir() . '/' . $apo_csv;
    my $csvfile_holo =  $self->get_workdir() . '/' . $holo_csv;
    CSVFILE: {
        my $header = "PDB;VHinter;VHintra;VLinter;VLintra;CHinter;CHintra;CLinter;CLintra\n";
        APO: {
            $self->set_filename($csvfile_apo);
            my $content = [ $header ];
            foreach my $pdb (sort keys %{$pdb_counts->{'APO'}}) {
                my ($VHinter,$VHintra,$VLinter,$VLintra,$CHinter,$CHintra,$CLinter,$CLintra) = (
                    $pdb_counts->{'APO'}->{$pdb}->{'VH'}->[0],$pdb_counts->{'APO'}->{$pdb}->{'VH'}->[1],
                    $pdb_counts->{'APO'}->{$pdb}->{'VL'}->[0],$pdb_counts->{'APO'}->{$pdb}->{'VL'}->[1],
                    $pdb_counts->{'APO'}->{$pdb}->{'CH'}->[0],$pdb_counts->{'APO'}->{$pdb}->{'CH'}->[1],
                    $pdb_counts->{'APO'}->{$pdb}->{'CL'}->[0],$pdb_counts->{'APO'}->{$pdb}->{'CL'}->[1]
                );
                my $string = "$pdb;$VHinter;$VHintra;$VLinter;$VLintra;$CHinter;$CHintra;$CLinter;$CLintra\n";
                push(@{$content}, $string);
            }
            $self->set_filedata($content);
            $self->write();
        }
        HOLO: {
            $self->set_filename($csvfile_holo);
            my $content = [ $header ];
            foreach my $pdb (sort keys %{$pdb_counts->{'HOLO'}}) {
                my ($VHinter,$VHintra,$VLinter,$VLintra,$CHinter,$CHintra,$CLinter,$CLintra) = (
                    $pdb_counts->{'HOLO'}->{$pdb}->{'VH'}->[0],$pdb_counts->{'HOLO'}->{$pdb}->{'VH'}->[1],
                    $pdb_counts->{'HOLO'}->{$pdb}->{'VL'}->[0],$pdb_counts->{'HOLO'}->{$pdb}->{'VL'}->[1],
                    $pdb_counts->{'HOLO'}->{$pdb}->{'CH'}->[0],$pdb_counts->{'HOLO'}->{$pdb}->{'CH'}->[1],
                    $pdb_counts->{'HOLO'}->{$pdb}->{'CL'}->[0],$pdb_counts->{'HOLO'}->{$pdb}->{'CL'}->[1]
                );
                my $string = "$pdb;$VHinter;$VHintra;$VLinter;$VLintra;$CHinter;$CHintra;$CLinter;$CLintra\n";
                push(@{$content}, $string);
            }
            $self->set_filedata($content);
            $self->write();
        }
    }
    my $pdb_stats = [ ];
    STATS: {
        $self->_raise_warning("\nI- [Leonidas] performing Student T test...");
        # raccolgo il numero di residui, per ogni pdb, che mappano all'interno di un dominio ($intra) o all'interfaccia tra catena pesante e leggera ($inter)
        # il primo elemento di ogni arrayref [[],[]] sono i residui per le forme apo, il secondo per le forme holo
        my $intra = { 'VH' => [[],[]], 'VL' => [[],[]], 'CH' => [[],[]], 'CL' => [[],[]]};
        my $inter = { 'VH' => [[],[]], 'VL' => [[],[]], 'CH' => [[],[]], 'CL' => [[],[]]};
        my $content = $self->read($csvfile_apo);
        shift @{$content};
        while (my $row = shift @{$content}) {
            chomp $row;
            my @fields = split(';', $row);
            push(@{$intra->{'VH'}->[0]}, $fields[2]);
            push(@{$intra->{'VL'}->[0]}, $fields[4]);
            push(@{$intra->{'CH'}->[0]}, $fields[6]);
            push(@{$intra->{'CL'}->[0]}, $fields[8]);
            push(@{$inter->{'VH'}->[0]}, $fields[1]);
            push(@{$inter->{'VL'}->[0]}, $fields[3]);
            push(@{$inter->{'CH'}->[0]}, $fields[5]);
            push(@{$inter->{'CL'}->[0]}, $fields[7]);
        }
        $content = $self->read($csvfile_holo);
        shift @{$content};
        while (my $row = shift @{$content}) {
            chomp $row;
            my @fields = split(';', $row);
            push(@{$intra->{'VH'}->[1]}, $fields[2]);
            push(@{$intra->{'VL'}->[1]}, $fields[4]);
            push(@{$intra->{'CH'}->[1]}, $fields[6]);
            push(@{$intra->{'CL'}->[1]}, $fields[8]);
            push(@{$inter->{'VH'}->[1]}, $fields[1]);
            push(@{$inter->{'VL'}->[1]}, $fields[3]);
            push(@{$inter->{'CH'}->[1]}, $fields[5]);
            push(@{$inter->{'CL'}->[1]}, $fields[7]);
        }
        $content = [ ];
        $content = [ "APO_vs_HOLO\tH0_(p-value < $pvalue)\n" ];
        $pvalue = int((1-$pvalue)*100); # alfa level per i test statistici
        my $ksquare; # pvalue per stabilire se una distribuzione è normale (requisito per il test T)
        # definisco le coppie di distribuzioni su cui fare il test T di Student
        my $pairs = {
            'VHintra' => [ $intra->{'VH'}->[0], $intra->{'VH'}->[1] ],
            'VLintra' => [ $intra->{'VL'}->[0], $intra->{'VL'}->[1] ],
            'CHintra' => [ $intra->{'CH'}->[0], $intra->{'CH'}->[1] ],
            'CLintra' => [ $intra->{'CL'}->[0], $intra->{'CL'}->[1] ],
            'VHinter' => [ $inter->{'VH'}->[0], $inter->{'VH'}->[1] ],
            'VLinter' => [ $inter->{'VL'}->[0], $inter->{'VL'}->[1] ],
            'CHinter' => [ $inter->{'CH'}->[0], $inter->{'CH'}->[1] ],
            'CLinter' => [ $inter->{'CL'}->[0], $inter->{'CL'}->[1] ]
        };
        foreach my $key ('VHintra','VLintra','CHintra','CLintra','VHinter','VLinter','CHinter','CLinter') {
            my ($apo, $holo) = @{$pairs->{$key}};
            # test di goodness of fit (K-squared test)
            my $pval = (100 - $pvalue)/100;
            $ksquare = Statistics::Normality::dagostino_k_square_test($apo);
            if ($ksquare <= $pval) {
                printf("\n\tW- [Leonidas] %s(apo) distribution could not be normal (%.1e/%.1e)", $key, $ksquare, $pval) 
            };
            $ksquare = Statistics::Normality::dagostino_k_square_test($holo);
            if ($ksquare <= $pval) {
                printf("\n\tW- [Leonidas] %s(holo) distribution could not be normal (%.1e/%.1e)", $key, $ksquare, $pval) 
            };
            my $ttest = Statistics::TTest->new();
            $ttest->set_significance($pvalue);
            $ttest->load_data($apo,$holo);
            # test T di Student (H0 = "i due campioni hanno la stessa media")
            my $verdict = $ttest->null_hypothesis();
            my $string = "$key\t\t$verdict\n";
            push(@{$content}, $string);
        }
        my $filename = $self->get_workdir . '/' . $ttest_dat;
        $self->set_filename($filename);
        $self->set_filedata($content);
        $self->write();
        $pdb_stats = $content;
    }
    GNUPLOT: {
        $self->_raise_warning("\nI- [Leonidas] generating histograms...");
        APO: {
            my $gnu_filename = $self->get_workdir . '/' . $apognu;
            REORDER: {
                my $content = $self->read($self->get_workdir . '/' . $apo_csv);
                my $header = shift @{$content};
                $header =~ s/;/  /g;
                my $domains = { 'VH' => { }, 'VL' => { }, 'CH' => { }, 'CL' => { } };
                while (my $row = shift @{$content}) {
                    my ($key, $value);
                    chomp $row;
                    my @fields = split(';', $row);
                    $key = sprintf("%05d_%s", $fields[1]+$fields[2], $fields[0]);
                    $value = "$fields[1] $fields[2]";
                    $domains->{'VH'}->{$key} = $value;
                    $key = sprintf("%05d_%s", $fields[3]+$fields[4], $fields[0]);
                    $value = "$fields[3] $fields[4]";
                    $domains->{'VL'}->{$key} = $value;
                    $key = sprintf("%05d_%s", $fields[5]+$fields[6], $fields[0]);
                    $value = "$fields[5] $fields[6]";
                    $domains->{'CH'}->{$key} = $value;
                    $key = sprintf("%05d_%s", $fields[7]+$fields[8], $fields[0]);
                    $value = "$fields[7] $fields[8]";
                    $domains->{'CL'}->{$key} = $value;
                }
                my @depo;
                foreach my $dom ('VH','VL','CH','CL') {
                    my $i = 0;
                    foreach my $key (reverse sort keys %{$domains->{$dom}}) {
                        $depo[$i] = 'dummy' unless $depo[$i];
                        $depo[$i] .= "  $domains->{$dom}->{$key}";
                        $i++;
                    }
                }
                $content = [ $header ];
                for (my $i = 0; $i < scalar @depo; $i++) {
                    push(@{$content}, "$depo[$i]\n");
                }
                $self->set_filename($self->get_workdir . '/ordine.dat');
                $self->set_filedata($content);
                $self->write();
            }
            
            my $gnuscript = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw the ditribution of the most relevant residues grouped by Ig domains
# 
set size ratio 0.45
set terminal png size 1800, 800
set output "$apo_png"
set title "APO FORMS"
unset key
set ylabel "# residues"
set ytics out
set yrange [-2:90]
unset xtics
# set xtics rotate
# set xtics nomirror
set grid y
set border 3
set style data histograms
set style histogram rowstacked
set style fill solid border -1
set boxwidth 0.75
plot \\
    newhistogram "VH domain" at --1, \\
        'ordine.dat' using 2:xtic(1) t column(2) lt rgb "cyan", \\
        '' using 3 t column(3) lt rgb "blue", \\
    newhistogram "VL domain", \\
        '' using 4:xtic(1) t column(4) lt rgb "cyan", \\
        '' using 5 t column(5) lt rgb "blue", \\
    newhistogram "CH domain", \\
        '' using 6:xtic(1) t column(6) lt rgb "cyan", \\
        '' using 7 t column(7) lt rgb "blue", \\
    newhistogram "CL domain", \\
        '' using 8:xtic(1) t column(8) lt rgb "cyan", \\
        '' using 9 t column(9) lt rgb "blue"
unset output
quit
END
            ;
            $self->set_filename($gnu_filename);
            $self->set_filedata([ $gnuscript ]);
            $self->write();
            # verifico che gnuplot sia installato
            my $gnuplot = qx/which gnuplot44  2> \/dev\/null/; # in realtà il comando è "gnuplot", siccome ho bisogno della versione 4.4 uso questo link ("gnuplot44") per distinguerlo dal Gnuplot installato di default
            chomp $gnuplot;
            $self->_raise_error("\nE- [Leonidas] Gnuplot software not found\n\t")
                unless $gnuplot;
            
            # creo il mio file .png
            my $gplot_log = qx/$gnuplot $gnu_filename 2>&1/;
                $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
#             print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
            
            unlink $gnu_filename;
            unlink $self->get_workdir . 'ordine.dat';
        }
        HOLO: {
            my $gnu_filename = $self->get_workdir . '/' . $holognu;
            REORDER: {
                my $content = $self->read($self->get_workdir . '/' . $holo_csv);
                my $header = shift @{$content};
                $header =~ s/;/  /g;
                my $domains = { 'VH' => { }, 'VL' => { }, 'CH' => { }, 'CL' => { } };
                while (my $row = shift @{$content}) {
                    my ($key, $value);
                    chomp $row;
                    my @fields = split(';', $row);
                    $key = sprintf("%05d_%s", $fields[1]+$fields[2], $fields[0]);
                    $value = "$fields[1] $fields[2]";
                    $domains->{'VH'}->{$key} = $value;
                    $key = sprintf("%05d_%s", $fields[3]+$fields[4], $fields[0]);
                    $value = "$fields[3] $fields[4]";
                    $domains->{'VL'}->{$key} = $value;
                    $key = sprintf("%05d_%s", $fields[5]+$fields[6], $fields[0]);
                    $value = "$fields[5] $fields[6]";
                    $domains->{'CH'}->{$key} = $value;
                    $key = sprintf("%05d_%s", $fields[7]+$fields[8], $fields[0]);
                    $value = "$fields[7] $fields[8]";
                    $domains->{'CL'}->{$key} = $value;
                }
                my @depo;
                foreach my $dom ('VH','VL','CH','CL') {
                    my $i = 0;
                    foreach my $key (reverse sort keys %{$domains->{$dom}}) {
                        $depo[$i] = 'dummy' unless $depo[$i];
                        $depo[$i] .= "  $domains->{$dom}->{$key}";
                        $i++;
                    }
                }
                $content = [ $header ];
                for (my $i = 0; $i < scalar @depo; $i++) {
                    push(@{$content}, "$depo[$i]\n");
                }
                $self->set_filename($self->get_workdir . '/ordine.dat');
                $self->set_filedata($content);
                $self->write();
            }
            
            my $gnuscript = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw the ditribution of the most relevant residues grouped by Ig domains
# 
set size ratio 0.45
set terminal png size 1800, 800
set output "$holo_png"
set title "HOLO FORMS"
unset key
set ylabel "# residues"
set ytics out
set yrange [-2:90]
unset xtics
# set xtics rotate
# set xtics nomirror
set grid y
set border 3
set style data histograms
set style histogram rowstacked
set style fill solid border -1
set boxwidth 0.75
plot \\
    newhistogram "VH domain" at --1, \\
        'ordine.dat' using 2:xtic(1) t column(2) lt rgb "yellow", \\
        '' using 3 t column(3) lt rgb "red", \\
    newhistogram "VL domain", \\
        '' using 4:xtic(1) t column(4) lt rgb "yellow", \\
        '' using 5 t column(5) lt rgb "red", \\
    newhistogram "CH domain", \\
        '' using 6:xtic(1) t column(6) lt rgb "yellow", \\
        '' using 7 t column(7) lt rgb "red", \\
    newhistogram "CL domain", \\
        '' using 8:xtic(1) t column(8) lt rgb "yellow", \\
        '' using 9 t column(9) lt rgb "red"
unset output
quit
END
            ;
            $self->set_filename($gnu_filename);
            $self->set_filedata([ $gnuscript ]);
            $self->write();
            # verifico che gnuplot sia installato
            my $gnuplot = qx/which gnuplot44  2> \/dev\/null/; # in realtà il comando è "gnuplot", siccome ho bisogno della versione 4.4 uso questo link ("gnuplot44") per distinguerlo dal Gnuplot installato di default
            chomp $gnuplot;
            $self->_raise_error("\nE- [Leonidas] Gnuplot software not found\n\t")
                unless $gnuplot;
            
            # creo il mio file .png
            my $gplot_log = qx/$gnuplot $gnu_filename 2>&1/;
                $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
#             print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
            
            unlink $gnu_filename;
            unlink $self->get_workdir . '/ordine.dat';
        }
    }
    return $pdb_stats;
}

sub rmsd_stats {
# essential descriptive statistics on RMSD. Given a RMSD profile along a MD simulations, this method provides those descriptors to depict the spread and the skewness of data.
# It takes as input a PDB code, then queries the database and return statistics for both apo and holo form.
    my ($self, $pdbID) = @_;
    
    $pdbID or $self->_raise_error("\nE- [Leonidas] undef PDB code\n\t");
    
    my $returned = { };
    
    my $dbh = $self->access2db();
    my $query_string = "SELECT rmsd, au FROM rmsd WHERE pdb = ? AND form = ? ORDER BY rmsd+0 ASC";
    my $sth = $dbh->prepare($query_string)
        or $self->_raise_error(sprintf("\nE- [Leonidas] mysql statement error: %s\n\t", $dbh->errstr));
    
    foreach my $form ('APO', 'HOLO') {
        
        # recupero i dati grezzi dal DB e li ordino
        $sth->execute($pdbID, $form)
            or $self->_raise_error(sprintf("\nE- [Leonidas] mysql statement error: %s\n\t", $dbh->errstr));
        my @rmsd;
        my @samples;
        my $progress = 0;
        while (my @row = $sth->fetchrow_array) {
            push(@rmsd, sprintf("%.8f", $row[0]));
            $progress = $progress + $row[1];
            push(@samples, $progress);
        }
        
        my $items = $samples[scalar @samples - 1];
        my $apercent = $items / 100; # range 1 percentile
        my $pos_Q1 = sprintf("%i", $apercent * 25);
        my $pos_Q2 = sprintf("%i", $apercent * 50);
        my $pos_Q3 = sprintf("%i", $apercent * 75);
        my ($Q1,$Q2,$Q3);
        for (my $i = 0; $i <= (scalar @samples - 1); $i++) {
            unless ($Q1) {
                if ($pos_Q1 > $samples[$i]) {
                    next;
                } else {
                    $Q1 = $rmsd[$i];
                }
            }
            unless ($Q2) {
                if ($pos_Q2 > $samples[$i]) {
                    next;
                } else {
                    $Q2 = $rmsd[$i];
                }
            }
            unless ($Q3) {
                if ($pos_Q3 > $samples[$i]) {
                    next;
                } else {
                    $Q3 = $rmsd[$i];
                }
            }
        }
        my $iqr = $Q3 - $Q1;
        my $pos_lower = $Q1 - (1.5 * $iqr);
        my $pos_upper = $Q3 + (1.5 * $iqr);
        my ($lower, $upper);
        for (my $i = 0; $i <= (scalar @rmsd - 1); $i++) {
            unless ($lower) {
                if ($pos_lower > $rmsd[$i]) {
                    next;
                } else {
                    $lower = $rmsd[$i+1];
                }
            }
            unless ($upper) {
                if ($pos_upper > $rmsd[$i]) {
                    next;
                } else {
                    $upper = $rmsd[$i-1];
                }
            }
        }
        
        # RIEPILOGO
#         printf("\n*** SUMMARY OF %s FORM", $form);
#         printf("\nITEMS....%i", $items);
#         printf("\nIQR......%.4f", $iqr);
#         printf("\nLOWER....%.4f", $lower);
#         printf("\nQ1.......%.4f", $Q1);
#         printf("\nMEDIAN...%.4f", $Q2);
#         printf("\nQ3.......%.4f", $Q3);
#         printf("\nUPPER....%.4f", $upper);
#         print "\n***\n";
        
        $returned->{$form} = [ $lower, $Q1, $Q2, $Q3, $upper ];
    }
    
    $sth->finish();
    $dbh->disconnect;
    
    return $returned;
}

sub _gnuplot_boxplot {
# Genera un script per Gnuplot di tipo box and whiskers. Ritorna una stringa contenente lo script
    my ($self, $datfile) = @_;
    
    $self->_raise_error(sprintf("\nE- [Leonidas] [%s] file not found\n\t", $datfile))
        unless (-e $datfile);
    
    my $pngfile = $datfile;
    $pngfile =~ s/(\.\w+){0,1}$/\.png/;
    
    $self->_raise_warning("\nI- [Leonidas] generating boxplot [$pngfile]...");
    
    my $content = $self->read($datfile);
    
    my @label_list = grep(/@/, @{$content});
    
    my $labels;
    if (scalar @label_list > 1) {
        $labels = "set xtics (";
        foreach my $item (@label_list) {
            my ($a,$b) = $item =~ m/^# (\d+) @ (\w+)/g;
            $labels .= "\"$b\" $a, ";
        };
        $labels =~ s/, $/)/;
    } else {
        $labels = "set xtics 1";
    }
    
    my @values = grep(/^\d/, @{$content});
    my $max = scalar @values + 1;
    my $gnuscript = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw box and whisker plot of RMSD distributions
# 
set size ratio 0.55
set terminal png size 1280, 800
set output "$pngfile"
set xrange [0:$max]
$labels 
set xtics rotate
set xtics nomirror
set ylabel "nm"
set yrange [0:1]
set ytics 0.1
set mytics 5
show mytics
set boxwidth 0.5
set style fill empty
plot '$datfile' using 1:3:2:6:5 with candlesticks whiskerbars 0.5 lt 3 lw 2 notitle, \\
     ''             using 1:4:4:4:4 with candlesticks lt 1 lw 2 notitle
unset output
quit
END
    ;
    
    return $gnuscript;
}

sub rmsd {
    my ($self) = @_;
    
    my $dataset = $self->get_dataset();
    # scrivo .dat file che dovranno essere letti da GnuPlot
    my ($apo_file, $holo_file);
    RMSD_SHEET: { # raccolgo le statistiche dei profili di RMSD delle mie strutture
        # noiosissimi cicli per raggruppare i PDB secondo la durata delle simulazioni, quindi per odrine alfabetico
        my %sorted;
        foreach my $label (keys %{$dataset}) {
            $sorted{$dataset->{$label}->{'DURATION'}.$label} = $label;
        }
        my @pdblist;
        foreach my $key (sort keys %sorted) {
            push(@pdblist, $sorted{$key});
        }
        
        my $header = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
# 
# Essential descriptive statistics of RMSD distributions, over MD simulations.
# The fields are depicted as follows:
# 1 - reference id
# 2 - lower value, Q1 - 1.5 x IQR (Inter Quartile Range)
# 3 - Q1 value, 25th percentile
# 4 - median value
# 5 - Q3 value, 75th percentile
# 6 - upper value, Q3 + 1.5 x IQR
# 
# All values are expressed in nm.
# 
END
        ;
    
        # nomi dei file .dat relativi alle forme apo e olo del dataset
        $apo_file = $self->get_workdir . '/RMSD.apo.dat';
        $holo_file = $self->get_workdir . '/RMSD.holo.dat';
        my $apo_content = [ $header ];
        my $holo_content = [ $header ];
        
        # definisco a quale PDB appartengono i dati di ogni riga di ogni file .dat
        my $id = 1;
        foreach my $pdb (@pdblist) {
            my $newline = "# $id @ $pdb";
            push(@{$apo_content}, $newline . "\n");
            push(@{$holo_content}, $newline . "\n");
            $id++;
        }
        push(@{$apo_content}, "# \n");
        push(@{$holo_content}, "# \n");
        
        # recupero le statistiche per ogni PDB
        $id = 1;
        $self->_raise_warning(sprintf("\nI- processing RMSD distributions..."));
        foreach my $pdb (@pdblist) {
           my $hashref = $self->rmsd_stats($pdb);
           my $apo_row = join("\t", $id, @{$hashref->{'APO'}}) . "\n";
           my $holo_row = join("\t", $id, @{$hashref->{'HOLO'}}) . "\n";
           push(@{$apo_content}, $apo_row);
           push(@{$holo_content}, $holo_row);
           $id++;
        }
        
        # scrivo i file
        $self->set_filename($apo_file);
        $self->set_filedata($apo_content);
        $self->write();
        $self->set_filename($holo_file);
        $self->set_filedata($holo_content);
        $self->write();
    }
    
    # verifico che gnuplot sia installato
    my $gnuplot = qx/which gnuplot44  2> \/dev\/null/; # in realtà il comando è "gnuplot", siccome ho bisogno però della versione 4.4 uso questo link ("gnuplot44") per distinguerlo dal Gnuplot installato di default
    chomp $gnuplot;
    $self->_raise_error("\nE- [Leonidas] Gnuplot software not found\n\t")
        unless $gnuplot;
    
    # creo i boxplot in formato .png
    foreach my $datfile ($apo_file, $holo_file) {
        my $gplot_script = $self->get_workdir() . 'boxplot.gnu';
        my $content = $self->_gnuplot_boxplot($datfile);
        $self->set_filename($gplot_script);
        $self->set_filedata( [ $content ] );
        $self->write();
        my $gplot_log = qx/$gnuplot $gplot_script 2>&1/;
        $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
        # print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
        unlink $gplot_script;
    }
}

1;


=head1 SPARTA::lib::Leonidas

=head1 LEONIDAS: the bravest king of Sparta.
    
    Leonidas I ("son of the lion") was a hero-king of Sparta, who was believed 
    in mythology to be a descendant of Heracles, possessing much of the latter's 
    strength and bravery. He is notable for his leadership at the Battle of 
    Thermopylae.
    
    The methods of this class group generic feautres of the analysis mode of 
    SPARTA package.

=head1 METHODS

=head2 cluster($hashref)
    
        $self->cluster();
    
    Retrieve the structure clusters found for apo and holo forms, respectively. 
    It relies on the output data obtained from the GROMACS g_cluster command. 
    This method produce two kind of  output files in the current working path:
    
        clust.count.*   the number of clusters found for each system
        
        clust.num.*     sample size (percent over the total number of structure 
                        sampled) of each cluster of dataset, averaged on all 
                        the systems

=head2 hotspot_cluster($mode)
    
        my $arrayref = hotspot_cluster('ene');
    
    This method performs a cluster analysis among the structures of the datatset, 
    since an hotspot (IERPs or RMRPs) profile is defined for everyone. Given apo 
    and holo forms of a pdb, the profile is a string in which each hotspot is 
    classified as relevant in apo form, in holo form or in neither of them. See 
    hotspot_decomp for a definition of hotspot. This method produce the 
    following output files in the current working path:
        
        xxx_clust.dismat.csv    table of occurencies for each residue of every 
                                structure
        xxx_clust.R             R script to perform cluster analysis
        xxx_clust.log           results of cluster analysis
        xxx_clust.eps           dendrogram with clusters highlighted
    
=head2 hotspot_decomp($mode)
    
        my $hashref = hotspot_decomp('flu');
    
    This method retrieve a list of the most relevant residues whose contributes 
    may be relevant in the stabilization of the structures of the dataset. These 
    residues map on recurrent positions scattered along each domain of the 
    proteins; we define them as hotspot (aka IERPs or RMRPs, from energetic or 
    motional point of view). Three subset are highlighted in the graphics: 
    relevant hotspots in apo forms (yellow), in holo forms (red) or in both 
    (orange). This method produce two kinds of output files in the current 
    working path:
        
        xxx_dist.heavy.*    they are distributions of such relevant hotspots
        xxx_dist.light.*    shared by apo/holo forms. Data are splitted 
                            according to the heavy chain and light chain, 
                            respectivley;
        
        xxx_dist.pml        PyMol script for visual representation
    
=head2 hotspot_stats($pvalue, $mode)
    
        hotspot_stats(0.05, 'ene');
    
    Performs statistical analyses about the distribution of the hotspots over the 
    four domains of the Fab structures loaded in the dataset; this mode take an 
    optional argument in order to define the alfa-level of statistical tests.
    Two subset of hotspots are considered in such analyses of this method: those 
    hotspots which map toward the interface between the heavy and light chains 
    (marked yellow/cyan in holo/apo forms); the other ones internal of each 
    domain (marked red/blue in holo/apo forms). This method produce two kinds 
    of output files in the current working path:
        
        xxx_stats.apo.*     they are distributions of such relevant hotspots 
        xxx_stats.holo.*    shared by VH/VL/CH/CL domains. Data are splitted 
                            according to apo and holo forms, respectively;
        
        xxx_stats.ttest.dat Results of Student's T test for each pair of hotspots 
                            subset (e.g.: the ones internal at VH domain between 
                            apo and holo)
        
    
=head2 rmsd($hashref)
    
        $self->rmsd();
    
    Print a boxplot of RMSD profiles of the structure dataset, for apo and holo 
    forms respectively (see also rmsd_stats method). This method produce two 
    kinds of output files in the current working path:
    
        RMSD.apo.*      boxplot and related data for apo and holo forms, 
        RMSD.holo.*     respectively
    

=head2 rmsd_stats($string)
    
    my $hashref = $self->rmsd_stats("1NSN");
    
    Essential descriptive statistics on RMSD, given a MD simulation. This method 
    provides those descriptors to depict the spread and the skewness of data 
    (ie quartiles, lower (Q1-1.5*IQR) and upper (Q3+1.5*IQR) thresholds).
    It takes as input a PDB code, then queries the database and returns 
    statistics for both apo and holo form. It returns a table as an hash 
    reference, such this one:
    
    $VAR1 = {
                    ...lower...Q1......median..Q3......upper...
          'HOLO' => [ '0.25', '0.32', '0.35', '0.37', '0.44' ],
          'APO'  => [ '0.28', '0.32', '0.33', '0.35', '0.39' ]
        };

=head1 UPDATES

=head2 2012-feb-15

    * Alpha release

=cut
