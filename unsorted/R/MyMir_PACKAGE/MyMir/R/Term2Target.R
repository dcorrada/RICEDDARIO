`Term2Target` <-
function (population = NULL, term.list = NULL, term.type = "GOmf", xref = NULL) {
# Questa funzione restituisce un dataframe contenente informazioni su tutti i geni target che sono accomunati sotto uno stesso termine (GO o KEGG)
# <population>      OBBLIGATORIO, oggetto di classe <UniPop>
# <term.list>       OBBLIGATORIO, stringa o vettore che definisce l'elenco degli identificatori
# <term.type>       stringa che identifica il tipo di identificatore (GO o KEGG), le modalità di <term.type> saranno "GObp", "GOcc", "GOmf" e "KEGG"
# <xref>            oggetto di classe <CrossLinks>, se non specificato viene caricato il dataset "MyMir.CrossLinks"



    if (is.null(population)) { stop("undef parameter <population>"); }
    if (is.null(term.list)) { stop("undef parameter <term.list>"); }
    if (is.null(xref)) {
        warning("undef parameter <xref>: dataset 'MyMir.CrossLinks' will be loaded...");
        data(MyMir.CrossLinks); # loading <MyMir> dataset, cross references for mmu
        xref <- MyMir.CrossLinks;
    }
    if (!is(xref, "CrossLinks")) { stop("wrong class for object call in <xref> parameter"); }
    
    term.list <- as.data.frame(term.list, stringsAsFactors=FALSE); names(term.list) <- c("termID");
    ensembl2refseq <- data.frame(); # collega l'ID di Ensembl (transcript o gene) ad un ID RefSeq
    ensembl2term <- data.frame(); # collega l'ID di Ensembl (transcript o gene) ad un ID di GO o KEGG
    term2desc <- data.frame(); # collega gli ID di GO o KEGG alla loro descrizione
    
#     Nel seguente blocco di codice faccio un parsing dell'oggetto <xref> in modo da ottenere i dataframes <ensembl2refseq>, <ensembl2term> e <term2desc> con un formato uniforme, a prescindere che tratti EnsemblGene o EnsemTranscript, GObp oppure KEGG
    {
        if (term.type == "GObp") {
            writeLines("-- Performing search on GO Biological Process");
            ensembl2refseq <- xref@RefSeq2Ensembl@s1$trans;
            ensembl2term <- xref@Trans2GO@s1$bp;
            term2desc <- xref@GO2Term@s1;
        } else if (term.type == "GOcc") {
            writeLines("-- Performing search on GO Cellular Component");
            ensembl2refseq <- xref@RefSeq2Ensembl@s1$trans;
            ensembl2term <- xref@Trans2GO@s1$cc;
            term2desc <- xref@GO2Term@s1;
        } else if (term.type == "GOmf") {
            writeLines("-- Performing search on GO Molecular Function");
            ensembl2refseq <- xref@RefSeq2Ensembl@s1$trans;
            ensembl2term <- xref@Trans2GO@s1$mf;
            term2desc <- xref@GO2Term@s1;
        } else if (term.type == "KEGG") {
            writeLines("-- Performing search on KEGG Pathway");
            ensembl2refseq <- xref@RefSeq2Ensembl@s1$gene;
            ensembl2term <- xref@Gene2Path@s1;
            term2desc <- xref@Gene2Path@s1;
            ensembl2term$name <- NULL;
            term2desc$gene <- NULL;
            term2desc <- unique(term2desc);
        } else {
            stop("unknown <term.type> parameter");
        }
        names(ensembl2refseq) <- c("refseqID", "ensemblID");
        names(ensembl2term) <- c("ensemblID", "termID");
        names(term2desc) <- c("termID", "term.desc");
    }
    
#     ora ridefinisco xref; lo scopo è quello di ottenere un nuovo dataframe dove per ogni elemento di <term.list> ho un elenco completo dei codici RefSeq dei trascritti a cui appartengono
    {

#         in primo luogo unisco la lista degli identifier - dati in input con il vettore <term.list> - al dataframe <term2desc>
        fusione.A <- merge(x = term2desc, y = term.list, by = "termID", stringsAsFactors = FALSE);
        
#         ora fondo <fusione.A> con <ensembl2term> e <ensembl2refseq>
        fusione.B <- merge(x = ensembl2term, y = fusione.A, by = "termID");
        fusione.C <- merge(x = ensembl2refseq, y = fusione.B, by = "ensemblID");
        
        xref <- fusione.C;
    }
    
#     a questo punto prendo i trascritti presenti nella popolazione di riferimento <population> e vado a fare un matching con i dati appena elaborati per <xref>
    final.match <- data.frame();
    {
#         prima di tutto snellisco e ridefinisco <population> con solo i dati che mi interessano
        population <- subset(population@population.data@s1, select = c("mm9", "GeneID", "GeneSymbol", "rank", "description"));
        names(population) <- c("refseqID", "geneID", "symbol", "rank", "gene.desc");
        
        final.match <- merge(x = population, y = xref, by = "refseqID");
    }
    
#     riordino i risultati prima di buttarli fuori
    final.match <- final.match[order(final.match$term.desc, final.match$rank, decreasing=TRUE), ];
    
#     RETURN VALUE
    result <- final.match;
    return(result);
}