## <classes.R> contenitore di classi, funzioni generiche e metodi

## CLASSI PRIMITIVE
# derivano da singole classi default di R
# 
# NOMENCLATURA:
# A) il nome di una classe primitiva è composto di un suffisso che identifica la classe che viene estesa (es.: "pippo.df" pippo estende un oggetto di classe "data.frame")
# B) gli slot di una classe primitiva hanno nomi tipo "s1", "s2", "s3", ecc...

setClass('BioMart.list', # BioMart dataset info
    representation(s1='list'),
    prototype(s1=list(
            database=NULL, # string defining BioMart database
            dataset=NULL # string defining BioMart dataset
        )
    )
)

setClass('CornaOut.df', # Output dataframe structure from <corna.test.fun> function
    representation(s1='data.frame'),
    prototype(
        s1=data.frame(
            total=NULL,
            expectation=NULL,
            observation=NULL,
            hypergeometric=NULL,
            fisher=NULL,
            description=NULL
        )
    )
)

setClass('Gene2Path.df', # crosslinks between Ensembl Genes and KEGG Pathways
    representation(s1='data.frame'),
    prototype(
        s1=data.frame(
            gene=NULL, # character vector of Ensembl gene identifiers
            path=NULL, # character vector of KEGG identifiers
            name=NULL # character vector of description of pathway
        )
    )
)

setClass('GO2Term.df', # crosslinks between GO id and term
    representation(s1='data.frame'),
    prototype(
        s1=data.frame(
            goid=NULL, # character vector of GO identifiers
            term=NULL # character vector of GO terms
        )
    )
)

setClass('Population.df', #  dataframe containing "population" subset
    representation(s1='data.frame'),
    prototype(
        s1=data.frame(
            RefSeqID = NULL, # character vector of RefSeq identifiers
            mm9 = NULL, # character vector of RefSeq identifiers according to <kgXref> table of mymir DB
            GeneID = NULL, # character vector of EntrezGene identifiers
            GeneSymbol = NULL, # character vector of GeneSymbol according to MGI
            rank = NULL, # numeric vector of target prediction rank score according to <targets_ranks> table of mymir DB
            description = NULL # character vector of text describing target gene
        )
    )
)

setClass('RefSeq2Ensembl.list', # crosslinks between RefSeq and Ensembl IDs
    representation(s1='list'),
    prototype(
        s1=list(
            trans=data.frame( # dealing with transcripts IDs
                refseq=NULL, # character vector of RefSeq identifiers
                ensembl_transcript=NULL # character vector of Ensembl transcript identifiers
            ),
            gene=data.frame( # dealing with gene IDs
                refseq=NULL, # character vector of RefSeq identifier
                ensembl_gene=NULL # character vector of Ensembl gene identifiers
            )
        )
    )
)

setClass('SQL.list', # list of single blocks which define a generic SQL statement
    representation(s1='list'),
    prototype(
        s1=list (
            select = c("SELECT"),
            from = c("FROM"),
            where = c("WHERE"),
            join = c("JOIN", "ON"),
            ord = c("ORDER BY"),
            group = c("GROUP BY"),
            having = c("HAVING"),
            limit = c("LIMIT")
        )
    )
)

setClass('Trans2GO.list', # crosslinks between Ensembl Transcripts and GO IDs
    representation(s1='list'),
    prototype(
        s1=list(
            bp=data.frame( # dataframe defining links between Ensembl and GO biological process 
                ensembl_transcript=NULL, # character vector, Ensembl IDs for the "universe"
                gobp=NULL
            ),
            cc=data.frame( # dataframe defining links between Ensembl and GO cellular component
                ensembl_transcript=NULL,
                gocc=NULL
            ),
            mf=data.frame( # dataframe defining links between Ensembl and GO molecular function
                ensembl_transcript=NULL,
                gomf=NULL
            )
        )
    )
)

setClass('Universe.df', # dataframe containing "universe" subset
    representation(s1='data.frame'),
    prototype(
        s1=data.frame(
            RefSeqID = NULL, # character vector of RefSeq identifiers
            mm9 = NULL, # character vector of RefSeq identifiers according to <kgXref> table of mymir DB
            GeneID = NULL, # character vector of EntrezGene identifiers
            GeneSymbol = NULL # character vector of GeneSymbol according to MGI
        )
    )
)


## CLASSI DERIVATE
# Le classi primitive non vengono usate direttamente dalle funzioni del package, a differenza delle classi derivate i cui componenti possono essere oggetti istanziati dalle mie classi primitive

