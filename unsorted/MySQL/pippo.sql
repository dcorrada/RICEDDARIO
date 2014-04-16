SELECT hg18_knowngene.name, hg18_knowngene.chrom, hg18_knowngene.txStart,
       hg18_knowngene.txEnd,
       hg18_kgxref.geneSymbol, hg18_kgxref.mRNA , hg18_kgxref.description

FROM hg18_knowngene, hg18_kgxref

WHERE hg18_knowngene.name=hg18_kgxref.kgID
      AND hg18_kgxref.mRNA=hg18_kgxref.refseq
      
LIMIT 20;

select hg18_kgtxinfo.name, hg18_kgtxinfo.category, hg18_kgxref.mrna, hg18_kgxref.description
from hg18_kgtxinfo
join hg18_kgxref on hg18_kgtxinfo.name =  hg18_kgxref.kgID
where hg18_kgtxinfo.name in
(select name from hg18_kgtxinfo where (not category = 'coding') and sourceAcc like 'NM%')




SELECT t3.geneSymbol, t3.refseq, t5.acc, t5.name, t1.description

FROM hg18_keggmapdesc t1
JOIN hg18_keggpathway t2 on t1.mapID = t2.mapID
JOIN hg18_kgxref t3 on t2.kgID = t3.kgID
JOIN go_goapart t4 on t3.SPID = t4.DBOBJECTID
JOIN go_term t5 on t4.GOID = t5.ACC

WHERE t5.name = 'integral to membrane'
AND t1.description = 'Axon guidance - Homo sapiens (human)'
LIMIT 20;



SELECT topo.kgID, ponte.query,
       ponte.target, uomo.kgID,
       ponte.identity

FROM mm9.miranda topo,
     mm9.hgBlastTab ponte,
     hg18.miranda uomo
     
WHERE topo.kgID = ponte.query 
  AND ponte.target = uomo.kgID

LIMIT 20;

