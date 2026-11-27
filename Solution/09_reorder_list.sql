-- 09_reorder_list.sql   -- IMPROVEMENT BEYOND THE BRIEF
-- A reorder priority list: which products will run out first, given how fast
-- each one has actually been selling.
--
-- WHY (in Nana's terms): the low-stock view flags every product at 5 units or
-- fewer. On this data that is 1,685 products, 42% of the catalogue, and every
-- one of them sold in the last four weeks. A list that long cannot be acted on.
-- A product with 3 left that sells 1 a month is not urgent; one with 3 left
-- that sells 3 a day is gone by tomorrow. This list puts the second above the
-- first.
--
-- DECISION NOTES:
--   D29. Sales speed = units sold per day over the last p_window_days (default
--        28) BEFORE p_anchor, taken from sale rows in inventory_log. Cross-
--        check: sale units in the log total 412,645; fulfilled-order units
--        total 415,712 — a gap of 3,067 units (0.74%). The gap is acceptable
--        for a velocity estimate but means the list slightly understates speed
--        for a small number of products.
--   D30. Days of cover = stock on hand / units per day. Out-of-stock and
--        negative stock count as 0 on hand, so they sort to the top (0 days).
--   D31. Listed if cover < p_cover_days (default 14 = two weeks, an assumed
--        supplier lead time; no actual lead-time data was provided).
--   D32. Products with no sales in the window are excluded: without a velocity
--        figure there is nothing to divide by. Known blind spot: new or
--        seasonal products that have not sold in the window will not appear
--        even if stock is critically low. Check those separately.
--   D33. LIMIT: this assumes the future looks like the last four weeks. It does
--        not know about flash sales, seasons or promotions. It also trusts
--        stock_quantity, which the diagnosis found unreliable for 144 products;
--        rows for those products are marked with stock_data_reliable = false.
--
-- Use:   SELECT * FROM reorder_list('2026-09-01');            -- the demo data ends Aug 2026
--        SELECT * FROM reorder_list(current_date, 28, 7);     -- in production, tighter

CREATE OR REPLACE FUNCTION reorder_list(
    p_anchor      date    DEFAULT current_date,
    p_window_days integer DEFAULT 28,
    p_cover_days  integer DEFAULT 14
)
RETURNS TABLE (
    product_id           integer,
    product_name         text,
    category_path        text,
    stock_quantity       integer,
    units_in_window      bigint,
    units_per_day        numeric,
    days_of_cover        numeric,
    stock_data_reliable  boolean   -- false for the 144 products whose stock_quantity
                                   -- disagreed with the movement log at audit time
)
LANGUAGE sql STABLE
AS $$
    WITH sold AS (
        SELECT l.product_id, sum(-l.change_qty) AS units
        FROM   inventory_log l
        WHERE  l.reason = 'sale'
          AND  l.created_at >= p_anchor - p_window_days
          AND  l.created_at <  p_anchor
        GROUP  BY l.product_id
        HAVING sum(-l.change_qty) > 0
    ),
    cover AS (
        SELECT p.product_id,
               p.product_name,
               p.stock_quantity,
               s.units::bigint                                           AS units_in_window,
               round(s.units::numeric / p_window_days, 2)               AS units_per_day,
               round(greatest(p.stock_quantity, 0)::numeric
                     / (s.units::numeric / p_window_days), 1)           AS days_of_cover,
               t.path,
               -- flag rows where stock_quantity was unreliable at audit time
               NOT EXISTS (
                   SELECT 1 FROM products chk
                   WHERE chk.product_id = p.product_id
                     AND chk.stock_quantity
                         = coalesce((SELECT sum(il.change_qty)
                                     FROM inventory_log il
                                     WHERE il.product_id = p.product_id), 0)
               )                                                         AS _unreliable
        FROM   sold s
        JOIN   products p ON p.product_id = s.product_id
        LEFT   JOIN v_category_tree t ON t.category_id = p.category_id
    )
    SELECT product_id,
           product_name,
           coalesce(path, '(Uncategorised)'),
           stock_quantity,
           units_in_window,
           units_per_day,
           days_of_cover,
           NOT _unreliable          -- true = stock figure is consistent with log
    FROM   cover
    WHERE  days_of_cover < p_cover_days
    ORDER  BY days_of_cover, units_in_window DESC, product_id;
$$;
