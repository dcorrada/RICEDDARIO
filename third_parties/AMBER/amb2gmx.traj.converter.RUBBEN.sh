#!/bin/bash
##
## Trajectory conversion script, Copyright 2008 Justin A. Lemkul (jalemkul@vt.edu)
##
## Script converts an mdcrd from an AMBER simulation to a Gromacs-compatible .xtc 
## trajectory for analysis using Gromacs tools.
##
## This script requires an installation of Gromacs, version 3.3 or later
## and an installation of AMBER9 or later
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
##
## Revision History
##
## Version 1.0 (3/5/2008) - initial script; processed ptraj output with trjconv/trjcat
##
## Version 1.1 (3/8/2008) - added ptraj step to convert mdcrd to .pdb series
##			  - added automatic renaming of .pdb files
##			  - added make_ndx to eliminate manual group selection in trjconv
##			  - added processing of inpcrd to generate time 0 reference
##
## Version 1.2 (3/8/2008) - added automated ptraj.in generation
##			  - added options to allow user to select starting/ending frame
##			    as well as the time interval for skipping
##
## Version 1.3 (3/12/2008)  - trjconv -t0 now used to set the time on each frame 
##			    - removed -settime from the trjcat step
##
## Version 1.4 (3/13/2008) - made script more universal; allows user to specify whether or not
##			     the trajectory contains water (this affects the make_ndx step)
##
## Version 1.5 (3/16/2008) - added support for multiple types of ions
##

echo
echo "###############################################################"
echo "#                 Trajectory Converter - v1.5                 #"
echo "#                  Written by: Justin Lemkul                  #"
echo "#                                                             #"
echo "#  This trajectory converts a series of .pdb files generated  #"
echo "#  by ptraj to a Gromacs-compatible trajectory for further    #"
echo "#  analysis. This script requires a working installation of   #"
echo "#  AMBER 9 and Gromacs 3.3 or later. Earlier versions of      #"
echo "#  these packages may work, but have not been explicitly      #"
echo "#  tested.                                                    #"
echo "#                                                             #"
echo "###############################################################" 
echo

echo " PREREQUISITES:"
echo
echo " You must have the following files in the working directory:"
echo
echo "    1. Your time = 0 input (rst or inpcrd file)"
echo "    2. Your trajectory" 
echo "    3. Your prmtop file"
echo
echo " Your ptraj input files will be generated automatically."
echo

echo "Enter the file name:"
echo
read namefile
echo 
echo "Enter the name of your prmtop file:"
echo
read prmtop 
echo
echo "Enter the name of your starting frame (i.e., inpcrd):"
echo
read inpcrd
echo
echo "Enter the name of your trajectory file (i.e., mdcrd.x_y.gz):"
echo
read traj_name
echo
read -p "Does this trajectory contain water? (y/n) "
echo
echo "How many types of ions are present in the trajectory? For example, if you have"
echo "only counterions, enter 1.  If your system contains a salt concentration beyond"
echo "simply neutralizing charge (i.e., 100 mM NaCl), enter 2.  If you have other ions"
echo "present (such as bound to the enzyme active site), enter the number of ion types"
echo "appropriate for your system.  This script supports only up to 4 types of ions."
echo
read ions
echo
echo "Enter frame number of the first frame to be read from the mdcrd file:"
echo "Your inpcrd file will serve as time = 0. Here, enter the first frame of the"
echo "trajectory you want considered. If you want to analyze every 10 ps of your trajectory,"
echo "and frames were saved every 1 ps, then enter 10. Make sure this number corresponds"
echo "to the interval you specify below. If you want to analyze every frame, enter 1."
echo
read firstframe
echo
echo "Enter ending frame number:"
echo
read lastframe
echo
echo "Enter frame interval:"
echo "For example, if you want to analyze every 10 ps, and each frame was recorded"
echo "every 1 ps, enter 10 here. If each frame represents 2 ps, enter 5, etc."
echo "To analyze every frame, enter 1."
echo
read skip
echo
echo "Enter AMBER time-step: "
echo
read tstep
echo
echo "#########################################################################"
echo "Conversion will be performed on" $traj_name "in conjunction with" $prmtop
echo "Analysis will begin with frame" $firstframe "and continue until frame" $lastframe
echo "Analysis will be conducted every" $skip "frames"

if [ $REPLY = y -o $REPLY = Y ]; then
	echo $traj_name "contains water and" $ions "type(s) of ions."
elif [ $REPLY = n -o $REPLY = N ]; then
	echo $traj_name "does not contain water."
else echo "Your response to 'Does your trajectory contain water?' was invalid. Please start over."
exit 1
fi

if [ $ions -ge 5 ]; then
	echo "You have specified too many types of ions.  This script only supports up to 4 types of ions."
exit 1
fi

