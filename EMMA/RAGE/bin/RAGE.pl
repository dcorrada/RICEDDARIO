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
use RAGE::lib::FileIO;
use Statistics::Descriptive;
use Carp;

## GLOBS ##
our $input;
our $R_bin;
our $opt = { };
our $file_obj = RAGE::lib::FileIO->new(); # oggetto per leggere/scrivere su file
our $content = [ ]; # buffer in cui butto dentro il contenuto dei file 
## SBLOG ##

USAGE: {
    print "\n*** RAGE ***\n";
    my $RAwarn = <<END
WARNING: this version adopt a brute force algorithm for Rank Aggregation. 
It is strongly suggested to define the options "min" and "max" within 
a range of 10 (defaults: min 6, max 14).

END
    ;
    my $help;
    use Getopt::Long;no warnings;
    GetOptions($opt, 'help|h', 'file|f=s', 'dist|d=s', 'min=i', 'max=i', 'clust|c=s');
    my $usage = <<END

********************************************************************************
EMMA - Rage Against G_clustEr
release 14.3.lbpc7

Copyright (c) 2011-2014, Dario CORRADA <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

This is a wrapper for an R script which perform hierarchical cluster analysis 
from an RMSD pairwise matrix.

Usually, the input RMSD matrix can be obtained by performing GROMACS' g_rms 
command with '-m' option. Alternatively you can submit any other custom matrix.

SYNOPSIS

\$ RAGE.pl [-f rmsd.xpm] [-d manhattan] [-min 3] [-max 8] [-c average]


OPTIONS
    
    -file|f <filename>
        INPUT, RMSD matrix in .xpm or .csv format
    
    -dist|d <'manhattan'|'euclidean'>
        the distance measure to be used 
        (default: 'manhattan')
    
    -min <num>  -max <num>
        minimum and maximum number of groups allowed for clustering
        (defaults: min 6, max 14)
    
    -clust|c <'single'|'complete'|'average'|'ward'>
        the agglomeration method to be used
        (default: 'complete')
    

REQUIREMENTS:
    
    The script requires R software with installed the following packages:
    "cluster"; "clValid"; "RColorBrewer"; "RankAggreg".
END
    ;
    
    if ($opt->{'help'}) { 
        print $usage; goto FINE;
    } else {
        print $RAwarn;
    }
}

INIT: {
    if (exists $opt->{'file'}) {
        $input = $opt->{'file'};
    } else {
        $input = 'rmsd.xpm';
    }
    
    $R_bin = qx/which R/;
    chomp $R_bin;
    croak  "E- R software not found\n\t" unless (-e $R_bin);
    $R_bin .= ' --vanilla <'; # opzione per far girare R in batch
    
    if (-f $input) {
        my ($format) = $input =~ /(\w{3})$/;
        if ($format eq 'xpm') {
            goto XPM_PARSER;
        } elsif ($format eq 'csv') {
            goto CLUSTERING;
        } else {
            croak "E- file format unknown\n\t";
        }
    } else {
        croak "E- input file [$input] not found\n\t";
    }
    
}

XPM_PARSER: {
    print "I- parsing [$input]...\n";
    
    my $rmsd_matrix = [ ]; # matrice dei valori di RMSD tra coppie di snapshots
    
    $file_obj->set_filename($input);
    $content = $file_obj->read();
    my $rmsd_range = { }; # lista dei valori di rmsd
    my $frames = [ ]; # elenco dei timeframes
    my $row = 0; # numero di riga della matrice
    while (my $newline = shift @{$content}) {
        chomp $newline;
        if ($newline =~ /^"[^ "]{1}.+"[\d\.]*" \*\/,$/) {
            my ($key,$value) = $newline =~ /^"([^ "]{1}).+"([\d\.]*)" \*\/,$/;
            $rmsd_range->{$key} = $value;
        } elsif ($newline =~ /^\/\* x-axis:  /) {
            my ($string) = $newline =~ /^\/\* x-axis:  ([\d ]+) \*\/$/;
            push(@{$frames}, split(' ', $string));
        } elsif ($newline =~ /^"[^ "]+"[,]{0,1}$/) {
            my ($string) = $newline =~ /^"([^ "]+)"[,]{0,1}$/;
            my @array = split('', $string);
            for (my $col=0; $col < scalar @array; $col++) {
                my $real_row = (scalar @array - 1) - $row; # FIX, la prima riga corrisponde all'ultimo timeframe e così via...
                $rmsd_matrix->[$real_row]->[$col] = $rmsd_range->{$array[$col]};
            }
            $row++;
        } else {
            next;
        }
    }
    
    # esporto la matrice
    $file_obj->set_filename('rmsd.matrix.csv');
    my $header = ';' . join(';' ,@{$frames} ) . "\n";
    $content = [ $header ];
    for (my $i=0; $i < scalar @{$frames}; $i++) {
        my $newline = "$frames->[$i];";
        $newline .= join(';',@{$rmsd_matrix->[$i]});
        $newline .= "\n";
        push(@{$content},$newline);
    }
    $file_obj->set_filedata($content);
    $file_obj->write();
}

