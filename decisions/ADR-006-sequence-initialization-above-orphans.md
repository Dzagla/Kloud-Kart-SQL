# ADR-006: Seed the order ID sequence above orphan line numbers

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Solution Architect

## Context

The original schema lacked primary key sequences, so concurrent orders would generate duplicate IDs if application code computed `max(id) + 1`. 

Furthermore, integrity check R2 revealed 692 orphan order items in `order_items` claiming order IDs up to 999,862, while the highest ID in `orders` is only 659,384. If an order ID sequence starts at 659,385, new orders will eventually hit those orphan ID numbers, and those old orphan items will silently attach themselves to brand-new, unrelated customer orders.

## Decision

I attached PostgreSQL sequences to all primary keys and explicitly seeded `orders_order_id_seq` to 999,862 (`greatest(max(orders.order_id), max(order_items.order_id))`), so that new orders start cleanly at 999,863.

## Alternatives considered

### Alternative A: Seed the sequence at `max(orders.order_id)` (~659,384)

- **How it would work:** Follow the standard practice of setting the sequence to the maximum existing order ID.
- **Why it is attractive:** Keeps order numbers contiguous without a 340,000-number gap.
- **Why rejected:** When new order numbers reach 900,101, the orphan items will attach themselves to real orders, corrupting invoices and warehouse pick lists.

### Alternative B: Delete the 692 orphan order items before creating the sequence

- **How it would work:** Purge orphan lines from `order_items` and keep the sequence contiguous.
- **Why it is attractive:** Cleans up orphan records immediately.
- **Why rejected:** Deleting orphan financial records destroys audit evidence. Those 692 lines total ~826,000 units of value and need operational investigation, not silent deletion.

## Consequences

- **What this buys:** Fast, thread-safe primary key generation that will never collide with pre-existing orphan order items.
- **What this costs:** Creates an intentional gap in order numbering between 659,384 and 999,863.
- **What it costs the client if I am wrong:** Financial auditors might ask why order numbers jumped by 340,000.
- **What would make me revisit this:** Operations and finance completing an audit of the orphan lines and archiving them to a separate backup table.

## What this survives

- **What was tested:** Verified directly in the database following the test suite runs:
  - Checked `pg_sequences` for `orders_order_id_seq`: `last_value` reached 1,039,862 (strictly $\ge 999,862$).
  - Tested for orphan attachment across all newly generated orders: queried `order_items` joined to `orders` where `order_id > 999862` having more than 1 item line; returned 0 rows.
  - Confirmed that the 692 orphan order items remain strictly isolated and did not attach to any newly created orders.
- **What was not tested:** Reaching the 64-bit sequence ceiling.
