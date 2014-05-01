\name{UniPop-class}
\docType{class}
\alias{UniPop-class}
\alias{Ensembl,UniPop-method}
\alias{Fetch,UniPop-method}

\title{Class "UniPop"}
\description{Dataset structure containing "universe" and "population" geneset}
\section{Slots}{
	 \describe{
    \item{\code{population.data}:}{object of class \code{"Population.df"} }
    \item{\code{population.ensembl.gene}:}{object of class \code{"character"}: character vector, Ensembl gene IDs for the "population" dataset }
    \item{\code{population.ensembl.trans}:}{object of class \code{"character"}: character vector, Ensembl transcript IDs for the "population" dataset }
    \item{\code{population.query}:}{object of class \code{"character"}: string defining SQL statement for retrieving "population" dataset }
    \item{\code{universe.data}:}{object of class \code{"Universe.df"} }
    \item{\code{universe.ensembl.gene}:}{object of class \code{"character"}: character vector, Ensembl gene IDs for the "universe" dataset }
    \item{\code{universe.ensembl.trans}:}{object of class \code{"character"}: character vector, Ensembl transcript IDs for the "universe" dataset }
    \item{\code{universe.query}:}{object of class \code{"character"}: string defining SQL statement for retrieving "universe" dataset }
  }
}
\section{Methods}{
  \describe{
    \item{\code{Ensembl}:}{updating object for slots \code{[population|universe].ensembl.[gene|trans]} }
    \item{\code{Fetch}:}{constructor method, see details on usage at \code{\link{Fetch.UniPop}} }
	 }
}
\examples{
showClass("UniPop")
}
\keyword{classes}
