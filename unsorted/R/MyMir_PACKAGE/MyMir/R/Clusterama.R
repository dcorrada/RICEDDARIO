## <clusterama.R> insieme di funzioni per condurre una cluster analysis utilizzando oggetti di classe <Clusterama>

`Clusterama` <-
function (pop.acc = FALSE, pop.orth = FALSE, sub.ont = NULL, ...) {
# Questa funzione si occupa di inizializzare un oggetto di classe <Clusterama>, producendo una matrice di dissimilarità a partire dal dataset fornito in input
#
# <pop.acc>     accessibility filter
# <pop.orth>    orthology filter
#
# <sub.ont>     sub-ontology ("MF", "BP", o "CC")
#
# <...>         parametri per <SemanticSimilarity>
    
    if (is.null(sub.ont)) { stop("undef <sub.ont> parameter"); }
    
    clusterama.obj <- new("Clusterama");
    
    semsim.matrix <- SemanticSimilarity(pop.acc = pop.acc, pop.orth = pop.orth, sub.ont = sub.ont, ...); # costruisco una matrice di similarità semantica
    dist.matrix <- sapply(semsim.matrix, function(x) { 1 - x });
    dist.matrix <- matrix(dist.matrix, ncol = ncol(semsim.matrix), dimnames = dimnames(semsim.matrix));
    dist.matrix <- as.dist(dist.matrix);
    
    writeLines("\n-- Initializing <Clusterama> object...");
    { # informazioni sul dataset originario
        writeLines("\t Data source info");
        clusterama.obj@data$acc <- pop.acc;
        clusterama.obj@data$orth <- pop.orth;
        clusterama.obj@data$ont <- toupper(sub.ont);
    }
    
    { # informazioni sulla matrice di distanza
        writeLines("\t Distance matrix on semantic similarities");
        clusterama.obj@dist$matrix <- as.matrix(dist.matrix);
        clusterama.obj@dist$size <- dist.matrix@Size;
        clusterama.obj@dist$labels <- dist.matrix@Labels;
    }
    
    { # Multidimensional Scaling
        writeLines("\t Multidimensional scaling");
        clusterama.obj <- MDS(clusterama.obj);
    }
    
    { # Clustering
        writeLines("\t Cluster analysis");
        clusterama.obj <- Hopach.Run(clusterama.obj); # stima del numero dei cluster
        clusterama.obj <- Partitional.Clustering(clusterama.obj, x11.out=FALSE, ps.out=FALSE); 
    }
    
    { # Summaries
        writeLines("\t Gathering summaries");
        clusterama.obj <- Cluster.Dataframes(clusterama.obj);
    }
    
    return(clusterama.obj);
}

`Dist.Heatmap` <-
function (clusterama=NULL, x11.out=TRUE, ps.out=TRUE, ...) {
# Questa funzione rappresenta la matrice di dissimilarità sotto forma di heatmap.
# A heat map is a false color image with a dendrogram added to the axis.
# Colors range from maximum similarity (blue) to maximum dissimilarity (red).
# 
# <clusterama>      oggetto di classe <Clusterama>
#
# <ps.out>          redirigo l'output grafico su un file postscript

#     INIZIALIZZAZIONI
    if (is.null(clusterama)) { stop("undef parameter <clusterama>"); }
    if (!is(clusterama, "Clusterama")) { stop("wrong class for object call in <clusterama> parameter"); }
    
    dist.matrix <- as.dist(clusterama@dist$matrix); # istanzio un oggetto di classe <dist> (v. "dist", package="stats")
    
    caver <- hclust(dist.matrix, method = "average"); # clustering gerarchico con metodo di agglomerazione "average linkage": la distanza tra due cluster viene definita come la distanza tra i rispettivi centri di massa (centroidi); esistono diversi metodi per il calcolo dei centroidi, qui viene usato l'UPGMA (v. "hclust", package="stats")
    
    dend <- as.dendrogram(caver); # strutura del dendogramma ottenuta dal clustering (v. "as.dendrogram", package="stats")
    
    my.palette <- rev(colorRampPalette(brewer.pal(10, "RdYlBu"))(256)); # palette di colori
    
    if (x11.out) {
        x11();
        heatmap(as.matrix(dist.matrix), Rowv = dend, col=my.palette, sym=T);
    }
    
    if (ps.out) {
        postscript(...);
        heatmap(as.matrix(dist.matrix), Rowv = dend, col=my.palette, sym=T);
        dev.off();
    }
}

