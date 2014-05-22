#!/bin/bash

awk '{if($1 =="ATOM") print substr($_, 30,27)}' traj.ca.pdb > trj.xyz
