from modeller import *
from modeller.automodel import * 

log.level(output=1, notes=0, warnings=0, errors=1, memory=0)
env = environ()

env.io.atom_files_directory = './'  # path per i file di input
                                    # si possono aggiungere piu' path separati dal simbolo ':'
                                    # (in modo analogo alla variabile di ambiente $PATH)
#
# Creazione della classe per customizzare i restraints
#
class mymodel(automodel):
    def special_restraints(self, aln):
        rsr = self.restraints
# elenco dei restraints per imporre beta-strands:
        rsr.add(secondary_structure.strand(self.residue_range('4:','7:')))
        rsr.add(secondary_structure.strand(self.residue_range('11:','13:')))
        rsr.add(secondary_structure.strand(self.residue_range('18:','24:')))
        rsr.add(secondary_structure.strand(self.residue_range('33:','38:')))
        rsr.add(secondary_structure.strand(self.residue_range('42:','45:')))
        rsr.add(secondary_structure.strand(self.residue_range('50:','54:')))
        rsr.add(secondary_structure.strand(self.residue_range('64:','70:')))
        rsr.add(secondary_structure.strand(self.residue_range('73:','81:')))
        rsr.add(secondary_structure.strand(self.residue_range('97:','100:')))
        rsr.add(secondary_structure.strand(self.residue_range('105:','112:')))
        rsr.add(secondary_structure.strand(self.residue_range('117:','123:')))
        rsr.add(secondary_structure.strand(self.residue_range('141:','146:')))
        rsr.add(secondary_structure.strand(self.residue_range('151:','155:')))
        rsr.add(secondary_structure.strand(self.residue_range('163:','171:')))
        rsr.add(secondary_structure.strand(self.residue_range('174:','184:')))


a = mymodel(env,
              alnfile  = '1CVS.ali',                        # file di allineamento (.pir o .ali)
              knowns   = '1cvs',                            # codice della sequenza templato
              sequence = 'snd0405',                         # codice della sequenza target
              assess_methods=(assess.DOPE, assess.GA341))   # funzioni di scoring per i modelli generati
 

a.starting_model= 1                 # primo modello rifinito 
a.ending_model  = 10                # ultimo modello rifinito
                                    # (determina il numero di modelli da calcolare)

#
# RAFFINAMENTO DEI MODELLI
#
#
# Minimizzazione
a.library_schedule = autosched.slow
a.max_var_iterations = 300
#
# Dinamica molecolare
a.md_level = refine.very_slow  # I parametri x la profondita' della dinamica molecolare sono i seguenti:
                               # None, refine.very_fast, refine.fast, refine.slow, refine.very_slow, refine.slow_large
#
# Cicli di ottimizzazione
a.repeat_optimization = 3
a.max_molpdf = 1e6


a.make()   # JOB PER LA CREAZIONE DEI MODELLI

#
# RANKING DEI MODELLI
#
ok_models = filter(lambda x: x['failure'] is None, a.outputs) # crea una lista dei modelli buoni

# ordina i modelli con la scoring function DOPE
key = 'DOPE score'
ok_models.sort(lambda a,b: cmp(a[key], b[key]))

# fornisce il modello migliore
m = ok_models[0]
print "Top model: %s (DOPE score %.3f)" % (m['name'], m[key])




from modeller.scripts import complete_pdb

env.libs.topology.read(file='$(LIB)/top_heav.lib') # read topology
env.libs.parameters.read(file='$(LIB)/par.lib') # read parameters

num_file = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10']

nome_file_input = 'snd0405.B999900%s.pdb'

nome_file_output = 'modello%s.profile'

for ciclo in num_file:
    mdl = complete_pdb(env, nome_file_input % ciclo) # read model file
    s = selection(mdl)   # all atom selection
    s.assess_dope(output='ENERGY_PROFILE NO_REPORT', file=nome_file_output % ciclo,
              normalize_profile=True, smoothing_window=15) # Assess with DOPE:

mdl = complete_pdb(env, '1CVS-c_149-359.pdb') # read model file
s = selection(mdl)   # all atom selection
s.assess_dope(output='ENERGY_PROFILE NO_REPORT', file='templato.profile',
              normalize_profile=True, smoothing_window=15) # Assess with DOPE:

