#! /usr/bin/perl

#importo le librerie che mi servono

use strict;
use DBI;

#ogni variabile che voglio usare la devo dichiarare con MY;
my @output; my ($conta,$step,$totale,$i,$j);

#mi connetto al database con DBI:mysql:NOME_DEL_DATABASE:INDIRIZZO_IP:3306, utente e password
my $dbh = DBI -> connect("DBI:mysql:epcr_mutanti2:localhost:3306","root","")
	or die "non mi posso connettere " . DBI -> errstr;

#per leggere quante righe ho (so che sono 514)
my $sth_count = $dbh->prepare("SELECT count(*) FROM docking")
	or die "non posso preparare lo stat\n" . $dbh -> errstr;

#per leggere solo 9 righe alla volta
my $sth_sel;

#leggo quante righe ci sono
$sth_count -> execute()
	or die "Non posso eseguire lo stat" . $dbh -> errstr;

#con questo recupero il risultato della select
my $righe = $sth_count->fetchrow_array();

#chiudo lo stat perchè non mi serve +
$sth_count->finish();


print "\n\nRighe $righe\n";

$step = 0; $conta = 0; 

#ok ora lancio lo stat per 9 righe alla volta
for ($i=0;$i<=$righe;$i=$i+9)
	{#preparo lo stat per un gruppo
	$sth_sel = $dbh -> prepare("SELECT IDS,protein,chain,res_num,res_name,ligand,energy,run,num_cluster,Ki_num,Ki_unit FROM docking LIMIT $i, 9")
        	or die "non posso preparare lo stat\n" . $dbh -> errstr;

	$sth_sel->execute()
		or die "Non posso eseguire lo stat\n" . $dbh -> errstr;
	
	#ciclo per ognuna delle 9 righe
	while (@output = $sth_sel->fetchrow_array())
		{#print "@output\n";

		#la quarta colonna della tabella è quella che ti interessa
		if ($output[3] eq 11)
			{$conta++;}
		
		#incremento un contatore
		$j++;

		}

	#fine della select
	$sth_sel->finish();

	#stampo il gruppo e quante cose ho trovato
	print "Step: $step, da: $i a $j, tot: $conta\n";

	#il totale delle cose viste
	$totale = $totale + $conta;

	#mando avanti step di uno (per il prossimo gruppo da 9) e azzero $conta
	$step++; $conta = 0;

	}

print "\n\nTotale: $totale\n";

#quando ho finito tutto mi disconnetto
$dbh->disconnect();
