-- run_all.sql  -  builds the whole solution on top of a FRESH load.
--
-- Prerequisite (from Lab/Resources, see fresh_load_test.sh):
--     psql -v ON_ERROR_STOP=1 -f schema.sql
--     psql -v ON_ERROR_STOP=1 -f load.sql
-- Then, from Lab/Solution:
--     psql -v ON_ERROR_STOP=1 -f run_all.sql
--
-- Order matters: 02 creates the id sequences and the stock CHECK that
-- 03 (place_order) relies on; 05 creates order_status_map used by the
-- monday_report() function in 05; 07 creates v_category_tree used by 09;
-- 08 adds the audit trigger; 09 (reorder_list) depends on v_category_tree
-- from 07, so 07 must precede 09.
-- NOT included on purpose:
--   01_integrity_checks.sql   read-only diagnosis; run it any time
--   04_report_baseline.sql    a measurement, not part of the system
--   06_orders_customer_index.sql  optional; a decision for Nana/Adwoa
\set ON_ERROR_STOP on
\ir 02_schema_changes.sql
\ir 03_place_order.sql
\ir 05_monday_report.sql
\ir 07_low_stock_rollup.sql
\ir 08_audit_trail.sql
\ir 09_reorder_list.sql
\echo 'run_all.sql: all objects created'
