-- 02_schema_changes.sql
-- Schema changes needed before order placement can be made safe.
-- Safe to re-run on a fresh load (schema.sql drops the tables, which drops
-- the OWNED BY sequences with them).
--
-- DECISION NOTES (copy into your decision record):
--   D1. Ids come from sequences. The tables had no id generator, so any code
--       that computed max(id)+1 would hand the same id to two simultaneous
--       buyers.
--   D2. The orders sequence starts above 999,862, NOT above 659,384. The
--       692 orphan order_items (check R2) carry order_ids up to 999,862.
--       Starting lower would eventually issue an id those lines already
--       claim, and they would silently attach to a new order.
--   D3. CHECK (stock_quantity >= 0) is added NOT VALID: it is enforced for
--       every new write (including a manual UPDATE in a terminal), but does
--       not reject the 14 products that already have negative stock. Those
--       need a physical recount before the constraint can be fully validated.
--       Follow-up: once warehouse staff correct the 14 negative balances, run:
--         ALTER TABLE products VALIDATE CONSTRAINT products_stock_non_negative;
--       Until then, the constraint remains NOT VALID and those 14 rows are
--       frozen against any UPDATE (see ADR-007).

BEGIN;

-- D1/D2: orders ------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS orders_order_id_seq OWNED BY orders.order_id;
SELECT setval('orders_order_id_seq',
              greatest((SELECT max(order_id) FROM orders),
                       (SELECT max(order_id) FROM order_items)));
ALTER TABLE orders ALTER COLUMN order_id
    SET DEFAULT nextval('orders_order_id_seq');

-- D1: order_items ----------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS order_items_order_item_id_seq
    OWNED BY order_items.order_item_id;
SELECT setval('order_items_order_item_id_seq',
              (SELECT max(order_item_id) FROM order_items));
ALTER TABLE order_items ALTER COLUMN order_item_id
    SET DEFAULT nextval('order_items_order_item_id_seq');

-- D1: inventory_log --------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS inventory_log_log_id_seq
    OWNED BY inventory_log.log_id;
SELECT setval('inventory_log_log_id_seq',
              (SELECT max(log_id) FROM inventory_log));
ALTER TABLE inventory_log ALTER COLUMN log_id
    SET DEFAULT nextval('inventory_log_log_id_seq');

-- D3: safety net -----------------------------------------------------------
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_stock_non_negative;
ALTER TABLE products
    ADD CONSTRAINT products_stock_non_negative
    CHECK (stock_quantity >= 0) NOT VALID;

COMMIT;
