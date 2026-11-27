# Data findings — Kloud Kart

## Summary

This audit evaluated the relational integrity, data validity, and operational consistency of the Kloud Kart database. The dataset contains 159,384 orders valued at 487.06M units across 40,420 customers, 4,023 products, and 282,352 inventory movements. 

The audit identified five critical structural and data defects: unconstrained order status spellings, unreconciled stock balances and duplicate restocks, discrepancies between order headers and line extensions, potential duplicate customer identities, and out-of-window order dates. Secondary issues include orphan records, a category loop, and unindexed foreign keys. All findings have been prioritized by their capacity to distort financial reporting or cause warehouse overselling.

## Reconciliation

| Stage | Rows | Delta | Reason |
|---|---|---|---|
| Orders loaded | 159,384 | 487,063,959.81 | Baseline dataset covering the full 13-month operational history. |
| Not spend (pending, cancelled, refunded) | 35,185 | 106,497,688.91 | Excluded from realized revenue: pending checkout (16,009 orders / 48.50M), cancelled orders (12,697 orders / 38.16M), refunded orders (6,479 orders / 19.83M). |
| Spend orders (completed and shipped) | 124,199 | 380,566,270.90 | Qualifying sales: completed orders (111,351 orders / 339.61M) and shipped orders (12,837 orders / 40.92M). |
| Of those, customer does not exist | 155 | 427,668.87 | Orphan spend orders referencing non-existent customer IDs (check R1); cannot be joined to valid customer records. |
| Total spent in the report (all customers) | 124,044 | 380,138,602.03 | Final customer spending reported by `monday_report`. Equals qualifying spend orders minus orphan spend (38,582 customers have $\ge 1$ spend order; 1,838 have none). |

For inventory, 144 of 4,023 products disagree with the movement log:
- **60 products** are explained by duplicate restock records logged in identical seconds.
- **40 products** are explained by logged warehouse recounts marked "not applied".
- **44 products** remain unexplained by any logged note and are tracked under "Could not verify".

---

## Findings, ranked by risk

### F-01: Inconsistent Order Status Spellings and Vocabulary — Severity: High

- **What it is:** `orders.status` is unconstrained free text. The column holds 15 raw string spellings which reduce to 7 distinct keys after `lower(trim(status))` across 5 business states (`completed`, `shipped`, `pending`, `cancelled`, `refunded`).
- **How I detected it:** Check T1/T2: compared `count(DISTINCT status)` against `count(DISTINCT lower(trim(status)))` and evaluated counts per state.
- **Scale:** 159,384 total orders. On the brief-consistent basis (excluding the 155 orphan orders), there are 124,044 valid spend orders worth 380.14M units. A literal query `WHERE status = 'completed'` matches only 22,050 orders (66.42M units), dropping **101,994 valid spend orders** (~82% of eligible spend, worth **313.72M units**).
- **Effect on the client's number:** Understates customer spend by 313.72M units if filtering literally on `completed`, or overstates spend by up to 58.00M units if counting cancelled/refunded orders.
- **What I did about it:** Built `order_status_map` mapping all 7 normalized keys to canonical states and an explicit boolean `counts_as_spend`. Created `v_unmapped_order_statuses` to immediately flag any newly introduced spelling.
- **Residual risk:** If business operations treats shipped orders (12,837 orders worth 40.92M units) as uncollected cash-on-delivery rather than spend, reported spend is overstated by 40.92M units.

### F-02: Unreconciled Stock Balances, Duplicate Restocks, and Negative Balances — Severity: High

- **What it is:** 144 products have a `stock_quantity` that disagrees with the sum of their logged movements in `inventory_log`. 14 products show negative stock balances (ranging from −4 to −1 units).
- **How I detected it:** Checks S1, S2, I3, V6, and V11: joined `products` with aggregated `inventory_log` movements before and after excluding duplicate restocks, and inspected correction notes.
- **Scale:** 144 products affected. Removing 60 duplicate restocks leaves 84 products with discrepancies: 22 products show recorded stock above log movements by 89 units (each matching an unapplied recount note); 62 show recorded stock below log by 268 units (18 with unapplied recounts, 44 unexplained). 14 products have stock below zero.
- **Effect on the client's number:** Recorded stock sitting above what the movement log explains (22 products, 89 units) is the direction that risks overselling if the log reflects physical reality. The opposite gap (62 products, 268 units below the log) risks under-selling. Neither can be confirmed without a physical count, which is unverified. The 14 negative balances are certain evidence of past overselling.
- **What I did about it:** Implemented `place_order` with row-level locks (`SELECT ... FOR UPDATE`) to prevent concurrent overselling. Deployed an automated audit trigger (`products_stock_audit`) and `adjust_stock()` to log all movements, added `CHECK (stock_quantity >= 0) NOT VALID` to prevent new negative balances without rewriting history, and built `v_stock_reconciliation` to monitor discrepancies.
- **Residual risk:** 44 products remain unexplained without an independent physical count; physical stock on shelves remains unverified until warehouse counts are executed.

### F-03: Header Total Amount Divergence from Line Item Summations — Severity: Medium

