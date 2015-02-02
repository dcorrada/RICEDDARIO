#!/usr/bin/python
#
# Domenico Fraccalvieri 23/03/2009
# 
# Questo script serve per calcolare il centroide di una molecola in un file .mae
# 
# INPUT:
# 
# OUTPUT:
# 
# USAGE:
# 

import string
import sys
import re
from numpy import mean

#    1        3    9.086000  -40.733000    8.144000  
coordMaePAT=re.compile("(\s*)(\d*)(\s*)(\d*)(\s*)([-+]?\d*\.\d*)(\s*)([-+]?\d*\.\d*)(\s*)([-+]?\d*\.\d*)")

def make_basename(filename):
	basename=filename[:-4]
	return basename

def get_coord(filename):
	fin = open(filename,'r')
	list_x=[]
	list_y=[]
	list_z=[]
	lines=fin.readlines()
	fin.close()
	for line in lines:
		if  coordMaePAT.match(line):
			n1, Anam, n2, Atype, n3, x, n4, y, n5, z = coordMaePAT.match(line).groups()
			list_x.append(float(x))
			list_y.append(float(y))
			list_z.append(float(z))
	return list_x,list_y,list_z

def make_centroid(list_x, list_y, list_z):
	cent_x=mean(list_x)
	cent_y=mean(list_y)
	cent_z=mean(list_z)
	return cent_x, cent_y, cent_z
	
def write_centroid(basename,cent_x, cent_y, cent_z):
	fout=open("centroid-"+basename+".txt",'w')
	fout.write("GRID_CENTER "+str(cent_x)+", "+str(cent_y)+", "+str(cent_z))
	fout.close()

if __name__ == '__main__':
	if len(sys.argv) !=2:
		print "Usage: %s <molecule>" % sys.argv[0]
		sys.exit()
	basename=make_basename(sys.argv[1])
	list_x,list_y,list_z=get_coord(sys.argv[1])
	cent_x, cent_y, cent_z=make_centroid(list_x, list_y, list_z)
	write_centroid(basename,cent_x, cent_y, cent_z)