CLUSTERING: {
    print "I- cluster analysis...\n";
    
    # defaults options
    my $rmsd_matrix = 'rmsd.matrix.csv';
    my $dist_method = 'manhattan';
    my $mink = 6;
    my $maxk = 14;
    my $clust_method = 'complete';
    
    # selected options
    $dist_method = $opt->{'dist'} if (exists $opt->{'dist'});
    $mink = $opt->{'min'} if (exists $opt->{'min'});
    $maxk = $opt->{'max'} if (exists $opt->{'max'});
    $clust_method = $opt->{'clust'} if (exists $opt->{'clust'});
    
    my $scRipt = <<END
library(cluster);
library(RColorBrewer);
library(RankAggreg);
library(clValid);

# IMPORTO LA MATRICE DELLE RMSD
rmsd.mat <- read.csv(
    "$rmsd_matrix",
    sep = ";",
    header = TRUE,
    stringsAsFactors = FALSE,
    dec = "."
); 

# CALCOLO LA MATRICE DU DISSIMILARITA'
# userei "manhattan" ipotizzando che il percorso da fare tra due snapshot debba
# passare per altrettanti snapshot discreti;
# non standardizzo visto che tutte le colonne sono valori di RMSD
dist.mat <- dist(rmsd.mat, method = "$dist_method");

# CLUSTERING GERARCHICO
# metodo di agglomerazione "average linkage": la distanza tra due cluster viene
# definita come la distanza tra i rispettivi centri di massa (centroidi);
# metodo per il calcolo dei centroidi, UPGMA
average <- hclust(dist.mat, method = "$clust_method");
dend <- as.dendrogram(average);
png("dist.matrix.png", width = 2048, height = 2048);
my.palette <- rev(colorRampPalette(brewer.pal(10, "RdYlBu"))(256));
heatmap(as.matrix(dist.mat), Rowv = dend, col=my.palette, sym=T);
dev.off();

# SILHOUETTE
mink <- $mink; # numero minimo di cluster
maxk <- $maxk; # numero massimo di cluster
silh.wid <- numeric(maxk); # valori di silhouette per cluster
silh.wid[1:mink] <- NA;
postscript("silhouette.plots.eps"); # silhouette plots
op <- par(mfrow = c(5,4), mar = .1+ c(2,1,2,1), mgp=c(1.5, .6,0));
tabella <- NULL;
for(k in mink:maxk) {
    cat("\\n== ", k," clusters  ========================================\\n");
    k.gr <- cutree(average, k = k);
    cat("grouping table: "); print(table(k.gr));
    thetop <- as.data.frame(table(k.gr));
    newline = c(thetop[thetop\$Freq == max(thetop\$Freq),]);
    si <- silhouette(k.gr, dist.mat);
    cat("silhouette:\\n"); print(summary(si));
    plot(si, main = paste("k =",k), col = 2:(k+1), do.n.k=FALSE, do.clus.stat=FALSE);
    silh.wid[k] <- summary(si)\$avg.width;
    check.array <- thetop[thetop\$Freq == max(thetop\$Freq),];
    best.pop <- 0;
    best.sil <- -1;
    best.k <- 0;
    for(r in 1:nrow(check.array)) {
        best.pop <- check.array[r,2];
        conf <- summary(si)\$clus.avg.widths[check.array[r,1]];
        if (conf > best.sil) {
            best.sil <- conf;
            best.k <- check.array[r,1];
        }
    }
    cat("\\n=========================================================\\n");
    tabella <- rbind( tabella, c(
        k,
        silh.wid[k],
        best.k,
        best.pop,
        best.sil
    ));
}
par(op);
dev.off();

colnames(tabella) <- c("kTOT", "mean_sil", "kMAX", "kMAX_elems", "kMAX_sil");
rownames(tabella) <- c(1:dim(tabella)[1]);

# CRITERI DI VALUTAZIONE DEL CLUSTERING
rawdata <- rmsd.mat[,-1];
rownames(rawdata) <- rmsd.mat[,1];
result <- clValid(rawdata, mink:maxk, maxitems=nrow(rawdata), clMethods="hierarchical", validation="internal", metric="$dist_method", method = "$clust_method");
criteria <- data.frame(result\@measures);
criteria <- rbind(criteria,tabella[,"mean_sil"]);
criteria <- rbind(criteria,tabella[,"kMAX_sil"]);
criteria <- rbind(criteria,tabella[,"kMAX_elems"]);
rownames(criteria) <- c("Connectivity","Dunn","Silhouette","mean_sil","kMAX_sil","kMAX_elems");
colnames(criteria) <- c(mink:maxk);
criteria <- t(criteria);

# RIEPILOGO
# la tabella di riepilogo è strutturata nelle seguenti colonne:
#     CLUSTERS      numero totale di cluster
#     Connectivity  criterio interno del pacchetto "clValid"
#     Dunn          criterio interno del pacchetto "clValid"
#     Silhouette    criterio interno del pacchetto "clValid"
#     mean_sil      silhouette media secondo il pacchetto "cluster"
#     kMAX_elems    numero di elementi appartenenti al cluster piu' popoloso
#     kMAX_sil      silhouette media relativa al cluster piu' popoloso
csv.out <- cbind(rownames(criteria),criteria)
colnames(csv.out) <- c("CLUSTERS","Connectivity","Dunn","Silhouette","mean_sil","kMAX_sil","kMAX_elems");
write.table(csv.out, file = "cluster.summary.csv", quote = TRUE, sep = ";", row.names = FALSE);

# PRUNING
# individuo il numero ottimale di cluster (ie altezza a cui tagliare il
# dendrogramma) ottimizzando la tabella ottenuta in precedenza
rank.table <- rbind(
    names(sort(criteria[,1], decreasing = FALSE)),
    names(sort(criteria[,2], decreasing = TRUE)),
    names(sort(criteria[,3], decreasing = TRUE)),
    names(sort(criteria[,4], decreasing = TRUE)),
    names(sort(criteria[,5], decreasing = TRUE)),
    names(sort(criteria[,6], decreasing = TRUE))
);
weight.table <- rbind(
    sort(criteria[,1], decreasing = FALSE),
    sort(criteria[,2], decreasing = TRUE),
    sort(criteria[,3], decreasing = TRUE),
    sort(criteria[,4], decreasing = TRUE),
    sort(criteria[,5], decreasing = TRUE),
    sort(criteria[,6], decreasing = TRUE)
);
# fuzione di normalizzazione, il flag "decreasing" serve a specificare se la
# lista deve essere minimizzata (FALSE) o massimizzata (TRUE)
ABnormal <- function(m,decreasing = FALSE){
    if (decreasing) {
        return ((m-min(m))/(max(m)-min(m)));
    } else {
        return ((max(m)-m)/(max(m)-min(m)));
    }
}
# normalizzo la tabella dei pesi
norm.table <- weight.table;
norm.table[1,] <- ABnormal(weight.table[1,],decreasing = FALSE);
norm.table[2,] <- ABnormal(weight.table[2,],decreasing = TRUE);
norm.table[3,] <- ABnormal(weight.table[3,],decreasing = TRUE);
norm.table[4,] <- ABnormal(weight.table[4,],decreasing = TRUE);
norm.table[5,] <- ABnormal(weight.table[5,],decreasing = TRUE);
norm.table[6,] <- ABnormal(weight.table[6,],decreasing = TRUE);

# RANK AGGREGATION
# Uso l'algoritmo a forza bruta: il numero di calcoli da fare aumenta in modo
# fattoriale il numero di dati da valutare (questo significa di non usare un k
# superiore a 10).
# La pesatura dei criteri di valutazione della cluster analysis purtroppo e'
# soggettiva: ho deciso di pesare molto la popolosita' del cluster piu' grosso 
# e la sua silhouette (peso = 4); a seguire vengono i criteri interni del 
# pacchetto "clValid" (peso = 2); per ultimo viene la silhouette media del 
# pacchetto "cluster" (peso = 1).
k <- dim(rank.table)[2]
bestcomb <- BruteAggreg(rank.table,k,norm.table,"Spearman",c(2,2,2,1,4,4))
png("RankAggreg.png", width = 2048, height = 2048);
plot(bestcomb)
dev.off();

groupes <- cutree(average, k = bestcomb\$top.list[1]);

# SILHOUETTE VALUES
# valori di silhouette dei singoli elementi
silist <- silhouette(groupes, dist.mat);
write.table(
    silist,
    file = "silhouette.best.csv",
    quote = FALSE,
    row.names = FALSE,
    col.names = FALSE,
    sep = ";"
);
END
        ;
        my $script_file = 'clustering.R';
        $file_obj->set_filename($script_file);
        $file_obj->set_filedata([ $scRipt ]);
        $file_obj->write();
        my $Rlog = qx/$R_bin $script_file 2>&1/;
        $file_obj->set_filename('scRipt.log');
        $file_obj->set_filedata([ $Rlog ]);
        $file_obj->write();
}

