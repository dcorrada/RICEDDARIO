\name{Clusterama-class}
\docType{class}
\alias{Clusterama-class}
\alias{UpdateDB,Clusterama-method}

\title{Class "Clusterama"}
\description{Dataset structure for cluster analysis}
\section{Slots}{
	 \describe{
    \item{\code{data}:}{source dataset info. It is a list containing three string describing: on which sub-ontology \code{SemanticSimilarity} function is applied; if target list is filtered for accessibility; if target list is filtered for orthology.}
    \item{\code{dist}:}{info about distance matrix. Distances relies on semantic similarities among GO term pairs; distance values range from 0, perfect similarity (identical GO terms), to 1, maximum dissimilarity. The component of this slot are distance matrix; the number of observations found from the dataset; the names of each observation}
    \item{\code{mds}:}{info about multidimensional scaling (MDS). MDS is a set of related statistical techniques often used in information visualization for exploring similarities or dissimilarities in data; an MDS algorithm starts with a matrix of item–item similarities, then assigns a location to each item in N-dimensional space.}
    \item{\code{pam}:}{info about partitional clustering, see more details on \code{\link{pam.object}}}
    \item{\code{summaries}:}{three summary dataframes from Clusterama computations: info about clusters; info about observation of each clusters; info about target which belong to observed GO terms}
  }
}
\section{Methods}{
  \describe{
    \item{\code{Clusterama}:}{constructor method, see details on usage at \code{\link{Clusterama}} }
	 }
}
\examples{
showClass("Clusterama")
}
\keyword{classes}
