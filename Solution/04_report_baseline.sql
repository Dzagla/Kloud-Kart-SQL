-- 04_report_baseline.sql  (STAND-IN for Adwoa's real query - we do not have hers)
-- Written the way slow Monday reports usually are: one correlated subquery per
-- figure, so every figure re-reads the orders table once per customer.
-- Run on a SAMPLE of customers; extrapolate. Do not run all 40,420 on a laptop
-- unless you are prepared to wait.
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
