\name{SemanticSimilarity}
\alias{SemanticSimilarity}
\title{Building Semantic Similarity Matrix}
\description{ This function calculates a semantic similarity score for each couple of GO terms which belong to a previous defined list; the list of GO terms is automatically obtained by parsing the tables on DB stored for association test results (see Details)
}
\usage{
SemanticSimilarity(organism = "mouse", pop.acc = FALSE, pop.orth = FALSE, semsim.algorithm = "Wang", sub.ont = NULL,)
}
\arguments{
  \item{organism}{string, an organism; \code{GOSemSim} package is currently
    implemented for "human", "rat", "mouse", "fly" and "yeast"}
  \item{pop.acc}{accessibility option, boolean; see Details}
  \item{pop.orth}{orthologue option, boolean;  see Details}
  \item{semsim.algorithm}{string, semantic similarity algorithm among "Resnik",
    "Lin", "Rel", "Jiang" and "Wang"; for more details about algorithms
    see \code{GOSemSim} documentation}
  \item{sub.ont}{string, a subontology among "MF", "BP", and "CC"}
}
\value{ A symmetric matrix which contains semantic similarity scores for each couple of GO terms
}
\details{ In order to correctly run this function the DB table names must follow 
a well defined nomenclature. Table names should be composed by an arbitrary 
prefix which describe the source of data plus a suffix which define the 
sub-ontology involved ("_GObp", "_GOcc" or "_GOmf"). Tipical table names are 
like "mir214_GObp" or "mmu_miR_161_GOmf".

Tables which come from accessible and/or orthologous target population must 
have a further optional suffix like "_acc" and/or "_orth" 
(e.g.: "miR_199_3p_acc_GObp", "miR_199_5p_acc_orth_GOmf"). For more details 
about definition of \code{pop.acc} and \code{pop.orth} see also 
\code{\link{QueryBuild.Population}}
}
\seealso{
\code{\link{goSim}}
}
\examples{
semsim.matrix <- SemanticSimilarity(sub.ont = 'mf'); 
}
