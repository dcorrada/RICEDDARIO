# ANALISI DI GENI DIFFERENZIALMENTE ESPRESSI CON SAM (Significance Analysis of Microarray)


# INPUTS 3 tipi di dati:
# 1) la matrice con i dati di espressione dei soli campioni da confrontare;
# 2) un vettore numerico per identificare le due classi di campioni da confrontare contenente solo dei numeri (0 = controllo, 1 = caso);
# 3) un vettore di nomi che identificano i singoli probeset (di default vengono usati come identificativi i nomi dei probeset stessi);

# ******************************************************************************
# ALLESTIMENTO DELLA MATRICE DI ESPRESSIONE

# # *** VIA RAPIDA: leggo direttamente la matrice di espressione da GEO ***
# # PRO: scelta obbligata se non sono disponibili i CEL files...
# # CONS: chi a pubblicato i dati ha già normalizzato i dati (NON necessariamente sono espressi come LOG2 o viene adottato RMA)
# library("CORNA")
# exp.dataframe <- GEO2df.fun(file="/home/dario/Desktop/GSE/GSE2459_family.soft.gz") # leggo dal SOFT file di GEO
# # exp_dataframe <- GEO2df.fun(string="GSE2459") # stessa cosa scaricando il file direttamente da GEO
# exp.matrix <- as.matrix(exp.dataframe) # converto i dati in matrice


# *** VIA LUNGA: leggo i dati di expr grezzi proveniente dai CEL files e li nomralizzo ***
# PRO: uso un metodo di normalizzazione UNICO
# CONS: devo disporre dei CEL files
library("affy")
rawdata <- ReadAffy(celfile.path="/home/dario/Desktop/GSE/GSE6970_RAW")  # creo un oggetto Affybatch a partire da una lista di CEL files
rawdata.RMA <- rma(rawdata) # normalizzo i dati con RMA
exp.matrix <- exprs(rawdata.RMA) # estraggo la matrice di espressione

# ******************************************************************************


classes <- rep(0,ncol(exp.matrix)) # inizializzo, contando il numero di campioni
classes[1:8] <- 1 # specifico quali campioni sono i casi (in questo caso le prime otto colonne)






library("mgu74av2.db") # annotation package specifico della piattaforma da cui provengono i dati, consultare la pagina di GEO sul GSE che si sta usando
library("siggenes") # pacchetto x condurre la SAM



# creo un array in cui i campioni sono indicizzati in classi
classes <- rep(0,ncol(exp.matrix)) # inizializzo, contando il numero di campioni
classes[10:length(classes)] <- 1 # specifico quali campioni sono i casi (in questo caso dalla colonna 10 all'ultima della matrice di espressione)


# creo un dataframe in cui mappo i probeset ad altri ID interrogando biomart
probe2entrez <- unlist(mget(rownames(exp.dataframe) , mgu74av2ENTREZID)) # mappo le probe vs EntrezGeneID
probe2entrez <- data.frame(probe=names(probe2entrez), entrez=probe2entrez, stringsAsFactors=F)
probe2entrez$entrez[is.na(probe2entrez$entrez)]<-"NULL"  # sostituisco gli eventuali NA con "NULL"


sam.out <- sam(exp.matrix, classes)


# # Queste righe di codice permettono di "guardare" dentro le features di biomart x poterti creare il dataframe di annotazioni che + mi aggrada (es. l'oggetto probe2ext in questo caso)
# library(biomaRt)
# listMarts()  # elenco dei DB accessibili via biomart (arg "biomart")
# mart_obj <- useMart(biomart="ensembl"); listDatasets(mart_obj) # lista dei datasets per il DB "ensembl" (arg "dataset")
# mart_obj <- useMart(biomart="ensembl", dataset="mmusculus_gene_ensembl"); listAttributes(mart_obj) # lista di attributi disponibili (arg "col.old")
# # cerco un attributo particolare?
# attributi.df <- listAttributes(mart_obj) # salvo la lista di attributi in un dataframe
# attributi.df[grep("affy", attributi.df$description, ignore.case=T),] # cerco gli attributi che nella loro descrizione contengono "affy"
# #  la stessa cosa è applicabile x la ricerca di database e/o datasets


# per unire due dataframe sulla base di una colonna comune..
# fusione <- merge(exp.dataframe, probe2ext, by = intersect(row.names(exp.dataframe), probe2ext$probe), all.x=T)




library("affy")
rawdata <- ReadAffy(celfile.path="/home/dario/Desktop/GSE/GSE1621_RAW/48hrs")  # creo un oggetto Affybatch a partire da una lista di CEL files
rawdata.RMA <- rma(rawdata) # normalizzo i dati con RMA
exp.matrix <- exprs(rawdata.RMA) # estraggo la matrice di espressione

# creo un array in cui i campioni sono indicizzati in classi
classes <- rep(0,ncol(exp.matrix)) # inizializzo, contando il numero di campioni
classes[5:length(classes)] <- 1 # specifico quali campioni sono i casi (in questo caso dalla colonna 10 all'ultima della matrice di espressione)

sam.out <- sam(exp.matrix, classes)
as.dataframe(sum.sam.out)

