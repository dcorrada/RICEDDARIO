## <clusterama.R> insieme di funzioni per condurre una cluster analysis

{ # dipendenze
    library("MyMir");
    library("cluster");
    library("RColorBrewer");
    library("hopach");
}

setClass('Clusterama', # Clusterama dataset class
    representation(
        data='list', # source dataset info
        dist='list', # info about distance matrix. Distances relies on semantic similarities among GO term pairs; distance values range from 0, perfect similarity (identical GO terms), to 1, maximum dissimilarity
        mds='list', # info about multidimensional scaling (MDS). MDS is a set of related statistical techniques often used in information visualization for exploring similarities or dissimilarities in data; an MDS algorithm starts with a matrix of item–item similarities, then assigns a location to each item in N-dimensional space.
        pam='list', # info about partitional clustering.
        summaries='list' # summaries dataframes from Clusterama computations
    ),
    prototype(
        data=list(
            acc=NULL, # logical, accessibility filter
            ont=NULL, # string, sub-ontology
            orth=NULL # logical, orthology filter
        ),
        dist=list(
            matrix=NULL, # matrix, distance matrix
            size=NULL, # integer, number of observations in the dataset
            labels=NULL # array, names of each observation
        ),
        mds=list(
            eig=NULL, # array, eigenvalues computed during the scaling process
            GOF=NULL, # double, Goodness Of Fit (GOF) the sum of above-zero eigenvalues for the total GOF = (sum{j=1..k} lambda[j]) / (sum{j=1..n} max(lambda[j], 0)), where lambda[j] are the eigenvalues (sorted decreasingly). A GOF of 0.8 is considered good for metric scaling.
            dims=NULL, # the dimension of the space which the data are to be represented in; it is related with the number of eigenvalues in order to obtain GOF > 0.8
            points=NULL # matrix with 'dims' columns whose rows give the coordinates of the points chosen to represent the dissimilarities.
        ),
        pam=list(
            k=NULL, # integer,number of clusters as suggested by HOPACH
            medoids=NULL, # array, the medoids or representative objects of the clusters.
            id.med=NULL, # array,  integer vector of _indices_ giving the medoid observation numbers
            clustering=NULL, # array, the clustering vector. An integer vector of length n, the number of observations, giving for each observation the number (`id') of the cluster to which it belongs
            clusinfo=NULL, # matrix, each row gives numerical information for one cluster.FIELDS: cardinality of the cluster; maximal and average dissimilarity between the observations in the cluster and the cluster's medoid; diameter of the cluster (maximal dissimilarity between two observations of the cluster); the separation of the cluster (minimal dissimilarity between an observation of the cluster and an observation of another cluster)
            silinfo=NULL # list, all "silhouette" info: "$widths" matrix with for each observation i the cluster to which i belongs, the neighbor cluster of i, and the silhouette width s(i); "$clus.avg.widths" the average silhouette width per cluster; "avg.width" the average of s(i) over all observations i
        ),
        summaries=list(
            clusters=NULL, # dataframe, info about clusters
            obs=NULL, # dataframe, info about observation of each clusters
            target=NULL # dataframe, info about target which belong to observed GO terms
        )
    )
)

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
        
        obs.df <- obs.df[obs.df$sil_width >= 0.25,]; # filtro solo gli elementi che hanno un silohuette value superiore a 0
        
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


# ATTENZIONE: questa funzione sarà da implementare come metodo della funzione generica <UpdateDB> per oggetti di classe <Clusterama>
`Update.Clusterama`  <-
function (object=NULL) {
# Questo metodo recupera i dati di un oggetto di classe <Clusterama> e li carica su tabelle apposite sul DB. In particolare, dato un oggetto di classe <Clusterama>, estrae i dataframes contenuti nello slot <summaries> e li carica come tre tabelle separate con la seguente nomenclatura:
#
#       [sub.ontology]_[filtri]_["cluster"|"obs"|"target"]
#
# [sub.ontology] -> tipo di ontologia (BP, CC o MF)
# [filtri] -> due logit che indicano quali filtri sono stati applicati neò reperimento del dataset (es.: "TRUE_FALSE" indica che sono dati filtrato per accessibilita' [True] ma non per ortologia [False])
# ["cluster"|"obs"|"target"] -> i tre dataframes dello slot <summaries>
#
# <object>     OBBLIGATORIO, oggetto di classe <Clusterama>

    db.usr <- get("db.usr", envir=MyMirEnv);
    db.pw <- get("db.pw", envir=MyMirEnv);
    db.host <- get("db.host", envir=MyMirEnv);
    db.name <- get("db.name", envir=MyMirEnv);
    
    dbd<-dbDriver("MySQL");   # carico il driver per MySQL
    dbh<-dbConnect(dbd, user = db.usr, password = db.pw, host = db.host, dbname = db.name); # mi connetto al database
    writeLines("-- connected to DB...");print(dbh);
    
    basename <- paste(object@data$ont, object@data$acc, object@data$orth, sep='_'); # il basename delle tabelle da caricare, stringa del tipo "[sub.ontology]_[filtri]_"
    df.list <- object@summaries; # lista dei dataframes che verranno caricati
    
    for (df.name in names(df.list)) {
        tab.name <- paste(basename, df.name, sep = "_"); # nome della tabella
        tab.data <- df.list[[df.name]]; # contenuto della tabella
        sth <- dbSendQuery(dbh, paste("DROP TABLE IF EXISTS", tab.name, sep =" ")); # rimuovo eventuali tabelle pre-esistenti
        
        row.names(tab.data) <- c(1:nrow(tab.data));
        writeLines(c("-- uploading <", tab.name, "> table\n"), sep = "");
        dbWriteTable(dbh, tab.name, tab.data, row.names=TRUE); # carico la tabella
        sth <- dbSendQuery(dbh, paste("ALTER TABLE", tab.name, "ADD PRIMARY KEY ( `row_names` ( 30 ) )", sep =" "));# e la indicizzo
    }
    
    #     mi disconnetto dal database
    if (dbDisconnect(dbh)) { writeLines("-- disconnected from DB");print(dbh);
    } else { writeLines("W- disconnection from DB failed!");print(dbh); }
}

