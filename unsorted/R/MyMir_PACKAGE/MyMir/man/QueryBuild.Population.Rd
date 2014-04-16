\name{QueryBuild.Population}
\alias{QueryBuild.Population}
\alias{QueryBuild.Universe}
\title{Query List Object Builder}
\description{
Creates objects of class\code{"QuerySelect"} for retrieving "universe" and "population" datasets
}
\usage{
QueryBuild.Population(mir = NULL, acc = FALSE, orth = FALSE)
QueryBuild.Universe(mir = "all")
}
\arguments{
  \item{mir}{string that defines the miRNA from which the predicted target genes originate; defining is mandatory in \code{QueryBuild.Population} function. See details for \code{QueryBuild.Universe} }
  \item{acc}{only for \code{QueryBuild.Population} function. If TRUE specifies to select target genes whose results accessible, according to PITA predictions}
  \item{orth}{only for \code{QueryBuild.Population} function. If TRUE specifies to select target genes whose there is an orthologue miR/target interaction in human, according to TargetScan predictions}
}
\details{
In \code{QueryBuild.Universe} function when \kbd{mir} parameter is defined as \kbd{"all"} it means that universe is considered as whole genome non redundant transcripts.
}
\value{
Object of class \code{"QuerySelect"}
}
\examples{
# building an SQL query for universe dataset
uni.mir = "all"
uni.query <- QueryBuild.Universe (uni.mir)

# building an SQL query for population dataset
pop.mir = "miR-199-5p"
pop.query <- QueryBuild.Population (pop.mir, acc = TRUE, orth = FALSE)
}