setClass('Clusterama', # Clusterama dataset class
    representation(
        data='list', # source dataset info
        dist='list', # info about distance matrix. Distances relies on semantic similarities among GO term pairs; distance values range from 0, perfect similarity (identical GO terms), to 1, maximum dissimilarity
        mds='list', # info about multidimensional scaling (MDS). MDS is a set of related statistical techniques often used in information visualization for exploring similarities or dissimilarities in data; an MDS algorithm starts with a matrix of item–item similarities, then assigns a location to each item in N-dimensional space.
        pam='list', # info about partitional clustering.
        summaries='list' # summaries dataframes from Clusterama computations
    ),
    prototype(
        data=list(
            acc=NULL, # logical, accessibility filter
            ont=NULL, # string, sub-ontology
            orth=NULL # logical, orthology filter
        ),
        dist=list(
            matrix=NULL, # matrix, distance matrix
            size=NULL, # integer, number of observations in the dataset
            labels=NULL # array, names of each observation
        ),
        mds=list(
            eig=NULL, # array, eigenvalues computed during the scaling process
            GOF=NULL, # double, Goodness Of Fit (GOF) the sum of above-zero eigenvalues for the total GOF = (sum{j=1..k} lambda[j]) / (sum{j=1..n} max(lambda[j], 0)), where lambda[j] are the eigenvalues (sorted decreasingly). A GOF of 0.8 is considered good for metric scaling.
            dims=NULL, # the dimension of the space which the data are to be represented in; it is related with the number of eigenvalues in order to obtain GOF > 0.8
            points=NULL # matrix with 'dims' columns whose rows give the coordinates of the points chosen to represent the dissimilarities.
        ),
        pam=list(
            k=NULL, # integer,number of clusters as suggested by HOPACH
            medoids=NULL, # array, the medoids or representative objects of the clusters.
            id.med=NULL, # array,  integer vector of _indices_ giving the medoid observation numbers
            clustering=NULL, # array, the clustering vector. An integer vector of length n, the number of observations, giving for each observation the number (`id') of the cluster to which it belongs
            clusinfo=NULL, # matrix, each row gives numerical information for one cluster.FIELDS: cardinality of the cluster; maximal and average dissimilarity between the observations in the cluster and the cluster's medoid; diameter of the cluster (maximal dissimilarity between two observations of the cluster); the separation of the cluster (minimal dissimilarity between an observation of the cluster and an observation of another cluster)
            silinfo=NULL # list, all "silhouette" info: "$widths" matrix with for each observation i the cluster to which i belongs, the neighbor cluster of i, and the silhouette width s(i); "$clus.avg.widths" the average silhouette width per cluster; "avg.width" the average of s(i) over all observations i
        ),
        summaries=list(
            clusters=NULL, # dataframe, info about clusters
            obs=NULL, # dataframe, info about observation of each clusters
            target=NULL # dataframe, info about target which belong to observed GO terms
        )
    )
)

setClass('CrossLinks', # Dataset structure containing crosslinks
    representation(
        BioMart='BioMart.list',
        Gene2Path='Gene2Path.df',
        GO2Term='GO2Term.df',
        RefSeq2Ensembl='RefSeq2Ensembl.list', # crosslinks between RefSeq and Ensembl IDs
        Trans2GO='Trans2GO.list' # crosslinks between Ensembl Transcripts and GO IDs
    )
)

setClass('OverReps', # Dataset structure for collecting all CORNA outputs
    representation(
        KEGG='CornaOut.df',
        GObp='CornaOut.df',
        GOcc='CornaOut.df',
        GOmf='CornaOut.df'
    )
)

setClass('QuerySelect', # for building SQL statement such as "SELECT ..."
    representation(
        statement="character", # string, SQL statement
        structure="SQL.list"
    )
)

setClass('UniPop', # Dataset structure containing "universe" and "population" geneset
    representation(
        population.data="Population.df",
        population.ensembl.gene="character", # array, Ensembl gene IDs for the "population" dataset
        population.ensembl.trans="character", # array, Ensembl transcript IDs for the "population" dataset
        population.query="character", # string defining SQL statement for retrieving "population" dataset 
        universe.data="Universe.df",
        universe.ensembl.gene="character", # character vector, Ensembl gene IDs for the "universe"
        universe.ensembl.trans="character", # character vector, Ensembl transcript IDs for the "universe"
        universe.query="character" # string defining SQL statement for retrieving "universe" dataset
    )
)


## FUNZIONI GENERICHE

