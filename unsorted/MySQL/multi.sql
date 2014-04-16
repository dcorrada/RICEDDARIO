-- RICERCA DI OCCORRENZE MULTIPLE

-- modificare la query ad-hoc a seconda del campo (es. term_type)
-- e della tabella interessata (es. go_term)

SELECT dbObjectId,
       COUNT(*) AS counter
FROM go_goapart
GROUP BY dbObjectId
HAVING counter > 100;