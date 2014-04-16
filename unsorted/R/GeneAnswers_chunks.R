## load library
library(GeneAnswers)

## example datasets
data('humanGeneInput') # datafame containing Entrez gene IDs with fold changes and p values
data('humanExpr') # dataframe gene expression profile of the genes in humanGeneInput

## build a GeneAnswers instance with statistical test based on biological process of GO and saved example data.
x <- geneAnswersBuilder(humanGeneInput, 'org.Hs.eg.db', categoryType='GO.BP', testType='hyperG', pvalueT=0.1, FDR.correct=TRUE, geneExpressionProfile=humanExpr)

## For Gene Ontology, some nodes are too general and not very relative to their interests. So we provide parameter level to determine how many top levels of GO nodes are removed.
w <- geneAnswersBuilder(humanGeneInput, 'org.Hs.eg.db', categoryType='GO.BP', testType='hyperG', pvalueT=0.1, FDR.correct=TRUE, geneExpressionProfile=humanExpr, level=2, verbose=FALSE) 

## build a GeneAnswers instance with statistical test based on KEGG and saved example data. 
y <- geneAnswersBuilder(humanGeneInput, 'org.Hs.eg.db', categoryType='KEGG', testType='hyperG', pvalueT=0.1, geneExpressionProfile=humanExpr, verbose=FALSE)

## build a GeneAnswers instance with statistical test based on DOLite and saved example data.
z <- geneAnswersBuilder(humanGeneInput, 'org.Hs.eg.db', categoryType='DOLite', testType='hyperG', pvalueT=0.1, FDR.correct=TRUE, geneExpressionProfile=humanExpr, verbose=FALSE)


# GeneAnswers package also provides a function (searchEntrez) to retrieve Entrez genes for given keywords by Entrez XML query. The retrieved information can be considered as a customized annotation library to test whether the given genes are relative to interested keywords. Here is a case to build a customized GeneAnswers instance.

## Mi faccio un universo custom interrogando Entrez 
keywordsList <- list(Apoptosis=c('apoptosis'), CellAdhesion=c('cell adhesion')) # lista con le chiavi di ricerca (posso usare anche espressioni + complesse con i tag e operatori booleani tipo 'zinc finger NOT 19[chr]')
entrezIDList <- searchEntrez(keywordsList, species="human") # di default searchEntrez fa una ricerca su uomo, le specie implementate sono “human”, “rat”, “mouse”, “fly”
qu <- geneAnswersBuilder(humanGeneInput, entrezIDList, testType='hyperG', totalGeneNumber = 45384, pvalueT=0.1, geneExpressionProfile=humanExpr, verbose=FALSE)


## Customized GeneAnswers instances
getAnnLib(qu) # have NULL at annLib slot (non c'è nessun file di annotazione
getCategoryType(qu) # have "User defiend" in categoryType slot (le categorie sono gli elementi definiti dalla lista creata (keywordsList in questo caso)


 

## mapping gene IDs and category IDs to gene symbols and category terms
xx <- geneAnswersReadable(x)
yy <- geneAnswersReadable(y, verbose=FALSE)
zz <- geneAnswersReadable(z, verbose=FALSE)
ww <- geneAnswersReadable(w, verbose=FALSE)



# Since function geneAnswersReadable implements conversation based on annotation database  in slot annLib, we assign 'org.Hs.eg.db' (per i dati di umano) to customized GeneAnswers instance annLib slot at first for make it readable.
qu <- setAnnLib(qu, 'org.Hs.eg.db')
qq <- geneAnswersReadable(qu, catTerm=FALSE) 


## plot barplot and / or piechart
geneAnswersChartPlots(xx, chartType='all')

## plot interactive concept-gene network
geneAnswersConceptNet(xx, colorValueColumn='foldChange', centroidSize='pvalue', output='interactive')

## plot Go-concept network for 2 level nodes removal
geneAnswersConceptNet(ww, colorValueColumn='foldChange', centroidSize='pvalue', output='fixed')

### Also, users can sort enrichment test information and plot it.
## sort enrichmentInfo dataframe by fdr adjusted p value
xxx <- geneAnswersSort(xx, sortBy='correctedPvalue')
yyy <- geneAnswersSort(yy, sortBy='pvalue') 
zzz <- geneAnswersSort(zz, sortBy='geneNum')
geneAnswersConceptNet(yyy, colorValueColumn='foldChange', centroidSize='geneNum', output='fixed')
geneAnswersConceptNet(zzz, colorValueColumn='foldChange', centroidSize='pvalue', output='fixed', showCats=c(10:16))


If users provide a gene expression profile, \Rpackage{GeneAnswers} package can generate a table or heatmap labeling relationship between genes and categories with a heatmap of these genes expression. We call this type of representation as concept-gene cross tabulation.

<<generate GO-gene cross tabulation, echo=T, eval=F>>=
## generate GO-gene cross tabulation
geneAnswersHeatmap(x, catTerm=TRUE, geneSymbol=TRUE)
@

