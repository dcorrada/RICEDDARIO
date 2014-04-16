--SQL della view "cross_info"
SELECT DISTINCT a.mirID, a.refseqID, b.geneSymbol, b.description, c.target_length, a.conserved, a.accessible, a.enhanced, a.total, c.density

FROM sites_scores AS a

LEFT JOIN kgXref AS b
       ON a.refseqID = b.refseq

JOIN sites_density AS c
  ON ((c.refseqID = a.refseqID) AND (c.mirID = a.mirID))

