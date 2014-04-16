\name{Hopach.Run}
\alias{Hopach.Run}
\title{Estimating the Optimal Number of Clusters}
\description{ This function takes as input an object of class \code{Clusterama} and performs an HOPACH clustering in order to find the optimal value 'k' for a partitional clustering procedure; this function also looks for the putative initial medoids from all the observation found (overrepresented GO terms in the package context). It updates the slot \code{pam} of an object of class \code{Clusterama}.
}
\usage{
Hopach.Run(clusterama = clusterama.object)
}
\arguments{
  \item{clusterama}{an object of class \code{Clusterama}}
}
\value{ An object of class \code{Clusterama}
}
\details{
}
\seealso{
\code{\link{hopach}}
}
\examples{
clusterama.obj <- Hopach.Run(clusterama.obj)
}
