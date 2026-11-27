# Kloud Kart — Data Integrity Diagnosis

**Prepared for:** Nana Adjei, Head of Operations
**Assessment:** DE03 SQL for Data Professionals
**Scope:** Integrity audit of the supplied Kloud Kart database and the business risks relevant to the Monday customer-spending report, stock accuracy, and customer records. The "How it was found" parts carry the technical detail; the "What it costs" parts are written for the business reader.

> **How to read the figures:** Unless stated otherwise, monetary figures are **currency units as stored in the dataset**. They are not labelled as cedis or dollars because the dataset's scale does not reconcile with the brief. The dataset holds 159,384 orders totalling about 487.06 million units over 13 months. That is about 3,056 units per order and roughly 400 orders a day on average (about 1,170 a day in the busiest month, August 2026), against the brief's "roughly 4,000 orders a day" and approximately $14 million annual turnover. Neither the volume nor the value reconciles. Nothing in this document depends on reconciling them, but the figures should be read as dataset measures, not verified financial-statement revenue.

## Executive assessment and ranking

The findings are ranked by the likely harm to decisions or operations, not by the number of rows flagged. Some checks found unusual data that is not, by itself, evidence of a fault. Those are separated at the end.

| Rank | Finding | Evidence from audit | Main business consequence |
|---:|---|---|---|
| 1 | Order statuses are inconsistent | 15 raw spellings; 7 remain after `lower(trim())`. A filter on the literal `completed` finds 22,091 of the 124,199 orders that count as spend (about 18%) | The Monday report can silently drop most completed and shipped orders, with no error, if it filters on one spelling |
| 2 | Stock records do not reconcile; duplicate restocks and negative stock exist | 144 products disagree with the inventory log; 84 after removing 60 duplicate restock rows. 22 products show 89 more units than the log explains, each with an unapplied recount. 14 products have negative stock | Stock shown as available may be higher than reality, which is the direction that causes overselling |
| 3 | Order values and line quantities need validation | 2,398 order totals differ from their lines; 6 lines have quantity 999 or 9,999, worth 3.07 million in line-derived value (1.06 million excluding cancelled orders) | A report built from line extensions can materially overstate sales; replacing header totals with line sums could erase legitimate discounts or fees |
| 4 | Customer records may represent duplicate identities | 533 email addresses are shared across 1,068 customer rows (537 pairs counted pairwise); all 537 pairs share a name and none share a phone number | Spending may be split across records, affecting customer totals and the top-100 ranking; an incorrect merge could combine different people |
| 5 | Orders fall outside the stated data window | 24 orders are dated after 31 August 2026, the end of the data window | If included in a report for the supplied period or a defined trailing 12 months, they may distort the reporting window |

### Why this order

*(Draft rationale — confirm or change it in your own words.)*

- **Rank 1** comes first because it changes the headline Monday figure for every customer, produces no error message, and the population affected is large: a literal `completed` filter sees about 18% of the orders that should count.
- **Rank 2** is second, even though stock is Nana's most visible complaint, because the dangerous part of it is bounded. The overselling direction (recorded stock above what the log explains) is 89 units across 22 products, plus 14 negative balances. The larger gap, 268 units across 62 products, runs the other way: the shop believes it has less than the log says, which risks under-selling rather than overselling. This is pending a physical count.
- **Rank 3** is large in value (3.07 million) but conditional: it only bites if the report is built from order lines.
- **Rank 4** could change the top-100 but has not yet been quantified.
- **Rank 5** is a reporting-boundary question, not a proven loss.

The ranking is provisional where the audit does not establish actual financial loss or physical stock.

---

## 1. Inconsistent order statuses

### 1. What is wrong

`orders.status` is free text. It holds 15 distinct raw values, which reduce to 7 after `lower(trim())`, describing 5 business states:

| State (after normalising) | Raw spellings merged | Orders | Value (units as stored) |
|---|---|---:|---:|
| Completed | `completed`, `complete` (with case and space variants) | 111,351 | 339.61M |
| Shipped | `shipped` | 12,848 | 40.96M |
| Pending | `pending` | 16,009 | 48.50M |
| Cancelled | `cancelled` (29.19M) and `canceled` (8.98M) | 12,697 | 38.16M |
| Refunded | `refunded` | 6,479 | 19.83M |
| **Total** | | **159,384** | **487.06M** |

A query matching only the literal `completed` returns **22,091 orders**. The orders that count as spend (completed plus shipped, see Decision 1) number **124,199**, so a literal filter misses **102,108** of them. Separately, a report that treats `complete` and `completed` as different states understates completed orders by 89,260.

### 2. How it was found