echo
echo "If this information is correct, type Enter to continue."
echo "If not, type Ctrl+c to exit the script."
echo
echo "#########################################################################"
echo
read dummy_variable

## Create ptraj input
printf "trajin $traj_name $firstframe $lastframe $skip\n" > firstline
printf "trajout mdcrd.pdb pdb" > secondline
cat firstline secondline > ptraj_full.in

rm firstline
rm secondline


#echo "Runing ambpdb..."
#ambpdb -p $prmtop < $inpcrd > mdcrd_0.pdb.1

printf "trajin $inpcrd \n" > firstline
printf "trajout mdcrd_0.pdb pdb" > secondline

## Modifica 19 Novembre 2008

cat firstline secondline > ptraj_inpcrd.in

rm firstline
rm secondline

echo "Running ptraj..."

ptraj $prmtop  ptraj_inpcrd.in 

mv mdcrd_0.pdb.1 mdcrd_0.pdb

ptraj $prmtop ptraj_full.in

## This step converts the .pdb.* extension to _*.pdb
## Credit where it's due: this section was contributed by user 'jschiwal' via
## the forum on LinuxQuestions.org

echo "Renaming files..."
echo

for file in mdcrd.pdb.*; do
  mv -v "$file" "${file%.pdb.*}_${file##*.}.pdb"
done

echo "All files successfully renamed."
echo

## Start Gromacs processing

echo " Invoking Gromacs' trjconv..."
echo " This step converts your .pdb structure files to "
echo " Gromacs' .xtc trajectory format."
echo
echo " Type Enter to continue."
read dummy_variable
echo

## Invoke make_ndx to create protein-only index group

if [ $REPLY = y -o $REPLY = Y -a $ions = 1 ]; then
make_ndx -f mdcrd_0.pdb -o protein_only.ndx <<EOF
del 14
del 13
del 12
del 11
del 10
del 9
del 8
del 7
del 6
del 5
del 4
del 3
del 2
del 0
q
EOF

elif [ $REPLY = y -o $REPLY = Y -a $ions = 2 ]; then
make_ndx -f mdcrd_0.pdb -o protein_only.ndx <<EOF
del 15
del 14
del 13
del 12
del 11
del 10
del 9
del 8
del 7
del 6
del 5
del 4
del 3
del 2
del 0
q
EOF

elif [ $REPLY = y -o $REPLY = Y -a $ions = 3 ]; then
make_ndx -f mdcrd_0.pdb -o protein_only.ndx <<EOF
del 16
del 15
del 14
del 13
del 12
del 11
del 10
del 9
del 8
del 7
del 6
del 5
del 4
del 3
del 2
del 0
q
EOF

elif [ $REPLY = y -o $REPLY = Y -a $ions = 4 ]; then
make_ndx -f mdcrd_0.pdb -o protein_only.ndx <<EOF
del 17
del 16
del 15
del 14
del 13
del 12
del 11
del 10
del 9
del 8
del 7
del 6
del 5
del 4
del 3
del 2
del 0
q
EOF

elif [ $REPLY = n -o $REPLY = N ]; then
make_ndx -f mdcrd_0.pdb -o protein_only.ndx <<EOF
del 9
del 8
del 7
del 6
del 5
del 4
del 3
del 2
del 0
q
EOF

fi

## Iteratively invoke the Gromacs trajectory converter, trjconv
## This program converts the files from .pdb to .xtc format
## 'Protein' group should be automatically selected by index group 

## Original "for" line:
## for file in *.pdb; do

for file in `ls | grep mdcrd`; do

## create variable for time, parse from filename
## Again, credit to user 'jschiwal' for the next two lines

     temp=${file#mdcrd_}
     num=${temp%.pdb}

     echo "Converting..." $file

## Modifica 19 Novembre 2008

     echo 0 | trjconv -s $file -f $file -n protein_only.ndx -o traj_$file.xtc -t0 $num

done

## Invoke the Gromacs trajectory concatenation tool, trjcat
## Concatenate the files to create a continuous .xtc trajectory

echo " Invoking Gromacs' trjcat..."
echo " This step converts assembles your series of .xtc files into "
echo " one single trajectory file that can be analyzed by Gromacs."
echo
echo " Type Enter to continue."
read dummy_variable
echo

echo "Concatenating..."
echo

trjcat -f *.pdb.xtc -o $namefile.start.xtc

## Convert the first frame to an input .gro file

## Modifica 19 Novembre 2008

echo 0 | editconf -f mdcrd_0.pdb -n protein_only.ndx -o $namefile.gro

echo 0 | trjconv  -f $namefile.start.xtc -o $namefile.xtc -s $namefile.gro -timestep $tstep

## Clean up intermediate files

rm *.pdb
rm *.pdb.xtc

rm protein_only.ndx
rm ptraj_*
rm $namefile.start.xtc

echo "Done."
