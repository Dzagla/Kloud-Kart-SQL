# Performance measurement report

## Target

The brief sets the performance target for the customer spending report:

> **"in seconds on an ordinary laptop"**

For order placement under contention, the requirement is zero overselling during flash-sale bursts, completing cleanly with an instant refusal message rather than an unhandled system crash or exception.

## Method

- **Hardware / Container Spec:**
  - Host OS: Windows 11 Pro / Windows_NT (x86_64).
  - Host CPU: 11th Gen Intel(R) Core(TM) i7 processor family (Intel64 Family 6 Model 140 Stepping 1, 8 logical cores / vCPUs).
  - Database Container: PostgreSQL 18.7 (Debian 18.7-1.pgdg13+5) running in Docker.
  - Memory Settings: `shared_buffers = 128MB`, `work_mem = 4MB`, `max_parallel_workers_per_gather = 2`.
- **What was timed:**
  - Query execution was timed from query submission to final result return using PostgreSQL's internal `\timing` mechanism (`psql`), measuring database execution duration.
  - Concurrency was timed using the official test suite `race_test.py`, measuring total wall-clock duration for 400 concurrent buyer threads to place orders simultaneously.
- **Runs and Reporting:**
  - Automated measurement via `measure.sh` executed 20 iterations per scenario ($N = 20$). Run 1 represents a cold buffer invocation; runs 2 through 20 represent warm cache executions. First, median, 95th percentile (p95), and worst execution times are recorded in milliseconds.
- **How to reproduce:**
  ```bash
  # Execute performance measurement script (20 iterations)
  bash Solution/measure.sh 20

  # Execute complete fresh build and concurrency harness
  bash Solution/fresh_load_test.sh
  ```

## Results

| Scenario | Runs | First (Cold) | Median | p95 | Worst | Target met? |
|---|---|---|---|---|---|---|
| **monday_report (all 40,420 customers)** | 20 | 381.4 ms | 281.7 ms | 312.3 ms | 381.4 ms | **Yes (0.28 s — "in seconds on an ordinary laptop")** |
| **top 100 customers ranking** | 20 | 281.4 ms | 248.8 ms | 295.2 ms | 301.0 ms | **Yes (0.25 s)** |
| **running total, one customer** | 20 | 39.0 ms | 41.1 ms | 46.2 ms | 56.3 ms | **Yes (0.04 s)** |
| **low_stock_rollup()** | 20 | 7.6 ms | 2.9 ms | 3.7 ms | 7.6 ms | **Yes (0.003 s)** |
| **reorder_list()** | 20 | 28.3 ms | 27.1 ms | 29.6 ms | 29.9 ms | **Yes (0.03 s)** |
| **Flash sale race test (400 buyers, 50 units)** | 1 | — | 2.34 s | — | 2.34 s | **Yes (2.34 s, 0 errors, 0 oversold)** |

## Before / after

| Query / stage | Before | After | Change |
|---|---|---|---|
| **Monday report (stand-in baseline, 100-customer sample)** | 1,412.8 ms (3 correlated subqueries on 100 customers) | 281.7 ms (all 40,420 customers, single pass) | **>2,000× faster effective throughput** |
| **Monday report (all 40,420 customers, estimated full query)** | ~40 minutes (brief-stated runtime for Adwoa's full report) | 281.7 ms (single-pass scan) | **Reduced from ~40 min to 0.28 s** |
| **Concurrent order placement (flash sale)** | Unprotected (frequent overselling and negative stock) | 2.34 s (400 threads, 50 sold, 350 refused, 0 errors) | **Zero oversold; 100% deterministic concurrency** |
| **Inventory audit coverage** | Partial / disconnected (144 mismatched products) | Every change made through the database is logged | **All stock changes captured with audit trail** |

## Caveats

1. **Contention Latency Under Extreme Queue Depth:** While row locking guarantees zero overselling, queuing 400 buyers behind a single row introduces an average latency of ~5.8 ms per transaction. At thousands of concurrent buyers, connection pool limits would require an external asynchronous queuing mechanism.
2. **Sequential Scan Scaling:** The single-pass report performs a sequential scan over the `orders` table. As order history expands from 160,000 orders into millions of rows, report runtimes will increase linearly, eventually requiring annual table partitioning or pre-aggregated reporting tables.
3. **Single Customer Lookup Index Trade-off:** Looking up a single customer's running total takes ~41 ms via table scan on this machine. Adding an index on `(customer_id, order_date)` drops lookup time to ~0.18 ms, but adds write overhead to every checkout insertion.