- Counted distinct raw status values, then distinct values after `lower(trim(status))`.
- Compared the literal `status = 'completed'` count with the normalised population.
- Summed `total_amount` per normalised state.

### 3. What it costs Nana if left uncorrected

The Monday report's "total spent" depends entirely on which statuses it counts, and nothing in the database enforces a vocabulary.

- **A literal filter** sees 22,091 orders worth 66.48M of the 124,199 orders worth 380.57M that should count, so spend per customer is understated for almost everyone.
- **Counting cancelled and refunded orders** would overstate spend by up to 58.00M (38.16M cancelled plus 19.83M refunded).
- **Pending orders** (48.50M) are excluded by assumption. If the business counts them, spend is understated by that amount.

This is a count of orders whose classification is sensitive to the spelling rule. It is not proof that every one is a valid sale.

### 4. Remediation and risk of getting it wrong

- Define a canonical status mapping and apply it consistently in the report. Map only verified synonyms (`complete` = `completed`); send unknown values to an exception list rather than guessing.
- Add a controlled status lookup or a database constraint after existing values are reviewed.
- Make the Monday report record the status definition and its "as at" date.

**Risk of remediation:** mapping an ambiguous status wrongly could include cancelled or refunded orders as spend, or exclude legitimate ones. Confirm the mapping against the business process before updating historical rows.

---

## 2. Stock reconciliation, duplicate restocks and negative balances

### 1. What is wrong

Product stock balances do not fully reconcile with the inventory movement log.

- **144 products** have a `stock_quantity` different from the sum of their logged movements.
- **60 duplicate restock rows** (identical product, quantity and second) account for part of this. Removing them reduces the mismatches to **84**.
- Of those 84, **22 products have recorded stock above what the log explains, by 89 units in total**, and **62 have it below, by 268 units in total**.
- **All 40 products carrying a "recount, not applied" note are among the 84.** That includes all 22 of the "above" group, where the unapplied recount points the same way as the gap (for example a logged recount of −6 and a gap of +6). In the other 62, 18 carry such a note and **44 remain unexplained by any note**.
- **14 products** have negative `stock_quantity`.

The 84 are not automatically proof that a balance is wrong. Some may reflect unrecorded opening stock, incomplete history or unapplied recounts. No independent physical count exists.

### 2. How it was found

- Compared each product's `stock_quantity` with the sum of its `change_qty` movements, before and after excluding the 60 duplicate restocks.
- Split the remaining differences by direction and summed the units.
- Cross-checked each against recount and correction notes.
- Counted products with `stock_quantity < 0`.

### 3. What it costs Nana if left uncorrected

The dangerous direction is **recorded stock higher than reality**, because the shop can then accept payment for stock it does not have. The audit bounds that exposure: **22 products and 89 units**, each with a recorded recount that was never applied, plus **14 products already below zero**. The 62 products in the other direction (268 units) are the safer error: they risk under-selling, not overselling.

What the data cannot show is which record is right. That needs a physical count. The 44 unexplained products are the least understood part. The brief confirms two overselling incidents last month; the data does not give their order values or refund costs, so no monetary figure is claimed. Exposure rises ahead of flash sales (about 400 orders in ten seconds on one product), where an unreliable balance is hit hard and fast.

### 4. Remediation and risk of getting it wrong

- Count the 22 products and the 14 negative balances first; then the 44 unexplained.
- Preserve the original log. Do not silently delete duplicate rows or overwrite balances.
- Make each approved correction a logged adjustment movement, applied in the same transaction as the balance change.
- Protect order placement with a row lock or an atomic conditional decrement, so the check, decrement, order and movement succeed or fail together.

**Risk of remediation:** deleting a legitimate restock, or applying a recount twice, creates a new error. Changing `stock_quantity` without a movement destroys the trail. A trigger alone does not stop two simultaneous buyers: each sees only its own transaction.

---

## 3. Order-value and line-quantity anomalies

### 1. What is wrong

- **2,398 orders** have a `total_amount` that differs from the sum of their lines.
- **1,610** of these are an exact 0.75, 0.90, 1.10 or 1.25 multiple of the line sum, a pattern consistent with discounts or fees. It is not proof of the rule.
- **Six order lines** have quantity 999 or 9,999, which look like keying errors. They contribute about **3.07 million** in line-derived value, or about **1.06 million** if cancelled orders are excluded.

The header may legitimately include discounts, tax or delivery, so a mismatch is a validation flag, not proof the header is wrong.

### 2. How it was found

- Compared `total_amount` with the sum of `quantity × unit_price` per order.
- Counted exact 0.75, 0.90, 1.10 and 1.25 multiples.
- Flagged quantities of 999 and 9,999 and summed their line-derived value, with and without cancelled orders.