`MDS` <-
function (clusterama=NULL) { # CLASSICAL MULTIDIMENSIONAL SCALING (v. "cmdscale", package="stats")
# Classical multidimensional scaling – a.k.a. Torgerson Scaling or Torgerson-Gower scaling – takes an input matrix giving dissimilarities between pairs of items and outputs a coordinate matrix whose configuration minimizes a loss function called strain.[1]
# [1] Borg, I. and Groenen, P.: "Modern Multidimensional Scaling: theory and applications" (2nd ed.), Springer-Verlag New York, 2005
    
    if (!is(clusterama, "Clusterama")) { stop("wrong class for object call in <clusterama> parameter"); }
    
    dist.matrix <- clusterama@dist$matrix;
    dist.size <- clusterama@dist$size;
    
    for (dim.number in seq(2, dist.size - 1, 1)) {
        mds <- cmdscale(as.dist(dist.matrix), k=dim.number, eig=TRUE);
        if (mds$GOF[2] > 0.8) break;
    }
    
    { # aggiorno l'oggetto di classe <Clusterama>
        clusterama@mds$eig <- mds$eig;
        clusterama@mds$GOF <- mds$GOF[2];
        clusterama@mds$dims <- dim.number;
        clusterama@mds$points <- mds$points;
    }
    
    return(clusterama);
}

`Hopach.Run`  <-
function (clusterama=NULL) { # Hierarchical Ordered Partitioning and Collapsing Hybrid (HOPACH) clustering algorithm (v. "hopach", package="hopach")
# The HOPACH hierarchical clustering algorithm is a hybrid between an agglomerative (bottom up) and a divisive (top down) algorithm.
# The HOPACH tree is built from the root node (all elements) down to the leaf nodes, but at each level collapsing steps are used to unite similar clusters. In addition, the clusters in each level are ordered with a deterministic algorithm based on the same distance metric that is used in the clustering. In this way, the ordering produced in the final level of the tree does not depend on the order of the data in the original data set. Unlike other hierarchical clustering methods, HOPACH  builds a tree of clusters in which the nodes need not be binary, i.e. there can be more than two children at each split.
# The divisive steps of the HOPACH algorithm are performed using the PAM algorithm.
# The Median (or Mean) Split Silhouette (MSS) criteria is used by HOPACH to (i) determine the optimal number of children at each node, (ii) decide which pairs of clusters to  collapse at each level, and (iii) identify the first level of the tree with maximally homogeneous clusters. In each case, the goal is to minimize MSS, which is a measure of cluster heterogeneity [1].
# [1] Pollard K. and van der Laan M., "A Method to Identify Significant Clusters in Gene Expression Data" (April 2002). U.C. Berkeley Division of Biostatistics Working Paper Series. Working Paper 107 - http://www.bepress.com/ucbbiostat/paper107)

    if (!is(clusterama, "Clusterama")) { stop("wrong class for object call in <clusterama> parameter"); }
    
    dist.matrix <- clusterama@dist$matrix;
    points <- clusterama@mds$points;
    
    
    hybrid.clus <- try(hopach(data=points, dmat=dist.matrix, d="euclid", clusters="best", coll="seq"), silent=TRUE);
    if ( !(is.list(hybrid.clus)) ) { # patch per un errore noto
        hybrid.clus <- try(hopach(data=points, d="euclid", clusters="best", coll="seq"), silent=FALSE);
    }
    

    clus.number <- hybrid.clus$clustering$k; # numero di clusters suggerito da HOPACH
    medoids.index <- hybrid.clus$clustering$medoids; # i medoids suggeriti da HOPACH (vettore di indici)
    medoids.labels <- medoids.labels <- clusterama@dist$labels[medoids.index] # nome delle osservazioni candidate a medoids
    
    { # aggiorno l'oggetto di classe <Clusterama>
        clusterama@pam$k <- clus.number;
        clusterama@pam$id.med <- medoids.index;
        clusterama@pam$medoids <- medoids.labels;
    }
    
    return(clusterama);
}

