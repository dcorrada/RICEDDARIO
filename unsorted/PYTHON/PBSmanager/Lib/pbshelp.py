# coding: UTF-8

#questo modulo dovrebbe servirmi per scrivere il PBS
import copy,os,sys,types,re,commands,time
from os.path import abspath,curdir

#un po' di variabili che dovrebbero valere per tutta la libreria
__author__ = "Paolo Cozzi <paolo.cozzi@itb.cnr.it>"

#questo è il numero massimo di job che possono essere eseguiti contemporanamente
MAX_QUEQUED_JOBS = 20
#se la coda è piena, devo aspettare questo tempo
QUEUE_TIME = 600
#ci sono dei casi dove il server non risponde Ex. No Permission.qsub: cannot connect to server michelangelo (errno=15007)
#in questi casi ho visto che basta aspettare un po' prima di ripetere la richiesta. Questo è il temp oche aspetto
SERVER_TIME = 300
#se non riesco a fare la stessa richiesta al server (per il problema No permission o altri di cui non so) ripeto per altre
SERVER_FAIL = 8

class pbs:
	"""In questa classe vorrei mettere i parametri che mi servono
	per scrivere un job PBS"""
	def __init__(self):
		"""Inizializza la classe"""
		self.parameters = {}
		
		#per le risorse disponibili, avrò un altro dizionario in base al tipo di risorsa
		self.parameters['#PBS -l'] = {}
		
		#posso definire dei parametri di default
		self.SetJobName()
		self.SetCWD()
		self.SetQueue()
		self.SetNofNodes()
	
	def SetJobName(self,name='pbsjob.sh'):
		"""Permette di settare il nome del job PBS. Di default
		e' pbsjob.sh"""
		self.parameters['#PBS -N'] = name
		
	def GetJobName(self):
		"""Recupera il nome del job PBS"""
		return self.parameters['#PBS -N']
	
	def SetCWD(self,cwd=None):
		"""Imposta la directory di lavoro per il job PBS.
		Di default è quella corrente"""
		
		#se non l'ho specificata, la directory è quella corrente
		if cwd == None:
			cwd = abspath(curdir)
			
		self.parameters['#PBS -d'] = cwd
		
	def GetCWD(self):
		"""Restituisce la directory di lavoro per il job PBS"""
		return self.parameters['#PBS -d']
	
	def SetQueue(self,queue='projects'):
		"""Imposta la coda dove eseguire il job. La queue di default
		e' 'projects'"""
		
		self.parameters['#PBS -q'] = queue
		
	def GetQueue(self):
		"""Restituisce la coda per il job PBS"""
		return self.parameters['#PBS -q']
	
	def SetNofNodes(self,nodes=1):
		"""Permette di impostare il numero di nodi richiesti"""
		
		#i nodi come la memoria fanno parte della lista delle risorse
		self.parameters['#PBS -l']['nodes'] = "%s" %(nodes)
		
	def GetNofNodes(self):
		"""Restituisce il numero dei nodi richiesti"""
		return self.parameters['PBS -l']['nodes']
	
	#da qui metto le funzioni che non sono attivate di default
	def SetMem(self,mem):
		"""Permette di definire quanta RAM utilizzare per eseguire il job-pbs
		devi definirla come stringa, 'tipo 1024mb'"""
		
		#anche la memoria fa parte dell'elenco delle risorse
		self.parameters['#PBS -l']['mem'] = "%s" %(mem)
		
	def GetMem(self):
		"""Permette di recuperare quanta memoria si ha richiesto"""
		return self.parameters['#PBS -l']['mem']
	
	def GetParameters(self):
		"""Restituisce il dizionario dei parametri impostati"""
		return self.parameters
	
	def SetParameters(self,dict_parameters):
		"""Permette di ridefinire il dizionario dei parametri"""
		if type(dict_parameters) != types.DictType:
			raise Exception, "Devi passare un dizionario di parametri"
		
		self.parameters = dict_parameters
		
	def SetCommands(self,list_cmd):
		"""Permette di definire una lista di comandi"""
		
		if type(list_cmd) != types.ListType:
			raise Exception, "Devi passare un lista di comandi"
		
		self.commands = list_cmd
		
	def GetCommands(self):
		"""Restituisce la lista di comandi da mandare a PBS"""
		return self.commands
	
