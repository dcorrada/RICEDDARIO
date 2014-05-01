\name{Clusterama}
\alias{Clusterama}
\title{Cluster Analysis from Overrepresented GO Terms}
\description{ This function is a constructor method for initializing objects of class \code{Clusterama}. Clusterama would be a mini-pipeline for sequentially filling the various slots of a \code{Clusterama} object; see "Details" to know how this function perform the analysis.
}
\usage{
Clusterama(pop.acc = FALSE, pop.orth = FALSE, sub.ont = NULL, ...)
}
\arguments{
  \item{pop.acc}{accessibility option, boolean; see Details}
  \item{pop.orth}{orthologue option, boolean;  see Details}
  \item{sub.ont}{string, a subontology among "MF", "BP", and "CC"}
  \item{...}{all optional arguments available for the \code{\link{SemanticSimilarity}} function}
}
\value{ An object of class \code{Clusterama}
}
\details{
This function fill of data an object of class \code{Clusterama} through several steps:\cr
\itemize{
    \item{ }{building a distance matrix based on semantic similarity values (see \code{\link{SemanticSimilarity}})}
    \item{ }{performing a multidimensional scaling from the distance matrix (see \code{\link{MDS}})}
    \item{ }{estimating the number of clusters (see \code{\link{Hopach.Run}})}
    \item{ }{partitional clustering (see \code{\link{Partitional.Clustering}})}
    \item{ }{summarize the results (see \code{\link{Cluster.Dataframes}})}
}
}
\seealso{
\code{\link{Clusterama-class}}
}
\examples{
# STEP 1:  Create and init a new object of class <Clusterama>
clusterama <- Clusterama (pop.acc = TRUE, pop.orth = TRUE, sub.ont = 'mf')

# STEP 2:  Print an heatmap of the calculated distance matrix
Dist.Heatmap (clusterama, x11.out=FALSE, ps.out=TRUE, file="heatmap.ps")

# STEP 3: Print a silhouette plot of the clusters obtained
Partitional.Clustering (clusterama, x11.out=FALSE, ps.out=TRUE, file="silhouette_plot.ps")

# STEP 4: Print to CSV file the results summary
write.table(clusterama@summaries$clusters, file="clusters.csv", quote=TRUE, sep=';', row.names=FALSE, col.names=TRUE);
write.table(clusterama@summaries$obs, file="obs.csv", quote=TRUE, sep=';', row.names=FALSE, col.names=TRUE);
write.table(clusterama@summaries$target, file="target.csv", quote=TRUE, sep=';', row.names=FALSE, col.names=TRUE);

# STEP 5: Update to DB the summaries
UpdateDB(clusterama)
}