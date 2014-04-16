\name{Dist.Heatmap}
\alias{Dist.Heatmap}
\title{Distance Matrix Heatmap}
\description{ This function takes as input an object of class \code{Clusterama} and plot an heatmap representing distances related to semantic similarity values among overrepresented GO terms. Colors range from maximum similarity (blue) to maximum dissimilarity (red).
}
\usage{
Dist.Heatmap(clusterama = clusterama.object, x11.out=TRUE, ps.out=TRUE, ...)
}
\arguments{
  \item{clusterama}{an object of class \code{Clusterama}}
  \item{x11.out,ps.out}{logical, switch graphical devices for drawing the heatmap}
  \item{...}{all optional arguments available for the \code{\link{postscript} function}}
}
\value{
}
\details{
}
\seealso{
\code{\link{heatmap}}
}
\examples{
clusterama.obj <- Dist.Heatmap(clusterama.obj, ps.out=FALSE)
}