setGeneric('CoalesceQuery', function(object, ...) standardGeneric('CoalesceQuery'))

setGeneric('Ensembl', function(object, ...) standardGeneric('Ensembl'))

setGeneric('Fetch', function(object, ...) standardGeneric('Fetch'))

setGeneric('UpdateDB', function(object, ...) standardGeneric('UpdateDB'))


## METODI

setMethod('CoalesceQuery','QuerySelect', # legge da un oggetto di classe <QuerySelect> lo slot <structure>, raggruppa tutti i componenti in un unica stringa e scrive sullo slot <statement>; ritorna un oggetto di classe <QuerySelect>
    function(object, ...) {
        
        query.elems <- unlist(object@structure@s1); # converto la lista in un vettore indicizzato
        
        # shifto il primo elemento di <query.elems> su <query.string>
        query.string <- query.elems[1];
        query.elems <- query.elems[-1];
        
        for (single.elem in query.elems) # accodo a <query.string> tutti gli elementi restanti
            query.string <- paste(query.string, single.elem);
        
        object@statement <- query.string; # scrivo tutto sullo slot <QuerySelect@statement>
        
        return(object);
    }
)

setMethod('Ensembl', 'UniPop', 
    function (object, type = "trans", xref = NULL, unipop = NULL, ...) {
# Questo metodo estrae un dataframe di 2 componenti, entrambi vettori di stringhe contenenti gli Ensembl IDs rispettivamente di universo e popolazione
# <type>      definisce quale Ensembl ID estrarre: "trans" = Ensembl transcript, "gene" = Ensembl gene
# <xref>      oggetto di classe <CrossLinks>
# <unipop>    oggetto di classe <UniPop>

    if (is.null(xref)) { 
        data(MyMir.CrossLinks);
        xref <- MyMir.CrossLinks;
    }
    
    if (is.null(unipop)) { stop("undef <UniPop> object"); }
    
    if (!(type %in%  c("trans", "gene"))) { stop("unknwon ensembl identifier");}
    
    uni.refseq.df <- unipop@universe.data@s1; # df dei trascritti appartenenti all'universo
    pop.refseq.df <- unipop@population.data@s1; # df dei trascritti appartenenti alla popolazione
    
    refseq2ensembl.df <- data.frame(); # df di associazione RefSeq Ensembl
    uni.ensembl.df <- data.frame();
    pop.ensembl.df <- data.frame();
    result <- unipop;
    
    if (type == "trans") {
        refseq2ensembl.df <- xref@RefSeq2Ensembl@s1$trans;
        
        uni.ensembl.df <- merge(x = uni.refseq.df, y = refseq2ensembl.df, by.x = "RefSeqID", by.y = "refseq", all = FALSE);
        uni.ensembl.df <- uni.ensembl.df[!is.na(uni.ensembl.df$ensembl_transcript),]; # rimuovo eventuali NA
        uni.ensembl.df <- uni.ensembl.df[!duplicated(uni.ensembl.df$ensembl_transcript),]; # rimuovo gli Ensembl transcript IDs ripetuti
        
        pop.ensembl.df <- merge(x = pop.refseq.df, y = refseq2ensembl.df, by.x = "RefSeqID", by.y = "refseq", all = FALSE);
        pop.ensembl.df <- pop.ensembl.df[!is.na(pop.ensembl.df$ensembl_transcript),];
        pop.ensembl.df <- pop.ensembl.df[!duplicated(pop.ensembl.df$ensembl_transcript),];

        result@universe.ensembl.trans <- uni.ensembl.df$ensembl_transcript;
        result@population.ensembl.trans <- pop.ensembl.df$ensembl_transcript;
    }
    
    if (type == "gene") {
        refseq2ensembl.df <- xref@RefSeq2Ensembl@s1$gene; 
    
        uni.ensembl.df <- merge(x = uni.refseq.df, y = refseq2ensembl.df, by.x = "RefSeqID", by.y = "refseq", all = FALSE);
        uni.ensembl.df <- uni.ensembl.df[!is.na(uni.ensembl.df$ensembl_gene),]; # rimuovo eventuali NA
        uni.ensembl.df <- uni.ensembl.df[!duplicated(uni.ensembl.df$ensembl_gene),]; # rimuovo gli Ensembl transcript IDs ripetuti
        
        pop.ensembl.df <- merge(x = pop.refseq.df, y = refseq2ensembl.df, by.x = "RefSeqID", by.y = "refseq", all = FALSE);
        pop.ensembl.df <- pop.ensembl.df[!is.na(pop.ensembl.df$ensembl_gene),];
        pop.ensembl.df <- pop.ensembl.df[!duplicated(pop.ensembl.df$ensembl_gene),];
        
        result@universe.ensembl.gene <- uni.ensembl.df$ensembl_gene;
        result@population.ensembl.gene <- pop.ensembl.df$ensembl_gene;
    }
    
    return(result);
    }
)

