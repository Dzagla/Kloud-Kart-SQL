-- 04_report_baseline.sql  (ILLUSTRATIVE STAND-IN — we do not have Adwoa's real query)
-- Written the way slow Monday reports usually are: one correlated subquery per
-- figure, so every figure re-reads the orders table once per customer.
--
-- This file runs only 1 of the 12 monthly subqueries on a 100-customer sample.
-- The ~40-minute baseline quoted in ADR-002 and the README is EXTRAPOLATED from
-- that sample, not measured directly:
--     sample time (100 customers, 3 subqueries) ≈ 1.4–1.7 s
--     → estimated full query (40,420 customers, 14 subqueries) ≈ 38–44 min
-- Do not run all 40,420 customers with this file on a laptop.
-- anchor = first day AFTER the last month reported
\set anchor '2026-09-01'
-- sample = how many customers to run
\set sample 100
\timing on

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.customer_id,
       c.full_name,
       (SELECT coalesce(sum(o.total_amount), 0) FROM orders o
         WHERE o.customer_id = c.customer_id
           AND lower(trim(o.status)) IN ('completed','complete','shipped')) AS total_spent,
       (SELECT count(*) FROM orders o
         WHERE o.customer_id = c.customer_id
           AND lower(trim(o.status)) IN ('completed','complete','shipped')) AS order_count,
       (SELECT coalesce(sum(o.total_amount), 0) FROM orders o
         WHERE o.customer_id = c.customer_id
           AND lower(trim(o.status)) IN ('completed','complete','shipped')
           AND o.order_date >= (date_trunc('month', :'anchor'::date) - interval '1 month')
           AND o.order_date <   date_trunc('month', :'anchor'::date))        AS m_01
       -- ...the real version repeats that last block for months 02..12
FROM   customers c
ORDER  BY c.customer_id
LIMIT  :sample;
