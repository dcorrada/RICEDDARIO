#!/bin/sh

grompp -f /home/dario/GOLEM_RAWDATA/tools/em.mdp -c ../allestimento/conf.ions.gro -p ../allestimento/topol.top -o em.tpr -maxwarn 2;

mdrun -s em.tpr -o em.trr -g em.log -e em.edr -c conf.em.gro -v;