class writepbs(pbs):
	"""Questa classe permette di scrivere un file PSB con i 
	requisiti che interessano all'utente"""
	def __init__(self):
		"""Instanzia la classe writepbs"""
		
		#applico l'init di pbs. In questo modo passo anche i parametri
		pbs.__init__(self)
	
	def SetPbs(self,pbs):
		"""Permette di passare un oggetto pbs a questa classe, e di
		reimpostare i parametri"""
		
		#devi verificare di passare un oggetto PBS
		#come faccio con il python 2.3?
		
		#adesso posso passargli i parametri
		self.parameters = pbs.GetParameters()
		
		#devo passargli i comandi
		self.commands = pbs.GetCommands()
	
	def WritePbsfile(self,directory=None):
		"""Scrive un file PBS nella directory specificata, di default
		e' la directory corrente. Si restituisce il percorso del file pbs"""
		
		if directory == None:
			directory = abspath(curdir)
		
		#prendo nota di dove ho salvato il file
		filename = "%s/%s" %(directory,self.GetJobName())
			
		file_pbs = open(filename,'w')
		
		#sh è la shell favorita
		file_pbs.write('#! /bin/sh\n\n')
		
		#adesso butto dentro tutti i parametri che ho definito
		for (parameter,value) in self.GetParameters().iteritems():
			#devo stare attento a quando valuto le risorse che voglio utilizzare
			if parameter == '#PBS -l':
				#in questo caso sto valutando le risorse che devo utilizzare
				#devo ciclare lungo il dizionario delle risorse
				for (resource,amount) in value.iteritems():
					file_pbs.write("%s %s=%s\n" %(parameter,resource,amount))
			
			else:
				#in questo caso, avrò un solo valore per tipo di parametro
				file_pbs.write("%s %s\n" %(parameter,value))
			
		#fuori dal ciclo posso staccare una riga (per chiudere i parametri)
		#e inserire i comandi
		file_pbs.write('\n')
		
		#scrivo tutti i comandi che mi sono stati passati
		try:
			for cmd in self.GetCommands():
				file_pbs.write("%s\n" %(cmd))
			
		except AttributeError:
			raise Exception, "Non hai definito nessun comando da eseguire con il job"
		
		#chiudo il file dei dati
		file_pbs.close()
		
		#attacco il filename a self
		self.filename = filename
		
		#restituisco il percorso del file (se serve)
		return filename
		
class qsub:
	"""Una classe per gestire le sottomissioni"""
	def __init__(self):
		"""instanzia la classe"""
		pass
	
	def Submit(self,filename):
		"""Permette di lanciare qsub specificando un percorso del file PBS"""
		
		#per prima cosa verifico quanti job sono in coda (esecuzione, waiting etc)
		test = qstat()
		
		#quando ci sono troppi job in esecuzione, anziche alzare un eccezione, provo ad aspettare
		#un po' e riprovare a sottomettere il job. Sperando non fare cazzate...
		
		#Questa variabile mi dirà se ho sottomesso oppure no.
		flag_submitted = 0
		
		#se ci sono errori, posso richiedere al massimo 8 volte
		count = 0
		
		while flag_submitted == 0 and count < SERVER_FAIL:
			n_of_jobs = test.ReadStatus()
		
			if n_of_jobs < MAX_QUEQUED_JOBS:
				#allora posso lanciare il Job perchè ne ho spediti pochi
				(status,output) = commands.getstatusoutput("qsub %s" %(filename))
		
				#ci sono dei casi in cui il server PBS non risponde. In questo caso aspetto SERVER_TIME
				#e rifaccio la stessa richiesta per SERVER_FAIL volte
				if status != 0:
					print "Il lancio di %s non e' andato a buon fine: %s. Riprovo..." %(filename,output)
					count += 1
					time.sleep(SERVER_TIME)
				else:
					#aggiorno il flag (sono riuscito a sottomettere)
					flag_submitted = 1
			
			else:
				print "Ci sono troppi (%s) job in esecuzione. Aspetto un attimo" %(n_of_jobs)
				#svuoto il bufffer per STDIN
				sys.stdout.flush()
				time.sleep(QUEUE_TIME)
				
		#fuori dal while, o ho sottomesso il Job (flag_sumbitted == 1)
		if flag_submitted == 1:
			#ritorno l'output (che sarebbe l'id del job?)
			return output
		
		#altrimenti ho avuto SERVER_FAIL errori e non ho sottomesso (flag_submitted == 0)
		else:
			#stampo a video che cos'era filename
			file = open(file,'r')
			data = file.readlines()
			file.close()
			
			for line in data:
				print line,
			
			#adesso lancio l'eccezzione
			raise Exception, "Non sono risucito a sottomettere %s: %s" %(filename,output)
		
		#fine della funzione


