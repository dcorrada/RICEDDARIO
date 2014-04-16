Per quanto riguarda gli script Perl in genere aggiornare la variabile d'ambiente 
PERL5LIB, specificando la directory parent più prossima. Esempio, se intalli il 
pacchetto in "/home/user/Desktop/RICEDDARIO" allora:

    export PERL5LIB=/home/user/Desktop:$PERL5LIB