\begin{figure}
\centering
<<fig=true, width=8, height=8, echo=T, eval=T>>=
## generate GO-gene cross tabulation
geneAnswersHeatmap(x, catTerm=TRUE, geneSymbol=TRUE)
@
\caption{GO-gene cross tabulation}
\label{fig:GO-gene cross tabulation}
\end{figure}    


<<genrate KEGG-gene cross tabulation echo=T, eval=F>>=
geneAnswersHeatmap(yyy)
@

\begin{figure}
\centering
<<fig=true, width=8, height=8, quiet=F, echo=T, eval=T>>=
geneAnswersHeatmap(yyy)
@
\caption{KEGG-gene cross tabulation}
\label{fig:KEGG-gene cross tabulation}
\end{figure}

For cross table, there are two types of representations. One is a table, which is better for few genes, and another one is a two-color heatmap that is adopted for a lot of genes. In the latter, white bar stands for that a gene belongs to that category.
<<generate DOLite-gene cross tabulation, echo=F, eval=F>>=
geneAnswersHeatmap(zzz, mapType='heatmap')
@

 
\begin{figure}
\centering
<<fig=true, width=8, height=8, quiet=T, echo=F, eval=T>>=
geneAnswersHeatmap(zzz, mapType='heatmap')
@
\caption{DOLite-gene cross tabulation}
\label{fig:DOLite-gene cross tabulation}
\end{figure}

<<generate customized GO-gene cross tabulation, echo=F, eval=F>>=
geneAnswersHeatmap(qq)
@

\begin{figure}
\centering
<<fig=true, width=8, height=8, quiet=T, echo=F, eval=T>>=
geneAnswersHeatmap(qq)
@
\caption{Customized GO-gene cross tabulation}
\label{fig: Customized GO-gene cross tabulation}
\end{figure}


Besides top categories, users can also show interested categories.
<<plot customized concept-gene cross tabulation,  echo=T, eval=T>>=  
GOBPIDs <- c("GO:0007049", "GO:0042592", "GO:0006259", "GO:0016265", "GO:0007243")
GOBPTerms <- c("cell cycle", "death", "protein kinase cascade", "homeostatic process", "DNA metabolic process") 
@

<<generate concept-gene cross tabulation,  echo=T, eval=F>>=
## generate concept-gene cross tabulation
geneAnswersConceptNet(x, colorValueColumn='foldChange', centroidSize='pvalue', output='fixed', showCats=GOBPIDs, catTerm=TRUE, geneSymbol=TRUE) 
@

\begin{figure}
\centering
\centering
\resizebox{1\textwidth}{!}{\includegraphics{conceptNet05.jpg}}
\caption{Screen shot of customized GO-gene network}
\label{customized GO-genes network}
\end{figure}

<<generate customized concept-gene cross tabulation, echo=T, eval=F>>=
geneAnswersHeatmap(x, showCats=GOBPIDs, catTerm=TRUE, geneSymbol=TRUE)
@


\begin{figure}
\centering
<<fig=true, width=8, height=8, quiet=T, echo=F, eval=T>>=
geneAnswersHeatmap(x, showCats=GOBPIDs, catTerm=TRUE, geneSymbol=TRUE)
@
\caption{Customized concept-gene cross tabulation}
\label{fig:Customized concept-gene cross tabulation}
\end{figure}

Function {\it geneAnswersConcepts} shows the linkages of specified categories. The width of edge stands for how overlapping between two categories.
<< generate concept-gene cross tabulation,  echo=T, eval=F>>=
## generate concept-gene cross tabulation
geneAnswersConcepts(xxx, centroidSize='geneNum', output='fixed', showCats=GOBPTerms) 
@

\begin{figure}
\centering
\centering
\resizebox{1\textwidth}{!}{\includegraphics{concept01.jpg}}
\caption{Screen shot of customized GO category linkage}
\label{customized GO category linkage}
\end{figure}



Users can also print top categories and genes on screen and save them in files by specification as well as these two types of visualization. The default file names are "topCategory.txt" and "topCategoryGenes.txt" for top categories with or without corresponding genes, respectively.
<<print top categories and genes,  echo=T, eval=T>>=  
## print top GO categories sorted by hypergeometric test p value
topGOGenes(x,  orderby='pvalue')
## print top KEGG categories sorted by gene numbers and sort genes by fold changes 
topPATHGenes(y, orderby='geneNum', top=4, topGenes=8, genesOrderBy='foldChange')
## print and save top 10 DOLites information 
topDOLiteGenes(z, orderby='pvalue', top=5, topGenes='ALL', genesOrderBy='pValue', file=TRUE)
@

