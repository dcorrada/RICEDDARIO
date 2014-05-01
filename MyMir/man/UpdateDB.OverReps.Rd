\name{UpdateDB.OverReps}
\alias{UpdateDB.OverReps}
\title{Upload association test results on database}
\description{This method parses an object of class \code{"OverReps"}; it coerce each slot into dataframes and upload them as separated table on the DB
}
\usage{
UpdateDB.OverReps(object, tablename = NULL)
}
\arguments{
  \item{object}{mandatory, object of class \code{"OverReps"}}
  \item{tablename}{mandatory, string, name (prefix) of the tables that will be uploaded; see Details}
}
\value{
}
\details{ This method will create tables named by a common prefix plus a suffix 
which defines the single component of \code{overall.test} dataset 
(e.g.: "mir214_GObp", "mir214_KEGG", etc.).
}
\examples{
# STEP 1:  Creating a dataset for universe and population
unipop.mir199.3p <- Fetch(new("UniPop"), pop.mir = "miR-199-3p" odbc.pw = 'foo')
# STEP 2:  Testing the dataset
test.mir199.3p <- OverallTest(unipop.mir199.3p)
# STEP 3: Upload the results
UpdateDB(test.mir199.3p, tablename='mir199.3p')
}
