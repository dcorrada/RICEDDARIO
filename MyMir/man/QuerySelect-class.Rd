\name{QuerySelect-class}
\docType{class}
\alias{QuerySelect-class}
\alias{CoalesceQuery,QuerySelect-method}

\title{Class "QuerySelect"}
\description{A data structure for building an SQL statement such as "SELECT ..."}
\section{Slots}{
	 \describe{
    \item{\code{statement}:}{object of class \code{"character"}: string, the final SQL statement}
    \item{\code{structure}:}{object of class \code{"SQL.list"}}
  }
}
\section{Methods}{
  \describe{
    \item{\code{CoalesceQuery}:}{parse an object of class \code{"SQL.list"} and update the slot \code{statement}}
	 }
}
\seealso{
    \code{\link{QueryBuild.Population}},    \code{\link{QueryBuild.Universe}}
}
\examples{
showClass("QuerySelect")

# STEP 1: creating an object of class <QuerySelect>
object <- new("QuerySelect")
# STEP 2: assemblying the query statement
object <- CoalesceQuery(object)
}
\keyword{classes}
