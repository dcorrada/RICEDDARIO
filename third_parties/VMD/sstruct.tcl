# Templato da usare per annotare i sistemi contenenti FABs

# --- PRELIMINARI
# carico la struttura
mol new {/home/dario/PRIMA/conf.gro};
# carico la traiettoria
mol addfile {/home/dario/PRIMA/dinamica/MD_15ns.noPBC.protein.xtc};
# cancello il primo frame (che corrisponde al file della struttura)
animate delete beg 0 end 0 top;
# faccio un caching della struttura secondaria lungo tutta la traiettoria
start_sscache top;
# resetto la vista
display resetview;
# ---

# *****************************
# *** CENNI DI NOMENCLATURA ***
# *****************************
# Seguiro' la nomenclatura adottata x gli anticorpi e, piu' in generale, x i
# domini Ig-like.
# 
# CATENE - i frammenti FAB possiedono 2 catene: una leggera (light, L) e una
# pesante (heavy, H).
#
# DOMINI - per ogni catena esistono 2 domini: uno variabile, in posizione
# N-terminale, e uno costante, C-terminale. Per quanto riguarda la catena
# leggera i domini si chiameranno rispettivamente 'VL' e 'CL'. Nel caso invece
# della catena pesante i rispettivi domini si chiameranno 'VH' e 'CH1' (questo
# perche' nell'anticorpo completo la catena pesante e' strutturata in tre domini
# costanti piu' uno variabile [Cterm-CH3-CH2-CH1-VH-Nterm]; nel frammento FAB
# rimane solo la struttura [Cterm-CH1-VH-Nterm].
#
# FOGLIETTI ED ELICHE - i domini Ig-like variabili (v-type) e costanti (c-type)
# sono descritti da un motivo strutturale di base chiamato "Greek key
# beta barrel", in cui una serie da 7-9 b-strand va a definire due foglietti
# orientati in conformazione b-sandwich. Nella definizione della topologia degli
# strand uso come riferimento [Bork P. The immunoglobulin fold. Journal of
# molecular biology. 1994;242(4):309-20], Figura 1.
# I domini COSTANTI sono definiti da 7 strand organizzati come sheetI (d-e-b-a)
# e sheetII (g-f-c). Due corte eliche sono abbozzate a livello dei loop che
# connettono gli strand a-b ed e-f [Feige MJ. How antibodies fold. Trends in
# biochemical sciences. 2010;35(4):189-98].
# I domini VARIABILI sono definiti da 9 strand organizzati come sheetI (d-e-b-a)
# e sheetII (g-f-c-c'-c''). Lo strand g talvolta e interrotto da una porzione
# non strutturata, mentre lo strand a appare in parte associato allo strand g;
# la lunghezza degli strand c' e c'' e' variabile e a volte c'' non e' neanche
# strutturato.
# *****************************

# --- CATENE
# Nel definire le catene vado ad escludere quei residui N- e C-terminali che sono notoriamente estremamente mobili
atomselect macro chainL {resid 220 to 427}; # light chain

atomselect macro chainH {resid 3 to 214}; # heavy chain
# ---

# --- DOMINI
atomselect macro domVL {resid 220 to 323};
atomselect macro domCL {resid 329 to 427};

atomselect macro domVH {resid 3 to 116};
atomselect macro domCH1 {resid 123 to 214};
# ---

# --- ELEMENTI STRUTTURALI
# dominio VL, sheet I/a-b-e-d
atomselect macro sheetVL_1 {(resid 221 to 230) or (resid 236 to 242) or (resid 287 to 292) or (resid 279 to 284)};
# dominio VL, sheet II/g-f-c-c'-c''
atomselect macro sheetVL_2 {(resid 314 to 323)  or (resid 301 to 307) or (resid 250 to 255) or (resid 259 to 267) or (resid 270 to 271)};

# dominio CL, sheet I/a-b-e-d
atomselect macro sheetCL_1 {(resid 331 to 335) or (resid 347 to 357) or (resid 390 to 399) or (resid 376 to 381)};
# dominio CL, sheet II/g-f-c
atomselect macro sheetCL_2 {(resid 422 to 427) or (resid 408 to 414) or (resid 361 to 367)};
# dominio CL, alfa eliche
atomselect macro helicesCL {(resid 339 to 344) or (resid 401 to 405)};

# dominio VH, sheet I/a-b-e-d
atomselect macro sheetVH_1 {(resid 3 to 12) or (resid 16 to 25) or (resid 78 to 83) or (resid 68 to 73)};
# dominio VH, sheet II/g-f-c-c'-c''
atomselect macro sheetVH_2 {(resid 104 to 115) or (resid 92 to 99) or (resid 34 to 40) or (resid 44 to 52) or (resid 57 to 60)};

# dominio CH1, sheet I/a-b-e-d
atomselect macro sheetCH1_1 {(resid 124 to 128) or (resid 139 to 149) or (resid 178 to 188) or (resid 167 to 175)};
# dominio CH1, sheet II/g-f-c
atomselect macro sheetCH1_2 {(resid 210 to 214) or (resid 197 to 202) or (resid 155 to 158)};
# dominio CH1, alfa eliche
# atomselect macro helicesCH1 {(resid  to ) or (resid  to )}; # non ne trovo...
# ---

