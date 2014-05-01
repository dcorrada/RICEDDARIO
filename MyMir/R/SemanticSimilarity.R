`SemanticSimilarity` <-
function(organism = "mouse", pop.acc = FALSE, pop.orth = FALSE, semsim.algorithm = "Wang", sub.ont = NULL) {
# # questa funzione calcola gli score di similarità semantica tra coppie di GO terms appartenenti ad una lista derivata dai termini over-rappresentati per una determinata popolazioni di target
#
# <organism>    organismo da selezionare; attualmente il package "GOSemSim" è implementato solo per "human", "rat", "mouse", "fly" e "yeast"
#
# <pop.acc>     v. funzione <QueryBuild.Population>
# <pop.orth>    v. funzione <QueryBuild.Population>
#
# <semsim.algorithm>    algoritmo di calcolo per la similarità semantica; sono disponibili i seguenti metodi "Resnik", "Lin", "Rel", "Jiang" e "Wang"
#
# <sub.ont>     tipo di ontologia, "MF", "BP", o "CC"

    odbc.dsn <- get("odbc.dsn", envir=MyMirEnv);
    odbc.pw <- get("odbc.pw", envir=MyMirEnv);
    

    go.root.id <- list(BP ="GO:0008150", CC = "GO:0005575", MF = "GO:0003674") # GO ID dei tre nodi root

    go.list <- array(); # GO term list

    sim.score.matrix <- matrix(); # symmetric matrix of similarity score between GO terms which belong to <go.list>

    writeLines("\n-- Retrieving GO term list...");
    
    writeLines("\tOpening a database handle...");
    dbh <- odbcConnect(dsn = odbc.dsn, pw = odbc.pw);    # apro un canale ('dbh')
    sqlQuery(dbh, "use mm9");   # definisco il DB da usare

    { # selezione delle tabelle di interesse dal DB
        table.list <- sqlTables(dbh)$TABLE_NAME; # recupero l'elenco di tutte le tabelle

        sub.ont <- toupper(sub.ont);
        if (sub.ont %in% c("MF", "BP", "CC")) { # quale sub-ontology è stata scelta?
            pattern <- paste('_GO', tolower(sub.ont), '$', sep="");
            table.list <- grep(pattern, table.list, value=TRUE);
            if (pop.acc || pop.orth) { # sono stati scelti GO term rappresentativi di solo una parte dei target predetti?
                if (pop.orth) { pattern <- paste('_orth', pattern, sep=""); }
                if (pop.acc) { pattern <- paste('_acc', pattern, sep=""); }
                table.list <- grep(pattern, table.list, value=TRUE);
            } else {
                pattern <- paste('(_orth|_acc)+', pattern, sep="");
                exclude <- grep(pattern, table.list, value=TRUE, perl=TRUE);
                table.list <- setdiff(table.list, exclude);
            }
        } else {
            print(sub.ont);
            stop('unknown sub-ontology ("MF";"BP";"CC")');
        }
    }

    for (mm9.table in table.list) { # recupero la lista dei GO terms
        query.string <- paste("SELECT row_names FROM", mm9.table);
        term.list <- as.character(sqlQuery(dbh, query.string)[[1]]);
        go.list <- c(go.list, term.list);
    }

    go.list <- go.list[!is.na(go.list)]; # rimuovo gli NA
    go.list <- unique(go.list); # rimuovo i doppioni

    odbcClose(dbh);  # chiudo il canale
    writeLines("-- GO term list retrieved!");
    
    { # verifico quali termini GO sono contemplati dal package GOSemSim
        go.list.A <- array(); # lista rifinita da <go.list>
        
        for (go.check in go.list) {
            semsim.score <- goSim(go.check, go.root.id[[sub.ont]], organism=organism, ont=sub.ont, measure=semsim.algorithm);
            if (semsim.score != 0) { go.list.A <- c(go.list.A, go.check); }
        }
        go.list.A <- go.list.A[-1]
    }
    
    writeLines("-- Building Semantic Similarity Score Matrix...");
    # inizializzo la matrice di similarity scores costruendo go.list[goterm.A], go.list[goterm.B]una matrice identità di adeguate dimensioni
    sim.score.matrix <- matrix(NA, nrow = length(go.list.A), ncol = length(go.list.A), dimnames = list(go.list.A, go.list.A));
    diag(sim.score.matrix) <- 1;

    for (goterm.A in seq(1,length(go.list.A)-1,1)) { # con due for annidati costruisco tutte le combinazioni possibili di coppie di GOterms
        go.list.B <- seq(goterm.A + 1,length(go.list.A),1);
        for (goterm.B in go.list.B) {
            semsim.score <- goSim(go.list.A[goterm.A], go.list.A[goterm.B], organism=organism, ont=sub.ont, measure=semsim.algorithm);
    #         print(paste("SemSim score among", go.list.A[goterm.A], go.list.A[goterm.B], "=>", semsim.score));
            sim.score.matrix[go.list.A[goterm.A], go.list.A[goterm.B]] <- semsim.score -> sim.score.matrix[go.list.A[goterm.B], go.list.A[goterm.A]]
        }
    }
    writeLines("-- Semantic Similarity Score Matrix Done!");
    return(sim.score.matrix);
}