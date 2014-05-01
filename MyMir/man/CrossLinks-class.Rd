\name{CrossLinks-class}
\docType{class}
\alias{CrossLinks-class}
\alias{Fetch,CrossLinks-method}

\title{Class "CrossLinks"}
\description{Dataset structure containing crosslinks}
\section{Slots}{
	 \describe{
    \item{\code{BioMart}:}{object of class \code{"BioMart.list"} }
    \item{\code{Gene2Path}:}{object of class \code{"Gene2Path.df"} }
    \item{\code{GO2Term}:}{object of class \code{"GO2Term.df"} }
    \item{\code{RefSeq2Ensembl}:}{object of class \code{"RefSeq2Ensembl.list"} }
    \item{\code{Trans2GO}:}{object of class \code{"Trans2GO.list"} }
  }
}
\section{Methods}{
  \describe{
    \item{\code{Fetch}:}{constructor method, see details on usage at \code{\link{Fetch.CrossLinks}} }
	 }
}
\examples{
showClass("CrossLinks")
}
\keyword{classes}
