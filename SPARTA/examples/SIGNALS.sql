-- interazioni interne
SELECT pdbsum.type, xres.pdb, CONCAT(xres.res, '-', pdbsum.resA) AS 'actor', CONCAT(pdbsum.chainB, '-', pdbsum.resB, '-', pdbsum.residB) AS 'partner'
FROM pdbsum
JOIN xres
ON xres.pdb = pdbsum.pdb
AND xres.chain = pdbsum.chainA
AND xres.source_res = pdbsum.residA
WHERE pdbsum.type <> 'Non-bonded contacts'
AND xres.pdb LIKE '1DQJ'
AND pdbsum.chainB <> 'A'
GROUP BY actor
ORDER BY xres.res + 0;

-- interazioni con l'antigene
SELECT pdbsum.type, xres.pdb, CONCAT(xres.res, '-', pdbsum.resA) AS 'actor', CONCAT(pdbsum.chainB, '-', pdbsum.resB, '-', pdbsum.residB) AS 'partner'
FROM pdbsum
JOIN xres
ON xres.pdb = pdbsum.pdb
AND xres.chain = pdbsum.chainA
AND xres.source_res = pdbsum.residA
AND xres.pdb LIKE '1DQJ'
AND pdbsum.chainB = 'A'
GROUP BY actor
ORDER BY xres.res + 0;
