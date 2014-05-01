-- ESEMPI DI QUERIES
/*
Per ottenere un CSV dalla seguente query usare un comando da shell tipo il seguente:
mysql -u corrada -p19korda80 sparta < QUERIES.sql | sed 's/\t/","/g;s/^/"/;s/$/"/;s/\n//g' > tabella.csv
*/

/*
cercare i residui della catena pesante H del pdb 1IQD che sono annotati dalla fonte di citazione primaria quale contatti noti con l'antigene;
quindi recuperare le annotazioni strutturali su esso (struttura secondaria, domini, regioni iper-variabili);
quindi vedere quali sono, dal lato antigene, i residui partner che entrano in contatto)
*/

SELECT structure.pdb,  structure.domain, structure.cdr, structure.dssp,
structure.chain, pdbsum.resA AS 'Fab_res', structure.res AS 'Fab_resID',
pdbsum.resB AS 'antigen_res', pdbsum.residB AS 'antigen_resID', pdbsum.type
FROM structure
JOIN xres
ON xres.pdb = structure.pdb
AND xres.chain = structure.chain
AND xres.res = structure.res
JOIN pdbsum
ON pdbsum.pdb = xres.pdb
AND pdbsum.chainA = xres.chain
AND pdbsum.residA = xres.source_res
WHERE structure.known = '1'
AND structure.pdb = '1IQD'
AND structure.chain = 'H';

/*
vado a vedere dove mappano le cdr su un pdb
*/
SELECT pdb, chain, res, domain, cdr
FROM structure
WHERE cdr in ('CDR-H1', 'CDR-H2', 'CDR-H3', 'CDR-L1', 'CDR-L2', 'CDR-L3')
AND pdb LIKE '1YQV'
ORDER BY res + 0;
