# # TEMPLATE STANDARD
# help.start()    # help su browser
rm(list = ls())    # rimuovo tutti gli oggetti presenti nella sessione
setwd('~/my_mir/R_scripts')     # mi sposto sul path dove tengo i miei scripts
# load(file = '/home/dario/my_mir/R_scripts/LastSession.RData'); # recupero l'immagine dell'ultima sessione di lavoro 
# # ###########################################################################
# Questo script mi serve per testare funzioni, metodi e classi del package in via di sviluppo



# TRIAL & ERROR CHUNK
remove.packages('MyMir')
Del MyMir_2.10-05.tar.gz; R CMD build /home/dario/my_mir/R_scripts/MyMir; R CMD INSTALL MyMir_2.10-05.tar.gz
library('MyMir')

# salvo l'immagine dell'ultima sessione di lavoro 
# save.image(file = '/home/dario/my_mir/R_scripts/LastSession.RData');
