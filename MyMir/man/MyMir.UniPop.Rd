\name{MyMir.UniPop}
\alias{MyMir.UniPop}
\docType{data}
\title{Dataset of Universe and Population}
\description{
Dataset containing "universe" and "population" geneset obtained by target prediction of miRNA "mmu-mir-199-3p" against Mus Musculus whole genome 3'-UTRs [assembly NCBI m37 (mm9)]
}
\usage{data(MyMir.UniPop)}
\format{
object of class \code{"UniPop"}
}
\details{
This dataset is an example obtained from the following example:
}
\examples{
MyMir.UniPop <- Fetch(new("UniPop"), pop.mir = "miR-199-3p", pop.limit = 1000)
}
\keyword{datasets}
