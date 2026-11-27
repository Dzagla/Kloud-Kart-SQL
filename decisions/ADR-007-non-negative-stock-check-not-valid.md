# ADR-007: Prevent negative stock with a NOT VALID check constraint

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Solution Architect

## Context

Nana made it clear that stock must never drop below zero. But in auditing the data, I found that 14 products in the catalog already have negative stock balances (ranging from −4 to −1 units), left over from past overselling incidents.

Adding a standard `CHECK (stock_quantity >= 0)` constraint fails immediately because PostgreSQL validates existing rows during creation and aborts when it sees those 14 negative balances.

I could not delay deploying the overselling protections while waiting for warehouse staff to recount those items.

## Decision

I added the constraint using PostgreSQL's `NOT VALID` clause: `ALTER TABLE products ADD CONSTRAINT products_stock_non_negative CHECK (stock_quantity >= 0) NOT VALID;`. 

This blocks all future updates and inserts from taking stock below zero, while allowing the 14 historical negative balances to remain visible until warehouse staff can physically count them.

## Alternatives considered

### Alternative A: Set existing negative balances to zero before adding the constraint

- **How it would work:** Run `UPDATE products SET stock_quantity = 0 WHERE stock_quantity < 0;` and apply a standard check constraint.
- **Why it is attractive:** Clean constraint validation right away.
- **Why rejected:** It invents stock on paper. Overwriting negative balances hides the shortfall from warehouse staff doing physical stocktakes.

### Alternative B: Rely only on application-level checks in `place_order()`

- **How it would work:** Check that stock is sufficient inside the order placement function and add no table constraints.
- **Why it is attractive:** No DDL changes required.
- **Why rejected:** It leaves the table unprotected against direct terminal updates or third-party bulk imports that could accidentally write negative stock.

## Consequences

- **What this buys:** Immediate database-level protection against new negative stock, without rewriting historical data or blocking deployment.
- **What this costs:** Because PostgreSQL evaluates table check constraints whenever any row is updated, all 14 negative-stock products are completely frozen against any update—including price edits, title corrections, or category reassignment—until their stock balance is brought to $\ge 0$.
- **What it costs the client if I am wrong:** Marketing or catalog staff attempting to change the price or name of any of those 14 products will be blocked by the database with a check constraint violation until warehouse counts are applied.
- **What would make me revisit this:** Warehouse staff finishing physical stocktakes on the 14 items, adjusting their balances, and running `ALTER TABLE products VALIDATE CONSTRAINT products_stock_non_negative;`.

## What this survives

- **What was tested:** 
  - Applied cleanly on a fresh load containing 14 negative balances without schema errors.
  - Tested updating a non-stock column on a negative-stock product (`UPDATE products SET price = 99.99 WHERE product_id = 5005;`): PostgreSQL rejected the update with `ERROR: new row for relation "products" violates check constraint "products_stock_non_negative"`, confirming the frozen-record behavior.
  - Passed all concurrency tests in `race_test.py` with zero overselling.
- **What was not tested:** N/A.