CLUSTER_LIST: {
    print "I- writing output...\n";
    my $rmsd_matrix = 'rmsd.matrix.csv';
    $rmsd_matrix = $input if ($input =~ /csv$/);
    $file_obj->set_filename($rmsd_matrix);
    $content = $file_obj->read();
    my $header = shift @{$content};
    chomp $header;
    $header =~ s/;//;
    my @frames = split(';', $header);
    
    my $clusts = { };
    $file_obj->set_filename('silhouette.best.csv');
    $content = $file_obj->read();
    my $i = 0;
    while (my $newline = shift @{$content}) {
        chomp $newline;
        my ($cluster,$neighbour,$sil) = split(';', $newline);
        $clusts->{$cluster} = { } unless (exists $clusts->{$cluster});
        $clusts->{$cluster}->{$frames[$i]} = $sil;
        $i++;
    }
    
    $file_obj->set_filename('RAGE.cluster.log');
    $content = [
        "*** RAGE - Rage Against G_clustEr ***\n",
        sprintf("Optimal clustering is composed of %i clusters\n", scalar keys %{$clusts}),
        'wait',
    ];
    my $bestcluster = { };
    my @sorted = sort { $a <=> $b } keys %{$clusts};
    while (my $cluster = shift @sorted) {
        $bestcluster->{$cluster} = [ ];
        my $pop = scalar keys %{$clusts->{$cluster}};
        $bestcluster->{$cluster}->[0] = $pop;
        push(@{$content}, sprintf("\n\n== CLUSTER %i (%i timeframes) ==\n", $cluster, $pop));
        my $stat_obj = Statistics::Descriptive::Full->new();
        $stat_obj->add_data(values %{$clusts->{$cluster}});
        my $mean = $stat_obj->mean();
        $bestcluster->{$cluster}->[1] = $mean;
        push(@{$content}, sprintf("Average silhouette: %.3f\n", $mean));
        my $silbest = $stat_obj->quantile(4);
        my $timebest;
        foreach my $frame (keys %{$clusts->{$cluster}}) {
            if ($clusts->{$cluster}->{$frame} == $silbest) {
                $timebest = $frame;
                last;
            } else {
                next;
            }
        }
        push(@{$content}, sprintf("Best timeframe [%i] (sil: %.3f)\n", $timebest, $silbest));
        my @ordered = sort { $a <=> $b } keys %{$clusts->{$cluster}};
        shift @ordered if ($ordered[0] == 0);
        my $cols = 1;
        my @elems;
        while (my $frame = shift @ordered) {
            push(@elems, $frame);
            if (scalar @elems > 8 || scalar @ordered < 1) {
                my $string = '[';
                $string .= join('  ', @elems);
                $string .= "]\n";
                push(@{$content}, $string);
                undef @elems;
                $cols = 0;
            }
            $cols++;
        }
    }
    my $maxpop = 1;
    my $maxsil = -1;
    my $thebest;
    foreach my $cluster (keys %{$bestcluster}) {
        my ($pop,$sil) = @{$bestcluster->{$cluster}};
        if ($pop > 0.75 * $maxpop) {
            if ($sil > $maxsil) {
                $thebest = $cluster;
                $maxsil = $sil;
                $maxpop = $pop
            }
        }
    }
    $content->[2] = sprintf("Best cluster is CLUSTER %i\n", $thebest);
    $file_obj->set_filedata($content);
    $file_obj->write();
}


CLEANSWEEP: { # elimino i file intermedi prodotti
    print "I- cleaning temporary files...\n";
    unlink 'clustering.R'; # script di clustering
    unlink 'scRipt.log'; # log dello script
    unlink 'rmsd.matrix.csv'; # matrice delle RMSD in formato csv
    unlink 'silhouette.best.csv'; # valori di silhouette per ogni punto
    unlink 'silhouette.plots.eps'; # silhouette plot per ogni clustering
}

FINE: {
    print "\n*** EGAR ***\n";
    exit;
}