setMethod('Fetch', 'CrossLinks',
    function(object, biomart = "ensembl", dataset = "mmusculus_gene_ensembl", org="mmu") {
# questo metodo si occupa di reperire i riferimenti incrociati tra RefSeqID, Ensembl IDs (transcript e gene), GO IDs (cellular component, molecular function e biological process)
#
# <org>           definisce l'organismo
#
# <biomart>       definisce il database di BioMart. Per un elenco completo usare la funzione <listMarts> del package <biomaRt>
# <dataset>       definisce il dataset da un database selezionato. Per un elenco completo lanciare uno script del genere:
#                     library(biomaRt); mart <- useMart('ensembl'); listDatasets(mart);
    
    writeLines("\n-- Creating an object of class <CrossLinks>...");
    
    writeLines("\n\tLoading crosslinks between <refseq_dna> ID and <ensembl_transcript_id>...");
    refseq2ensembl_tran <-  BioMart2df.fun( biomart=biomart, dataset=dataset,
                                            col.old=c("refseq_dna", "ensembl_transcript_id"),
                                            col.new=c("refseq", "ensembl_transcript"));
    writeLines("\n\tLoading crosslinks between <refseq_dna> ID and <ensembl_gene_id>...");
    refseq2ensembl_gene <-  BioMart2df.fun( biomart=biomart, dataset=dataset,
                                            col.old=c("refseq_dna", "ensembl_gene_id"),
                                            col.new=c("refseq", "ensembl_gene"));
    writeLines("\n\tLoading crosslinks between <ensembl_transcript_id> ID and <go_biological_process_id>...");
    tran2gobp  <- BioMart2df.fun(   biomart=biomart, dataset=dataset,
                                    col.old=c("ensembl_transcript_id", "go_biological_process_id"),
                                    col.new=c("ensembl_transcript", "gobp"));
    writeLines("\n\tLoading crosslinks between <ensembl_transcript_id> ID and <go_cellular_component_id>...");
    tran2gocc  <- BioMart2df.fun(   biomart=biomart, dataset=dataset,
                                    col.old=c("ensembl_transcript_id", "go_cellular_component_id"),
                                    col.new=c("ensembl_transcript", "gocc"));
    writeLines("\n\tLoading crosslinks between  <ensembl_transcript_id> ID and <go_molecular_function_id>...");
    tran2gomf  <- BioMart2df.fun(   biomart=biomart, dataset=dataset,
                                    col.old=c("ensembl_transcript_id", "go_molecular_function_id"),
                                    col.new=c("ensembl_transcript", "gomf"));
    writeLines("\n\tLoading links between GO id and term...");
    corna.go2term <- GO2df.fun(url = "ftp://ftp.ncbi.nlm.nih.gov/gene/DATA/gene2go.gz");
    
    writeLines("\n\tLoading pathway information from KEGG...");
    corna.gene2path <- KEGG2df.fun(org = org);
    
#     creo un oggetto di classe <CrossLinks>
    crosslink.obj <- new("CrossLinks");
    crosslink.obj@BioMart@s1$database <- biomart;
    crosslink.obj@BioMart@s1$dataset <- dataset;
    crosslink.obj@RefSeq2Ensembl@s1$trans <- refseq2ensembl_tran;
    crosslink.obj@RefSeq2Ensembl@s1$gene <- refseq2ensembl_gene;
    crosslink.obj@Trans2GO@s1$bp <- tran2gobp;
    crosslink.obj@Trans2GO@s1$cc <- tran2gocc;
    crosslink.obj@Trans2GO@s1$mf <- tran2gomf;
    crosslink.obj@GO2Term@s1 <- corna.go2term;
    crosslink.obj@Gene2Path@s1 <- corna.gene2path
    
    writeLines("\n-- Object of class <CrossLinks> done!");
    return(crosslink.obj);
    }
)

