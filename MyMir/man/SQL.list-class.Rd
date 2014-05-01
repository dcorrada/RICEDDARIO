\name{SQL.list-class}
\docType{class}
\alias{SQL.list-class}

\title{Class "SQL.list"}
\description{Primitive Class - list of single blocks which define a generic SQL statement}
\section{Slots}{
	 \describe{
    \item{\code{s1}:}{object of class \code{"list"} 
    contains character vector which represent a single block; e.g.: the component \code{"select"} will be defined as c("SELECT", "field1 AS f1", "field2 AS f2"), the component \code{"join"} will be defined as c("JOIN", "tableB", "ON", "foo = bar")}
  }
}
\section{Methods}{
No methods defined with class "SQL.list" in the signature.
}
\examples{
showClass("SQL.list")
}
\keyword{classes}
