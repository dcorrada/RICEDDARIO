\name{Partitional Clustering}
\alias{Partitional Clustering}
\title{Partitional Clustering}
\description{ This function takes as input an object of class \code{Clusterama} and performs a partitional clustering among all the observation found (overrepresented GO terms in the package context). It updates the slot \code{pam} of an object of class \code{Clusterama} and optionally returns a 'silhouette plot' of the results (see 'Details').
}
\usage{
Partitional.Clustering(clusterama = clusterama.object, x11.out=TRUE, ps.out=TRUE, ...)
}
\arguments{
  \item{clusterama}{an object of class \code{Clusterama}}
  \item{x11.out,ps.out}{logical, switch graphical devices for drawing 'silhouette plot'}
  \item{...}{all optional arguments available for the \code{\link{postscript} function}}
}
\value{ An object of class \code{Clusterama}
}
\details{
A 'silhouette plot' is a barplot; for each observation i, a bar is drawn, representing its silhouette width s(i). Observations are grouped per cluster.
}
\seealso{
\code{\link{pam}} \code{\link{pam.object}} \code{\link{plot.partition}}
}
\examples{
clusterama.obj <- Partitional.Clustering(clusterama.obj, ps.out=FALSE)
}
