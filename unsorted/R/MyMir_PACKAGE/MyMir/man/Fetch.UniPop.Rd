\name{Fetch.UniPop}
\alias{Fetch.UniPop}
\title{Input Raw Data for Universe and Population Dataset}
\description{Constructor method for initializing objects of class \code{"UniPop"}; it belongs to generic function \code{"Fetch"}}
\usage{
Fetch(new("UniPop"), uni.mir = "all", pop.mir = NULL, pop.acc = FALSE, pop.orth = FALSE, pop.limit = 100)
}
\arguments{
  \item{uni.mir}{string identifier for "universe" dataset; it defines the miRNA from which the predicted target genes originate. When parameter is defined as \kbd{"all"}  (default) it means that "universe" is considered as whole genome non redundant transcripts.}
  \item{pop.mir}{mandatory, string identifier for "population" dataset.}
  \item{pop.acc}{accessibility option, boolean; see documentation 
    about \code{QueryBuild.Population} function}
  \item{pop.orth}{orthologue option, boolean; see documentation 
    about \code{QueryBuild.Population} function}
  \item{pop.limit}{integer, sample size of population dataset}
}
\value{ an object of class \code{"UniPop"}
}
\details{ In this version of the package ONLY if you define the parameter \kbd{uni.mir = "all"} 
the function will load and integrate \code{\link{universe.mm9}} dataset in the output.\cr
Removing "if" constructs (lines like \kbd{if (uni.mir == "all") ...}) in the source code will launch \code{QueryBuild.Universe} SQL statement as well.
}
\examples{
unipop.mir199.3p <- Fetch(new("UniPop"), pop.mir = "miR-199-3p", pop.limit = 1000);
}
