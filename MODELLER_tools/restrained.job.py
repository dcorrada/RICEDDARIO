# Questo script serve per modellare una struttura esistente (templato 1) con un 
# loop da un templato 2. Lo scopo è quello di mantenere nel modello intatta la 
# struttura del templato 1 e appiccicarci il loop proveniente dal templato 2

from modeller import *              # Load standard Modeller classes
from modeller.automodel import *    # Load the automodel class

log.level(output=1, notes=0, warnings=0, errors=1, memory=0)
env = environ()  # create a new MODELLER environment to build this model in

# directories for input atom files
env.patch_default = False
env.io.atom_files_directory = './'

env.io.hetatm = True # se ci sono ligandi da includere mantenere questa riga

# Questo blocco definisce la regione sulla sequenza target da lasciar libera di 
# muovere, in questo caso per adattare il loop del templato 2 al templato 1. 
# Tutto il resto rimane freezato secondo le coordinate del templato 1
class MyModel(automodel):
    def select_atoms(self):
        return selection(self.residue_range('90', '101'))

a = MyModel(env,
              alnfile  = 'alignment.ali',     # alignment filename
              knowns   = ('3F1O', '3F1P'),    # codes of the templates
              sequence = 'rawmodel')          # code of the target

# Qui creo un solo modello senza rifinire (a.md_level = None) di modo da 
# mantenere il loop generato il più possibile simile alla conformazione 
# del templato 2
a.starting_model= 1
a.ending_model  = 1
a.md_level = None

a.make()                            # do the actual homology modeling
