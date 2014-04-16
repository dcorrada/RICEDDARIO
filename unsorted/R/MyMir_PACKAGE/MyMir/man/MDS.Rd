\name{MDS}
\alias{MDS}
\title{Classical Multidimensional Scaling}
\description{ This function parse an object of class \code{Clusterama} and takes as input the distance matrix computed on semantic similarity score among a list of GO terms. It outputs a coordinate matrix whose configuration minimizes a loss function called strain [1], updating the slot \code{mds} of the object of class \code{Clusterama}.\cr
[1] Borg, I. and Groenen, P.: "Modern Multidimensional Scaling: theory and applications" (2nd ed.), Springer-Verlag New York, 2005
}
\usage{
MDS(clusterama = clusterama.object)
}
\arguments{
  \item{clusterama}{an object of class \code{Clusterama}}
}
\value{ An object of class \code{Clusterama}
}
\details{
}
\seealso{
\code{\link{cmdscale}}
}
\examples{
clusterama.obj <- MDS(clusterama.obj)
}
