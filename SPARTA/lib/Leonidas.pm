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
use SPARTA::lib::KS_test; # libreria x test di Kolmogorov-Smirnov
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

sub crossrefs {
    my ($self) = @_;
    
    my $query = <<END
SELECT refschema.ref, structure.pdb, structure.res, structure.resname, xres.source_chain, xres.source_res
FROM refschema
JOIN structure
ON structure.pdb = refschema.pdb
AND structure.res = refschema.res
JOIN xres
ON structure.pdb = xres.pdb
AND structure.chain = xres.chain
AND structure.res = xres.res
END
    ;
    my $dbh = $self->access2db();
    $self->set_query_string($query);
    my $sth = $self->query_exec('dbh' => $dbh);
    my %dbdata;
    while (my @row = $sth->fetchrow_array()) {
        my ($ref,$pdb,$res,$resname,$source_chain,$source_res) = @row;
        # rex è la stringa relativa al pdb
        my $rex = sprintf("%s.%s-%s", $source_chain, $source_res, $resname); # pdb originale
#         my $rex = sprintf("%03d-%s", $res, $resname); # pdb processato da me
        $dbdata{$ref} = { } unless (exists $dbdata{$ref});
        $dbdata{$ref}->{$pdb} = $rex;
    }
    $sth->finish();
    $dbh->disconnect;
    
    my $dataset = $self->get_dataset();
    my @pdblist = sort keys %{$dataset};
    
    my $content = [ sprintf("reference;%s\n", join(';',@pdblist)) ];
    foreach my $ref (sort keys %dbdata) {
        my $string = "$ref;";
        foreach my $pdb (@pdblist) {
            if (exists $dbdata{$ref}->{$pdb}) {
                $string .= $dbdata{$ref}->{$pdb} . ';';
            } else {
                $string .= 'null;';
            }
        }
        $string =~ s/;$/\n/;
        push(@{$content}, $string);
    }
    
    my $csv_filename = $self->get_workdir . '/CROSSREFS.csv';
    $self->set_filename($csv_filename);
    $self->set_filedata($content);
    $self->write();
    $self->_raise_warning("\nI- [Leonidas] [CROSSREFS.csv] written");
}

sub eneflu_correlation {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    $self->_raise_warning("\nI- [Leonidas] energy/fluctuations correlation...");
    
    $running = 0E0; $queued = 0E0;
    print "\n";
    foreach my $pdb (keys %{$dataset}) { #  ('1AFV')
        foreach my $form  ('APO', 'HOLO') {
            push @thr, threads->new(\&_correlation, $self, $pdb, $form);
        }
    }
    for (@thr) { $_->join() }; # aspetto che tutti i thread siano terminati
    
    @thr = ( );
}

