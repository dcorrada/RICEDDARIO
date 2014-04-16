# *** MACRO
# Le macro sono selezioni personalizzate definite con una stringa alfanumerica.
# Vengono inizializzate via Tcl console, e poi possono essere richiamate in VMD
# come le Singlewords.

# faccio una prima macro e la chiamo "pippo"
atomselect macro pippo {resid 3 to 54};
# faccio una seconda macro, subset di "pippo", e la chiamo "pluto"
atomselect macro pluto {backbone and pippo};
# cancello la macro "pippo"
atomselect delmacro pippo;
# ATTENZIONE: cancellando "pippo" la macro figlia "pluto" non funziona non
# essendo più definita