### 3. What it costs Nana if left uncorrected

If the Monday report sums `quantity × unit_price`, the six lines could inflate sales by about 3.07 million (about 1.06 million excluding cancelled orders). That exposure is conditional on how the report is built. Using header amounts for one report and line sums for another would also give inconsistent customer totals. Because many differences look like deliberate adjustments, replacing headers with line sums could make the report less accurate.

### 4. Remediation and risk of getting it wrong

- Validate the six quantities against source orders and payment records; correct only where confirmed.
- Add a sensible quantity limit for new order lines.
- Create an exception report for header/line differences, grouped by status; investigate patterns rather than mass-updating.
- Document whether discounts, tax and delivery sit in the header, the lines or separate fields.

**Risk of remediation:** overwriting headers with line sums can erase valid discounts or fees; correcting the large quantities without source evidence can alter legitimate orders.

---

## 4. Potential duplicate customer identities

### 1. What is wrong

**533 email addresses** are each shared by more than one customer row, involving **1,068 rows**. Counted pairwise that is **537 pairs**, because two addresses appear on three rows. In all 537 pairs the names match; in none do the phone numbers.

This is evidence of possible duplicate identities, not proof. Shared household or business addresses, or data-entry practice, could explain some matches.

### 2. How it was found

- Grouped customers by `lower(trim(email))` and counted addresses on more than one row.
- Counted the rows involved and the resulting pairs.
- Compared names and phone numbers within each pair.

### 3. What it costs Nana if left uncorrected

If two records are one person, the Monday report splits that person's spend and order count across two IDs, so they may be missing from the top-100 or ranked too low. For example, two records of one customer showing 80,000 and 70,000 would appear as two smaller customers rather than one at 150,000 (an illustration, not a measured pair). The actual effect on the top-100 has not been quantified; it should be measured by comparing the ranking before and after only verified links.

### 4. Remediation and risk of getting it wrong

- Create a review queue for the 537 candidate pairs and verify identity with other evidence (delivery details, account history, customer confirmation).
- Merge only confirmed duplicates, keeping a mapping from old IDs to the surviving record.
- Where evidence is insufficient, keep the records separate and mark the match unresolved.
- Recalculate the top-100 after verified merges and record how many customers move.

**Risk of remediation:** merging two different people exposes one person's order history to another and corrupts communications. Leaving true duplicates splits spending. The right response is controlled identity resolution, not automatic deduplication.

---

## 5. Orders outside the stated data window

### 1. What is wrong

The data window ends on **31 August 2026**, but **24 orders** are dated after it. This may be a load error, test data or genuine later activity. The audit shows only that they are outside the window.

### 2. How it was found

Compared `orders.order_date` with 31 August 2026 and counted the later-dated orders.

### 3. What it costs Nana if left uncorrected

If the Monday report describes only the supplied period, including these orders changes totals and rankings. If it is a rolling trailing 12 months as at the run date, some may be legitimate. The risk is a reporting-boundary error, not a proven loss, and it depends on the "as at" date and the intended window.

### 4. Remediation and risk of getting it wrong

- Inspect the 24 orders, their statuses, values and load timestamps.
- Confirm whether the window is tied to the dataset cutoff or the run date.
- Use an explicit `as_at` date and a clearly defined trailing-12-month boundary.
- Exclude rows only if their provenance confirms they are outside the intended population.

**Risk of remediation:** excluding legitimate later orders understates spend; including invalid ones overstates it. A documented boundary is safer than deleting rows.

---

## Other integrity findings and checks not promoted to the top five

These stay in the audit record, but their counts alone do not justify ranking them above the five findings.