class qstat:
	"""Una classe per monitorare le sottomissioni"""
	def __init__(self):
		"""instanzia la classe"""
		
		#simulo il fatto che ho fatto un qstat
		#self.status = """
		#Job id              Name             User            Time Use S Queue
		#------------------- ---------------- --------------- -------- - -----
		#17277.michelangelo  pbsjob.sh        pcozzi          00:01:24 R projects
		#17278.michelangelo  pbsjob.sh        pcozzi          00:01:24 R projects
		#17279.michelangelo  pbsjob.sh        pcozzi          00:01:23 R projects
		#17280.michelangelo  pbsjob.sh        pcozzi          00:01:23 R projects
		#"""
		pass
		
	def ReadStatus(self):
		"""Permette di legqere lo status dei Job sottomessi. In uscita si ritorna il
		numero dei job in coda"""
		
		#inizializzo questi attributi di classe, così se qstat non restituice job
		#non faccio casini
		self.raw_status = []
		self.job_status = {}
		
		#eseguo qstat
		(status,output) = commands.getstatusoutput('qstat')
		
		#Ho visto che a volte qstat non risponde, perciò provo a ripetere qstat ogni
		#minuto, fino a che non mi risponde. Ci provo per 8 volte, Altrimenti lancio l'eccezione
		count = 0
		
		#ci sono dei casi in cui il server PBS non risponde. In questo caso aspetto SERVER_TIME
		#e rifaccio la stessa richiesta per SERVER_FAIL volte
		while status != 0 and count < SERVER_FAIL:
			#in questo caso qstat non è andato a buon fine, aspetto SERVER_TIME
			time.sleep(SERVER_TIME)
			
			#aggiorno count
			count += 1
			
			#rilancio qstat
			(status,output) = commands.getstatusoutput('qstat')
			
		#se fuori dal ciclo, non sono riuscito a fare qstat
		if status != 0:
			#lancio finalmente l'eccezione
			raise Exception, "qstat -a ha restituito stato %s" %(status)
		
		#ok, se non c'è nessun risultato ritorno al chiamante
		if len(output) == 0:
			return
		
		#per prima cosa divido le righe dello status
		lines = output.split('\n')
				
		#adesso la prima riga sono le colonne, le altre sono i dati
		columns = lines.pop(0)
		
		#adesso splitto le colonne su \s\s+
		columns = re.split('\s\s+',columns)
		
		#gli ultimi tre campi sono adesso all'ultimo posto della lista columns
		tmp = columns.pop()
		
		#forse è più semplice che li aggiunga a mano
		columns += ['Time Use', 'S', 'Queue']
		
		#la seconda linea è quella della riga orizzontale
		del lines[0]
		
		#adesso splitto le restanti colonne per leggere i singoli job
		jobs = []
		
		for line in lines:
			line = re.split('\s+',line)
			jobs += [line]
			
		#memorizzo la tabella degli status
		self.raw_status = [columns] + jobs
		
		#adesso leggo per ogni job ID uno status
		jobs = {}
		
		#questi sono i possibili stati di un job
		#C -  Job is completed after having run/
		#E -  Job is exiting after having run.
		#H -  Job is held.
		#Q -  job is queued, eligible to run or routed.
		#R -  job is running.
		#T -  job is being moved to new location.
		#W -  job is waiting for its execution time
			#(-a option) to be reached.
		#S -  (Unicos only) job is suspend.
		
		completed = 0
		exiting = 0
		held = 0
		queued = 0
		running = 0
		location = 0
		waiting = 0
		suspend = 0
		
		#vorrei prendere nota di quanti job sono running,
		for line in self.raw_status[1:]:
			#la cella 0 è quella del jobID, mentre la 4 è quella dello status
			jobs[line[0]] = line[4]
			
			#valuto i vari stati. Per completed
			if line[4] == 'C':
				completed += 1
				
			#per exiting
			elif line[4] == 'E':
				exiting += 1
				
			#per held
			elif line[4] == 'H':
				held += 1
				
			#per queued
			elif line[4] == 'Q':
				queued += 1
				
			#per running
			elif line[4] == 'R':
				running += 1
				
			#per location
			elif line[4] == 'T':
				location += 1
				
			#per waiting
			elif line[4] == 'W':
				waiting += 1
				
			#per suspend 
			elif line[4] == 'S':
				suspend += 1
				
			else:
				#non so cosa sia lo status
				print line
				raise Exception, "Non so leggere lo status di status di questo job"
		
		#il numero dei job che vedo con qstat
		self.n_of_jobs = len(self.raw_status[1:])
		
		#mi segno il dizionario dei Job e dei loro status
		self.job_status = jobs
		
		#creo un dizionario per ricordarmi quanti job sono nei diversi stati
		self.queue_status = {'completed' : completed, 'exiting' : exiting, 'held' : held, 'queued' : queued, 'running' : running, 'location' : 	location, 'waiting' : waiting, 'suspend' : suspend}
		
		#ritorno il numero dei job che vedo in coda
		return self.n_of_jobs
			
	def GetStatus(self):
		"""permette di leggere lo stato dei Job e ritornare una Lista con tutti i job in esecuzione"""
		
		#provo a ritornare il mio stato
		try:
			return self.raw_status[1:]
		except AttributeError:
			#in questo caso, non ho ancora letto lo stato, perciò
			n_of_jobs = self.ReadStatus()
			#adesso posso tornare il risultato
			return self.raw_status[1:]
			
	
