# Scriptino GNUplot per plottare i profili DOPE di templato e modello

set terminal png size 2400, 800
set size ratio 0.33
set output "DOPE.profile.png"
set key outside
set grid
set tics out
set xtics 5
set mxtics 5
set xlabel "resID"
set ytics 0.005
set mytics 5
set xlabel "DOPE"
plot '3F1P.profile' using 1:42 w l lc 3 lw 3 title '3F1P', \
'3F1O.profile' using 1:42 w l lc 2 lw 3 title '3F1O', \
'rawmodel.profile' using 1:42 w l lc 1 lw 3 title 'MODEL'