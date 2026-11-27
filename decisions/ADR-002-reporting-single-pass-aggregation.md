# ADR-002: Compute the Monday customer report in a single pass

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Solution Architect

## Context

Adwoa runs a weekly customer-spending report every Monday. The brief states that it takes about 40 minutes and occasionally fails to finish. We never saw Adwoa's actual query; `04_report_baseline.sql` is a plausible stand-in written the way slow reports usually are, using correlated subqueries per metric. 

When I timed the stand-in query on a sample of 100 customers with only 3 subqueries (lifetime spend, order count, and one month), it took ~1.4–1.7 seconds. Extrapolating the full query (14 subqueries for total spend, order count, and all 12 trailing months) across all 40,420 customers yields an estimated 38 to 44 minutes ($14/3 \times 1.5\text{ s} \times 404.2 \approx 2,400\text{ s}$), closely matching the 40-minute runtime reported in the brief.

I had to make the report run fast on Kloud Kart's existing database without making Adwoa wait 40 minutes every week.

## Decision

I rewrote the Monday customer report into a single table scan using SQL aggregate `FILTER (WHERE ...)` clauses grouped by customer, joined once to the customer list, and ranked with `RANK() OVER (ORDER BY total_spent DESC)`.

## Alternatives considered

### Alternative A: Composite index on `orders(customer_id, order_date)`

- **How it would work:** Keep the correlated subqueries and add a covering index on `(customer_id, order_date) INCLUDE (total_amount, status)` to speed up each subquery lookup.
- **Why it is attractive:** Leaves the query structure unchanged.
- **Why rejected:** The Monday report aggregates data for every customer in the business, touching 124,044 spend orders across the table. When a query scans that much of a table, the database planner correctly ignores the index and does a sequential table scan anyway. Furthermore, testing on 20,000 order inserts showed the index adds write overhead to every new checkout (~1.35x on my machine; ~2.5x on the 2-core test copy).

### Alternative B: A materialized view refreshed on Sunday night

- **How it would work:** Precompute customer aggregates into a materialized view on a scheduled timer.
- **Why it is attractive:** Instant responses for Monday morning readers.
- **Why rejected:** It adds moving parts (refresh jobs and extra storage) and presents stale numbers if orders are placed after the refresh. Because my single-pass query calculates live numbers for all 40,420 customers in ~281 ms, pre-aggregation is unnecessary.

### Alternative C: Upgrading to a larger database server

- **How it would work:** Pay for more CPU cores and memory to execute the correlated subqueries faster.
- **Why it is attractive:** Requires no SQL changes.
- **Why rejected:** More hardware cannot fix an algorithmic flaw that repeatedly scans the orders table for each customer. Hardware costs would rise while runtimes continued to degrade as order volume grew.

## Consequences

- **What this buys:** The full report runs across all 40,420 customers in 281.7 ms median, and the top 100 list runs in 248.8 ms (well within the brief's target of "in seconds on an ordinary laptop"). It requires no extra disk space and adds zero write penalty to customer checkout.
- **What this costs:** Requires standard SQL `FILTER` clause support.
- **What it costs the client if I am wrong:** If order volume grows past several million rows, a single sequential table scan will take several seconds, requiring table partitioning by year.
- **What would make me revisit this:** Order history growing beyond 5 million rows, or Adwoa requiring sub-second live spend lookups in an interactive web application.

## What this survives

- **What was tested:** Tested across 20 consecutive runs on the full dataset (159,384 orders, 40,420 customers) with default memory settings:
  - Full report: 281.7 ms median, 312.3 ms p95, 381.4 ms worst.
  - Top 100 spenders: 248.8 ms median, 295.2 ms p95, 301.0 ms worst.
- **What was not tested:** Query timings on cold disk reads after a system reboot with completely empty memory caches.