sub hinge_flucts {
    my ($self) = @_;
    
    $self->_raise_warning("\nI- [Leonidas] bending angles analysis...");
    my $angles = { 'APO' => { }, 'HOLO' => { } };
    DB_ACCESS: { # recupero i dati dal database
        my $dbh = $self->access2db();
        my $sth = $self->query_exec('dbh' => $dbh, 'query' => "SELECT pdb, form, heavy, light FROM hinges");
        while (my @row = $sth->fetchrow_array) {
            my ($pdb,$form,$heavy,$light) = @row;
            $angles->{$form}->{$pdb} = { 'heavy' => [ ], 'light' => [ ] }
                unless (exists $angles->{$form}->{$pdb});
            push(@{$angles->{$form}->{$pdb}->{'heavy'}}, $heavy);
            push(@{$angles->{$form}->{$pdb}->{'light'}}, $light);
        }
        $sth->finish();
        $dbh->disconnect;
    }
    
    my $statistics = { };
    STATS: { # reperisco medie e deviazioni standard degli angoli misurati
        foreach my $form (keys %{$angles}) {
            foreach my $pdb (keys %{$angles->{$form}}) {
                foreach my $chain (keys %{$angles->{$form}->{$pdb}}) {
                    my $array = $angles->{$form}->{$pdb}->{$chain};
                    my $mean = Statistics::Basic::mean($array);
                    my $stddev = Statistics::Basic::stddev($array);
                    my $label = "$form\_$chain";
                    $statistics->{$pdb} = { }
                        unless (exists $statistics->{$pdb});
                    $statistics->{$pdb}->{$label} = [ ]
                        unless (exists $statistics->{$pdb}->{$label});
                    $statistics->{$pdb}->{$label}->[0] = sprintf("%.2f", $mean);
                    $statistics->{$pdb}->{$label}->[1] = sprintf("%.2f", $stddev);
                }
            }
        }
        my $content = [ # headers
            ";APO_heavy;;HOLO_heavy;;APO_light;;HOLO_light;\n",
            "PDB;mean;stddev;mean;stddev;mean;stddev;mean;stddev;\n"
        ];
        foreach my $pdb (sort keys %{$statistics}) {
            my $data = $statistics->{$pdb};
            my $newline = "$pdb";
            for my $feat ('APO_heavy', 'HOLO_heavy', 'APO_light', 'HOLO_light') {
                $newline .= sprintf(";%.2f;%.2f", $data->{$feat}->[0], $data->{$feat}->[1]);
            }
            $newline .= "\n";
            push(@{$content}, $newline);
        }
        my $filename = $self->get_workdir . '/' . "bender.values.csv";
        $self->set_filename($filename);
        $self->set_filedata($content);
        $self->write();
        $self->_raise_warning("\nI- [Leonidas] [bender.values.csv] written");
    }
    
    ANOVA: { # faccio una 2way-ANOVA per vedere se le variazioni negli angoli di bending sono significativamente diverse tra le catene light e heavy, tra le forme apo e holo; verifico inoltre se questi due fattori interagiscono tra loro
        
        my $Rbin = $self->_whichR(); # R command line
        # preparo il file di dati per R
        my $content = [ "PDB;APOheavy;HOLOheavy;APOlight;HOLOlight\n" ];
        foreach my $pdb (sort keys %{$statistics}) {
            my $data = $statistics->{$pdb};
            my $newline = "$pdb";
            for my $feat ('APO_heavy', 'HOLO_heavy', 'APO_light', 'HOLO_light') {
                $newline .= sprintf(";%.2f", $data->{$feat}->[1]);
            }
            $newline .= "\n";
            push(@{$content}, $newline);
        }
        $self->set_filename('Rdata.csv');
        $self->set_filedata($content);
        $self->write();
        
        my $samplesize = scalar keys %{$statistics};
        my $Rfile = $self->get_workdir . '/' . "bender.anova.log";
        my $boxplot = $self->get_workdir . '/' . "bender.boxplot.eps";
        my $scRipt = <<END
# importo la tabella delle stddev degli angoli di bending
bends <- read.csv2("Rdata.csv", header = TRUE, dec = ".", sep = ";", row.names = 1, stringsAsFactors = FALSE);

# Test per la normalità (p-value >= 0.05)
ks.test(bends\$APOheavy, pnorm, mean(bends\$APOheavy), sd(bends\$APOheavy)); # apo, heavy chain
ks.test(bends\$APOlight, pnorm, mean(bends\$APOlight), sd(bends\$APOlight)); # apo, light chain
ks.test(bends\$HOLOheavy, pnorm, mean(bends\$HOLOheavy), sd(bends\$HOLOheavy)); # holo, heavy chain
ks.test(bends\$HOLOlight, pnorm, mean(bends\$HOLOlight), sd(bends\$HOLOlight)); # holo, light chain

# Test di omoschedasticità (p-value >= 0.05, se il numero di osservazioni per gruppo è simile l'esito del test non è vincolante)
bartlett.test(as.list(bends))

r <- c(t(as.matrix(bends))); # metto tutti i dati in un unico vettore
f1 <- c("apo", "holo"); # definisco il primo livello fattoriale
f2 <- c("heavy", "light"); # definisco il secondo livello fattoriale
n <- $samplesize; # numero dei campioni
forms <- gl(2,1,n*4,factor(f1)); # fattorizzo r per il primo livello
chains <- gl(2,2,n*4,factor(f2)); # fattorizzo r per il secondo livello

# correzione di Welch per ANOVA parametrica eteroschedastica (p-value <= 0.05, ci sono differenze significative tra i gruppi)
oneway.test(r ~ forms * chains, data=bends, var.equal=F);

av <- aov(r ~ forms * chains); # Two-way ANOVA
# il riepilogo seguente mi dice se sono significativamente diverse le distribuzioni
# per il primo (forms) o per il secondo fattore (chains): v. ultima colonna, p-value < 0.05.
# la terza riga (forms:chains) mi dice se c'è una possibile interazione tra i due fattori
summary(av);

# boxplot: la sovrapposizione dei notch (restringimenti) rappresenta graficamente se due distribuzioni sono significativamente diverse
postscript("$boxplot");
boxplot(bends, outline = FALSE, horizontal = FALSE, notch = TRUE, ylab = "bending amplitude (degrees)", ylim = c(0, max(r)), las = 1)
dev.off();
END
        ;
        $self->set_filename('scRipt.R');
        $self->set_filedata([ $scRipt ]);
        $self->write();
        my $Rlog = qx/$Rbin scRipt.R 2>&1/;
        $self->_raise_warning("\nI- [Leonidas] [bender.boxplot.eps] written");
        
        # devo scrivere il log di R su file perchè non riesco a parsare direttamente $Rlog
        $self->set_filename('R.log');
        $self->set_filedata([ $Rlog ]);
        $self->write();
        
        my $Rout = $self->read('R.log');
        $content = [ "*** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***\n\n" ];
        while (my $newline = shift @{$Rout}) {
            chomp $newline;
            if ($newline =~ /^data:  bends\$/) {
                $newline =~ s/^data:  bends\$/KS test on /;
                push(@{$content}, "$newline\t");
                $newline = shift @{$Rout};
                push(@{$content}, "$newline");
            } elsif ($newline =~ /^Bartlett's K-squared/) {
                push(@{$content}, "\nTest of homogeneity of variances\n$newline\n");
            } elsif ($newline =~ /^data:  r and forms \* chains/) {
                push(@{$content}, "\nWelch correction for heteroschedasticity\n");
                $newline = shift @{$Rout};
                push(@{$content}, "$newline\n\n");
            } elsif ($newline =~ /> summary\(av\);/) {
                push(@{$content}, "Two-way ANOVA\n");
                for (1..7) {
                    $newline = shift @{$Rout};
                    push(@{$content}, "$newline");
                } 
            }
        }
        $self->set_filename($Rfile);
        $self->set_filedata($content);
        $self->write();
        $self->_raise_warning("\nI- [Leonidas] [bender.anova.log] written");
        unlink('scRipt.R', 'Rdata.csv', 'R.log');
    }
}

