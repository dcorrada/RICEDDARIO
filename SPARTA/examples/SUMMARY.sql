/*
Per esportare in una comoda tabella CSV questa query lanciare da bash il seguente comando 

mysql -u corrada -p19korda80 sparta < /home/dario/script/SPARTA/examples/SUMMARY.sql | sed 's/\t/";"/g;s/^/"/;s/$/"/;' > tabella.csv
*/

-- creo una tabella temporanea per mappare i residui delle catene leggere tra la nomenclatura originale e la mia
DROP TABLE IF EXISTS alternative;
CREATE TEMPORARY TABLE alternative
SELECT CONCAT(structure.domain, structure.chain, '(', structure.cdr, ') - ', structure.resname, ' ', structure.res) AS 'alt', xres.chain, xres.source_res
FROM structure
JOIN xres
ON xres.pdb = structure.pdb
AND xres.chain = structure.chain
AND xres.res = structure.res
WHERE structure.pdb = '1YQV'
AND structure.chain <> 'A'
ORDER BY structure.res + 0 ASC;

-- Dato un PDB e una serie di residui di interesse voglio andare a vedere quali contatti essi vanno a prendere con chi
SELECT CONCAT(structure.domain, structure.chain, ' (', structure.cdr, ')') AS 'Region',
abnum.kabat AS 'Kabat', abnum.abnum AS 'Chothia',
CONCAT(structure.resname, '-', structure.chain, structure.res) AS 'Residue',
IF (pdbsum.chainB LIKE 'A', (CONCAT('ANTIGEN - ', pdbsum.resB, ' ', pdbsum.residB)), (alternative.alt)) AS 'Contact',
pdbsum.type AS 'Interaction'
FROM structure
JOIN xres
ON xres.pdb = structure.pdb
AND xres.chain = structure.chain
AND xres.res = structure.res
LEFT JOIN abnum
ON abnum.pdb = structure.pdb
AND abnum.chain = structure.chain
AND abnum.res = structure.res
LEFT JOIN pdbsum
ON pdbsum.pdb = xres.pdb
AND pdbsum.chainA = xres.chain
AND pdbsum.residA = xres.source_res
LEFT JOIN alternative
ON alternative.chain = pdbsum.chainB
AND alternative.source_res = pdbsum.residB
WHERE structure.pdb = '1YQV'
AND (
(structure.res BETWEEN 26 AND 32)
OR (structure.res BETWEEN 53 AND 56)
OR (structure.res BETWEEN 85 AND 90)
OR (structure.res BETWEEN 100 AND 104)
OR (structure.res BETWEEN 114 AND 120)
OR (structure.res BETWEEN 129 AND 136)
OR (structure.res BETWEEN 164 AND 166)
OR (structure.res BETWEEN 174 AND 176)
OR (structure.res BETWEEN 174 AND 176)
OR (structure.res BETWEEN 271 AND 275)
OR (structure.res BETWEEN 307 AND 309)
OR (structure.res BETWEEN 336 AND 341)
)
ORDER BY structure.res + 0 ASC;

