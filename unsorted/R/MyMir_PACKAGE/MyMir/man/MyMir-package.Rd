\name{MyMir-package}
\alias{MyMir-package}
\alias{MyMir}
\docType{package}
\title{
A functional analysis of a pool microRNA target genes
}
\description{
MyMir is a package with functions for collecting miRNA target from a defined database and find statistically over-represented target/functional annotation relationships.\cr
Over-represented ontologies can also be clustered together by applying the semantic similarity criterion. This package allows to perform a partitional clustering procedure in order to highlight the most similar over-represented
}
\details{
\tabular{ll}{
Package: \tab MyMir\cr
Type: \tab Package\cr
Version: \tab 2.10-05\cr
Date: \tab 2010-05-02\cr
Depends: \tab CORNA, GOSemSim, methods, RODBC, RMySQL\cr
License: \tab GPL-2\cr
}
Prior to apply \code{mymir} functions you must have installed MySQL ODBC driver. \emph{Be sure that the package \bold{libmyodbc} is installed  (e.g. for Ubuntu platforms). You also have to configure a Domain Source Name (DSN) to access to our database.}\cr
Please contact the mantainer for:\cr
\itemize{
    \item{ }{having an account to our database;}
    \item{ }{howto configure a DSN;}
    \item{ }{info about data stored on our database.}
}
}
\author{
Dario Corrada

Maintainer: Dario Corrada <dario.corrada@itb.cnr.it>
}
\keyword{ package }
\examples{
# # STEP 0: calling the package
library(MyMir);

# # STEP 1:  Querying the database and creating a dataset for universe and population
unipop.mir199.3p <- Fetch(new("UniPop"), pop.mir = "miR-199-3p", pop.limit = 1000);

# # STEP 3:  Testing the dataset for over-represented metabolic pathways and GO terms
test.mir199.3p <- OverallTest(unipop.mir199.3p);

# # STEP 3a: looking inside the results...
str(test.mir199.3p, max.level=4)
# Formal class 'OverReps' [package "MyMir"] with 4 slots
#   ..@ KEGG:Formal class 'CornaOut.df' [package "MyMir"] with 1 slots
#   .. .. ..@ s1:'data.frame':    8 obs. of  6 variables:
#   ..@ GObp:Formal class 'CornaOut.df' [package "MyMir"] with 1 slots
#   .. .. ..@ s1:'data.frame':    44 obs. of  6 variables:
#   ..@ GOcc:Formal class 'CornaOut.df' [package "MyMir"] with 1 slots
#   .. .. ..@ s1:'data.frame':    13 obs. of  6 variables:
#   ..@ GOmf:Formal class 'CornaOut.df' [package "MyMir"] with 1 slots
#   .. .. ..@ s1:'data.frame':    17 obs. of  6 variables:
#
# we find over-represented categories at significant level, both among GO terms and among KEGG pathways

test.mir199.3p@KEGG # an object of class “CornaOut.df”
# Slot "s1":
#       total expectation observation hypergeometric       fisher            description
# 04150    48           3          10   0.0003759513 0.0003759513 mTOR signaling pathway
# 05200   303          18          29   0.0061286172 0.0088259072     Pathways in cancer
# 05213    49           3           8   0.0069858155 0.0069858155     Endometrial cancer
# 00310    39           2           6   0.0243701314 0.0243701314     Lysine degradation
# 03040   113           7          12   0.0320820524 0.0408874916            Spliceosome
# 05218    66           4           8   0.0375508032 0.0562972922               Melanoma
# 04510   183          11          17   0.0392435984 0.0551710214         Focal adhesion
# 03018    55           3           7   0.0398766661 0.0398766661        RNA degradation
#
# the evaluation of selected KEGG pathways highlights involvement in cancer;
# we want to know which predicted targets belong to these categories...

# # STEP 4: creating a panel of term IDs (referred to "Pathways in cancer", "Endometrial cancer", "Melanoma")
black.list <- c("05200", "05213", "05218")

# # STEP 5: searching the targets
black.targets <- Term2Target(population = unipop.mir199.3p, term.list = black.list, term.type = "KEGG");

head(black.targets) # an example of the output
#        refseqID geneID symbol  rank                                      gene.desc          ensemblID termID          term.desc
# 26    NM_009733  12005  Axin1 1.000                                         axin 1 ENSMUSG00000024182  05200 Pathways in cancer
# 40    NM_145221  72993  Appl1 0.874                                    DIP13 alpha ENSMUSG00000040760  05200 Pathways in cancer
# 5  NM_001033369 269275 Acvr1c 0.863                    activin A receptor, type IC ENSMUSG00000026834  05200 Pathways in cancer
# 7     NM_007462  11789    Apc 0.767                    adenomatosis polyposis coli ENSMUSG00000005871  05200 Pathways in cancer
# 33    NM_029094  74769 Pik3cb 0.708 phosphatidylinositol 3-kinase, catalytic, beta ENSMUSG00000032462  05200 Pathways in cancer
# 4  NM_001033238 208650   Cblb 0.587                   Casitas B-lineage lymphoma b ENSMUSG00000022637  05200 Pathways in cancer

my.subset <- subset(black.targets, term.desc != "Pathways in cancer");
unique(my.subset$gene.desc[duplicated(my.subset$gene.desc)]);
# [1] "phosphatidylinositol 3-kinase, catalytic, beta" "phosphatase and tensin homolog"                 "phosphatidylinositol 3-kinase, regulatory"
# [4] "mitogen activated protein kinase kinase 1"      "protein kinase raf 1"
#
# a list of predicted targets which belongs both in the "Melanoma" and in the "Endometrial cancer" KEGG pathways

# # STEP 6: upload your results on DB
UpdateDB(test.mir199.3p, tablename='mir199.3p')
}
