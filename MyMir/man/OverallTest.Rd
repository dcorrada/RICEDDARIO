\name{OverallTest}
\alias{OverallTest}
\title{Statistical association test over GO and KEGG}
\description{Performs hypergeometric and Fisher's exact tests to infer whether or not a GO term (or a KEGG pathway) is more likely to associate with genes which belong to population dataset}
\usage{
OverallTest(unipop = NULL, xref = NULL)
}
\arguments{
  \item{unipop}{mandatory, object of class \code{"UniPop"}}
  \item{xref}{object of class \code{"CrossLinks"}; if not specified \code{MyMir.CrossLinks} dataset will be loaded}
}
\value{
an object of class \code{"OverReps"}
}
\details{ All results returned have p-value <= 0.05 from hypergeometric tests. 
Statistical tests are performed using the function \code{corna.test.fun} of CORNA package.
}
\examples{
# STEP 1: obtainining a dataset which defines universe and population
unipop <- unipop.mir199.3p <- Fetch(new("UniPop"), pop.mir = "miR-199-3p", pop.limit = 1000, odbc.pw = 'foo');
# STEP 2: launching the tests
test.mir199.3p <- OverallTest(unipop.mir199.3p)
}
