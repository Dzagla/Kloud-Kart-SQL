# Kloud Kart — Inventory & Order Management (DE03)

Engineering solution for Kloud Kart Ltd. (Accra, Ghana), addressing stock overselling under flash-sale contention, slow Monday executive reporting, hierarchical category stock rollups, and data integrity audit reconciliation on PostgreSQL.

---

## Project Structure

The repository is organized by concern into dedicated directories:

```text
.
├── .dockerignore              # Docker build exclusions
├── .env                       # Local environment variables (DB credentials, connection strings)
├── .env.example               # Template environment configuration
├── .gitignore                 # Git ignore rules (.env)
├── docker-compose.yml         # Container definitions (PostgreSQL 18 & race-test runner)
├── Dockerfile                 # Custom PostgreSQL 18 image specification
├── README.md                  # Project overview, architecture summary, and quickstart guide
├── decisions/                 # Architecture Decision Records (ADRs 001–007) in house format
│   ├── ADR-001-preventing-stock-overselling.md
│   ├── ADR-002-reporting-single-pass-aggregation.md
│   ├── ADR-003-spend-definition-and-order-totals.md
│   ├── ADR-004-status-mapping-table.md
│   ├── ADR-005-inventory-audit-trail-and-trigger.md
│   ├── ADR-006-sequence-initialization-above-orphans.md
│   └── ADR-007-non-negative-stock-check-not-valid.md
├── docs/                      # Formal written deliverables and assessment documentation
│   ├── client_memo.md         # One-page executive memo to Nana Adjei (plain business language)
│   ├── data_findings.md       # Full data findings with reconciliation table and ranked risks
│   ├── data_diagnosis.md      # Extended diagnostic audit analysis and rationale
│   ├── improvement.md         # Documented justification for reorder priority list
│   └── measurement_report.md  # Detailed benchmark report (median, p95, worst across 20 runs)
├── Solution/                  # Production-ready SQL scripts and evaluation runners
│   ├── 01_integrity_checks.sql       # 29 read-only diagnostic integrity checks
│   ├── 02_schema_changes.sql         # Sequences and non-negative stock constraint (NOT VALID)
│   ├── 03_place_order.sql            # Concurrency-safe order placement with row-level locks
│   ├── 04_report_baseline.sql        # Stand-in baseline query using correlated subqueries
│   ├── 05_monday_report.sql          # Single-pass 12-month Monday spending report and views
│   ├── 06_orders_customer_index.sql  # Optional covering index (analyzed with trade-offs)
│   ├── 07_low_stock_rollup.sql       # Recursive category tree stock rollup function
│   ├── 08_audit_trail.sql            # Automatic movement trigger and adjust_stock() procedure
│   ├── 09_reorder_list.sql           # Sales-velocity reorder prioritization function
│   ├── fresh_load_test.sh            # End-to-end fresh build verification script
│   ├── measure.sh                    # Automated 20-run benchmark timing script
│   └── run_all.sql                   # Master build script applying all solution files in order
└── Resources/                 # Starter data, base schema, and unmodified test harness
    ├── schema.sql             # Original unindexed, unconstrained schema
    ├── load.sql               # Data loading script for provided CSV files
    ├── race_test.py           # Concurrency race test harness (runs unmodified)
    └── data/                  # Raw CSV files (categories, products, customers, orders, etc.)
```

---

## Deliverables Index & Rubric Mapping

