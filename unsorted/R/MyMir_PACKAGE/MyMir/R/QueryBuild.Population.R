`QueryBuild.Population` <-
function(mir = NULL, acc = FALSE, orth = FALSE) {
# Questa funzione allestisce le query dei gruppi POPOLAZIONE. Ritorna un oggetto di classe <QuerySelect>.
# <mir>   OBBLIGATORIO, stringa che specifica il nome del miRNA
# <acc>   logico, considera solo i target predetti come accessibili secondo PITA
# <orth>  logico, considera solo i target di cui TargetScan ha rilevato una interazione ortologa nell'uomo


    if (is.null(mir)) {
        stop("undef miRNA in <mir> parameter");
    } else {

        my.query.select <- new("QuerySelect");

# # TUTTE le UTR predette per ogni miRNA con rank superiore a 0
        query.population <- c(  my.query.select@structure@s1["select"],
                                my.query.select@structure@s1["from"],
                                my.query.select@structure@s1["join"],
                                my.query.select@structure@s1["join"],
                                my.query.select@structure@s1["where"],
                                my.query.select@structure@s1["ord"]);
        names(query.population) <- c(names(query.population)[1:2], "join.1",  "join.2", names(query.population)[5:6]);
        
        attach(query.population);
        query.population$select <- c(select, 'DISTINCT b.RefSeqID, c.mRNA AS \'mm9\', b.GeneID, b.GeneSymbol, a.rank, c.description');
        query.population$from <- c(from, 'targets_ranks AS a');
        query.population$join.1 <- c(join.1[1], 'fasta3utr AS b', join.1[2], 'a.refseqID = b.RefSeqID');
        query.population$join.2 <- c('LEFT', join.2[1], 'kgXref AS c', join.2[2], 'a.refseqID = c.mRNA');
        query.population$where <- c(where, paste('(a.mirID LIKE \'', mir, '\')', sep=""), 'AND (a.rank > 0 )');
        query.population$ord <- c(ord, 'a.rank DESC');

# # UTR predette per ogni miRNA con varie restrizioni combinabili
        if (isTRUE(acc)) { # sono accessibili secondo PITA?
            query.population$where <- c(query.population$where, 'AND (a.acc LIKE \'1\')');
        }
        if (isTRUE(orth)) { # sono ortolghe nell'uomo secondo TargetScan?
            query.population$where <- c(query.population$where, 'AND (a.orth LIKE \'1\')');
        }
        
        detach(query.population);
        
#     ridefinisco lo slot <QuerySelect@structure>
        my.query.select@structure@s1 <- query.population;
#     assemblo la query in una stringa
        my.query.select <- CoalesceQuery(my.query.select);
        return(my.query.select);
    }
}
