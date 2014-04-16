#!/bin/sh

pwd;
echo;

mysql -u dario myUCSC < myUCSC_dump.sql;
echo "creazione tabelle completata!";

cd ./myUCSC_tables;
pwd;
echo;
mysqlimport -u dario myUCSC -L *.txt;
echo "popolamento DB completato!";