| Deliverable | File Location | Assessment Criterion | Weight | Summary |
|---|---|---|:---:|---|
| **Data Diagnosis** | [`docs/data_findings.md`](docs/data_findings.md) | **Analyze** | 20% | 5 ranked critical risks (F-01 to F-05), reconciliation table, "looked wrong, is not wrong" items, and unverified assumptions. |
| **Working SQL Solution** | [`Solution/run_all.sql`](Solution/run_all.sql) | **Apply** | 20% | Complete top-to-bottom build on a fresh load; satisfies all 4 operational criteria and passes all tests. |
| **Concurrency & Reporting** | [`Solution/03_place_order.sql`](Solution/03_place_order.sql)<br>[`Solution/05_monday_report.sql`](Solution/05_monday_report.sql) | **Apply / Create** | 20% | Row-level locking for zero overselling (2.09 s flash sale); single-pass report reduced from ~40 min to 0.28 s. |
| **Decision Records (ADRs)** | [`decisions/`](decisions/) | **Evaluate** | 20% | 7 formal ADRs detailing context, active decisions, real rejected alternatives, client costs, and limits. |
| **Client Memo & Improvement** | [`docs/client_memo.md`](docs/client_memo.md)<br>[`docs/improvement.md`](docs/improvement.md) | **Evaluate / Create** | 20% | One-page business memo to Nana; plus sales-velocity reorder prioritization ranking based on 28-day trailing sales. |

---

## Key Metrics at a Glance

| Target / Operation | Baseline / Stated | Achieved | Evidence |
|---|---|---|---|
| **Monday Report (all 40,420 customers)** | ~40 minutes (correlated subqueries) | **281.7 ms** (0.28 s) | Single-pass scan with aggregate `FILTER`; median of 20 runs in [`measure.sh`](Solution/measure.sh). |
| **Top 100 Spenders Ranking** | Extrapolated ~40 minutes | **248.8 ms** (0.25 s) | Window `RANK()` filter evaluated inside `monday_report()`. |
| **Flash-Sale Concurrency (400 buyers, 50 units)** | Unprotected (frequent overselling) | **2.09 s** | 50 sold, 350 refused cleanly, 0 errors, 0 oversold in [`race_test.py`](Resources/race_test.py). |
| **Low-Stock Category Rollup** | "In a couple of seconds" | **2.9 ms** | Recursive category CTE with loop guard and depth limit; handles circular links. |
| **Reorder Priority List (Improvement)** | Unusable static list (1,685 items / 42%) | **27.1 ms** | Ranks items by runout risk (days of cover) based on 28-day trailing velocity on local laptop copy. |
| **Inventory Movement Audit Trail** | 144 unlogged mismatches | **Every DB change logged** | Trigger logs all movements; unlabelled changes tagged with user; negative stock blocked. |

---

## Quickstart & Verification

All scripts are configured to run from the repository root (`Lab/`) using Git Bash on Windows or Linux bash.

### 0. Start the Database Container (Docker Compose)
To launch the PostgreSQL 18 container with the required connection settings (`max_connections=500` to support flash-sale concurrency) and volume mounts:

```bash
docker compose up -d kloudkart
```

To run the concurrency race test in a standalone container (without needing local Python/psycopg2):

```bash
docker compose run --rm race-test
```

### 1. Verify End-to-End Fresh Build and Concurrency
Run the automated test script. It drops and creates a separate database (`kloudkart_fresh`), loads the raw CSV data, builds all solution objects in order, runs all 29 integrity checks, and executes `race_test.py` unmodified:

```bash
bash Solution/fresh_load_test.sh
```

**Expected Result:**
- All tables loaded and indexed.
- `run_all.sql: all objects created`.
- 29 integrity checks executed.
- `race_test.py`: Test 1 (25/25 rounds OK), Test 2 (flash sale: 50 sold, 350 refused, 0 errors, ~2.09 s), Test 3 (oversell attempt refused cleanly), Test 4 (audit trail intact: 5 sold, 6 movements recorded).
- `PASSED — exactly one buyer gets the last unit, every time.`

### 2. Run Query Performance Benchmarks
Execute the timing harness across 20 iterations to compute first (cold), median, p95, and worst timings:

```bash
bash Solution/measure.sh 20
```

### 3. Run Diagnostic Integrity Checks
Execute the read-only audit suite against the working database:

```bash
docker exec -i kloudkart psql -U postgres -d kloudkart -f /lab/Solution/01_integrity_checks.sql
```

---

## Architectural Decision Summary

