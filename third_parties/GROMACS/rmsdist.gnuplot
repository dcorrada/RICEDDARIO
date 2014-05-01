# 
# Gnuplot script per rappresentare le matrici di Giulia sulla fluttuazione delle distanze
# 

unset key # tolgo la legenda


set size 2,1  # dimensioni e posizione dell'area di lavoro
set origin 0,0

set multiplot  # x disegnare più grafi sull'area di lavoro

set pm3d map  # genero la palette di colori su una superficie bi-dimensionale
set cbrange[0 to 5]  # range della palette (da variare per mettere in evidenza le differenze, mantenere la stessa scala tra olo e apo)

set tics out  # tics esterni al grafico

set xrange[0:437]  # il range dipende dal numero di residui (uso come riferimento il numero di residui del fab e solo quello: non plotto i risultati relativi alla catena dell'antigene)
set yrange[0:430]


set xtics 50  # setto la frequenza dei major tics
set ytics 50

set mxtics 10 # setto la frequenza dei minor tics
set mytics 10

set size square 0.5,1 # plot della matrice APO
set origin 0,0
set title "APO form"
splot "matrix.APO.dat"

set size square 0.5,1 # plot della matrice OLO
set origin 0.5,0
set title "HOLO form"
splot "matrix.OLO.dat"

unset multiplot
unset output
set terminal X11
quit



# stampa su file
# set terminal png size 800,800
# set output "matrix.png"
set terminal postscript color
set output "matrix.ps"
# e riplottare