`Partitional.Clustering`  <-
function (clusterama=NULL, x11.out=TRUE, ps.out=TRUE, ...) { #  Partitioning Around Medoids (PAM) clustering (v. "pam", package="cluster")
# Partitioning Around Medoids (PAM) is based on the search for k representative objects - medoids - among samples; then k clusters are constructed by assigning each observation to the nearest medoid with a goal of finding k representative objects that minimize the sum of the dissimilarities of the observation to their closest representative object
    
    if (!is(clusterama, "Clusterama")) { stop("wrong class for object call in <clusterama> parameter"); }
    
    dist.matrix <- clusterama@dist$matrix; # matrice di distanza
    clus.number <- clusterama@pam$k; # numero di cluster
    clus.medoids <- clusterama@pam$id.med; # index vector dei medoids
    
    pam.hopach <- pam(dist.matrix, k=clus.number, diss=TRUE, medoids=clus.medoids, keep.diss=TRUE, keep.data=TRUE);
    
    if (x11.out) {
        x11();
        plot(pam.hopach, which.plots=2, main=""); # _silhouette plot_ For each observation i, a bar is drawn, representing its silhouette width s(i). Observations are grouped per cluster.
    }
    
    if (ps.out) {
        postscript(...);
        plot(pam.hopach, which.plots=2, main="");
        dev.off();
    }
    
    {# aggiorno l'oggetto di classe <Clusterama>
        clusterama@pam$clustering <- pam.hopach$clustering;
        clusterama@pam$clusinfo <- pam.hopach$clusinfo;
        clusterama@pam$silinfo <- pam.hopach$silinfo;
    }
    
    return(clusterama);
}

