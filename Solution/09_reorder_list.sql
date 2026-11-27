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
-- DECISION NOTES (defaults chosen by the assistant - confirm or change):
--   D29. Sales speed = units sold per day over the last p_window_days (default
--        28) BEFORE p_anchor, taken from sale rows in inventory_log. Checked:
--        total sale units in the log (412,645) match units on fulfilled orders
--        (415,712) within 0.7%.
--   D30. Days of cover = stock on hand / units per day. Out-of-stock and
--        negative stock count as 0 on hand, so they sort to the top (0 days).
--   D31. Listed if cover < p_cover_days (default 14 = two weeks, a GUESS: it
--        should be roughly the supplier lead time, which nobody told us).
--   D32. Products with no sales in the window are not listed: there is no speed
--        to divide by. A product that never sold is not at risk of running out.
--   D33. LIMIT: this assumes the future looks like the last four weeks. It does
--        not know about flash sales, seasons or promotions. It also trusts
--        stock_quantity, which the diagnosis found unreliable for 144 products.
--
-- Use:   SELECT * FROM reorder_list('2026-09-01');            -- the demo data ends Aug 2026
--        SELECT * FROM reorder_list(current_date, 28, 7);     -- in production, tighter

CREATE OR REPLACE FUNCTION reorder_list(
    p_anchor      date    DEFAULT current_date,
    p_window_days integer DEFAULT 28,
    p_cover_days  integer DEFAULT 14
)
RETURNS TABLE (
    product_id        integer,
    product_name      text,
    category_path     text,
    stock_quantity    integer,
    units_in_window   bigint,
    units_per_day     numeric,
    days_of_cover     numeric
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
    )
    SELECT p.product_id,
           p.product_name,
           coalesce(t.path, '(Uncategorised)'),
           p.stock_quantity,
           s.units::bigint,
           round(s.units::numeric / p_window_days, 2),
           round(greatest(p.stock_quantity, 0)::numeric / (s.units::numeric / p_window_days), 1)
    FROM   sold s
    JOIN   products p ON p.product_id = s.product_id
    LEFT   JOIN v_category_tree t ON t.category_id = p.category_id
    WHERE  greatest(p.stock_quantity, 0)::numeric / (s.units::numeric / p_window_days) < p_cover_days
    ORDER  BY 7, s.units DESC, p.product_id;
$$;
