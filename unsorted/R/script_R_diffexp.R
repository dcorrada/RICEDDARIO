library(Biobase)
library(GEOquery)
library(gcrma)
library(affy)
library(affydata)
library(genefilter)
library(multtest)
library(annotate)
library(mgu74av2.db)
# library(mgu74a.db)
# library(hgu133a.db)


# source("http://bioconductor.org/biocLite.R")
# biocLite("mgu74a.db")

path<-"/home/dario/Desktop/GSE1621_RAW"
# path<-"/home/dario/Desktop/GSE76_RAW"
# path<-"/home/dario/Desktop/GSE8401_RAW"
max<-26
# max<-36
# max<-83
v<-c(1:4,9:12,17:20)
# v<-c(1:18)
# v<-c(1:31)


data<-ReadAffy(celfile.path=path)
normalized<-gcrma(data)
normalized<-normalized[,1:max]
getSymbols<-function(x)(getSYMBOL(x,"mgu74av2"))
# getSymbols<-function(x)(getSYMBOL(x,"mgu74a"))
# getSymbols<-function(x)(getSYMBOL(x,"hgu133a"))
cl<-matrix(nrow=max);cl[]<-0;cl[v]<-1;cl<-as.numeric(cl)
f1<-pOverA(0.25,log2(100))
f2<-function(x)(IQR(x)>0.5)
ff<-filterfun(f1,f2)
selected<-genefilter(normalized,ff)
subset<-normalized[selected,]
resT<-mt.maxT(exprs(subset), classlabel=cl, B=10000)
ord<-order(resT$index)
rawp<-resT$rawp[ord]
names(rawp)<-geneNames(subset)
res<-mt.rawp2adjp(rawp, proc="BH")
sum(res$adjp[, "BH"]<0.05)
sigProbes<-names(rawp)[1:sum(res$adjp[,"BH"]<0.05)]
sigSymbols<-sort(as.character(unlist(lapply(sigProbes,getSymbols))))
outPath<-paste(path, "sigSymbols", sep="")
write.table(sigSymbols, file=outPath, quote=F, row.names=F, col.names=F)
