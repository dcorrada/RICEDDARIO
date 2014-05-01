# TEMPLATE STANDARD
help.start()    # help su browser
rm(list = ls())    # rimuovo tutti gli oggetti presenti nella sessione
setwd('~/my_mir/R_scripts')     # mi sposto sul path dove tengo i miei scripts
load(file = '/home/dario/my_mir/R_scripts/LastSession.RData') # recupero l'immagine dell'ultima sessione di lavoro
save.image(file = '/home/dario/my_mir/R_scripts/LastSession.RData') # salvo l'immagine dell'ultima sessione di lavoro 

# #############################################################################
# TUTORIAL SU CLUSTERING

library(MyMir);
library(RColorBrewer);
library(hopach);

load(file = '/home/dario/my_mir/R_scripts/raw.data.RData');
# raw.data <- list();
# for (sub.ont in c("bp", "cc", "mf")) { # carico una lista di matrici di similarità semantica
#     raw.data[[sub.ont]] <- SemanticSimilarity(odbc.pw = 'korda',  pop.acc = TRUE, pop.orth = TRUE, sub.ont = sub.ont);
#     raw.data[[sub.ont]][is.na(raw.data[[sub.ont]])] <- 0; # gestione degli NA
# }

semsim.matrix <- raw.data$cc; # considero una delle tre matrici di similarità semantica

# Il clustering gerarchico richiede una MATRICE DI DISSIMILARITÀ come input, calcolabile con la funzione standard <dist>
# Basta convertire la matrice ottenuta dalla funzione <SemanticSimilarity> in un oggetto di classe "dist"
# Uso come indice di dissimilarità [1 - semantic similarity] visto che semsim è una scala che va da 0 a 1
dist.matrix <- sapply(semsim.matrix, function(x) { 1 - x });
dist.matrix <- matrix(dist.matrix, ncol = ncol(semsim.matrix), dimnames = dimnames(semsim.matrix));

# converto la matrice di dissimilarità in un oggetto di classe "dist"
dist.matrix <- as.dist(dist.matrix);

# Clustering gerarchico con metodo di agglomerazione "average linkage": la distanza tra due cluster viene definita come la distanza tra i rispettivi centri di massa (centroidi); esistono diversi metodi per il calcolo dei centroidi, qui verrà usato l'UPGMA
caver <- hclust(dist.matrix, method = "average");
dend <- as.dendrogram(caver); # dendogramma del clustering


# quanti cluster prendere in considerazione? funzione 'silcheck' dal package 'hopach'
optimal.groupes <- silcheck(as.matrix(dist.matrix), diss=TRUE); # returns a vector with first component the chosen number of clusters (maximizing average silhouette) and second component the corresponding average silhouette.
class.number <- round(optimal.groupes[1]);
groupes <- cutree(caver, k = class.number);



# matrice dissimilarità (heatmap)
my.palette = rev(colorRampPalette(brewer.pal(10, "RdYlBu"))(256)) # palette di colori
heatmap(as.matrix(dist.matrix), Rowv = dend, col=my.palette, sym=T)

# dendrogramma con evidenziato il numero di clusters suggerito
x11();
plot(caver, hang=-1);
rect.hclust(caver, k=class.number, border="blue");

# summaries
table(groupes); # quanti elementi ci sono x ogni classe
summary(as.numeric(table(groupes))); # alcune statistiche sulle tabelle di frequenza dei gruppi (es. quanti elementi appartengono ad un gruppo)



x11();

# Partitioning Around Medoids (PAM) is based on the search for k representative objects - medoids - among samples; then k clusters are constructed by assigning each observation to the nearest medoid with a goal of finding k representative objects that minimize the sum of the dissimilarities of the observation to their closest representative object
pam.sil <- pam(as.matrix(dist.matrix), diss=TRUE, k=class.number, keep.diss=TRUE, keep.data=TRUE); # ritorna un oggetto di classe "pam", estensione della classe "partition" (see '?pam.object' or '?partition.object')
pam.sil$medoids; # elenco dei medoids scelti
pam.sil$clustering; # vettore indicizzato: indice = elemento; valore = cluster a cui è stato assegnato
pam.sil$clusinfo; # matrix, each row gives numerical information for one cluster. FIELDS: cardinality of the cluster; maximal and average dissimilarity between the observations in the cluster and the cluster's medoid; diameter of the cluster (maximal dissimilarity between two observations of the cluster); the separation of the cluster (minimal dissimilarity between an observation of the cluster and an observation of another sim.matrixcluster)
pam.sil$silinfo; # a list with all "silhouette" info (see '?silhouette'): "$widths" matrix with for each observation i the cluster to which i belongs, the neighbor cluster of i, and the silhouette width s(i); "$clus.avg.widths" the average silhouette width per cluster; "avg.width" the average of s(i) over all observations i


par(mfrow=c(1,2));
plot(pam.sil, which.plots=1, lines=0, shade=FALSE, color=TRUE, labels=4, plotchar=FALSE, span=FALSE); # _clusplot_ consists of a two-dimensional representation of the observations, in which the clusters are indicated by ellipses (see 'clusplot.partition' for more details).
plot(pam.sil, which.plots=2); # _silhouette plot_ For each observation i, a bar is drawn, representing its silhouette width s(i). Observations are grouped per cluster.