setMethod('Fetch', 'UniPop',
    function(object, uni.mir = "all", pop.mir = NULL, pop.acc = FALSE, pop.orth = FALSE, pop.limit = 100, ...) {
# questo metodo recupera universo e popolazione dal DB e li inserisce in un oggetto di classe <UniPop>
#
# <uni.mir>     v. funzione <QueryBuild.Universe>
# 
# <pop.mir>     v. funzione <QueryBuild.Population>
# <pop.acc>     v. funzione <QueryBuild.Population>
# <pop.orth>    v. funzione <QueryBuild.Population>
# 
# <pop.limit>   numero di record che riempiono il dataframe che descrive la popolazione
    
    odbc.dsn <- get("odbc.dsn", envir=MyMirEnv);
    odbc.pw <- get("odbc.pw", envir=MyMirEnv);
    
    # nomi delle tabelle temporanee da caricare sul DB
    universotab <- paste("universotab", Sys.getpid(), sep="_");
    popolazionetab <- paste("popolazionetab", Sys.getpid(), sep="_");

    
    writeLines("\n-- Creating target dataset...");
    if (is.null(pop.mir)) { stop("undef miRNA in <pop.mir> parameter"); }
    
    writeLines("\tOpening a database handle...");
    
    dbh<-odbcConnect(dsn = odbc.dsn, pw = odbc.pw);    # apro un canale ('dbh') su un DSN MySQL: le configurazioni dei DSN, sono nel file /etc/odbc.ini
#     odbcGetInfo(dbh);dbh;  # info sul canale
    sqlQuery(dbh, "use mm9");   # definisco il DB da usare
    
    writeLines("\tUpload universe...");
#     costruisco la query per l'universo
    universe.query <- QueryBuild.Universe(uni.mir);
    
    universe.tab <- data.frame();
    if (uni.mir == "all") { # ATTENZIONE: x convenienza di tempo uso un dataset di genoma di topo già pronto, anche se la funzione <query.build.universe> funziona comunque passandogli come parametro "all"
        data(universe.mm9);
        universe.tab <- universe.mm9;
    } else {
        sqlCopy(dbh, universe.query@statement, universotab, rownames=F, verbose=F); # creo sul DB una tabella temporanea dei risultati della query
        universe.tab <- sqlFetch(dbh, universotab, nullstring = NA, stringsAsFactors = F); # fetching della query 
        universe.tab$GeneID <- as.character(universe.tab$GeneID); # converto il campo "GeneID" in stringa
    }
    
    writeLines("\tUploading population...");
#     costruisco la query per la popolazione
    population.query <- QueryBuild.Population(pop.mir, acc = pop.acc, orth = pop.orth);
    
    sqlCopy(dbh, population.query@statement, popolazionetab, rownames=F, verbose=F);
    population.tab <- sqlFetch(dbh, popolazionetab, nullstring = NA, stringsAsFactors = F, max = pop.limit);
    population.tab$GeneID <- as.character(population.tab$GeneID);
    
#     elimino le tabelle temporanee create sul DB
    if (uni.mir != "all") { sqlDrop(dbh, universotab); } # ATTENZIONE: uso un dataset, non ho creato nessuna tabella
    sqlDrop(dbh, popolazionetab);
    
    odbcClose(dbh);  # chiudo il canale
    
#     creo un oggetto di classe <UniPop>
    unipop.obj <- new('UniPop');
    unipop.obj@universe.query <- universe.query@statement;
    unipop.obj@population.query <- population.query@statement;
    unipop.obj@universe.data@s1 <- universe.tab;
    unipop.obj@population.data@s1 <- population.tab;
    
    # Obtaining associations dataframes between <UniPop> dataset and Ensembl identifiers
    writeLines("\tUploading Ensembl IDs...");
    unipop.obj <- Ensembl(new("UniPop"), type = "trans", unipop = unipop.obj);
    unipop.obj <- Ensembl(new("UniPop"), type = "gene", unipop = unipop.obj);

    
    writeLines("-- Target dataset done!");
    return(unipop.obj);
    }
)