\subsection{Homologous Gene Mapping}
Since DOLite is developed for human, any genes from other species can not take advantage of this novel annotation database. Therefore,  \Rpackage{GeneAnswers} package provides two functions for this type of data interpretation. {\it getHomoGeneIDs} can map other species gene Entrez IDs to human homologous gene Entrez IDs at first. Then users can perform normal GeneAnswers functions. Finally, function {\it geneAnswersHomoMapping} maps back to original species gene Entrez IDs. Current version supports two types of homologous gene mapping. One is called "direct", which is simple and only works between mouse and human. Since all of human gene symbols are capitalized, while only first letter of mouse homologous gene symbols is uppercase, this method simply maps homologous genes by capitalized moues gene symbols. Another method adopts \Rpackage{biomaRt}, a BioConductor package, to do mapping. \Rpackage{biomaRt} contacts its online server to mapping homologous genes. Its database include more accurate information, but it might take longer to do that, while 'direct' method can rapidly do conversation though it is possible to miss some information.

<<homogene conversation,  echo=T, eval=T>>=  
 ## load mouse example data
data('mouseExpr')
data('mouseGeneInput') 
mouseExpr[1:10,]
mouseGeneInput[1:10,]
 ## only keep first one for one to more mapping
pickHomo <- function(element, inputV) {return(names(inputV[inputV == element])[1])}
 ## mapping geneInput to homo entrez IDs.
homoLL <- getHomoGeneIDs(mouseGeneInput[,1], species='mouse', speciesL='human', mappingMethod='direct')
newGeneInput <- mouseGeneInput[mouseGeneInput[,1] %in% unlist(lapply(unique(homoLL), pickHomo, homoLL)),]
dim(mouseGeneInput)
dim(newGeneInput)
newGeneInput[,1] <- homoLL[newGeneInput[,1]]
## mapping geneExpr to homo entrez IDs.
homoLLExpr <- getHomoGeneIDs(as.character(mouseExpr[,1]), species='mouse', speciesL='human', mappingMethod='direct')
newExpr <- mouseExpr[as.character(mouseExpr[,1]) %in% unlist(lapply(unique(homoLLExpr) , pickHomo, homoLLExpr)),]
newExpr[,1] <- homoLLExpr[as.character(newExpr[,1])]
dim(mouseExpr)
dim(newExpr)
## build a GeneAnswers instance based on mapped data
v <- geneAnswersBuilder(newGeneInput, 'org.Hs.eg.db', categoryType='DOLite', testType='hyperG', pvalueT=0.1, FDR.correct=TRUE, geneExpressionProfile=newExpr)
## make the GeneAnswers instance readable, only map DOLite IDs to terms
vv <- geneAnswersReadable(v, geneSymbol=F)
getAnnLib(vv)
## mapping back to mouse genes
uu <- geneAnswersHomoMapping(vv, species='human', speciesL='mouse', mappingMethod='direct')
getAnnLib(uu)
## make mapped genes readable, DOLite terms are not mapped
u <- geneAnswersReadable(uu, catTerm=FALSE)
## sort new GeneAnswers instance
u1 <- geneAnswersSort(u, sortBy='pvalue')
@

<<plot concept-gene network,  echo=T, eval=F>>=
## plot concept-gene network
geneAnswersConceptNet(u, colorValueColumn='foldChange', centroidSize='pvalue', output='fixed')
@

\begin{figure}
\centering
\centering
\resizebox{1\textwidth}{!}{\includegraphics{conceptNet06.jpg}}
\caption{Screen shot of homogene DOLite-gene network}
\label{homogene DOLite-genes network}
\end{figure}

<<generate homogene DOLite-gene cross tabulation, echo=T, eval=F>>=
## plot homogene DOLite-gene cross tabulation
geneAnswersHeatmap(u1)
@

\begin{figure}
\centering
<<fig=true, width=8, height=8, quiet=T, echo=F, eval=T>>=
## plot homogene DOLite-gene cross tabulation
geneAnswersHeatmap(u1)
@
\caption{homogene DOLite-gene cross tabulation}
\label{fig:homogene DOLite-gene cross tabulation}
\end{figure}

<<homogene conversation,  echo=T, eval=T>>=  
## output top information
topDOLiteGenes(u, geneSymbol=FALSE, catTerm=FALSE, orderby='pvalue', top=6, topGenes='ALL', genesOrderBy='pValue', file=TRUE)  
@

\section{Session Info}
<<sessionInfo, results=tex, print=TRUE>>=
toLatex(sessionInfo())
@

\section{Acknowledgments}
We would like to thanks the users and researchers around the world contribute to the lumi package, provide great comments and suggestions and report bugs

\section{References}

Du, P., Feng, G., Flatow, J., Song, J., Holko, M., Kibbe, W.A. and Lin, S.M., (2009) 'From disease ontology to disease-ontology lite: statistical methods to adapt a general-purpose ontology for the test of gene-ontology associations', Bioinformatics 25(12):i63-8

Feng, G., Du, P., Krett, N.L., Tessel, M., Rosen, S., Kibbe, W.A., and Lin, S.M., (submitted) 'Bioconductor Methods to Visualize Gene-list Annotations',

%\bibliographystyle{plainnat}
%\bibliography{GeneAnswers}


\end{document} 


