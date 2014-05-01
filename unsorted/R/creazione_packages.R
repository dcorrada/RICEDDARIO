# # TEMPLATE STANDARD
# help.start()    # help su browser
rm(list = ls())    # rimuovo tutti gli oggetti presenti nella sessione
setwd('~/my_mir/R_scripts')     # mi sposto sul path dove tengo i miei scripts
# getwd()
# # ###########################################################################

# # INIZIALIZZAZIONI
# carico le library necessarie per il mio package
library(RODBC);
library(CORNA);
library(tools);
# carico la sessione con gli oggetti necesssari per il mio package
load(file = '/home/dario/my_mir/R_scripts/mymir_objects.Rdata');


# comando x creare la struttura base di un package, ritorna come valore eventuali side-effects
# Quando sarà tutto fatto <package.skeleton> creerà un file chiamato 'Read-and-delete-me' con cui procedere e da cancellare a procedura ultimata
package.skeleton(
    name = "mymir", # nome del package (sarà il nome anche della directory principale)
    list = c("coalesce.query", "fetch.crosslinks", "fetch.unipop", "unipop.data", "biomart.crosslinks", "query.build.population", "query.build.universe"), # vettore di stringhe in cui elenco gli oggetti da mettere dentro il package
    environment = .GlobalEnv, # environmente dove cercare gli oggetti della lista
    path = "/home/dario/my_mir/R_scripts", # path dove creare il package
    force = FALSE, # se vero sovrascrive su directory esistenti
);

# creazione dell'INDEX file
setwd('~/my_mir/R_scripts/mymir');
Rdindex(paste("./man/", dir(path = "./man"), sep = ""), outFile = "INDEX"); 

# # Comandi da lanciare via shell
R CMD build --use-zip "/home/dario/my_mir/R_scripts/myoop" # faccio un tarball del mio package
R CMD check myoop_0.10-04.tar.gz # faccio un check del mio package
R CMD INSTALL myoop_0.10-04.tar.gz # installo il package

# DISINSTALLARE il package
remove.packages("myoop");

# # UPDATE DEL PACKAGE:
# 1) Cancellare il file <mymir/INDEX>
# 2) Aggiornare il file <mymir/DESCRIPTION> (IMPORTANTE: specificare le dipendenze se vengono usati nuovi packages)
# 2b) Aggiornare il file <mymir/man/mymir-package.Rd> (ANALOGO del file DESCRIPTION)
# 3a) Se si tratta di un DATASET creare un nuovo file .rda nella cartella <mymir/data>  con il comando "save"
# 3b) Se si tratta di una FUNZIONE creare un nuovo script .R nella cartella <mymir/R>
# 4) Creare un nuovo file di documentazione .Rd nella cartella <mymir/man> per il nuovo oggetto aggiunto al package.
# 5) Creare un nuovo INDEX file con il comando "Rdindex" (package "tools")
# 6) Aggiornare il file <mymir/NAMESPACE> per definire quali variabili si intende esportare (in questo modo, ad es., si può richiamare la funzione "pippo" in maniera completamente qualificato)