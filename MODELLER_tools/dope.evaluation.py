# Questo script crea un profilo del DOPE score a partire da un modello o da un PDB

from modeller import *
from modeller.scripts import complete_pdb

log.verbose()    # request verbose output
env = environ()
env.libs.topology.read(file='$(LIB)/top_heav.lib') # read topology
env.libs.parameters.read(file='$(LIB)/par.lib') # read parameters

mdl = complete_pdb(
    env,
    'rawmodel.B99990001.pdb' # nome del PDB da valutare
)

# Assess with DOPE:
s = selection(mdl)
s.assess_dope(  
    output='ENERGY_PROFILE NO_REPORT',
    file='rawmodel.profile', # nome del file contenente il profilo DOPE
    normalize_profile=True,
    smoothing_window=5
)