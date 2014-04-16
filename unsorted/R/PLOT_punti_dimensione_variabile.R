# Esempio di scatterplot in cui la dimensione dei punti è variabile
npoints <- 100
posx = sample(seq(0, 1, 0.01), npoints, replace=T)
posy = sample(seq(0, 1, 0.01), npoints, replace=T)
pointSize = sample(seq(0, 5, 0.1), npoints, replace=T)

plot(posx, posy, pch=20, cex=pointSize, xlim=c(0,1), ylim=c(0,1)) 