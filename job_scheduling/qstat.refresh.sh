#!/bin/sh

A=0

while echo "CICLO NUMERO $A";

do

qstat
sleep 120
let "A=$A+1"
clear;

done;

