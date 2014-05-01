\name{OverReps-class}
\docType{class}
\alias{OverReps-class}
\alias{UpdateDB,OverReps-method}

\title{Class "OverReps"}
\description{Dataset structure for collecting all \code{corna.test.fun} outputs dealing with all GO terms and KEGG pathways}
\section{Slots}{
	 \describe{
    \item{\code{KEGG}:}{object of class \code{"CornaOut.df"} }
    \item{\code{GObp}:}{object of class \code{"CornaOut.df"} }
    \item{\code{GOcc}:}{object of class \code{"CornaOut.df"} }
    \item{\code{GOmf}:}{object of class \code{"CornaOut.df"} }
  }
}
\section{Methods}{
  \describe{
    \item{\code{UpdateDB}:}{update the contents of the object separated tables on the DB; see documentation about \code{\link{UpdateDB.OverReps}} function}
	 }
}
\examples{
showClass("OverReps")
}
\keyword{classes}