| Check | Result | Assessment and action |
|---|---:|---|
| Category tree contains a loop | 2 categories; 6 products | Categories 9001 (Seasonal Promotions) and 9002 (Promotions) are each other's parent, so no walk from a top-level category reaches them. The 6 products inside (1 out of stock, 2 low) disappear from a category rollup that starts at the roots. **A foreign key would not prevent this**; it only blocks a missing parent. It needs a loop check, and marketing must decide the true parent. |
| Category parent references a missing category (R5) | 1 category | Category 9003 (Clearance) points at a parent (8999) that does not exist. It has no children and no products today, so there is no current effect, but a rollup that starts only from top-level categories would skip it. A foreign key would prevent this case once the row is repaired. |
| Orders referencing missing customers (R1) | 210 orders; about 665,000 units | These cannot belong to a valid customer, so they cannot affect a per-customer ranking. About 0.14% of dataset order value. Missing IDs sit in a high range (999007+), which may indicate injected or test records; verify provenance. |
| Order items referencing missing orders (R2) | 692 lines; about 826,000 units | These cannot join to a valid order and do not affect per-customer totals built from valid orders. Missing order IDs are in the 900101+ range; check provenance. |
| Inventory movements referencing missing products (R3) | 120 rows | These cannot be tied to a current product. Missing product IDs are in the 99011+ range. Retain for audit until their origin is known. |
| Order items referencing missing products (R4) | 0 rows | No orphan product references were found. |
| Products with no category (R6) | 37 rows | A NULL category may be intentional. Review with the product team before treating it as a fault. |
| Customer names with leading/trailing spaces (T5) | 1,153 rows | A presentation and matching-quality issue. Trim for display and search; do not use it alone to merge customers. |
| Customer city spelling variants (T3/T4) | 15 raw; 12 after `lower(trim())` | Standardise only verified equivalents. |
| Inventory log dated after 31 August 2026 (V5) | 40 rows | Check provenance, as with the 24 later-dated orders. |
| Identical `sale` log rows in product, quantity and second (I4) | 459 rows | **Not a fault by itself.** Two genuine customers can buy the same item in the same second. Removing them as "duplicates" made the stock reconciliation worse, not better. |
| Repeated product names (I5) | 841 rows involved | **Not a fault without more evidence.** Different products can share a name. |
| Negative inventory movement quantities (V9) | 262,646 rows | **Not a fault.** Negative quantities are how outward movements are recorded. |
| Zero-quantity stock-take movements (V10) | 90 rows | **Not a fault by itself.** A count that matched can record no movement. |
| Recount notes marked "not applied" (V11) | 40 rows | Part of Finding 2, not an additional 40 faults; all 40 products are among the 84. |

### Orphan-record prioritisation

The three orphan families (missing customers, orders, products) appear in ID ranges outside the main data: 999007+, 900101+ and 99011+. This is consistent with test or injected records but is not proof. The 692 orphan order lines and 210 orphan orders do not join to a valid order or customer, so their impact on the per-customer Monday report is lower than the five findings above. They still need cleanup and foreign-key protection.

---

## How costs are stated in this document

Costs are stated only where the data supports them: counts, stored values, and units of stock. Where a loss cannot be bounded from the data, the document says so rather than inventing a figure. For example, the cost of the two overselling incidents cannot be calculated because order values and refunds are not in the dataset.

## Decisions and limitations Nana should know

1. **Customer spend definition:** "spent" counts orders whose normalised status is **completed, complete or shipped** (124,199 orders; 380.57M units as stored), and excludes pending, cancelled and refunded orders. The brief does not define "spent", so this is a working assumption requiring confirmation. In particular, confirm whether a shipped order is already paid.
2. **Transaction amount:** the report uses `orders.total_amount`, not line sums, because 2,398 headers differ from their lines and some differences may be discounts, tax or fees.
3. **Stock truth:** log reconciliation is not a physical stocktake. The 84 mismatches and 14 negative balances need verification before any adjustment.
4. **Customer identity:** a shared email plus a shared name is a candidate match, not proof. Phone numbers differ in every pair.
5. **Date boundary:** the 24 later-dated orders and 40 later-dated movements need provenance checks and an explicit reporting cutoff.
6. **Category tree:** a loop and a missing-parent category exist. The rollup shows the affected products in a separate row rather than dropping them; the true parents are a decision for marketing.
7. **Currency and scale:** the dataset does not reconcile with the brief's volume or turnover (see the note at the top), so figures are stated as stored.

## Recommended immediate order of work

1. Agree the spend definition and make the Monday report use it consistently.
2. Count the 22 products with unapplied recounts and the 14 negative balances; then the 44 unexplained.
3. Validate the six extreme quantities and investigate the 2,398 header/line differences without mass-overwriting totals.
4. Review the 537 candidate duplicate pairs and measure the effect of verified merges on the top-100.
5. Validate the 24 later-dated orders and 40 later-dated movements against an explicit cutoff.
6. Repair the category loop with marketing, then add protections: a status lookup, foreign keys for missing parents, and a loop check for the category tree. Keep the exception checks running so new faults are detected rather than silently accepted.

**Overall conclusion:** The highest risks are not the largest row counts. They are the errors that can change Nana's decisions or make the shop promise stock it cannot deliver: inconsistent order classification, stock that overstates what is on the shelf, order values that depend on an unconfirmed assumption, and customer identities split across records. Fixes should preserve the audit trail, rest on verified source evidence, and be measured against the Monday report and flash-sale conditions.