sub hotspots {
# questa sub produce un file .csv delle componenti dell'autovettore combinato di ogni sistema apo/holo di ogni struttura
    my ($self, $mode) = @_;
    my $dataset = $self->get_dataset();
    my $dbh = $self->access2db();
    my ($xdecomp, $xdist, $csv_file);
    if ($mode eq 'flu') {
        $xdecomp = 'fludecomp';
        $xdist = 'fludist';
        $csv_file = 'flu_eigens.csv';
    } elsif ($mode eq 'ene') {
        $xdecomp = 'enedecomp';
        $xdist = 'enedist';
        $csv_file = 'ene_eigens.csv';
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

sub hotspot_cluster {
    my ($self, $mode) = @_;
    my $dataset = $self->get_dataset();
    my $dbh = $self->access2db();
    
    my ($db_table, $dismat);
    if ($mode eq 'flu') {
        $db_table = 'fludecomp';
        $dismat = 'flu_distmat.csv';
    } elsif ($mode eq 'ene') {
        $db_table = 'enedecomp';
        $dismat = 'ene_distmat.csv';
    } else {
        $self->_raise_error("\nI- [Leonidas] unknown mode");
    }
    
    $self->_raise_warning("\nI- [Leonidas] creating distance matrix...");
    my %refs; # lista dei residui da selezionare
    MYSQL: {
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
    $self->_raise_warning("\nI- [Leonidas] [$dismat] written");
    
    $self->_raise_warning("\nI- [Leonidas] performing cluster analysis...");
    my $silhouette = $self->clust($occur, $mode);
    
    return $silhouette;
}

sub hotspot_stats {
    my ($self,$pvalue,$stat_test,$mode) = @_;
    my $dataset = $self->get_dataset();
    my $dbh = $self->access2db();
    
    my ($decomp_table, $ttest_dat);
    if ($mode eq 'flu') {
        $decomp_table = 'fludecomp';
    } elsif ($mode eq 'ene') {
        $decomp_table = 'enedecomp';
    } else {
        $self->_raise_error("\nI- [Leonidas] unknown mode");
    }
    
    $self->_raise_warning("\nI- [Leonidas] hotspot statistics...");
    
    # distribuzione di hotspots nei singoli PDB
    my $pdb_counts = {'APO' => { }, 'HOLO' => { } };
    foreach my $pdb (sort keys %{$dataset}) {
        $pdb_counts->{'APO'}->{$pdb} = { 'VH' => 0E0, 'VL' => 0E0, 'CH' => 0E0, 'CL' => 0E0 };
        $pdb_counts->{'HOLO'}->{$pdb} = { 'VH' => 0E0, 'VL' => 0E0, 'CH' => 0E0, 'CL' => 0E0 };
    }
    foreach my $cat ('APO', 'HOLO') {
        my $query = "SELECT pdb, ref, form FROM $decomp_table WHERE form IN ('$cat\', 'BOTH')";
        my $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
        while (my ($pdb, $ref, $form) = $sth->fetchrow_array) {
            my ($domain) = $ref =~ /(VH|VL|CH|CL)/;
            $pdb_counts->{$form}->{$pdb}->{$domain}++;
        }
    }
    
    $dbh->disconnect;
    
    # file csv
    foreach my $cat ('APO', 'HOLO') {
        my $csv_file = "$mode\_stats.$cat.csv";
        my $header = "PDB;VH;VL;CH;CL\n";
        my $content = [ $header ];
        foreach my $pdb (sort keys %{$pdb_counts->{$cat}}) {
            my ($VH,$VL,$CH,$CL) = ( $pdb_counts->{$cat}->{$pdb}->{'VH'}, $pdb_counts->{$cat}->{$pdb}->{'VL'}, $pdb_counts->{$cat}->{$pdb}->{'CH'}, $pdb_counts->{$cat}->{$pdb}->{'CL'} );
            my $string = "$pdb;$VH;$VL;$CH;$CL\n";
            push(@{$content}, $string);
        }
        $self->set_filename($self->get_workdir() . '/' . $csv_file);
        $self->set_filedata($content);
        $self->write();
        $self->_raise_warning("\nI- [Leonidas] [$csv_file] written");
    }
    
    if ($stat_test eq 'TT') {
        $self->_raise_warning("\nI- [Leonidas] performing Student T test...");
        # raccolgo il numero di residui, per ogni pdb, che mappano su un dominio; il primo elemento di ogni arrayref [[],[]] sono i residui per le forme apo, il secondo per le forme holo
        my $intra = { 'VH' => [[],[]], 'VL' => [[],[]], 'CH' => [[],[]], 'CL' => [[],[]]};
        my %index = ('APO' => 0, 'HOLO' => 1);
        foreach my $cat ('APO', 'HOLO') {
            my $csv_file = "$mode\_stats.$cat.csv";
            my $content = $self->read($csv_file);
            shift @{$content};
            while (my $row = shift @{$content}) {
                chomp $row;
                my @fields = split(';', $row);
                push(@{$intra->{'VH'}->[$index{$cat}]}, $fields[1]);
                push(@{$intra->{'VL'}->[$index{$cat}]}, $fields[2]);
                push(@{$intra->{'CH'}->[$index{$cat}]}, $fields[3]);
                push(@{$intra->{'CL'}->[$index{$cat}]}, $fields[4]);
            }
        }
        my $content = [ ];
        $content = [ "APO_vs_HOLO\tH0_(P-value < $pvalue)\n" ];
        $pvalue = int((1-$pvalue)*100); # alfa level per i test statistici
        my $ksquare; # pvalue per stabilire se una distribuzione è normale (requisito per il test T)
        # definisco le coppie di distribuzioni su cui fare il test T di Student
        my $pairs = {
            'VH' => [ $intra->{'VH'}->[0], $intra->{'VH'}->[1] ],
            'VL' => [ $intra->{'VL'}->[0], $intra->{'VL'}->[1] ],
            'CH' => [ $intra->{'CH'}->[0], $intra->{'CH'}->[1] ],
            'CL' => [ $intra->{'CL'}->[0], $intra->{'CL'}->[1] ]
        };
        foreach my $key ('VH','VL','CH','CL') {
            my ($apo, $holo) = @{$pairs->{$key}};
            # test di goodness of fit (K-squared test)
            my $pval = (100 - $pvalue)/100;
            $ksquare = Statistics::Normality::dagostino_k_square_test( $apo );
            if ($ksquare <= $pval) {
                printf("\n  %s(apo) distribution could not be normal (%.1e/%.1e), maybe try KS test?!", $key, $ksquare, $pval) 
            };
            $ksquare = Statistics::Normality::dagostino_k_square_test( $holo );
            if ($ksquare <= $pval) {
                printf("\n  %s(holo) distribution could not be normal (%.1e/%.1e), maybe try KS test?!", $key, $ksquare, $pval) 
            };
            my $ttest = Statistics::TTest->new();
            $ttest->set_significance($pvalue);
            $ttest->load_data($apo,$holo);
            # test T di Student (H0 = "i due campioni hanno la stessa media")
            my $verdict = $ttest->null_hypothesis();
            my $string = "$key\t\t$verdict\n";
            push(@{$content}, $string);
        }
        my $filename = $self->get_workdir . '/' . "$mode\_Ttest.dat";
        $self->set_filename($filename);
        $self->set_filedata($content);
        $self->write();
        $self->_raise_warning("\nI- [Leonidas] [$mode\_Ttest.dat] written");
    } elsif ($stat_test eq 'KS') {
        $self->_raise_warning("\nI- [Leonidas] performing Kolmogorov-Smirnov test...");
        # raccolgo il numero di residui, per ogni pdb, che mappano su un dominio; il primo elemento di ogni arrayref [[],[]] sono i residui per le forme apo, il secondo per le forme holo
        my $intra = { 'VH' => [[],[]], 'VL' => [[],[]], 'CH' => [[],[]], 'CL' => [[],[]]};
        my %index = ('APO' => 0, 'HOLO' => 1);
        foreach my $cat ('APO', 'HOLO') {
            my $csv_file = "$mode\_stats.$cat.csv";
            my $content = $self->read($csv_file);
            shift @{$content};
            while (my $row = shift @{$content}) {
                chomp $row;
                my @fields = split(';', $row);
                push(@{$intra->{'VH'}->[$index{$cat}]}, $fields[1]);
                push(@{$intra->{'VL'}->[$index{$cat}]}, $fields[2]);
                push(@{$intra->{'CH'}->[$index{$cat}]}, $fields[3]);
                push(@{$intra->{'CL'}->[$index{$cat}]}, $fields[4]);
            }
        }
        my $content = [ ];
        $content = [ "APO_vs_HOLO\tH0_(P-value < $pvalue)\n" ];
        # definisco le coppie di distribuzioni su cui fare il test di Kolmogorov-Smirnov
        my $pairs = {
            'VH' => [ $intra->{'VH'}->[0], $intra->{'VH'}->[1] ],
            'VL' => [ $intra->{'VL'}->[0], $intra->{'VL'}->[1] ],
            'CH' => [ $intra->{'CH'}->[0], $intra->{'CH'}->[1] ],
            'CL' => [ $intra->{'CL'}->[0], $intra->{'CL'}->[1] ]
        };
        foreach my $key ('VH','VL','CH','CL') {
            my ($apo, $holo) = @{$pairs->{$key}};
            my $obj = SPARTA::lib::KS_test->new();
            my $result = $obj->test('distref' => $apo,'distobs' => $holo,'alfa' => $pvalue);
            if ($result == 1) {
                push(@{$content}, "$key\t\tnot rejected\n");
            } else {
                push(@{$content}, "$key\t\trejected\n");
            }
        }
        my $filename = $self->get_workdir . '/' . "$mode\_KStest.dat";
        $self->set_filename($filename);
        $self->set_filedata($content);
        $self->write();
        $self->_raise_warning("\nI- [Leonidas] [$mode\_KStest.dat] written");
    } else {
        $self->_raise_warning("\nW- [Leonidas] unknown statistics test...");
    }
    
    # verifico che gnuplot sia installato
    my $gnuplot = qx/which gnuplot44  2> \/dev\/null/; # in realtà il comando è "gnuplot", siccome ho bisogno della versione 4.4 uso questo link ("gnuplot44") per distinguerlo dal Gnuplot installato di default
    chomp $gnuplot;
    $self->_raise_error("\nE- [Leonidas] Gnuplot software not found\n\t")
        unless $gnuplot;
    
    # istogrammi per gnuplot
    my %colors = ('APO' => 'blue', 'HOLO' => 'red');
    foreach my $cat ('APO', 'HOLO') {
        my $gnu_file = 'histogram.gnu';
        my $csv_file = "$mode\_stats.$cat.csv";
        my $dat_file = "ordine.dat";
        my $png_file = "$mode\_stats.$cat.png";
        REORDER: {
            my $content = $self->read($csv_file);
            my $header = shift @{$content};
            $header =~ s/;/  /g;
            my $domains = { 'VH' => { }, 'VL' => { }, 'CH' => { }, 'CL' => { } };
            while (my $row = shift @{$content}) {
                my ($key, $value);
                chomp $row;
                my @fields = split(';', $row);
                $key = sprintf("%05d_%s", $fields[1], $fields[0]);
                $value = "$fields[1]";
                $domains->{'VH'}->{$key} = $value;
                $key = sprintf("%05d_%s", $fields[2], $fields[0]);
                $value = "$fields[2]";
                $domains->{'VL'}->{$key} = $value;
                $key = sprintf("%05d_%s", $fields[3], $fields[0]);
                $value = "$fields[3]";
                $domains->{'CH'}->{$key} = $value;
                $key = sprintf("%05d_%s", $fields[4], $fields[0]);
                $value = "$fields[4]";
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
set output "$png_file"
set title "$cat FORMS"
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
        '$dat_file\' using 2:xtic(1) t column(2) lt rgb "$colors{$cat}", \\
    newhistogram "VL domain", \\
        '' using 3:xtic(1) t column(3) lt rgb "$colors{$cat}", \\
    newhistogram "CH domain", \\
        '' using 4:xtic(1) t column(4) lt rgb "$colors{$cat}", \\
    newhistogram "CL domain", \\
        '' using 5:xtic(1) t column(5) lt rgb "$colors{$cat}"
unset output
quit
END
        ;
        $self->set_filename($gnu_file);
        $self->set_filedata([ $gnuscript ]);
        $self->write();
        my $gplot_log = qx/$gnuplot $gnu_file 2>&1/;
        $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
#         print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
        unlink $gnu_file;
        unlink $dat_file;
        $self->_raise_warning("\nI- [Leonidas] [$png_file] written");
    }
}

sub rankproducts {
# Two-sample rank products [Koziol, FEBS letters, 2010, 584: 4481-4484]
    
    my $timer = time();
    
    my ($self, $mode, $random_permutations) = @_;
    $random_permutations = 100 unless ($random_permutations);
    
    my ($infile, $outfile);
    if ($mode eq 'flu') {
        $infile = 'flu_eigens.csv';
        $outfile = 'flu_rankprod.csv';
    } elsif ($mode eq 'ene') {
        $infile = 'ene_eigens.csv';
        $outfile = 'ene_rankprod.csv';
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
    push(@{$content}, "PROBE;LOG(RP);RANKapo;EVALapo;FDRapo;RANKholo;EVALholo;FDRholo\n");
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

sub rp_dist {
# versione rivista di hotspot_decomp
    my ($self, $mode, $evalue) = @_;
    
    my ($decomp_table, $infile);
    if ($mode eq 'flu') {
        $decomp_table = 'fludecomp';
        $infile = 'flu_rankprod.csv';
    } elsif ($mode eq 'ene') {
        $decomp_table = 'enedecomp';
        $infile = 'ene_rankprod.csv';
    } else {
        $self->_raise_error("\nI- [Leonidas] unknown mode");
    }
    
    $self->_raise_warning("\nI- [Leonidas] hotspots distribution...");
    
    # faccio un parsing del file di output dal rankproducts
    my $hotspots = { };
    my $filename = $self->get_workdir(). '/' . $infile;
    $self->set_filename($filename);
    my $content = $self->read();
    my $csv_file = "$mode\_hotspots.csv";
    my $csv_content = [ ];
    shift @{$content}; # rimuovo l'header
    while (my $row = shift(@{$content})) {
        chomp $row;
        my @data = split(';', $row);
        my ($ref, $rp, $eapo, $eholo) = ($data[0], $data[1], $data[3], $data[6]);
        $hotspots->{$ref} = { };
        $hotspots->{$ref}->{'major'} = 'null';
        $hotspots->{$ref}->{'occurs'} = [ '0.000', '0.000', '0.000' ];
        # scarto gli hotspots che presentano un E-value maggiore di $evalue
        next if ($eapo > $evalue && $eholo > $evalue);
        # classifico gli hotspots in base al loro punteggio RP
        if ($rp >= 0.1) {
            $hotspots->{$ref}->{'major'} = 'HOLO';
            push(@{$csv_content}, "$ref;HOLO\n");
        } elsif ($rp <= -0.1) {
            $hotspots->{$ref}->{'major'} = 'APO';
            push(@{$csv_content}, "$ref;APO\n");
        } elsif ($rp >= -0.05 && $rp <= 0.05) {
            $hotspots->{$ref}->{'major'} = 'BOTH';
            push(@{$csv_content}, "$ref;BOTH\n");
        }
    }
    $self->set_filename($self->get_workdir(). '/' . $csv_file);
    $self->set_filedata($csv_content);
    $self->write();
    $self->_raise_warning("\nI- [Leonidas] [$csv_file] written...");
    
    my $dataset = $self->get_dataset();
    my $totpdb = scalar keys %{$dataset}; # numero di PDB del dataset
    my $dbh = $self->access2db();
    my ($query, $sth);
    for my $cat ('APO', 'HOLO', 'BOTH') {
        $query = "SELECT ref, count(*) FROM $decomp_table WHERE form LIKE '$cat' GROUP BY ref";
        $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
        my %index = ('APO' => 0, 'HOLO' => 1, 'BOTH' => 2);
        while (my ($ref,$count) = $sth->fetchrow_array()) {
            if (exists $hotspots->{$ref}) {
                $count = sprintf("%.3f", $count/$totpdb);
                $hotspots->{$ref}->{'occurs'}->[$index{$cat}] = $count;
            }
        }
    }
    $sth->finish();
    $dbh->disconnect;
    
    # statistiche su quanto sono simili le distribuzioni di hotspots tra apo e holo
    my %dist_apo = ( 'VH' => [ ], 'VL' => [ ], 'CH' => [ ], 'CL' => [ ] );
    my %dist_olo = ( 'VH' => [ ], 'VL' => [ ], 'CH' => [ ], 'CL' => [ ] );
    foreach my $ref (sort keys %{$hotspots}) {
        my ($dom) = $ref =~ /^(\w{2})/;
        push(@{$dist_apo{$dom}}, $hotspots->{$ref}->{'occurs'}[0] + $hotspots->{$ref}->{'occurs'}[1]);
        push(@{$dist_olo{$dom}}, $hotspots->{$ref}->{'occurs'}[1] + $hotspots->{$ref}->{'occurs'}[2]);
    }
    $self->_raise_warning("\nI- [Leonidas] performing Kolmogorov-Smirnov test...");
    $content = [ "APO_vs_HOLO\tH0_(P-value < $evalue)\n" ];
    foreach my $key ('VH','VL','CH','CL') {
        my ($apo, $holo) = ($dist_apo{$key}, $dist_olo{$key});
        my $obj = SPARTA::lib::KS_test->new();
        my $result = $obj->test('distref' => $apo,'distobs' => $holo,'alfa' => $evalue);
        if ($result == 1) {
            push(@{$content}, "$key\t\tnot rejected\n");
        } else {
            push(@{$content}, "$key\t\trejected\n");
        }
    }
    $filename = $self->get_workdir . '/' . "$mode\_KStest.dat";
    $self->set_filename($filename);
    $self->set_filedata($content);
    $self->write();
    $self->_raise_warning("\nI- [Leonidas] [$mode\_KStest.dat] written");
    
    # stacked histogram per mostrare la distribuzione degli hotspots
    # verifico che gnuplot sia installato
    my $gnuplot = qx/which gnuplot44  2> \/dev\/null/; # in realtà il comando è "gnuplot", siccome ho bisogno della versione 4.4 uso questo link ("gnuplot44") per distinguerlo dal Gnuplot installato di default
    chomp $gnuplot;
    $self->_raise_error("\nE- [Leonidas] Gnuplot software not found\n\t") unless $gnuplot;
    foreach my $dom ('VH', 'VL', 'CH', 'CL') {
        my $dat_file = "$mode\_dist.$dom.dat";
        my $dat_content = [ ];
        my $header = "RESIDUE  APO  BOTH  HOLO\n";
        push(@{$dat_content}, $header);
        foreach my $ref (sort keys %{$hotspots}) {
            next if ($ref !~ /^$dom/);
            my $values = join('  ', @{$hotspots->{$ref}->{'occurs'}});
            push(@{$dat_content}, sprintf("%s  %s\n", $ref, $values));
        }
        $self->set_filename($self->get_workdir() . '/' . $dat_file);
        $self->set_filedata($dat_content);
        $self->write();
        $self->_raise_warning("\nI- [Leonidas] [$dat_file] written...");
        
        my $png_file = $dat_file;
        $png_file =~ s/dat$/png/;
        my $gnu_file = $self->get_workdir() . '/plot.gnu';
        my $gnuscript = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw the ditribution of the most relevant residues according to decomposition analysis
# 
set terminal png size 1800, 800
set size ratio 0.25
set output "$png_file"
set key under nobox
set yrange [0:1]
set ylabel "% of total"
set ytics
set xtics rotate
set grid y
set border 3
set style data histograms
set style histogram rowstacked
set style fill solid border -1
set boxwidth 0.75
plot '$dat_file' using 4:xtic(1) t column(4) lt rgb "red", \\
        '' using 3 t column(3) lt rgb "orange", \\
        '' using 2 t column(2) lt rgb "yellow"
END
        ;
        $self->set_filename($gnu_file);
        $self->set_filedata([ $gnuscript ]);
        $self->write();
        # creo il file .png
        my $gplot_log = qx/$gnuplot  $gnu_file 2>&1/;
            $gplot_log =~ s/^\s//g; $gplot_log =~ s/\n*$//g;
#         print "\n\t[GNUPLOT] $gplot_log"; # eventuali messaggi da gnuplot
        unlink $gnu_file;
    }
    
    # rappresentazione per PyMol
    my $filelist = { }; # lista dei file pdb che mi serviranno
    foreach my $pdbID (keys %{$dataset}) {
        $filelist->{$pdbID} = $dataset->{$pdbID}->{'PDB'};
    }
    $self->set_pdblist($filelist); # pdblist è un attributo della classe Theodorus che eredito
    my $refined = { 'APO' => { }, 'HOLO' => { }, 'BOTH' => { } }; # liste di residui coinvolti per ogni pdb
    $dbh = $self->access2db();
    foreach my $cat (keys %{$refined}) {
        my @refs;
        foreach my $ref (keys %{$hotspots}) {
            my $match = $hotspots->{$ref}->{'major'};
            next unless ($cat eq $match);
            push(@refs, $ref);
        }
        my $string = q/'/ . join(q/', '/, @refs) . q/'/;
        $query = "SELECT pdb, res FROM $decomp_table WHERE ref IN ($string) AND form LIKE \'$cat\'";
        $sth = $self->query_exec('dbh' => $dbh, 'query' => $query);
        while (my ($pdb,$res) = $sth->fetchrow_array) {
            $refined->{$cat}->{$pdb} = [ ]
                unless (exists $refined->{$cat}->{$pdb});
            push(@{$refined->{$cat}->{$pdb}}, $res);
        }
    }
    $sth->finish();
    $dbh->disconnect;
    $content = $self->pml_hotspot($refined);
    my $pml_file = "$mode\_hotspots.pml";
    $self->set_filename($self->get_workdir() . '/' . $pml_file);
    $self->set_filedata($content);
    $self->write();
    $self->_raise_warning("\nI- [Leonidas] [$pml_file] written...");
}

sub samba {
    my ($self) = @_;
    my $dataset = $self->get_dataset();
    
    # verifico che gnuplot sia installato
    my $gnuplot = qx/which gnuplot44  2> \/dev\/null/; # in realtà il comando è "gnuplot", siccome ho bisogno della versione 4.4 uso questo link ("gnuplot44") per distinguerlo dal Gnuplot installato di default
    chomp $gnuplot;
    $self->_raise_error("\nE- [Leonidas] Gnuplot software not found\n\t") unless $gnuplot;
    
    $self->_raise_warning("\nI- [Leonidas] distance fluctuation analysis");
    my $flucts = $self->fluctvalues(); # recupero i valori di distance fluctuations
    
    my $pairs; # recupero le coppie di residui per cui voglio calcolare la distanza (Ca-Ca)
    foreach my $form (keys %{$flucts}) {
        foreach my $pdb (keys %{$flucts->{$form}}) {
            $pairs->{$pdb} = { }
                unless (exists $pairs->{$pdb});
            foreach my $other (keys %{$flucts->{$form}->{$pdb}->{'others'}}) {
                my $paratope = $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'paratope'};
                my $pair = "$paratope;$other";
                $pairs->{$pdb}->{$pair} = 1
                    unless (exists $pairs->{$pdb}->{$pair});
            }
        }
    }
    
    my $distmatrix = $self->cadistances($pairs); # calcolo le distanze
    foreach my $form (keys %{$flucts}) {
        foreach my $pdb (keys %{$flucts->{$form}}) {
            foreach my $other (keys %{$flucts->{$form}->{$pdb}->{'others'}}) {
                my $paratope = $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'paratope'};
                my $dist = $distmatrix->{$pdb}->[$paratope][$other];
                $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'distance'} = $dist;
#                 # trasformo i miei valori di distance restrint in valori di distance fluctuation
#                 my $fluct = $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'fluct'};
#                 $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'fluct'} = (1/($fluct/$dist))**2;
            }
        }
    }
    
    # suddivido i residui in categorie in base ai valori di distance fluctuation
    my $flucat = $self->flucategories($flucts);
    
    # rappresentazione per PyMol
    my $filelist = { }; # lista dei file pdb che mi serviranno
    foreach my $pdbID (keys %{$dataset}) {
        $filelist->{$pdbID} = $dataset->{$pdbID}->{'PDB'};
    }
    $self->set_pdblist($filelist); # pdblist è un attributo della classe Theodorus che eredito
    foreach my $form (keys %{$flucat}) {
        my $data = $flucat->{$form};
        my $content = $self->pml_flucts($data);
        my $pml_file = "samba.$form.pml";
        $self->set_filename($self->get_workdir() . '/' . $pml_file);
        $self->set_filedata($content);
        $self->write();
        $self->_raise_warning("\nI- [Leonidas] [$pml_file] written...");
    }
    
#     print "\nBREAK";return; # RIGA DI TESTING
    
    # preparo i csv files
    foreach my $form (keys %{$flucts}) {
        my $filename = $self->get_workdir . "/samba.$form.csv";
        my $content = [ "PDB;PARATOPE;POSITION;RESIDUE;DISTANCE;FLUCTUATION\n" ];
        foreach my $pdb (keys %{$flucts->{$form}}) {
            foreach my $other (keys %{$flucts->{$form}->{$pdb}->{'others'}}) {
                my $paratope = $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'paratope'};
                my $residue = $other;
                my $distance = sprintf("%.3f", $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'distance'});
                my $fluctuation = sprintf("%.3f", $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'fluct'});
                my $position = $flucts->{$form}->{$pdb}->{'others'}->{$other}->{'position'};
                my $string = "$pdb;$paratope;$position;$residue;$distance;$fluctuation\n";
                push(@{$content}, $string);
            }
        }
        $self->set_filename($filename);
        $self->set_filedata($content);
        $self->write();
        $self->_raise_warning("\nI- [Leonidas] [samba.$form.csv] written");
    }
    
    # preparo gli scatterplot
    my $dat_filename = $self->get_workdir . '/samba.dat';
    my $gnu_filename = $self->get_workdir . '/samba.gnu';
    foreach my $form (keys %{$flucts}) {
        my $png_filename = $self->get_workdir . "/samba.$form.png";
        my $csv_filename = $self->get_workdir . "/samba.$form.csv";
        $self->set_filename($csv_filename);
        my $data = $self->read();
        shift @{$data}; # rimuovo l'header
        my $content = [ "CHdist  CHflu  VHdist VHflu  CLdist  CLflu  VLdist  VLflu\n" ];
        while (my $row = shift @{$data}) {
            chomp $row;
            my @array = split(';',$row );
            my ($pos,$dist,$flu) = ($array[2],$array[4],$array[5]);
            my $string;
            $pos =~ m/CH/ and do { $string = "$dist  $flu  -1  -1  -1  -1  -1  -1\n" };
            $pos =~ m/VH/ and do { $string = "-1  -1  $dist  $flu  -1  -1  -1  -1\n" };
            $pos =~ m/CL/ and do { $string = "-1  -1  -1  -1  $dist  $flu  -1  -1\n" };
            $pos =~ m/VL/ and do { $string = "-1  -1  -1  -1  -1  -1  $dist  $flu\n" };
            push(@{$content}, $string);
        }
        $self->set_filename($dat_filename);
        $self->set_filedata($content);
        $self->write();
        my $gnuscript = <<END
# 
# *** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***
#
# Gnuplot script to draw scatterplot distance fluctuation
# 
set title "$form form"
set size ratio 0.55
set terminal png size 1280, 800
set output "$png_filename"
set xlabel "distance (A)"
set xrange [0:80]
set xtics 10
set mxtics 9
show mxtics
set ylabel "LOG(Dij)"
set logscale y
set yrange [10:100]
plot '$dat_filename' using 1:2 with points pointtype 3 pointsize 0.5 lc rgb "blue" title "CH1", \\
        '' using 3:4 with points pointtype 3 pointsize 0.5 lc rgb "cyan" title "VH", \\
        '' using 5:6 with points pointtype 3 pointsize 0.5 lc rgb "red" title "CL", \\
        '' using 7:8 with points pointtype 3 pointsize 0.5 lc rgb "orange" title "VL"
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
            unlink $dat_filename;
            $self->_raise_warning("\nI- [Leonidas] [samba.$form.png] written");
    }
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

sub _correlation {
    my ($self, $pdb, $form) = @_;
    
    unless (${$semaforo}) { # accodo il job se tutti gli slot (v. $thread_num) sono occupati
        lock $queued; $queued = $queued + 1;
        $self->_thread_monitor();
    }
    $semaforo->down(); # occupo uno slot
    { lock $running; $running = $running + 1; }
    $self->_thread_monitor();
    
#     $self->_raise_warning("\nI- [Leonidas] JOB [$pdb\_$form] started...");
    my $data = { };
    DB_ACCESS: { # recupero i dati dal database
        my $dbh = $self->access2db();
# i dati che reperisco in questo modo permettono di confrontare direttamente i 
# punti delle matrici energetiche e dinamiche. Ho visto che cosi facendo i dati
# sono debolmente correlati. Per energie molto negative o molto positive la 
# coordinazione delle fluttuazioni tende ad aumentare o a diminuire, 
# rispettivamente; d'altra parte, per energie di interazione prossime a zero i
# valori di fluttuazione sono completamente casuali.
 
        my $sth = $self->query_exec('dbh' => $dbh, 'query' => "SELECT resA, resB, ene FROM enematrix WHERE pdb = '$pdb' AND form = '$form'");
        while (my @row = $sth->fetchrow_array) {
            my ($resA,$resB,$value) = @row;
            my $ID = sprintf("%d;%d", $resA,$resB);
            $value = sprintf("%.3e", $value);
            $data->{$ID} = [ ];
            push(@{$data->{$ID}},$value);
        }
        $sth->finish();
        $sth = $self->query_exec('dbh' => $dbh, 'query' => "SELECT resA, resB, fluct FROM flumatrix WHERE pdb = '$pdb' AND form = '$form'");
        while (my @row = $sth->fetchrow_array) {
            my ($resA,$resB,$value) = @row;
            my $ID = sprintf("%d;%d", $resA,$resB);
            $value = sprintf("%.3e", $value);
            push(@{$data->{$ID}},$value);
        }
        
        $sth->finish();
        $dbh->disconnect;
    }
    
    my $csv_file = "$pdb\_$form.csv";
    my $filename = $self->get_workdir(). '/' . $csv_file;
    CSVFILE: { # scrivo la tabella dei valori ene/flu
        my $content = [ "ENE;FLU\n" ];
        foreach my $ID (keys %{$data}) {
            my $newline = "$data->{$ID}->[0];$data->{$ID}->[1]\n";
            push(@{$content}, $newline);
        }
        $self->set_filename($filename);
        $self->set_filedata($content);
        $self->write();
    }
    
    CORRELAZ: {
        my $Rbin = $self->_whichR(); # R command line
        my $Rfile = $self->get_workdir . '/' . "$pdb\_$form.log";
        my $scatterplot = $self->get_workdir . '/' . "$pdb\_$form.png";
        my $scRipt = <<END
# importo la tabella delle stddev degli angoli di bending
rawdata <- read.csv2("$csv_file", header = TRUE, dec = ".", sep = ";", stringsAsFactors = FALSE);

png("$scatterplot");

# disegno lo scatterplot dei punti
plot(rawdata\$ENE,rawdata\$FLU, xlab = "non-bonded interaction energy", ylab = "distance fluctuation", pch=20);

# regressione lineare delle energie in funzione delle fluttuazioni
regr<-lm(rawdata\$FLU~rawdata\$ENE);
# disegno la retta di regressione
abline(regr, lty=2);

# informazioni sulla regressione 
summary(regr);

dev.off();
END
        ;
        $self->set_filename("$pdb\_$form.scRipt.R");
        $self->set_filedata([ $scRipt ]);
        $self->write();
        my $Rlog = qx/$Rbin $pdb\_$form.scRipt.R 2>&1/;
        
        # devo scrivere il log di R su file perchè non riesco a parsare direttamente $Rlog
        $self->set_filename("$Rfile.raw");
        $self->set_filedata([ $Rlog ]);
        $self->write();
        
        my $Rout = $self->read("$Rfile.raw");
        my $content = [ "*** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***\n\n" ];
        my $OK = 0;
        while (my $newline = shift @{$Rout}) {
            chomp $newline;
            if ($newline =~ /> summary\(regr\);/) {
                $OK = 1;
            } elsif ($OK) {
                push(@{$content}, "$newline\n");
            } else {
                next;
            }
        }
        $self->set_filename($Rfile);
        $self->set_filedata($content);
        $self->write();
        unlink("$pdb\_$form.scRipt.R", "$Rfile.raw");
    }
    
#     $self->_raise_warning("\nI- [Leonidas] JOB [$pdb\_$form] finished");
    
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
    $self->_raise_error("\nE- [Leonidas] R software not found\n\t")
        unless $Rbin;
    $Rbin .= ' --vanilla <'; # opzione per farlo girare in batch
    return $Rbin;
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

=head2 hinge_flucts()
    
        hinge_flucts();
    
    This method performs statistics of the angles (means) and their variations 
    (stddev) along the hinge regions of the chains of every system (apo/holo 
    structures). Moreover, a two-way ANOVA will be carried out in order to find 
    if the bending variations are significant between light/heavy chains and/or 
    apo/holo forms. This method produce the following output files in the 
    current working path:
        
        bender.values.csv   table of average angles among the trajectories
        bender.anova.log    results of two-way ANOVA
        bender.boxplo.eps   boxplot, overlaps between notches give a visual idea
                            if distributions are significantly different

=head2 hotspots($mode)
    
        my $outfile = hotspots('ene')
    
    For each structure of the dataset the method collects the components - from 
    the most representative eigenvectors - for those residues which are mapped 
    as hotspots. This method produce  a .csv table  in the current working path 
    (xxx_eigens.csv).
    

=head2 hotspot_cluster($mode)
    
        my $arrayref = hotspot_cluster('ene');
    
    This method performs a cluster analysis among the structures of the datatset, 
    since an hotspot (IERPs or RMRPs) profile is defined for everyone. Given apo 
    and holo forms of a pdb, the profile is a string in which each hotspot is 
    classified as relevant in apo form, in holo form or in neither of them. See 
    hotspot_decomp for a definition of hotspot. This method produce the 
    following output files in the current working path:
        
        xxx_distmat.csv     table of occurencies for each residue of every 
                            structure
        xxx_clust.log       results of cluster analysis
        xxx_clust.eps       dendrogram with clusters highlighted

=head2 hotspot_stats($pvalue, $test, $mode)
    
        hotspot_stats(0.05, 'KS', 'ene');
    
    Performs statistical analyses about the distribution of the hotspots over the 
    four domains of the Fab structures loaded in the dataset; this mode take two 
    arguments in order to define the alfa-level and te statistical tests (KS = 
    Kolmogorov-Smirnov; TT = Student T test).
    This method produce the following output files in the current working path:
        
        xxx_stats.APO.*     they are distributions of such relevant hotspots 
        xxx_stats.HOLO.*    shared by VH/VL/CH/CL domains. Data are splitted 
                            according to apo and holo forms, respectively;
        
        xxx_KStest.dat      Results of statistics test for each pair of hotspots 
                            subset (ie the ones belonging to VH/VL/CH/CL domains 
                            between apo and holo forms, respectively)
    

=head2 rankproducts($mode, [$perms])
    
        my $outfile = hotspot_cluster('ene', 1000);
    
    This method relies on input file produced from Leonidas::hotspots. The two 
    sample rank products is then performed in order to find out those hotspots 
    that may be more relevant in apo forms, in holo forms or both. In order to 
    get a significance level on RP values multiple testing will be performed 
    ($perms define the number of permutations). This method produce a .csv 
    output file termed ene_rankprod.csv.
    
    DEFAULTS:
        $perms = 100; 

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

=head2 rp_dist($mode, $eval)
    
        my $hashref = hotspot_decomp('flu', 0.05);
    
    This method relies on input file produced from Leonidas::rankproducts. This 
    method retrieve a list of the most relevant residues whose contributes 
    may be relevant in the stabilization of the structures of the dataset. These 
    residues map on recurrent positions scattered along each domain of the 
    proteins; we define them as hotspot (aka IERPs or RMRPs, from energetic or 
    motional point of view). The hotspots that may be more relevant in apo/holo 
    forms are collected according to RP values given from the 
    Leonidas::rankproducts output. Nevertheless, if the RP score is associated 
    with an E-value higher than $eval, then the hotspot is not considered as 
    relevant. This method produce the following kinds of output files in the 
    current working path:
        
        xxx_dist.yy.dat    distributions of all hotspots and their amount in 
        xxx_dist.yy.png    apo/holo forms. Data are splitted according to the 
                           different domains.
       
        xxx_KStest.dat     Results of Kolmogorov-Smirnov test for each pair of 
                           hotspots distribution (ie the ones belonging to 
                           VH/VL/CH/CL domains between apo and holo forms, 
                           respectively). H0 = "The distribution are similar?"
        
        xxx_hotspots.csv    list of the most relevant hotspots in apo forms,  
        xxx_hotspots.pml    holo forms or both
    

=head2 samba()
    
        samba();
    
    In this method every system of the dataset is scanned in order to retrieve 
    the distance fluctuation values of all of the residue of Fab against the 
    subset of those residue involved in the binding (paratope).This method 
    produce the following output files in the current working path:
        
        samba.APO.csv       list of distance fluctuation values of each residue,
        samba.HOLO.csv      with the respective Ca-Ca distances from the nearest
                            residue belonging to the paratope (in Angstrom)
        
        samba.APO.png       scatter plot of the distance fluctuation values
        samba.HOLO.png      in correlation with the distances from the paratope
        
        samba.APO.pml       PyMol scripts for mapping fluctuations along pdb,
        samba.HOLO.pml      fluctuation values are standardized in a range
                            spanning from 0 to 100
    
=cut