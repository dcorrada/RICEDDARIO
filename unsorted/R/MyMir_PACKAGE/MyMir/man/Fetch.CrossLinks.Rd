\name{Fetch.CrossLinks}
\alias{Fetch.CrossLinks}
\title{Retrieving a framework of crosslinks between RefSeq, Ensembl, GO and KEGG IDs}
\description{Constructor method for initializing objects of class \code{"CrossLinks"}; it belongs to generic function \code{"Fetch"}}
\usage{
Fetch(new("CrossLinks"), biomart = "ensembl", dataset = "mmusculus_gene_ensembl", org="mmu")
}
\arguments{
  \item{biomart}{string, BioMart database}
  \item{dataset}{string, BioMart dataset}
  \item{org}{string, organism (three letter code such as "mmu" for Mus Musculus, "hsa" for Homo Sapiens, etc.)}
}
\value{ an object of class \code{"CrossLinks"}
}
\details{
}
\examples{
mmu.xref <- Fetch(new("CrossLinks"));
}
