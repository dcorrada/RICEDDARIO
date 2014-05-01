`OverallTest` <-
function (unipop = NULL, xref = NULL) {
# Questa funzione lancia il test statistico implementato nel package CORNA (funzione <corna.test.fun>) su: 1) KEGG pathway; 2) GO molecular function; 3) GO biological process; 4) GO cellular component. Ritorna una lista di 4 dataframe, ognuno secondo il formato presentato da <corna.test.fun> (v. documentazione allegata alla funzione).
# <unipo>    OBBLIGATORIO, oggetto di classe <UniPop>
# <xref>     oggetto di classe <CrossLinks>, se non specificato viene caricato il dataset "MyMir.CrossLinks"
    
#     INIZIALIZZAZIONI
    if (is.null(unipop)) { stop("undef parameter <unipop>"); }
    if (!is(unipop, "UniPop")) { stop("wrong class for object call in <unipop> parameter"); }
    if (is.null(xref)) {
        warning("undef parameter <xref>: dataset 'MyMir.CrossLinks' will be loaded...");
        data(MyMir.CrossLinks); # loading <MyMir> dataset, cross references for mmu
        xref <- MyMir.CrossLinks;
    }
    if (!is(xref, "CrossLinks")) { stop("wrong class for object call in <xref> parameter"); }
    
    writeLines("\n-- Creating overrepresentation dataset...");
    writeLines("\t Testing KEGG pathway...");
    path2name <- unique(xref@Gene2Path@s1[c("path", "name")]);
    test.KEGG <- corna.test.fun(x = unipop@population.ensembl.gene, y = unipop@universe.ensembl.gene , z = xref@Gene2Path@s1,
                                hypergeometric = TRUE, fisher = TRUE,
                                hyper.lower.tail = FALSE, fisher.alternative = "two.sided", p.adjust.method = "none",
                                min.pop = 10, desc = path2name );
    
    writeLines("\t Testing GO molecular function...");
    test.GOmf <- corna.test.fun(x = unipop@population.ensembl.trans, y = unipop@universe.ensembl.trans, z = xref@Trans2GO@s1$mf,
                                hypergeometric = TRUE, fisher = TRUE,
                                hyper.lower.tail = FALSE, fisher.alternative = "two.sided", p.adjust.method = "none",
                                min.pop = 10, desc = xref@GO2Term@s1 );
    
    writeLines("\t Testing GO cellular component...");
    test.GOcc <- corna.test.fun(x = unipop@population.ensembl.trans, y = unipop@universe.ensembl.trans, z = xref@Trans2GO@s1$cc,
                                hypergeometric = TRUE, fisher = TRUE,
                                hyper.lower.tail = FALSE, fisher.alternative = "two.sided", p.adjust.method = "none",
                                min.pop = 10, desc = xref@GO2Term@s1 );
    
    writeLines("\t Testing GO biological process...");
    test.GObp <- corna.test.fun(x = unipop@population.ensembl.trans, y = unipop@universe.ensembl.trans, z = xref@Trans2GO@s1$bp,
                                hypergeometric = TRUE, fisher = TRUE,
                                hyper.lower.tail = FALSE, fisher.alternative = "two.sided", p.adjust.method = "none",
                                min.pop = 10, desc = xref@GO2Term@s1 );
    
    writeLines("\t Subsetting on p-value..."); # tengo solo i dati con p-value <= 0.05
    test.KEGG <- subset(test.KEGG, hypergeometric <= 0.05);
    test.GOmf <- subset(test.GOmf, hypergeometric <= 0.05);
    test.GOcc <- subset(test.GOcc, hypergeometric <= 0.05);
    test.GObp <- subset(test.GObp, hypergeometric <= 0.05);
    
    test.list <- new('OverReps');
    test.list@KEGG@s1 <- test.KEGG;
    test.list@GObp@s1 <- test.GObp
    test.list@GOcc@s1 <- test.GOcc;
    test.list@GOmf@s1 <- test.GOmf;
    writeLines("-- Overrepresentation dataset done!");
    return(test.list);
}