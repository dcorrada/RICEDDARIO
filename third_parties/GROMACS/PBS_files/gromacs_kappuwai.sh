#!/bin/sh
#PBS -N MOI
#PBS -r n
#PBS -q projects 
#PBS -l nodes=1:ppn=8
NCPU=`wc -l < $PBS_NODEFILE`
cd $PBS_O_WORKDIR
echo "================================================================="
echo -n 'Job is running on node '; cat $PBS_NODEFILE
echo PBS: qsub is running on $PBS_O_HOST
echo PBS: originating queue is $PBS_O_QUEUE
echo PBS: executing queue is $PBS_QUEUE
echo PBS: working directory is $PBS_O_WORKDIR
echo PBS: execution mode is $PBS_ENVIRONMENT
echo PBS: job identifier is $PBS_JOBID
echo PBS: job name is $PBS_JOBNAME
echo PBS: node file is $PBS_NODEFILE
echo PBS: current home directory is $PBS_O_HOME
echo Number of CPU: $NCPU
echo PBS: PATH = $PBS_O_PATH
echo "================================================================="
NODE=`hostname`
if [ "$NODE" == "kappuwai" ] ; then 
/usr/mpi/gcc/openmpi-1.3.2/bin/mpirun -v -np $NCPU /opt/GMX407/bin/mdrun -g md.log -s topol.tpr -v >&md.job 

elif [ "$NODE" != "c0-2" ] && [ "$NODE" != "c0-1" ] ; then 

touch Leggimi.$PBS_JOBID.txt
echo "Your simulation files will be at /NODES_DATA/{$NODE}_$PBS_O_LOGNAME/sim.$NODE.$PBS_JOBID" >> Leggimi.$PBS_JOBID.txt
chmod +x Leggimi.$PBS_JOBID.txt
cp * /DATA/$PBS_O_LOGNAME/sim.$NODE.$PBS_JOBID
cd /DATA/$PBS_O_LOGNAME/sim.$NODE.$PBS_JOBID
/usr/mpi/gcc/openmpi-1.4.3/bin/mpirun -v -np $NCPU /opt/GMX407/bin/mdrun -g md.log -s topol.tpr -v >&md.job

else

touch Leggimi.$PBS_JOBID.txt
echo "Your simulation files will be at /NODES_DATA/{$NODE}_$PBS_O_LOGNAME/sim.$NODE.$PBS_JOBID" >> Leggimi.$PBS_JOBID.txt
chmod +x Leggimi.$PBS_JOBID.txt
cp * /DATA/$PBS_O_LOGNAME/sim.$NODE.$PBS_JOBID
cd /DATA/$PBS_O_LOGNAME/sim.$NODE.$PBS_JOBID
/usr/mpi/gcc/openmpi-1.3.2/bin/mpirun -v -np $NCPU /opt/GMX407/bin/mdrun -g md.log -s topol.tpr -v >&md.job

echo "SCELTA ULTIMA" >>Leggimi.$PBS_JOBID.txt


fi

