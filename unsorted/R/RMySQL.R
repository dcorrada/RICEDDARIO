help.start()    # help su browser


library(DBI)    # avvio l'interfaccia generica DBI...
library(RMySQL) # e quella specifica per MySQL

dbd<-dbDriver("MySQL")   # carico il driver per MySQL
dbh<-dbConnect(dbd, user="dario", dbname="mm9")    # stabilisco una connessione al database

# preparo la query in uno statement handle
sth<-dbSendQuery(dbh, paste("SELECT kgID, mirID, tot_orth, tot_pita",
                            "FROM predicted_sites",
                            "WHERE tot_nrsites > 10"))

# fa un fetch della query passata allo statement handle nel dataframe 'tabella'
# NON tipizza i vettori di stringhe come factor
result<-fetch(sth)


# fa un fetch della tabella 'sites_scores' nel dataframe 'tabella'
# NON tipizza i vettori di stringhe come factor
tabella<-dbReadTable(dbh, "sites_scores")


# creo sul database una nuova tabella ('risultati') che rispecchia il dataframe 'result'
dbWriteTable(dbh, "risultati", result, row.names=F)  

# elimino la tabella 'risultati' dal database
dbRemoveTable(dbh, "risultati")  

dbDisconnect(dbh)   # mi dicsonnetto dal database