`Cluster.Dataframes`  <-
function (clusterama=NULL) { # raccolgo in tabelle i risultati prodotti con Clusterama

    if (!is(clusterama, "Clusterama")) { stop("wrong class for object call in <clusterama> parameter"); }
    
    odbc.dsn <- get("odbc.dsn", envir=MyMirEnv) ;
    odbc.pw <- get("odbc.pw", envir=MyMirEnv);
    
    summaries.list <- list();
    
    { # <clusters.df> raccoglie informazioni sui cluster ottenuti
        clusters.df <- as.data.frame(clusterama@pam$clusinfo[,c(1,3)], row.names=paste("PAM", seq(1,dim(clusterama@pam$clusinfo)[1],1), sep='.') );
        
        clusters.df$av_width <- clusterama@pam$silinfo$clus.avg.widths; # valore medio di silhouette del cluster
        
        clusters.df <- clusters.df[order(clusters.df$size, decreasing=TRUE),]; # riordino per numerosità del cluster
        
        clusters.df$cluster <- row.names(clusters.df);
        clusters.df <- clusters.df[,c(4,1:3)];
        
        summaries.list$clusters <- clusters.df;
    }
    
    { # <obs.df> raccoglie informazioni sulle singole osservazioni
        
        # SILHOUETTE WIDTHS
        # Put a(i) = average dissimilarity between i and all other points of the cluster to which i belongs. For all other clusters C, put d(i,C) = average dissimilarity of i to all observations of C. The smallest of these d(i,C) is b(i), and can be seen as the dissimilarity between i and its "neighbor" cluster. Finally, s(i) = ( b(i) - a(i) ) / max( a(i), b(i) ). Observations with a large s(i) (almost 1) are very well clustered, a small s(i) (around 0) means that the observation lies between two clusters, and observations with a negative s(i) are probably placed in the wrong cluster.
        
        obs.df <- as.data.frame(clusterama@pam$silinfo$widths[,c(1,3)]); # tabelle con i valori di silhouette width per ogni osservazione
        
        obs.df$cluster <- paste("PAM", obs.df$cluster, sep='.'); # rinomino i clusters
        
#         is.med <- row.names(obs.df) %in% clusterama@pam$medoids; # mi appunto quali elementi sono i medoids iniziali aggiorno la tabella; keep in mind che il clustering poi evolve, di conseguenza più medoids iniziali potrebbero cadere nello stesso cluster finale
#         obs.df$medoid <- is.med; # aggiorno la tabella
        
        for (thresold in seq(1,0.25,-0.05)) { # considero solo i cluster con silohuette width superiore almeno a 0.25 (meglio se la soglia è piu' alta)
            found <- summaries.list$clusters[summaries.list$clusters$av_width >= thresold,];
            tot <- summaries.list$clusters[summaries.list$clusters$av_width > 0,];
            ratio <- nrow(found) / nrow(tot);
            if (ratio >= 0.75) {
                obs.df[obs.df$cluster %in% found$cluster, ];
                break;
            }
        }
        
        obs.df <- obs.df[obs.df$sil_width >= 0.25,]; # filtro solo gli elementi che hanno un silohuette value superiore a 0.25
        
        obs.df$obs <- row.names(obs.df);
        
        data("MyMir.CrossLinks");
        obs.desc <- MyMir.CrossLinks@GO2Term@s1[MyMir.CrossLinks@GO2Term@s1$goid %in% obs.df$obs,];
        obs.df <- merge(x=obs.df, y=obs.desc, by.x="obs", by.y="goid");
        
        obs.df <- obs.df[order(obs.df$cluster),];
        
        obs.df <- obs.df[,c(1,4,2,3)];
        
        summaries.list$obs <- obs.df;
    }
    
    { # <target.df> raccoglie informazioni sui target associati alle singole osservazioni
        writeLines("\n-- Retrieving miRNA list...");
        writeLines("\tOpening a database handle...");
        dbh <- odbcConnect(dsn = odbc.dsn, pw = odbc.pw);    # apro un canale ('dbh')
        sqlQuery(dbh, "use mm9");   # definisco il DB da usare
        mirna.list <- as.character(sqlQuery(dbh, "SELECT DISTINCT mirID FROM prediction_summary")[,1]); # recupero la lista dei miRNA
        odbcClose(dbh);  # chiudo il canale
        
        target.df <- data.frame();
        
        for (microRNA in mirna.list) {
            writeLines(paste("\n-- Retrieving genes from <", microRNA, "> targets...", sep=''));
            
            term.type <- paste("GO", tolower(clusterama@data$ont), sep="");
            unipop <- Fetch(new("UniPop"), pop.mir = microRNA, pop.limit = 1000, pop.acc = clusterama@data$acc, pop.orth = clusterama@data$orth);
            cluster.list <- summaries.list$clusters[summaries.list$clusters$av_width > 0, 1]; # 0.25 per GObp, 0.5 per le altre ontologie
            
            GO.list <- summaries.list$obs[summaries.list$obs$cluster %in% cluster.list, 1];
            target.list <- Term2Target(unipop, GO.list, term.type);
            mirna.labels <- rep(microRNA, nrow(target.list));
            target.list$miRNA <- mirna.labels;
            cluster.labels <- summaries.list$obs[match(target.list$termID, summaries.list$obs$obs),3];
            target.list$cluster <- cluster.labels;
            
            target.df <- rbind(target.df, target.list);
        }
        
        summaries.list$target <- target.df;
    }
    
    {# aggiorno l'oggetto di classe <Clusterama>
        clusterama@summaries$clusters <- summaries.list$clusters;
        clusterama@summaries$obs <- summaries.list$obs;
        clusterama@summaries$target <- summaries.list$target;
    }
    
    return(clusterama);
}