- **What it is:** 2,398 orders have a `total_amount` that differs from the sum of their line items (`quantity * unit_price`). Six order lines contain extreme quantities (999 and 9,999) representing keying typos.
- **How I detected it:** Checks V1, V7, and V8: compared `o.total_amount` against `sum(i.quantity * i.unit_price)` and computed the ratios between header and line sums.
- **Scale:** 2,398 orders (1.5% of orders). 1,610 orders show exact 0.75, 0.90, 1.10, or 1.25 multiples of line totals. Six order lines with quantities $\ge 999$ carry 3.07 million in line-derived value (1.06 million excluding cancelled orders).
- **Effect on the client's number:** If reporting is derived from line items, total sales are inflated by 3.07 million units due to keying errors, while legitimate commercial discounts and fees are eliminated.
- **What I did about it:** Retained `orders.total_amount` for all executive reporting and spend rankings rather than summing line items, preserving commercial discount structures and insulating totals from quantity typos.
- **Residual risk:** Without formal documentation of discount/surcharge policies, individual customer totals may differ from warehouse pack-slip value audits.

### F-04: Potential Duplicate Customer Identities — Severity: Medium

- **What it is:** 533 distinct email addresses are shared across 1,068 customer rows (531 pairs plus 2 triples, so 537 pairs counted pairwise across 533 groups). In all 533 groups, customer names match; in none do phone numbers match.
- **How I detected it:** Check I1: grouped `customers` by `lower(trim(email))` with `HAVING count(*) > 1`, and compared names and phone numbers within candidate groups.
- **Scale:** 1,068 customer records involved (2.6% of customer base across 533 groups).
- **Effect on the client's number:** If candidate groups represent identical people, their spend and order counts are split across multiple `customer_id` records, potentially dropping high-value customers out of the Top 100 spender ranking.
- **What I did about it:** Not done in the database build; recommended. The build does not perform automatic deduplication or merging, as merging without independent customer confirmation risks combining different people sharing an email. Recommended establishing a manual identity review process before any account consolidation.
- **Residual risk:** Top-100 spend rankings may understate the rank of customers whose purchases were split across multiple accounts.

### F-05: Orders Dated Outside the Stated Reporting Period — Severity: Low

- **What it is:** 24 orders (and 40 inventory movements) are dated after 31 August 2026, the nominal cutoff of the 13-month dataset.
- **How I detected it:** Checks V4 and V5: queried records with timestamps `> '2026-08-31 23:59:59'`.
- **Scale:** 24 orders out of 159,384 (0.015% of orders).
- **Effect on the client's number:** Negligible impact on overall revenue; slightly alters trailing-month totals if reporting windows do not enforce an explicit anchor date.
- **What I did about it:** Parameterized `monday_report(p_anchor)` and `reorder_list(p_anchor)` with an explicit anchor date parameter (`p_anchor = '2026-09-01'`), ensuring reporting boundaries are mathematically deterministic.
- **Residual risk:** Minimal; future automated cron executions will shift the anchor window dynamically to `current_date`.

---

## Looked wrong, is not wrong

| Apparent problem | Why it looks wrong | Why it is actually fine |
|---|---|---|
| **I4: Identical SALE rows in inventory log (459 rows)** | Multiple log rows share the exact same `product_id`, `change_qty`, and second-level timestamp `created_at`. | In a high-volume retail store, two distinct customers can legitimately purchase the same SKU within the same second. Removing these as "duplicates" made stock reconciliation worse by 459 units. |
| **I5: Duplicate product names (841 rows)** | 841 product rows share a name with at least one other row. | Different distinct SKUs (varying by size, color, model year, or packaging) legitimately share commercial display names while maintaining unique primary keys and barcodes. |
| **V9: Negative movement quantities in log (262,646 rows)** | 262,646 rows in `inventory_log` have negative `change_qty` values. | Negative values are the deliberate design mechanism for recording stock reductions (sales, damages, returns to vendor). |
| **V10: Stock-take rows with change quantity 0 (90 rows)** | 90 inventory movements of reason `stock_take` have `change_qty = 0`. | When a physical inventory count matches recorded stock exactly, an audit row with zero change is logged to record that the physical count occurred without altering balances. |
| **R6: Products with NULL category (37 rows)** | 37 products have no foreign reference in `category_id`. | A small number of unclassified, miscellaneous, or bundled items may legitimately lack an assigned category; the rollup explicitly surfaces them under `(Uncategorised)`. |

---

## Could not verify

1. **The 0.75, 0.90, 1.10, and 1.25 Multiples:** Audit check V8 identified 1,610 orders where header totals are exact 0.75x, 0.90x, 1.10x, or 1.25x multiples of line items. While these strongly suggest standard 25% promotions, 10% loyalty discounts, or 10%/25% fees, no promotional code table or fee policy documentation was provided to confirm this rule.
2. **Whether "Shipped" Counts as Paid Spend:** Shipped orders total 12,837 orders worth 40.92M units. If Kloud Kart operates on cash-on-delivery or post-delivery invoicing terms, shipped orders that have not settled payment may overstate realized customer spend.
3. **True Physical Stock Figures:** 144 products diverge from the movement log. While 60 are explained by duplicate restocks and 40 by unapplied recounts, **44 products remain completely unexplained**. No physical stocktake count exists to establish whether recorded balances or logged movements reflect physical warehouse reality.
4. **Dataset Scale and Monetary Currency Against the Brief:** The brief specifies roughly 4,000 orders per day and ~$14 million annual turnover. The dataset contains 159,384 orders (roughly 400 orders/day) totaling 487.06 million stored units over 13 months. Neither transaction volume nor monetary scale reconciles with the brief; numbers are reported in raw stored units.
5. **Origin and Business Meaning of Orphan Records:** 210 orders reference non-existent customers (999007+), 692 order items reference non-existent orders (900101+ to 999862), and 120 log entries reference non-existent products (99011+). These high ID ranges suggest test scripts or failed bulk imports, but their business origin could not be verified without access to source systems.