# SILHOUETTE WIDTH s(i). For each observation i, the _silhouette width_ s(i) is defined as follows:
# Put a(i) = average dissimilarity between i and all other points of the cluster to which i belongs. For all other clusters C, put d(i,C) = average dissimilarity of i to all observations of C. The smallest of these d(i,C) is b(i), and can be seen as the dissimilarity between i and its "neighbor" cluster. Finally, s(i) = ( b(i) - a(i) ) / max( a(i), b(i) ).
# Observations with a large s(i) (almost 1) are very well clustered, a small s(i) (around 0) means that the observation lies between two clusters, and observations with a negative s(i) are probably placed in the wrong cluster.

silpam <- silhouette(pam.sil);
silpam <- as.data.frame(silpam[1:length(rownames(silpam)),]);
negative.sils <- silpam[silpam[, "sil_width"] < 0,];




# Il package 'hopach' fa una cluster analysis ibrida facendo prima un agglomerative clustering e poi un partitioning clustering, calcola i valori di silhouette e restituisce il numero di clusters ottimali per il partitioning.
# ATTENZIONE: ho bisogno di avere una rappresentazione dei miei dati a partire dalla matrice di dissimilarità x poter usare il package 'hopach'.

# CLASSICAL MULTIDIMENSIONAL SCALING
# Multidimensional scaling (MDS) is a set of related statistical techniques often used in information visualization for exploring similarities or dissimilarities in data. An MDS algorithm starts with a matrix of item–item similarities, then assigns a location to each item in N-dimensional space.
# Classical multidimensional scaling – a.k.a. Torgerson Scaling or Torgerson-Gower scaling – takes an input matrix giving dissimilarities between pairs of items and outputs a coordinate matrix whose configuration minimizes a loss function called strain.[1]
# Testing the results for reliability implies the evaluation of Goodness Of Fit (GOF) e.g. the sum of above-zero eigenvalues for the total GOF = (sum{j=1..k} lambda[j]) / (sum{j=1..n} max(lambda[j], 0)), where lambda[j] are the eigenvalues (sorted decreasingly). A GOF of 0.8 is considered good for metric scaling and 0.9 is considered good for non-metric scaling.
# [1] Borg, I. and Groenen, P.: "Modern Multidimensional Scaling: theory and applications" (2nd ed.), Springer-Verlag New York, 2005

for (dim.number in seq(2, dist.matrix@Size - 1, 1)) {
    mds <- cmdscale(dist.matrix, k=dim.number, eig=TRUE);
    if (mds$GOF[2] > 0.8) break;
}
paste("DIMS: ", dim.number, " - GOF: ", mds$GOF[2]); # DIMS è il numero di dimensioni prese in considerazione per ottenere un GOF > 0.8


# Hierarchical Ordered Partitioning and Collapsing Hybrid (HOPACH) clustering algorithm
# The HOPACH hierarchical clustering algorithm is a hybrid between an agglomerative (bottom up) and a divisive (top down) algorithm.
# The HOPACH tree is built from the root node (all elements) down to the leaf nodes, but at each level collapsing steps are used to unite similar clusters. In addition, the clusters in each level are ordered with a deterministic algorithm based on the same distance metric that is used in the clustering. In this way, the ordering produced in the final level of the tree does not depend on the order of the data in the original data set. Unlike other hierarchical clustering methods, HOPACH  builds a tree of clusters in which the nodes need not be binary, i.e. there can be more than two children at each split.
# The divisive steps of the HOPACH algorithm are performed using the PAM algorithm.
# The Median (or Mean) Split Silhouette (MSS) criteria is used by HOPACH to (i) determine the optimal number of children at each node, (ii) decide which pairs of clusters to  collapse at each level, and (iii) identify the first level of the tree with maximally homogeneous clusters. In each case, the goal is to minimize MSS, which is a measure of cluster heterogeneity [1].
# [1] Pollard K. and van der Laan M., "A Method to Identify Significant Clusters in Gene Expression Data" (April 2002). U.C. Berkeley Division of Biostatistics Working Paper Series. Working Paper 107 - http://www.bepress.com/ucbbiostat/paper107)

hybrid.clus <- hopach(data=mds$points, dmat=as.matrix(dist.matrix), d="euclid", clusters="best", coll="seq");

clus.number <- hybrid.clus$clustering$k; # numero di clusters suggerito da HOPACH
clus.medoids <- hybrid.clus$clustering$medoids; # i medoids suggeriti da HOPACH (vettore di indici)

pam.hopach <- pam(as.matrix(dist.matrix), k=clus.number, diss=TRUE, medoids=clus.medoids, keep.diss=TRUE, keep.data=TRUE);
pam.hopach$clustering;
pam.hopach$clusinfo;
pam.hopach$silinfo;




x11();
par(mfrow=c(1,2));
plot(pam.sil, which.plots=1, lines=0, shade=FALSE, color=TRUE, labels=4, plotchar=FALSE, span=FALSE);
plot(pam.sil, which.plots=2);
x11();
par(mfrow=c(1,2));
plot(pam.hopach, which.plots=1, lines=0, shade=FALSE, color=TRUE, labels=4, plotchar=FALSE, span=FALSE);
plot(pam.hopach, which.plots=2);
