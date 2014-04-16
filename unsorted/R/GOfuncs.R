
#~ Dato in input una regexp contenente una descrizione ritorna un vettore
#~ di termini GO che fanno riferimento a quella descrizione
#~ Es.: tutti i termini la cui descrizione comincia come "transcription factor..."
#~ > GOTerm2Tag("^transcription factor.+")
#~ [1] "GO:0000126" "GO:0000127" "GO:0005667" "GO:0005669" "GO:0005672"
#~ [6] "GO:0005673" "GO:0005674" "GO:0003700" "GO:0042991" "GO:0008134"
#~ [11] "GO:0033276"

GOTerm2Tag <- function(term) {
     GTL <- eapply(GOTERM, function(x) {
         grep(term, x@Term, value = TRUE)
     })
     Gl <- sapply(GTL, length)
     names(GTL[Gl > 0])
 }
