`QueryBuild.Universe` <-
function (mir = "all") {
# Questa funzione allestisce le query dei gruppi UNIVERSO. Ritorna un oggetto di classe <QuerySelect>.
# <mir> stringa che definisce il miRNA da prendere in considerazione. Di default ("all") considera tutte le predizioni di tutti i miRNA

    my.query.select <- new("QuerySelect");
    
# # TUTTE le UTR del dataset
    if (mir=='all') {
#         creo una lista contenente solo gli elementi dello slot <QuerySelect@structure> che mi servono
        query.universe <- c(my.query.select@structure@s1["select"],
                            my.query.select@structure@s1["from"],
                            my.query.select@structure@s1["join"]);
        
#         riempio i singoli componenti di <query.universe> con gli attributi mancanti
        attach(query.universe);
        query.universe$select <- c(select, 'DISTINCT a.RefSeqID, b.mRNA AS \'mm9\', a.GeneID, a.GeneSymbol');
        query.universe$from <- c(from, 'fasta3utr AS a');
        query.universe$join <- c('LEFT', join[1], 'kgXref AS b', join[2], 'a.RefSeqID = b.mRNA');
        detach(query.universe);
        
        
# # TUTTE le UTR predette per ogni miRNA
    } else {
            query.universe <- c(my.query.select@structure@s1["select"],
                                my.query.select@structure@s1["from"],
                                my.query.select@structure@s1["join"],
                                my.query.select@structure@s1["join"],
                                my.query.select@structure@s1["where"]);
            names(query.universe) <- c(names(query.universe)[1:2], "join.1",  "join.2", names(query.universe)[5]);
        
            attach(query.universe);
            query.universe$select <- c(select, 'DISTINCT b.RefSeqID, c.mRNA AS \'mm9\', b.GeneID, b.GeneSymbol');
            query.universe$from <- c(from, 'prediction_summary AS a');
            query.universe$join.1 <- c(join.1[1], 'fasta3utr AS b', join.1[2], 'a.refseqID = b.RefSeqID');
            query.universe$join.2 <- c('LEFT', join.2[1], 'kgXref AS c', join.2[2], 'a.RefSeqID = c.mRNA');
            query.universe$where <- c(where, paste('(a.mirID LIKE \'', mir, '\')', sep=""));
            detach(query.universe);
    }
    
#     ridefinisco lo slot <QuerySelect@structure>
    my.query.select@structure@s1 <- query.universe;
#     assemblo la query in una stringa
    my.query.select <- CoalesceQuery(my.query.select);
    return(my.query.select);
}

