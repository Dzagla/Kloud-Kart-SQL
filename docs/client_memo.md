# Memo to Nana

**From:** Solution Architect  
**Date:** 27 November 2026  
**Subject:** Operational Audit, Concurrency Controls, and Reporting Performance  

## What I found

An audit of the store records revealed four operational risks:

1. **Unreliable Order Classification:** Order statuses are entered as free text with fifteen variations. A strict filter for "completed" orders misses over 100,000 spend orders worth roughly 314 million units.
2. **Stock Discrepancies and Overselling:** 144 product stock figures disagree with movement records. 60 are explained by duplicate delivery entries and 40 by unapplied recount notes, leaving 44 unexplained. Fourteen products sit below zero due to past overselling.
3. **Mismatched Order Amounts:** 2,398 orders have header amounts that differ from item sums. Most reflect standard commercial discounts or fees, but six lines contain clerical quantity errors (999 or 9,999 units) that would inflate sales by three million units if calculated from lines.
4. **Candidate Duplicate Customer Accounts:** 533 email addresses are shared across 1,068 customer records with matching names but different telephone numbers. These are candidate duplicates that risk splitting customer spending across separate accounts.

## What I built

| What you asked for | Status | Evidence |
|---|---|---|
| **Stop overselling during flash sales** | Completed | Checkout locks the product row during purchase. Tested under 400 simultaneous buyers competing for 50 items: exactly 50 succeeded, 350 received clear "out of stock" notices, zero oversold, runtime 2.34 seconds. |
| **A fast Monday report for Adwoa** | Completed | Redesigned the 12-month report into a single consolidated pass. Runs across all 40,420 customers in 0.28 seconds (down from roughly 40 minutes). Top-100 spender ranking generates in 0.25 seconds. |
| **Category-level low-stock visibility** | Completed | Built a hierarchical inventory rollup that aggregates stock across categories at any depth in 3 milliseconds, safely isolating a circular category link without dropping items. |
| **An auditor trail of stock movements** | Completed | Every stock change made through the database is automatically logged with user accountability, and future negative balances are blocked. |
| **Actionable stock reorder prioritization** | Completed | Added a daily sales velocity ranking that estimates days of remaining stock cover, ranking urgent fast-sellers ahead of slow movers in 27 milliseconds. |

## What I recommend

1. **Conduct Physical Stocktakes on 58 Items:** Prioritize counting the 14 products with negative stock balances and the 44 unexplained discrepancy products.
2. **Review Candidate Duplicate Accounts:** Have customer service verify identity across the 533 candidate duplicate customer groups before merging any accounts.
3. **Confirm Payment Policies with Finance:** Agree whether orders marked as "shipped" represent settled revenue, and document commercial discount rules.

## What I could not stand behind

- **Silently resetting historical records:** I refused to overwrite the 14 negative stock balances to zero or delete duplicate restock rows, as doing so destroys audit history before a physical stocktake occurs.
- **Automatically merging customer accounts:** Merging candidate accounts without customer confirmation risks combining different people who share an email address.
- **Recalculating historical order totals from line items:** Replacing header amounts with line sums would introduce multi-million clerical errors and erase valid customer discounts.
