\name{Term2Target}
\alias{Term2Target}
\title{Finding predicted target genes grouped by GO or KEGG terms}
\description{Assuming a list of GO (or KEGG) terms, this function retrieve all 
predicted target genes which belong to each term. }
\usage{
Term2Target(population = NULL, term.list = NULL, term.type = "GOmf", xref = NULL)
}
\arguments{
  \item{population}{mandatory, universe/population dataset,obtained by applying 
    the function \code{\link{Fetch.UniPop}} }
  \item{term.list}{mandatory, character vector listing every terms of interest}
  \item{term.type}{string, defines the kind of \code{term.list} belongs ("KEGG" 
    for metabolic pathways, "GObp" for GO Biological Process, "GOcc" for GO Cellular 
    Components, "GOmf" for GO Molecular Function)}
  \item{xref}{object of class \code{"CrossLinks"}; if not specified \code{MyMir.CrossLinks} dataset will be loaded}
}
\value{ A dataframe containing 8 variables:
  \item{$ refseqID}{RefSeq identifiers}
  \item{$ geneID}{EntrezGene identifiers}
  \item{$ symbol}{GeneSymbol according to MGI}
  \item{$ rank}{target prediction rank score according to <targets_ranks> table of mymir DB}
  \item{$ gene.desc}{text describing target gene}
  \item{$ ensemblID}{Ensembl identifier}
  \item{$ termID}{term identifier, according to GO or KEGG}
  \item{$ term.desc}{term}
}