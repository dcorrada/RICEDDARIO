#!/usr/bin/python
import sys
import os

def read_file(filename):
	fin=open(filename,'r')
	rows_file=fin.readlines()
	fin.close()
	return rows_file

def chek_start_end(rows):
	running_row=0
	start_row=[]
	end_row=[]
	for row in rows:
		if 'f_m_ct' in row:
			start_row.append(running_row)
		if row[0]=='}' and running_row>5:
			end_row.append(running_row)
		running_row=running_row+1
	return start_row, end_row

def write_complexes(rows, start_row, end_row,filename):
	i=1
	for start, end in zip(start_row, end_row):
		fout=open(filename[:-14]+"-complex-"+str(i)+".mae",'w')
		fout.writelines(rows[0:6])
		fout.writelines(rows[start:end+1])
		fout.close
		i=i+1

if __name__ == '__main__':
	if len(sys.argv) !=2:
		print "Usage: %s <complexes.mae>" % sys.argv[0]
		sys.exit()
	mae_lines=read_file(sys.argv[1])
	start_comp, end_comp=chek_start_end(mae_lines)
	write_complexes(mae_lines, start_comp, end_comp,sys.argv[1])