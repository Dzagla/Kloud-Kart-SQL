-- 03_place_order.sql
-- The only supported way to sell stock. One call = one atomic unit of work:
-- check stock, decrement it, create the order and its line, log the movement.
-- If anything fails, none of it happens.
--
-- DECISION NOTES:
--   D4. FUNCTION, not procedure. The test calls it with SELECT. A function
--       runs inside the caller's transaction and is simpler; we never need to
--       COMMIT halfway because there is nothing to retry (see D5).
--   D5. Row lock (SELECT ... FOR UPDATE), default READ COMMITTED. The second
--       buyer waits on the product row, then re-reads it and sees the new
--       stock. SERIALIZABLE was rejected: it turns the race into errors, and
--       a function cannot retry itself with a fresh snapshot, so the error
--       would reach the client.
--   D6. Why not a trigger alone: each buyer's trigger runs inside that
--       buyer's own transaction and neither can see the other's uncommitted
--       work. Triggers are good for the audit row; they do not take turns.
--   D7. Customer and product are checked to exist. The schema has no foreign
--       keys and the data contains orphans (R1, R3); this function must not
--       create new ones.
--   D8. New orders start as 'pending', lower-case, one of the 5 real states
--       (see T1/T2). total_amount = price x quantity, taken at the moment of
--       sale from products.price (not from the caller).
--   D9. No lock_timeout inside the function: a timeout would raise an error
--       to the client, which the contract forbids. Waiting is bounded by the
--       length of the queue, not by a timer. REVISIT for flash sales.
--   D24. Logs its own movement and tells the audit trigger not to repeat it
--       (see 08_audit_trail.sql). Works whether or not that file has been run.
--   D10. Single-product only (the contract's signature). With multi-item
--       orders, lock products in ascending product_id to avoid deadlocks.
--
-- GUARANTEE AND ITS LIMIT: correct only for writers that go through this
-- function. A manual UPDATE products SET stock_quantity ... bypasses the lock
-- (the CHECK constraint still stops it going below zero).

CREATE OR REPLACE FUNCTION place_order(
    p_customer_id bigint,
    p_product_id  bigint,
    p_quantity    integer
)
RETURNS TABLE (success boolean, order_id bigint, message text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_price    numeric(12,2);
    v_stock    integer;
    v_order_id bigint;
BEGIN
    IF p_quantity IS NULL OR p_quantity < 1 THEN
        RETURN QUERY SELECT false, NULL::bigint,
                            'Invalid quantity: must be at least 1'::text;
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = p_customer_id) THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Unknown customer'::text;
        RETURN;
    END IF;

    -- THE LOCK. Everyone else wanting this product waits here until we commit.
    SELECT p.price, p.stock_quantity
      INTO v_price, v_stock
      FROM products p
     WHERE p.product_id = p_product_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Unknown product'::text;
        RETURN;
    END IF;

    IF v_stock < p_quantity THEN
        RETURN QUERY SELECT false, NULL::bigint,
            format('Out of stock: %s requested, %s available', p_quantity, v_stock);
        RETURN;
    END IF;

    -- Tell the audit trigger (08_audit_trail.sql) that this change is logged
    -- below, so it does not write a second row. Transaction-local.
    PERFORM set_config('kloudkart.audit_handled', 'on', true);
    UPDATE products
       SET stock_quantity = stock_quantity - p_quantity
     WHERE product_id = p_product_id;
    PERFORM set_config('kloudkart.audit_handled', 'off', true);

    INSERT INTO orders (customer_id, order_date, status, total_amount)
    VALUES (p_customer_id, now(), 'pending', v_price * p_quantity)
    RETURNING orders.order_id INTO v_order_id;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product_id, p_quantity, v_price);

    INSERT INTO inventory_log (product_id, change_qty, reason, created_at, note)
    VALUES (p_product_id, -p_quantity, 'sale', now(), 'order ' || v_order_id);

    RETURN QUERY SELECT true, v_order_id, 'Order placed'::text;
END;
$$;
