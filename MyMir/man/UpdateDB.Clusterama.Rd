\name{UpdateDB.Clusterama}
\alias{UpdateDB.Clusterama}
\title{Upload cluster analysis results on database}
\description{This method parses an object of class \code{Clusterama}; the function looks for slot \code{summaries} and upload each dataframe as separated table on the DB
}
\usage{
UpdateDB.Clusterama(object)
}
\arguments{
  \item{object}{mandatory, object of class \code{Clusterama}}
}
\value{
}
\details{ This method will create tables named by three kind of tags:\cr
[sub.ontology] -> sub ontology type (BP, CC o MF)\cr
[filters] -> two logicals defining which filter (accessibility and/or orthology) were applied onto the original dataset\cr
["cluster"|"obs"|"target"] -> the name of the three dataframes contained in the slot \code{summaries} of an object of class \code{Clusterama}\cr\cr
A typical tablename would be such as "MF_TRUE_FALSE_obs", a table obtained from a "obs" dataframe; cluster analysis was performed on GO Molecular Function overrepresented term; the original dataset was obtained from target filtered out for accessibility but not for orthology.
}
\examples{
# STEP 1:  Performing a cluster analysis
clusterama <- Clusterama (pop.acc = TRUE, pop.orth = TRUE, sub.ont = 'mf')
# STEP 2: Upload the results
UpdateDB(clusterama)
}
