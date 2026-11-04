SELECT 0::bigint id,'All software'::text label UNION ALL
 SELECT id,name||' · '||upper(category) FROM dcmon.software_product ORDER BY id;
