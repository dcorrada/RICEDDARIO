from modeller import *
from modeller.automodel import *
from modeller.parallel import *

# Use 2 CPUs in a parallel job on this machine
j = job()
j.append(local_slave())
j.append(local_slave())

log.level(output=1, notes=0, warnings=0, errors=1, memory=0)
env = environ()

env.io.atom_files_directory = './'  # path per i file di input
                                    # si possono aggiungere piu' path separati dal simbolo ':'
                                    # (in modo analogo alla variabile di ambiente $PATH)


a = automodel (env,
               alnfile  = 'align.pir',                        # file di allineamento (.pir o .ali)
               knowns   = ('snd0102', 'snd0203', 'snd0304', 'snd0405', 'snd0506', 'snd0607', 'snd0708'),     # codice della sequenza templato
               sequence = 'snd0106',                         # codice della sequenza target
               assess_methods=(assess.DOPE, assess.GA341))   # funzioni di scoring per i modelli generati

# Numero di modelli "grezzi"
a.starting_model= 1
a.ending_model= 4


#
# OTTIMIZZAZIONE DEI MODELLI
#

# Minimizzazione
a.library_schedule = autosched.normal     # autosched.slow, autosched.normal, autosched.fast, autosched.very fast, autosched.fastest
a.max_var_iterations = 300

# Dinamica molecolare
# None, refine.very_fast, refine.fast, refine.slow, refine.very_slow, refine.slow_large
a.md_level = refine.very_fast             # MD globale sul modello

# Cicli di ottimizzazione
a.repeat_optimization = 3
a.max_molpdf = 1e6

a.use_parallel_job(j)               # Use the job for model building
a.make()                            # JOB PER LA CREAZIONE DEI MODELLI



#
# RANKING DEI MODELLI
#
ok_models = filter(lambda x: x['failure'] is None, a.outputs) # crea una lista dei modelli buoni

# ordina i modelli con la scoring function DOPE
key = 'DOPE score'
ok_models.sort(lambda a,b: cmp(a[key], b[key]))


# fornisce una lista dei modelli ordinata secondo DOPE score
print "\n\n*** TOP RANK ***\n"
for i in range(4):
      m = ok_models[i]
      print "%s (DOPE score %.3f)" % (m['name'], m[key])

