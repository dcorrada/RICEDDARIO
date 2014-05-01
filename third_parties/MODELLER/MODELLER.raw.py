from modeller import *
from modeller.automodel import *
from modeller.scripts import complete_pdb


log.level(output=1, notes=0, warnings=0, errors=1, memory=0)
env = environ()

env.patch_default = False
env.io.atom_files_directory = './'  # path per i file di input; si possono aggiungere piu' path come se fosse un array es. ['.', '../atom_files']


# Creazione di una classe per definire su quali regioni condurre il loop refinement
class myloop(automodel):
    def select_atoms(self):
        return selection(self.residue_range('507:C', '516:C')) # elenco dei loop ([resid]:[chain])
                         #self.residue_range('66:', '69:'), # all'occorrenza se ne possono mettere di piu'
                         #self.residue_range('49:', '52:'))

# Aggiunta di restraint sepciali se qualche regione viene predetta con elementi di struttura secondaria ma cadono in un gap (quindi non hanno un templato di riferimento)
#    def special_restraints(self, aln):
#        rsr = self.restraints
# imposizione di un restraint su una regione predetta come beta-strand
#        rsr.add(secondary_structure.strand(self.residue_range('143:','149:')))


a = myloop(env,
              alnfile  = 'alignment.ali',     # alignment filename
              knowns   = 'clean',              # codes of the templates
              sequence = 'patch')              # code of the target
a.starting_model= 1                 # index of the first model 
a.ending_model  = 1                 # index of the last model
                                    # (determines how many models to calculate)
a.md_level = None
a.make()                            # do the actual homology modeling