1. **[ADR-001: Prevent Stock Overselling via Row-Level Exclusive Locks](decisions/ADR-001-preventing-stock-overselling.md)**  
   Uses `SELECT price, stock_quantity FROM products WHERE product_id = p_product_id FOR UPDATE` inside `place_order()` under `READ COMMITTED` isolation. Concurrency contention queues at the row lock, allowing the second buyer to re-read the updated committed balance and receive an instant, clean "out of stock" message without database exceptions.
2. **[ADR-002: Single-Pass Conditional Aggregation for Monday Reporting](decisions/ADR-002-reporting-single-pass-aggregation.md)**  
   Replaces the ~40-minute correlated subquery pattern with a single table scan over `orders` using SQL standard `FILTER (WHERE ...)` clauses grouped by `customer_id`, dropping execution time across all 40,420 customers to **0.28 seconds**.
3. **[ADR-003: Spend Definition and Header Total Amount Precedence](decisions/ADR-003-spend-definition-and-order-totals.md)**  
   Defines spend as `completed` and `shipped` orders (excluding `pending`, `cancelled`, and `refunded`), calculating spend from `orders.total_amount` while excluding orphan orders (155 orders / 427.67K units). Reconciles customer spend to **380,138,602.03 units** across 38,582 spending customers, insulating financial figures from 3.07M units in line-item quantity typos (orders of 999 and 9,999 units).
4. **[ADR-004: Decoupled Configuration Table for Order Status Normalization](decisions/ADR-004-status-mapping-table.md)**  
   Introduces `order_status_map` mapping 7 normalized raw spellings to 5 canonical states, accompanied by the operational exception view `v_unmapped_order_statuses` to prevent silent revenue omission.
5. **[ADR-005: Comprehensive Inventory Audit Trail via Trigger with Session Flagging](decisions/ADR-005-inventory-audit-trail-and-trigger.md)**  
   Attaches an `AFTER INSERT OR UPDATE` trigger (`products_stock_audit`) on `products.stock_quantity`. `place_order` sets `kloudkart.audit_handled = 'on'` to avoid duplicate logging, while direct terminal and administrative updates are captured automatically as unlabelled corrections.
6. **[ADR-006: Primary Key Sequence Initialization Above Orphan ID Ranges](decisions/ADR-006-sequence-initialization-above-orphans.md)**  
   Seeds `orders_order_id_seq` to 999,862 (above the 692 orphan order items that claim order IDs up to 999,862), ensuring new orders start at 999,863 and preventing historical orphan lines from silently attaching to new purchases.
7. **[ADR-007: Non-Negative Stock Constraint Enforced as NOT VALID](decisions/ADR-007-non-negative-stock-check-not-valid.md)**  
   Applies `CHECK (stock_quantity >= 0) NOT VALID` to `products`. Blocks all future transactions and scripts from driving stock negative while allowing historical negative balances (14 products, −4 to −1 units) to remain visible until physical warehouse recounts occur.

---

## Improvement Beyond the Brief: Reorder Priority List

Documented in [`docs/improvement.md`](docs/improvement.md) and implemented in [`Solution/09_reorder_list.sql`](Solution/09_reorder_list.sql):
- **The Problem:** The requested static 5-unit low-stock filter flags **1,685 products** (41.9% of the catalog), creating an unworkable alert list that fails to distinguish fast-selling revenue drivers from dormant stock.
- **The Solution:** `reorder_list(p_anchor, p_window_days, p_cover_days)` calculates trailing daily sales velocity over the prior 28 days from `inventory_log` and computes **days of cover** ($\text{stock} / \text{daily velocity}$).
- **The Result:** Ranks items by immediate runout urgency, filtering to items with fewer than 14 days of cover (assumed supplier lead time). Runs in **27.1 ms** on the local test copy without modifying tables or impacting checkout performance.

---

## AI-Use Declaration

> *"AI wrote and explained the SQL and checked my reasoning; the diagnosis ranking, decision rationale, ADRs, and memo are my own."*
