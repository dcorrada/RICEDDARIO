#! /usr/bin/env python
# coding: UTF-8

#Voglio scrivere un programma per gestire i job PBS. Non ho ancora bene idea di che cosa mi serva per adesso
#cercherò di lanciare dei calcoli e vedere quali problemi ci sono con il lancio del job.

import sys,os,getopt

#importo i miei moduli
import pbshelp

#devo impostare il programma in modo da ricevere dei parametri, e lanciare qsub in modo trasparente

#definisco la variabie usage
usage = """

	%s: programma per lanciare dei comandi con qsub
	
	uso %s [<parameters> | <filename1> <filename2> ]
	
	--commands='<list_of_commands>': una lista di comandi da lanciare
	--mem=<size>: specifica quanta memoria usare in Mb.
	--jobname=<name>: il nome da assegnare al job
	
	-----------------------------------------------------------------------
	
	<filename>: passa il file specificato cosi' com'e' a qsub 

""" %(sys.argv[0],sys.argv[0])

if len(sys.argv) <= 1:
	#in questo caso non ho dato nessun parametro
	print usage
	sys.exit(1)

#per prima cosa imposto leggo i parametri
try:
	[optlist,filenames]=getopt.gnu_getopt(sys.argv[1:],'',['commands=','mem=','jobname='],)
except getopt.GetoptError, message:
	raise Exception, "Comando non riconosciuto: %s\n%s" %(message,usage)

#optlist contiene tutte le opzioni legalizzate
#filenames sono argomenti che non sono opzioni, ad esempio il nome di un file

#adesso controllo di aver specificato o i parametri o un file
if len(optlist) == 0 and len(filenames) != 0:
	#in questo caso faccio un qsub (con le mie liberie) di ogni file che mi hai passato
	Qsub = pbshelp.qsub()
	
	for file in filenames:
		Qsub.Submit(file)
		
elif len(optlist) != 0 and len(filenames) == 0:
	#qui creo un oggetto pbs, gli passo i comandi, scrivo il file e lo lancio
	#per adesso il nome del file PBS sarà quello di defaults
	Pbs = pbshelp.pbs()
	
	#ciclo lungo la lista delle opzioni-valori
	for opzione in optlist:
		[comando,valore] = opzione
		
		#prendo il comando e lo preparo
		if comando == '--commands':
			#passo i comandi come una lista di valori
			Pbs.SetCommands([valore])
			
		if comando == '--mem':
			#passo quanta memoria usare
			Pbs.SetMem("%smb" %(valore))
			
		if comando == '--jobname':
			#passo il nome del job
			Pbs.SetJobName(valore)
	
	#Qui dovrei aver analizzato tutte le opzioni
	#creo una classe per il file pbs, passo le cose e creo il file da lanciare
	filePBS = pbshelp.writepbs()
	filePBS.SetPbs(Pbs)
	
	#debug
	#print filePBS.parameters
	#print filePBS.commands
	file = filePBS.WritePbsfile()

	#una volta salvato il file, lo posso sottomettere
	Qsub = pbshelp.qsub()
	Qsub.Submit(file)
	
else:
	
	raise Exception, "Errore: O specifichi i parametri, o i file da inviare\n%s" %(usage)

#fine del programmino
