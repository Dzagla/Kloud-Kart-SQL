# ADR-003: Define customer spend using order headers and completed/shipped statuses

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Solution Architect

## Context

The brief asked for a report of customer "spend" but did not specify which order statuses count, nor whether spend should be calculated from the order header (`total_amount`) or summed from individual line items. 

In auditing the data on the brief-consistent basis (excluding the 155 orphan orders that reference non-existent customers):
- There are **124,044 qualifying spend orders** worth **380,138,602.03 units**.
- 2,398 orders have header totals that do not match their line sums. Within those discrepancies, 1,610 orders are exact multiples (0.75, 0.90, 1.10, 1.25) of their line totals, indicating standard commercial discounts or fees. Meanwhile, six order lines contain extreme quantity typos (999 and 9,999) worth 3.07 million units in line value.

I needed a clear, defensible definition of customer spend that reflects actual commercial revenue without distorting the numbers.

## Decision

I defined customer spend as orders in `completed`, `complete`, or `shipped` status (excluding `pending`, `cancelled`, and `refunded`), and calculated spend strictly from `orders.total_amount` rather than line item summations, while excluding orphan orders whose customer does not exist.

## Alternatives considered

### Alternative A: Recomputing spend by summing order lines (`quantity * unit_price`)

- **How it would work:** Join orders to line items and sum line extensions.
- **Why it is attractive:** Normalization principles suggest that line items represent the granular truth of an order.
- **Why rejected:** It pulls in 3.07 million units of fictitious sales from the six 999/9,999 quantity typos, and erases the commercial discounts and fees reflected in the 1,610 ratio orders.

### Alternative B: Filtering strictly on the literal spelling `'completed'`

- **How it would work:** Filter orders using `WHERE status = 'completed'`.
- **Why it is attractive:** Simple and conservative.
- **Why rejected:** On the clean basis (orphans excluded), a literal filter matches only 22,050 orders (66.42M units), dropping **101,994 valid spend orders** (worth **313.72M units**) because of spelling variants like `'complete'` and orders marked `'shipped'`.

### Alternative C: Overwriting discrepant headers with line sums in the database

- **How it would work:** Run an automated batch update to force `orders.total_amount = sum(quantity * unit_price)`.
- **Why it is attractive:** Cleans up the 2,398 audit discrepancies.
- **Why rejected:** It destroys historical financial data and erases customer discounts without knowing the commercial agreement behind each order.

## Consequences

- **What this buys:** Total reported spending reconciles cleanly to 380,138,602.03 units across 38,582 spending customers (1,838 have zero spend). It insulates financial reports from line quantity typos and respects customer billing.
- **What this costs:** Relies on the assumption that shipped orders (12,837 orders worth 40.92M units) are settled and that header ratios represent valid commercial adjustments.
- **What it costs the client if I am wrong:** If shipped orders are unpaid or returned, revenue is overstated by 40.92M units.
- **What would make me revisit this:** Written guidance from finance stating that shipped orders cannot be counted as paid, or an explicit table explaining discount codes.

## What this survives

- **What was tested:** Reconciled on the brief-consistent basis:
  - 159,384 loaded orders (487,063,959.81 units)
  - minus 35,185 non-spend orders (106,497,688.91 units)
  - minus 155 orphan spend orders (427,668.87 units)
  - equals 124,044 spend orders and 380,138,602.03 total reported spend across 38,582 spending customers.
- **What was not tested:** Cross-checking order totals against external merchant bank settlement statements.
