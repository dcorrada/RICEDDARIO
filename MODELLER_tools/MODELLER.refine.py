from modeller import *
from modeller.automodel import *
from modeller.scripts import complete_pdb


log.level(output=1, notes=0, warnings=0, errors=1, memory=0)
env = environ()

env.io.atom_files_directory = './'  # path per i file di input; si possono aggiungere piu' path come se fosse un array es. ['.', '../atom_files']


# Creazione di una classe per definire su quali regioni condurre il loop refinement
class myloop(dope_loopmodel):
    def select_loop_atoms(self):
        return selection(self.residue_range('507:C', '516:C')) # elenco dei loop ([resid]:[chain])
                         #self.residue_range('66:', '69:'), # all'occorrenza se ne possono mettere di piu'
                         #self.residue_range('49:', '52:'))

# Aggiunta di restraint sepciali se qualche regione viene predetta con elementi di struttura secondaria ma cadono in un gap (quindi non hanno un templato di riferimento)
#    def special_restraints(self, aln):
#        rsr = self.restraints
# imposizione di un restraint su una regione predetta come beta-strand
#        rsr.add(secondary_structure.strand(self.residue_range('143:','149:')))


m = myloop(env,
            sequence = 'refined',            # codice dei file di output
            inimodel='patch.B99990001.pdb',  # nome del modello migliore ottenuto nella fase di fine-models
            loop_assess_methods=assess.DOPE)
            #assess_methods=(assess.DOPE, assess.GA341))

# (determina il numero di modelli da calcolare)
m.loop.starting_model= 1          # primo modello rifinito 
m.loop.ending_model  = 10         # ultimo modello rifinito


# RAFFINAMENTO DEI MODELLI
# Minimizzazione
m.library_schedule = autosched.slow
m.max_var_iterations = 300
# Dinamica molecolare
# I parametri x la profondita' della dinamica molecolare sono i seguenti: none, refine.very_fast, refine.fast, refine.slow, refine.very_slow, refine.slow_large
m.md_level = refine.very_slow
# Cicli di ottimizzazione
m.repeat_optimization = 3
m.max_molpdf = 1e6


# LANCIO DEI JOB
m.make()


# GENERAZIONE DEI DOPE PROFILES
#env.libs.topology.read(file='$(LIB)/top_heav.lib')
#env.libs.parameters.read(file='$(LIB)/par.lib')

#num_file = ['01', '02' , '03' , '04', '05', '06', '07', '08', '09', '10']

#nome_file_input = 'refined.BL00%s0001.pdb' # nome dei modelli creati da sottoporre a valutazione DOPE

#nome_file_output = 'modello%s.profile'

#for ciclo in num_file:
    #mdl = complete_pdb(env, nome_file_input % ciclo) # read model file (i modelli creati)
    #s = selection(mdl)   # all atom selection
    #s.assess_dope(output='ENERGY_PROFILE NO_REPORT', file=nome_file_output % ciclo,
              #normalize_profile=True, smoothing_window=15) # Assess with DOPE:

#mdl = complete_pdb(env, 'patch.B99990001.pdb') # read model file (il modello iniziale, non loop refined)
#s = selection(mdl)   # all atom selection
#s.assess_dope(output='ENERGY_PROFILE NO_REPORT', file='modello-iniziale.profile',
              #normalize_profile=True, smoothing_window=15) # Assess with DOPE:

