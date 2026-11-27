-- 06_orders_customer_index.sql   (OPTIONAL - read the note before running)
--
-- MEASURED on a 2-core test copy, PostgreSQL 16, 159,384 orders, warm cache:
--   Full Monday report (all customers) : ~150-210 ms before, ~150-165 ms after.
--                                        NO CHANGE: it needs every order, so the
--                                        planner correctly keeps the table scan.
--   One customer's running total       : ~8 ms before, ~0.4-1.0 ms after.
--   Inserting 20,000 order rows        : ~32-38 ms before, ~95-97 ms after
--                                        (about 2.5x slower per insert).
--
-- So this index does NOT speed up the report Nana asked for. It speeds up
-- looking up ONE customer, and it slows every new order slightly. Decide
-- whether single-customer lookups matter enough to Adwoa to pay for that.
-- Re-measure on your own machine before deciding; these are my numbers.
--
-- In production use CREATE INDEX CONCURRENTLY so the shop keeps taking orders
-- while it builds (it cannot run inside a transaction block).

CREATE INDEX IF NOT EXISTS orders_customer_date_idx
    ON orders (customer_id, order_date) INCLUDE (total_amount, status);
ANALYZE orders;
