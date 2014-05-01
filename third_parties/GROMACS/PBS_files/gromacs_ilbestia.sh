#!/bin/sh
#PBS -N Fbr4
#PBS -q projects
#PBS -l nodes=3:ppn=4
#PBC -V
NCPU=`wc -l < $PBS_NODEFILE`
cd $PBS_O_WORKDIR
echo "================================================================="
echo Master MPI process running on `hostname`
echo Working dir is $PBS_O_WORKDIR
echo Available resource are cat $PBS_NODEFILE
echo Number of CPU: $NCPU
echo "================================================================="
mpirun -v -np $NCPU /opt/GMX407/bin/mdrun -v >& md.job
