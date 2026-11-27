-- integrity_checks.sql
-- One row per check: what was tested, where, and how many rows it flags.
-- Read-only. Safe to re-run after every change; compare the counts.
--
-- Group letters (R/I/V/T/S) follow the four questions in the Learning Path:
--   R = relationship not enforced (no FOREIGN KEY)
--   I = identity not enforced     (no UNIQUE)
--   V = value range not enforced  (no CHECK / NOT NULL)
--   T = type / vocabulary         (free text, timestamp without zone)
--   S = stock reconciliation      (derived number disagrees with its source)
--
-- "NOT A FAULT" rows are included on purpose, with count shown, so the reader
-- can see they were looked at and deliberately excluded from the diagnosis.

\pset pager off

WITH
dup_restock AS (          -- identical restock logged twice (same product, qty, second)
    SELECT log_id
    FROM  (SELECT log_id, reason,
                  row_number() OVER (PARTITION BY product_id, change_qty, reason, created_at
                                     ORDER BY log_id) AS rn
           FROM   inventory_log) x
    WHERE rn > 1 AND reason = 'restock'
),
order_calc AS (           -- order total as the application wrote it vs. rebuilt from its lines
    SELECT o.order_id, o.total_amount,
           sum(i.quantity * i.unit_price) AS calc
    FROM   orders o JOIN order_items i USING (order_id)
    GROUP  BY o.order_id, o.total_amount
),
log_net AS (
    SELECT product_id, sum(change_qty) AS net FROM inventory_log GROUP BY product_id
),
log_net_clean AS (        -- same, with the duplicate restocks removed
    SELECT product_id, sum(change_qty) AS net
    FROM   inventory_log
    WHERE  log_id NOT IN (SELECT log_id FROM dup_restock)
    GROUP  BY product_id
)
SELECT * FROM (

-- R: relationships ----------------------------------------------------------
SELECT 'R1' AS id, 'orders -> customers: customer does not exist' AS check_name, count(*) AS rows_flagged
FROM orders o WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id)
UNION ALL
SELECT 'R2', 'order_items -> orders: order does not exist', count(*)
FROM order_items i WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = i.order_id)
UNION ALL
SELECT 'R3', 'inventory_log -> products: product does not exist', count(*)
FROM inventory_log l WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = l.product_id)
UNION ALL
SELECT 'R4', 'order_items -> products: product does not exist', count(*)
FROM order_items i WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = i.product_id)
UNION ALL
SELECT 'R5', 'categories: parent_id points at a missing category', count(*)
FROM categories c WHERE c.parent_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM categories p WHERE p.category_id = c.parent_id)
UNION ALL
SELECT 'R6', 'products with no category (NULL) - 37 is small; check before calling it a fault', count(*)
FROM products WHERE category_id IS NULL

-- I: identity ---------------------------------------------------------------
UNION ALL
SELECT 'I1', 'customers: email shared by more than one row (rows involved)', coalesce(sum(n), 0)
FROM (SELECT count(*) AS n FROM customers GROUP BY lower(trim(email)) HAVING count(*) > 1) d
UNION ALL
SELECT 'I2', 'order_items: same product twice on one order (rows involved)', coalesce(sum(n), 0)
FROM (SELECT count(*) AS n FROM order_items GROUP BY order_id, product_id HAVING count(*) > 1) d
UNION ALL
SELECT 'I3', 'inventory_log: restock logged twice, same second (extra rows)', count(*)
FROM dup_restock
UNION ALL
SELECT 'I4', 'inventory_log: SALE rows identical in product/qty/second - NOT A FAULT (two real sales)', coalesce(sum(n - 1), 0)
FROM (SELECT count(*) AS n FROM inventory_log WHERE reason = 'sale'
      GROUP BY product_id, change_qty, created_at HAVING count(*) > 1) d
UNION ALL
SELECT 'I5', 'products: same name on more than one product - NOT A FAULT without more evidence', coalesce(sum(n), 0)
FROM (SELECT count(*) AS n FROM products GROUP BY lower(product_name) HAVING count(*) > 1) d

-- V: values -----------------------------------------------------------------
UNION ALL
SELECT 'V1', 'order_items: quantity 999 or 9999 (keying errors)', count(*)
FROM order_items WHERE quantity >= 999
UNION ALL
SELECT 'V2', 'order_items: unit_price = 0', count(*)
FROM order_items WHERE unit_price = 0
UNION ALL
SELECT 'V3', 'order_items: unit_price IS NULL', count(*)
FROM order_items WHERE unit_price IS NULL
UNION ALL
SELECT 'V4', 'orders: order_date after 2026-08-31 (data window ends there)', count(*)
FROM orders WHERE order_date > '2026-08-31 23:59:59'
UNION ALL
SELECT 'V5', 'inventory_log: created_at after 2026-08-31', count(*)
FROM inventory_log WHERE created_at > '2026-08-31 23:59:59'
UNION ALL
SELECT 'V6', 'products: stock_quantity < 0', count(*)
FROM products WHERE stock_quantity < 0
UNION ALL
SELECT 'V7', 'orders: total_amount differs from sum of its lines', count(*)
FROM order_calc WHERE total_amount <> calc
UNION ALL
SELECT 'V8', '   of which: total is exactly 0.75x / 0.90x / 1.10x / 1.25x the lines (looks like discount/fee)', count(*)
FROM order_calc WHERE total_amount <> calc AND round(total_amount / nullif(calc, 0), 2) IN (0.75, 0.90, 1.10, 1.25)
UNION ALL
SELECT 'V9', 'inventory_log: negative change_qty - NOT A FAULT (how an outward movement is recorded)', count(*)
FROM inventory_log WHERE change_qty < 0
UNION ALL
SELECT 'V10', 'inventory_log: stock_take with change_qty 0 - NOT A FAULT (count matched, nothing to move)', count(*)
FROM inventory_log WHERE reason = 'stock_take' AND change_qty = 0
UNION ALL
SELECT 'V11', 'inventory_log: correction noted "recount, not applied"', count(*)
FROM inventory_log WHERE reason = 'correction' AND note = 'recount, not applied'

-- T: types and vocabulary ---------------------------------------------------
UNION ALL
SELECT 'T1', 'orders.status: distinct spellings', count(DISTINCT status)
FROM orders
UNION ALL
SELECT 'T2', 'orders.status: distinct after lower(trim()) - 7 left, meaning 5 states', count(DISTINCT lower(trim(status)))
FROM orders
UNION ALL
SELECT 'T3', 'customers.city: distinct spellings', count(DISTINCT city)
FROM customers
UNION ALL
SELECT 'T4', 'customers.city: distinct after lower(trim())', count(DISTINCT lower(trim(city)))
FROM customers
UNION ALL
SELECT 'T5', 'customers.full_name: leading/trailing spaces', count(*)
FROM customers WHERE full_name <> trim(full_name)

-- S: stock reconciliation ---------------------------------------------------
UNION ALL
SELECT 'S1', 'products where stock_quantity <> sum of inventory_log', count(*)
FROM products p LEFT JOIN log_net l USING (product_id)
WHERE p.stock_quantity <> coalesce(l.net, 0)
UNION ALL
SELECT 'S2', '   same test after removing the duplicate restocks (I3)', count(*)
FROM products p LEFT JOIN log_net_clean l USING (product_id)
WHERE p.stock_quantity <> coalesce(l.net, 0)
) checks
ORDER BY left(id,1), substr(id,2)::int;