class qdel:
	"""Una classe per killare i vari job"""
	def __init__(self):
		"""Instanzia la classe"""
		pass
	def KillAll(self):
		"""Uccide tutti i job in esecuzione"""
		
		#per prima cosa leggo in job in eseguzione
		running_jobs = qstat()
		n_of_jobs = running_jobs.ReadStatus()
		
		#adesso ciclo per ogni job che ho letto
		for job in running_jobs.GetStatus():
			#l'id del job sta nella prima cella della tupla job
			jobID = job[0]
			
			#posso cancellare il job
			(status,output) = commands.getstatusoutput("qdel %s" %(jobID))
		
			if status != 0:
				print "Non ho potuto killare %s: %s" %(jobID,output)
			
		#fine delle pippe mentali
		return
		
	def KillbyJobID(self,jobID):
		"""permette di uccidere un Job specificando un id"""
		
		#eseguo il comando
		(status,output) = commands.getstatusoutput("qdel %s" %(jobID))
		
		if status != 0:
			raise Exception,  "Non ho potuto killare %s: %s" %(jobID,output)
			
		#fine
		return
		
	def KillbyJobName(self,name):
		"""permette di uccidere tutti quei job che hanno lo stesso JobName"""
		
		#per prima cosa leggo in job in eseguzione
		running_jobs = qstat()
		n_of_jobs = running_jobs.ReadStatus()
		
		#adesso ciclo per ogni job che ho letto
		for job in running_jobs.GetStatus():
			#l'id del job sta nella prima cella della tupla job
			#il suo nome nella seconda
			(jobID,jobname) = (job[0],job[1])
			
			#qui controllo che jobname sia == a quello fornito in ingress
			if jobname == name:
				#posso cancellare il job
				self.KillbyJobID(jobID)
			
		#fine 
		return
		
