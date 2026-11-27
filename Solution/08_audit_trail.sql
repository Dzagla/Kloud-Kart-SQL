-- 08_audit_trail.sql
-- A stock trail an auditor can walk: EVERY change to products.stock_quantity
-- leaves a row in inventory_log, whoever made it.
--
-- DECISION NOTES (defaults chosen by the assistant - confirm or change, then
-- record in your own words):
--   D23. A TRIGGER is the right tool here and the WRONG tool for overselling.
--        It guarantees "this code runs on every change, even from a terminal",
--        so the trail cannot be forgotten. It does not make two buyers take
--        turns (each buyer's trigger sees only its own transaction) - that is
--        the row lock in place_order.
--   D24. place_order already writes its own log row, and tells the trigger so
--        (kloudkart.audit_handled) to avoid a double entry. This keeps
--        place_order correct even if this file is never run. TRADE-OFF: two
--        code paths write the log, and the flag can be set by anyone, so it is
--        a convention, not a wall.
--   D25. A change made with no label is still logged, as reason 'correction'
--        with the note 'UNLABELLED direct change by <user>', so auditors can
--        filter for them. Labelled changes go through adjust_stock().
--   D26. History is NOT rewritten. 144 products already disagree with their
--        log (check S1). v_stock_reconciliation shows each one; closing the
--        gap needs a physical count, which is a business action, not SQL.
--   D27. LIMIT (unverified/untested here): anyone with write access to
--        inventory_log can still edit or delete rows. race_test.py itself
--        deletes log rows during cleanup, so append-only cannot be enforced in
--        this lab. In production: revoke UPDATE/DELETE on inventory_log from
--        the application role.
--   D28. Reasons are restricted to the six already in use.

-- 1. Only the six existing reasons are legal ---------------------------------
ALTER TABLE inventory_log DROP CONSTRAINT IF EXISTS inventory_log_reason_valid;
ALTER TABLE inventory_log
    ADD CONSTRAINT inventory_log_reason_valid
    CHECK (reason IN ('sale','restock','return','correction','damage','stock_take'));

-- 2. The trigger ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION log_stock_movement()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_reason text;
    v_note   text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.stock_quantity <> 0 THEN
            INSERT INTO inventory_log (product_id, change_qty, reason, created_at, note)
            VALUES (NEW.product_id, NEW.stock_quantity, 'restock', now(), 'opening balance');
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE of stock_quantity
    IF NEW.stock_quantity IS NOT DISTINCT FROM OLD.stock_quantity THEN
        RETURN NEW;
    END IF;

    IF coalesce(current_setting('kloudkart.audit_handled', true), 'off') = 'on' THEN
        RETURN NEW;                       -- caller (place_order) logged it itself
    END IF;

    v_reason := coalesce(nullif(current_setting('kloudkart.stock_reason', true), ''), 'correction');
    v_note   := coalesce(nullif(current_setting('kloudkart.stock_note',   true), ''),
                         'UNLABELLED direct change by ' || session_user);

    INSERT INTO inventory_log (product_id, change_qty, reason, created_at, note)
    VALUES (NEW.product_id, NEW.stock_quantity - OLD.stock_quantity, v_reason, now(), v_note);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS products_stock_audit ON products;
CREATE TRIGGER products_stock_audit
    AFTER INSERT OR UPDATE OF stock_quantity ON products
    FOR EACH ROW EXECUTE FUNCTION log_stock_movement();

-- 3. The labelled way to change stock -----------------------------------------------
-- adjust_stock(7, 48, 'restock', 'delivery note 1021')
-- adjust_stock(7, -2, 'damage',  'dropped in warehouse')
-- Positive = stock in, negative = stock out. Refuses to take stock below zero.
CREATE OR REPLACE FUNCTION adjust_stock(
    p_product_id bigint,
    p_change     integer,
    p_reason     text,
    p_note       text DEFAULT NULL
)
RETURNS TABLE (success boolean, new_stock integer, message text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_stock integer;
BEGIN
    IF p_reason NOT IN ('restock','return','correction','damage','stock_take') THEN
        RETURN QUERY SELECT false, NULL::integer,
            'Reason must be one of: restock, return, correction, damage, stock_take (sales go through place_order)'::text;
        RETURN;
    END IF;

    SELECT p.stock_quantity INTO v_stock
      FROM products p WHERE p.product_id = p_product_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::integer, 'Unknown product'::text;
        RETURN;
    END IF;

    IF v_stock + p_change < 0 THEN
        RETURN QUERY SELECT false, v_stock,
            format('Refused: would take stock below zero (%s on hand, change %s)', v_stock, p_change);
        RETURN;
    END IF;

    IF p_change = 0 THEN                 -- a count that matched: logged, nothing moves
        INSERT INTO inventory_log (product_id, change_qty, reason, created_at, note)
        VALUES (p_product_id, 0, p_reason, now(), p_note);
    ELSE
        PERFORM set_config('kloudkart.stock_reason', p_reason, true);
        PERFORM set_config('kloudkart.stock_note', coalesce(p_note, ''), true);
        UPDATE products SET stock_quantity = stock_quantity + p_change
         WHERE product_id = p_product_id;
        PERFORM set_config('kloudkart.stock_reason', '', true);
        PERFORM set_config('kloudkart.stock_note', '', true);
    END IF;

    RETURN QUERY SELECT true, v_stock + p_change, 'Recorded'::text;
END;
$$;

-- 4. Where the trail does not tie out (history is left as it was, D26) ---------------
CREATE OR REPLACE VIEW v_stock_reconciliation AS
SELECT p.product_id,
       p.product_name,
       p.stock_quantity,
       coalesce(l.log_net, 0)                    AS log_net,
       p.stock_quantity - coalesce(l.log_net, 0) AS difference,   -- 0 = trail ties out
       l.last_movement
FROM   products p
LEFT   JOIN (SELECT product_id, sum(change_qty) AS log_net, max(created_at) AS last_movement
             FROM inventory_log GROUP BY product_id) l USING (product_id)
WHERE  p.stock_quantity <> coalesce(l.log_net, 0);
