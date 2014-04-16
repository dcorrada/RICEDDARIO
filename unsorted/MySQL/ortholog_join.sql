/*
questa query unisce le predizioni fatte con rnahybrid per uomo e topo
utilizzando come ponte la tabella dei geni ortologhi umani per il topo
chiamata 'hgBlastTab'
*/

SELECT topo.kgID, topo.mirID,
       ponte.query, ponte.target,
       uomo.kgID, uomo.mirID,
       ponte.identity

FROM mm9.rnahybrid topo

JOIN mm9.hgBlastTab ponte
  ON topo.kgID = ponte.query

JOIN hg18.rnahybrid uomo
  ON ponte.target = uomo.kgID

WHERE topo.mirID = uomo.mirID





