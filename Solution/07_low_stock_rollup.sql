-- 07_low_stock_rollup.sql
-- Low-stock visibility, rolled up through the category tree at ANY depth.
--
-- DECISION NOTES (defaults chosen by the assistant - confirm or change, then
-- record in your own words):
--   D17. A category's figure INCLUDES everything beneath it (Electronics
--        includes Phones, which includes Cases). A product is counted once in
--        each of its ancestors, and never twice within the same category, so
--        the top-level rows add up to the grand total (checked below).
--   D18. 'Low' = stock between 1 and p_threshold (default 5). 'Out of stock'
--        = stock <= 0 and is reported separately. 5 is a GUESS: nobody told us
--        Kloud Kart's reorder level. It is a parameter so it can be changed
--        without touching the logic.
--   D19. Depth is never written into the query. The tree is walked by a
--        recursive query that stops when a pass finds no more children, with
--        TWO guards against loops: the CYCLE clause (marks and drops a row that
--        would revisit a category) and a hard depth cap of 50.
--   D20. A category whose parent does not exist (R5, 'Clearance') is treated
--        as a root and flagged, rather than silently vanishing.
--        v_categories_unreachable lists anything the walk still cannot reach
--        (for example a closed loop with no root). It should return no rows.
--   D21. Products with no category (R6, 37 products) get their own
--        '(Uncategorised)' row so the report still reconciles to every product.
--   D22. DATA FINDING: categories 9001 and 9002 are each other's parent - a
--        closed loop with no root, so no walk from a root can reach them. The
--        6 products inside them would vanish from the rollup, so they get a
--        '(Unreachable category - fix the tree)' row instead. The walk
--        terminates on this real loop (guards D19). Fix = decide the true
--        parent of 9001/9002 with marketing; nothing here guesses it.

-- 1. The tree, with readable paths ---------------------------------------------
CREATE OR REPLACE VIEW v_category_tree AS
WITH RECURSIVE tree AS (
    SELECT c.category_id, c.category_name, c.parent_id,
           1 AS depth,
           c.category_name::text AS path,
           (c.parent_id IS NOT NULL) AS parent_missing
    FROM   categories c
    WHERE  c.parent_id IS NULL
       OR  NOT EXISTS (SELECT 1 FROM categories p WHERE p.category_id = c.parent_id)
    UNION ALL
    SELECT c.category_id, c.category_name, c.parent_id,
           t.depth + 1,
           t.path || ' > ' || c.category_name,
           false
    FROM   categories c
    JOIN   tree t ON c.parent_id = t.category_id
    WHERE  t.depth < 50                                   -- guard 2: hard cap
) CYCLE category_id SET is_cycle USING walked             -- guard 1: loop detection
SELECT category_id, category_name, parent_id, depth, path, parent_missing
FROM   tree
WHERE  NOT is_cycle;

-- 2. Every category paired with everything beneath it (itself included) -------
CREATE OR REPLACE VIEW v_category_ancestry AS
WITH RECURSIVE walk AS (
    SELECT c.category_id AS ancestor_id, c.category_id AS descendant_id, 0 AS levels_below
    FROM   categories c
    UNION ALL
    SELECT w.ancestor_id, c.category_id, w.levels_below + 1
    FROM   walk w
    JOIN   categories c ON c.parent_id = w.descendant_id
    WHERE  w.levels_below < 50
) CYCLE descendant_id SET is_cycle USING walked
SELECT ancestor_id, descendant_id, levels_below
FROM   walk
WHERE  NOT is_cycle;

-- 3. Anything the tree cannot reach (expected: no rows) -------------------------
CREATE OR REPLACE VIEW v_categories_unreachable AS
SELECT c.category_id, c.category_name, c.parent_id
FROM   categories c
WHERE  NOT EXISTS (SELECT 1 FROM v_category_tree t WHERE t.category_id = c.category_id);

-- 4. The rollup -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION low_stock_rollup(p_threshold integer DEFAULT 5)
RETURNS TABLE (
    category_id    integer,
    category_path  text,
    depth          integer,
    products       bigint,
    out_of_stock   bigint,
    low_stock      bigint
)
LANGUAGE sql STABLE
AS $$
    WITH per_category AS (          -- collapse products to ONE row per category first,
        SELECT p.category_id,       -- so joining to ancestors cannot multiply product rows
               count(*)                                                        AS products,
               count(*) FILTER (WHERE p.stock_quantity <= 0)                   AS out_of_stock,
               count(*) FILTER (WHERE p.stock_quantity > 0
                                  AND p.stock_quantity <= p_threshold)         AS low_stock
        FROM   products p
        WHERE  p.category_id IS NOT NULL
        GROUP  BY p.category_id
    )
    SELECT t.category_id,
           t.path,
           t.depth,
           coalesce(sum(pc.products), 0)::bigint,
           coalesce(sum(pc.out_of_stock), 0)::bigint,
           coalesce(sum(pc.low_stock), 0)::bigint
    FROM   v_category_tree t
    JOIN   v_category_ancestry a ON a.ancestor_id = t.category_id
    LEFT   JOIN per_category pc  ON pc.category_id = a.descendant_id
    GROUP  BY t.category_id, t.path, t.depth

    UNION ALL

    SELECT NULL::integer,
           '(Uncategorised)',
           0,
           count(*),
           count(*) FILTER (WHERE p.stock_quantity <= 0),
           count(*) FILTER (WHERE p.stock_quantity > 0 AND p.stock_quantity <= p_threshold)
    FROM   products p
    WHERE  p.category_id IS NULL

    UNION ALL

    SELECT NULL::integer,
           '(Unreachable category - fix the tree)',
           0,
           count(*),
           count(*) FILTER (WHERE p.stock_quantity <= 0),
           count(*) FILTER (WHERE p.stock_quantity > 0 AND p.stock_quantity <= p_threshold)
    FROM   products p
    WHERE  p.category_id IS NOT NULL
      AND  NOT EXISTS (SELECT 1 FROM v_category_tree t WHERE t.category_id = p.category_id)

    ORDER  BY 2;
$$;
--
-- Use:   SELECT * FROM low_stock_rollup();        -- default threshold 5
--        SELECT * FROM low_stock_rollup(10);
--        SELECT * FROM low_stock_rollup() WHERE depth <= 2;   -- top of the tree only