setMethod('UpdateDB', 'Clusterama',
    function (object) {
# Questo metodo recupera i dati di un oggetto di classe <Clusterama> e li carica su tabelle apposite sul DB. In particolare, dato un oggetto di classe <Clusterama>, estrae i dataframes contenuti nello slot <summaries> e li carica come tre tabelle separate con la seguente nomenclatura:
#
#       [sub.ontology]_[filtri]_["cluster"|"obs"|"target"]
#
# [sub.ontology] -> tipo di ontologia (BP, CC o MF)
# [filtri] -> due logit che indicano quali filtri sono stati applicati neò reperimento del dataset (es.: "TRUE_FALSE" indica che sono dati filtrato per accessibilita' [True] ma non per ortologia [False])
# ["cluster"|"obs"|"target"] -> i tre dataframes dello slot <summaries>
#
# <object>     OBBLIGATORIO, oggetto di classe <Clusterama>

    # recupero le credenziali necessarie per accedere al database
    db.usr <- get("db.usr", envir=MyMirEnv);
    db.pw <- get("db.pw", envir=MyMirEnv);
    db.host <- get("db.host", envir=MyMirEnv);
    db.name <- get("db.name", envir=MyMirEnv);
    
    dbd<-dbDriver("MySQL");   # carico il driver per MySQL
    dbh<-dbConnect(dbd, user = db.usr, password = db.pw, host = db.host, dbname = db.name); # mi connetto al database
    writeLines("-- connected to DB...");print(dbh);
    
    basename <- paste(object@data$ont, object@data$acc, object@data$orth, sep='_'); # il basename delle tabelle da caricare, stringa del tipo "[sub.ontology]_[filtri]_"
    df.list <- object@summaries; # lista dei dataframes che verranno caricati
    
    for (df.name in names(df.list)) {
        tab.name <- paste(basename, df.name, sep = "_"); # nome della tabella
        tab.data <- df.list[[df.name]]; # contenuto della tabella
        sth <- dbSendQuery(dbh, paste("DROP TABLE IF EXISTS", tab.name, sep =" ")); # rimuovo eventuali tabelle pre-esistenti
        
        row.names(tab.data) <- c(1:nrow(tab.data)); # creo ex-novo un vettore per indicizzare le tabelle
        writeLines(c("-- uploading <", tab.name, "> table\n"), sep = "");
        dbWriteTable(dbh, tab.name, tab.data, row.names=TRUE); # carico la tabella
        sth <- dbSendQuery(dbh, paste("ALTER TABLE", tab.name, "ADD PRIMARY KEY ( `row_names` ( 30 ) )", sep =" "));# e la indicizzo
    }
    
    #     mi disconnetto dal database
    if (dbDisconnect(dbh)) { writeLines("-- disconnected from DB");print(dbh);
    } else { writeLines("W- disconnection from DB failed!");print(dbh); }
}
)

setMethod('UpdateDB', 'OverReps',
    function (object, tablename = NULL) {
# Questo metodo recupera i dati di un oggetto di classe <OverReps> e li carica su una tabella apposita sul DB.
# <object>     OBBLIGATORIO, oggetto di classe <OverReps>
# <tablename>   OBBLIGATORIO, stringa, nome della tabella da caricare sul DB
    
    if (is.null(tablename)) { stop("undef parameter <tablename>"); }
    
    db.usr <- get("db.usr", envir=MyMirEnv);
    db.pw <- get("db.pw", envir=MyMirEnv);
    db.host <- get("db.host", envir=MyMirEnv);
    db.name <- get("db.name", envir=MyMirEnv);

    dbd<-dbDriver("MySQL");   # carico il driver per MySQL
    dbh<-dbConnect(dbd, user = db.usr, password = db.pw, host = db.host, dbname = db.name); # mi connetto al database
    writeLines("-- connected to DB...");print(dbh);
    
#     upload dei dati: l'oggetto <object> verrà splittato nelle sue singole componenti (i dataframe "$KEGG", "$GObp", "$GOcc" e "$GOmf"). Ogni componente verrà caricato sul DB come una tabella a sè stante
    results <- list(KEGG = object@KEGG@s1, GObp = object@GObp@s1, GOcc = object@GOcc@s1, GOmf = object@GOmf@s1);
    for (term in names(results)) {
        tab.name <- paste(tablename, term, sep = "_"); # nome della tabella
        tab.data <- results[[term]]; # contenuto della tabella
        sth <- dbSendQuery(dbh, paste("DROP TABLE IF EXISTS", tab.name, sep =" ")); # rimuovo eventuali tabelle pre-esistenti
        
        writeLines(c("-- uploading <", tab.name, "> table\n"), sep = "");
        dbWriteTable(dbh, tab.name, tab.data, row.names=TRUE); # carico la tabella
        sth <- dbSendQuery(dbh, paste("ALTER TABLE", tab.name, "ADD PRIMARY KEY ( `row_names` ( 30 ) )", sep =" "));# e la indicizzo
    }
    
#     mi disconnetto dal database
    if (dbDisconnect(dbh)) { writeLines("-- disconnected from DB");print(dbh);
    } else { writeLines("W- disconnection from DB failed!");print(dbh); }
    }
)
