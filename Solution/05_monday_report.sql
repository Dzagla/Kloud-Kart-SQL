-- 05_monday_report.sql
-- The Monday customer-spending report, computed in ONE pass over orders.
--
-- DECISION NOTES (defaults chosen by the assistant - confirm or change, then
-- record in your own words):
--   D11. 'Spend' = completed + complete + shipped. Pending, cancelled and
--        refunded do not count. Change it in ONE place: order_status_map.
--   D12. Status spellings are mapped through a table, not a CASE inside the
--        report, so a new spelling shows up in v_unmapped_order_statuses
--        instead of being silently dropped from spend.
--   D13. 'Trailing 12 months' is relative to a parameter, p_anchor (the first
--        day AFTER the last month to include). m12 = the month before the
--        anchor, m01 = twelve months before it.
--   D14. total_amount (as written at checkout) is used, not the sum of order
--        lines, because 1,589 totals differ from their lines by exact
--        0.75/0.90/1.10/1.25 multiples that look like discounts or fees (V7/V8)
--        and the six 999/9999 quantity typos (V1) would otherwise inflate spend.
--        UNVERIFIED: nobody has confirmed what those multiples are.
--   D15. RANK(), not ROW_NUMBER: customers tied on total spend share a rank,
--        so the top-100 can contain more than 100 rows if 100th place ties.
--   D16. Orders whose customer does not exist (R1, 210 orders) cannot appear
--        in a per-customer report; they are excluded, not reassigned.

-- 1. The status vocabulary, decided once -------------------------------------
CREATE TABLE IF NOT EXISTS order_status_map (
    status_key       text PRIMARY KEY,      -- lower(trim(orders.status))
    canonical_status text    NOT NULL,
    counts_as_spend  boolean NOT NULL
);
INSERT INTO order_status_map (status_key, canonical_status, counts_as_spend) VALUES
    ('completed', 'completed', true),
    ('complete',  'completed', true),
    ('shipped',   'shipped',   true),
    ('pending',   'pending',   false),
    ('cancelled', 'cancelled', false),
    ('canceled',  'cancelled', false),
    ('refunded',  'refunded',  false)
ON CONFLICT (status_key) DO NOTHING;

-- Any status spelling that is NOT mapped. Should always return zero rows.
CREATE OR REPLACE VIEW v_unmapped_order_statuses AS
SELECT lower(trim(o.status)) AS status_key, count(*) AS orders
FROM   orders o
WHERE  NOT EXISTS (SELECT 1 FROM order_status_map m WHERE m.status_key = lower(trim(o.status)))
GROUP  BY 1;

-- 2. Per-customer report -------------------------------------------------------
CREATE OR REPLACE FUNCTION monday_report(
    p_anchor date DEFAULT date_trunc('month', now())::date
)
RETURNS TABLE (
    customer_id  integer,
    full_name    text,
    total_spent  numeric,
    order_count  bigint,
    m01 numeric,
    m02 numeric,
    m03 numeric,
    m04 numeric,
    m05 numeric,
    m06 numeric,
    m07 numeric,
    m08 numeric,
    m09 numeric,
    m10 numeric,
    m11 numeric,
    m12 numeric,
    spend_rank   bigint
)
LANGUAGE sql STABLE
AS $$
    WITH spend AS (
        SELECT o.customer_id, o.order_date, o.total_amount
        FROM   orders o
        JOIN   order_status_map m ON m.status_key = lower(trim(o.status))
        WHERE  m.counts_as_spend
    ),
    agg AS (
        SELECT s.customer_id,
               sum(s.total_amount) AS total_spent,
               count(*)            AS order_count,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '12 months' AND s.order_date < p_anchor - interval '11 months') AS m01,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '11 months' AND s.order_date < p_anchor - interval '10 months') AS m02,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '10 months' AND s.order_date < p_anchor - interval '9 months') AS m03,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '9 months' AND s.order_date < p_anchor - interval '8 months') AS m04,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '8 months' AND s.order_date < p_anchor - interval '7 months') AS m05,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '7 months' AND s.order_date < p_anchor - interval '6 months') AS m06,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '6 months' AND s.order_date < p_anchor - interval '5 months') AS m07,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '5 months' AND s.order_date < p_anchor - interval '4 months') AS m08,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '4 months' AND s.order_date < p_anchor - interval '3 months') AS m09,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '3 months' AND s.order_date < p_anchor - interval '2 months') AS m10,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '2 months' AND s.order_date < p_anchor - interval '1 months') AS m11,
        sum(s.total_amount) FILTER (WHERE s.order_date >= p_anchor - interval '1 months' AND s.order_date < p_anchor - interval '0 months') AS m12
        FROM   spend s
        GROUP  BY s.customer_id
    )
    SELECT c.customer_id,
           c.full_name,
           coalesce(a.total_spent, 0)  AS total_spent,
           coalesce(a.order_count, 0)  AS order_count,
        coalesce(a.m01, 0) AS m01,
        coalesce(a.m02, 0) AS m02,
        coalesce(a.m03, 0) AS m03,
        coalesce(a.m04, 0) AS m04,
        coalesce(a.m05, 0) AS m05,
        coalesce(a.m06, 0) AS m06,
        coalesce(a.m07, 0) AS m07,
        coalesce(a.m08, 0) AS m08,
        coalesce(a.m09, 0) AS m09,
        coalesce(a.m10, 0) AS m10,
        coalesce(a.m11, 0) AS m11,
        coalesce(a.m12, 0) AS m12,
           rank() OVER (ORDER BY coalesce(a.total_spent, 0) DESC) AS spend_rank
    FROM   customers c
    LEFT   JOIN agg a ON a.customer_id = c.customer_id;
$$;

-- 3. Top 100 ----------------------------------------------------------------------
-- No separate object needed: the ranking is computed inside monday_report, so
-- the top 100 is a filter on it. (A window function cannot sit in WHERE, which
-- is why the rank is computed first, inside the function.)
--
--   SELECT * FROM monday_report('2026-09-01') WHERE spend_rank <= 100 ORDER BY spend_rank;

-- 4. Running per-customer total (what Adwoa keeps by hand) -------------------------
-- One row per counted order, with the customer's cumulative spend after it.
-- ROWS frame, ordered by date then order_id: two orders with the same timestamp
-- get a stable order instead of both showing the combined total (which RANGE
-- would do).
CREATE OR REPLACE VIEW v_customer_running_total AS
SELECT o.customer_id,
       o.order_id,
       o.order_date,
       o.total_amount,
       sum(o.total_amount) OVER (
           PARTITION BY o.customer_id
           ORDER BY o.order_date, o.order_id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM   orders o
JOIN   order_status_map m ON m.status_key = lower(trim(o.status))
WHERE  m.counts_as_spend;
