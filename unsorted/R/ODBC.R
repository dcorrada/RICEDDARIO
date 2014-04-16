help.start()    # help su browser

library(RODBC)    # avvio l'interfaccia ODBC

# apro un canale ('dbh') su un DSN MySQL ('default')
# le configurazioni dei DSN, sono nel file /etc/odbc.ini
dbh<-odbcConnect("mirna", pw = 'korda')

sqlQuery(dbh, "use mm9")    # accedo al database 'mm9'

# scarico la tabella 'sites_scores' nel dataframe 'tabella'
# tramite un vettore inizializzo il parametro as.is in modo tale che solo
# l'ultima colonna (vettore di stringhe) NON venga convertita in un dato di tipo factor
# as.is e' un parametro ereditato dalla funzione sqlQuery
tabella<-sqlFetch(dbh, sqtable='sites_scores', as.is=c(F,F,F,F,F,F,T))


# salvo il risultato di una query in un dataframe
# il parametro max (opzionale) indica quante righe salvare dalla query
result<-sqlQuery(dbh, paste("SELECT kgID, mirID, tot_orth, tot_pita",
                            "FROM predicted_sites",
                            "WHERE tot_nrsites > 10"),
                 max=10)
                 
# creo sul database una nuova tabella ('risultati') che rispecchia il dataframe 'result'
sqlSave(dbh, result, tablename='risultati')

# elimino la tabella 'risultati' dal database
sqlDrop(dbh, 'risultati')


odbcClose(dbh)    # chiudo il canale

# In alternativa ad usare ODBC su CRAN c'e' anche un package
# apposito chiamato 'RMySQL'; si tratta di una libreria DBI analoga
# nel funzionamento al DBI di Perl
