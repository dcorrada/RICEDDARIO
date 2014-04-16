# 
# Gnuplot script per rappresentare la matrice di differenza tra le matrici
# rmsdist ottenute per le forme apo e olo
# 
# Gnuplot script per rappresentare una matrice differenza a partire dalle fluttuazione delle distanze di Apo e Olo
# 


unset key # tolgo la legenda

set size square;

set pm3d map  # genero la palette di colori su una superficie bi-dimensionale
set palette defined ( 0 "dark-blue", 1 "blue", 2 "light-blue", 3 "white", 4 "light-red", 5 "red", 6 "dark-red" ) # colori della palette 
set cbrange[-5 to 5]  # estensione della colorramp

set tics out  # tics esterni al grafico

set xrange[0:437]  # il range dipende dal numero di residui (uso come riferimento il numero di residui del fab e solo quello: non plotto i risultati relativi alla catena dell'antigene)
set yrange[0:437]


set xtics 50  # setto la frequenza dei major tics
set ytics 50

set mxtics 10 # setto la frequenza dei minor tics
set mytics 10

# set title "diff matrix"
splot "matrix.diff.dat"


unset output
set terminal X11
quit



# stampa su file
# set terminal png size 800,800
# set output "matrix.png"
set terminal postscript color
set output "matrix.diff.ps"
# e riplottare
