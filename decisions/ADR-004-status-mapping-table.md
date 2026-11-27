# ADR-004: Map order statuses through a configuration table

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Solution Architect

## Context

The `orders.status` column was created as unconstrained free text. The raw data contains 15 different spellings across casing and whitespace variations, which reduce to 7 normalized spellings across 5 actual business states (`completed`, `shipped`, `pending`, `cancelled`, `refunded`).

If I hardcode status mappings into a `CASE` statement inside reporting queries, any new spelling entered tomorrow will silently drop out of spend calculations without raising an error.

## Decision

I created a configuration table, `order_status_map`, which maps each normalized status string (`lower(trim(status))`) to its canonical state and an explicit boolean `counts_as_spend` flag, backed by an exception view `v_unmapped_order_statuses` that flags any unknown status immediately.

## Alternatives considered

### Alternative A: Hardcoding `CASE` statements inside views and functions

- **How it would work:** Write `CASE WHEN lower(trim(status)) IN ('completed', 'shipped') ...` inside the SQL queries.
- **Why it is attractive:** No extra table to create or maintain.
- **Why rejected:** Silent failures. If upstream systems write a new status like `'paid'` or `'in_transit'`, the query quietly ignores it, dropping valid spend without alerting anyone.

### Alternative B: Converting the column to an ENUM or adding a CHECK constraint

- **How it would work:** Restrict `orders.status` to a strict list of allowed values.
- **Why it is attractive:** Strong validation at the database level.
- **Why rejected:** It requires rewriting or migrating historical rows first, which could break external applications. Furthermore, adding new enum values in PostgreSQL requires DDL migrations rather than simple data inserts.

## Consequences

- **What this buys:** Spend accounting rules are controlled in one place. Changing whether a status counts as spend requires updating a single boolean row. Any unmapped spelling appears immediately in `v_unmapped_order_statuses`.
- **What this costs:** Queries filtering on status perform a small join against a 7-row table.
- **What it costs the client if I am wrong:** Negligible; correcting an errant status mapping takes a single SQL statement.
- **What would make me revisit this:** Engineering standardizing the checkout application to write foreign-keyed status IDs.

## What this survives

- **What was tested:** Evaluated on all 159,384 orders. All 7 normalized spellings map deterministically to the 5 business states, leaving 0 unmapped rows in `v_unmapped_order_statuses`.
- **What was not tested:** Behavior if the table grows to thousands of arbitrary status entries.
