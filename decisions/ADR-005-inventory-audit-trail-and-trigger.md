# ADR-005: Capture stock movements with an audit trigger and session flag

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Solution Architect

## Context

144 products have stock balances that disagree with their movement history in `inventory_log`. Nana asked for an audit trail that an auditor could walk through: every single change to product stock must be logged, whether it came from checkout, warehouse adjustments, or direct terminal updates. 

However, `place_order` already writes its own log entry so it can link the sale to the newly created `order_id`. If I put an automatic trigger on `products`, standard checkout orders would get logged twice.

## Decision

I deployed an `AFTER INSERT OR UPDATE OF stock_quantity` trigger on `products` to log every inventory change, and had `place_order` set a transaction-local setting (`set_config('kloudkart.audit_handled', 'on', true)`) so the trigger skips execution during checkout. Unlabelled direct changes are logged automatically as `correction` movements with the note `'UNLABELLED direct change by <session_user>'`. Labelled operational adjustments are routed through `adjust_stock()`.

## Alternatives considered

### Alternative A: Rely only on stored procedures without a trigger

- **How it would work:** Log inventory movements exclusively inside `place_order()` and `adjust_stock()`.
- **Why it is attractive:** Simpler design with no trigger logic.
- **Why rejected:** Any manual or administrative `UPDATE products SET stock_quantity = ...` run from a terminal would bypass the log entirely, creating the exact audit blind spots found in the historical data.

### Alternative B: Have the trigger write all log entries, including sales

- **How it would work:** Remove the log insert from `place_order` and let the trigger handle all logging.
- **Why it is attractive:** Single code path for writing the log.
- **Why rejected:** A row trigger on `products` does not know the `order_id` generated in the `orders` table. It would log an anonymous sale without linking to the specific customer order, degrading audit traceability.

## Consequences

- **What this buys:** Every stock change made through the database is logged. No update to `stock_quantity` via SQL can occur without leaving an audit record. Uncoordinated direct updates are captured and tagged with the responsible database user.
- **What this costs:** The session flag `kloudkart.audit_handled` relies on an internal software convention. The log is not strictly append-only (users with direct table permissions can edit or delete rows, and superusers can disable triggers).
- **What it costs the client if I am wrong:** A developer or script could set the session flag manually to bypass the audit trigger, or someone with direct database write access could alter past log rows.
- **What would make me revisit this:** In a production deployment, revoking direct `UPDATE` and `DELETE` permissions on `inventory_log` and `products` from interactive users, forcing all updates through an authenticated application service.

## What this survives

- **What was tested:** Verified in `race_test.py` Test 4 (5 purchases produced exactly 5 sales movements and 1 initial setup entry with zero duplicates) and manual terminal updates were successfully logged with the `'UNLABELLED direct change'` note.
- **What was not tested:** Malicious database superusers disabling triggers or directly tampering with historical rows in `inventory_log`.
