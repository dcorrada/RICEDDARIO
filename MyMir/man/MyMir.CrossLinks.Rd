\name{MyMir.CrossLinks}
\alias{MyMir.CrossLinks}
\docType{data}
\title{Crosslinks framework for Mus Musculus}
\description{
object of class \code{"CrossLinks"} dealing with Mus Musculus genome [assembly NCBI m37 (mm9)]
}
\usage{data(MyMir.CrossLinks)}
\format{
object of class \code{"CrossLinks"}
}
\details{
This dataset is an example obtained from the following example:
}
\examples{
MyMir.CrossLinks <- Fetch(new("CrossLinks"), biomart = "ensembl", dataset = "mmusculus_gene_ensembl", org="mmu")
}
\keyword{datasets}