# Improvement beyond the brief: Reorder Priority List by Sales Velocity

## The problem it solves

The brief asked for a query to flag products with low stock, using a threshold of 5 units or fewer. 

When I ran that on Kloud Kart's data, it returned **1,685 products**—almost 42% of the entire catalogue. Because every single one of those products had sales in the last month, a purchasing manager cannot simply buy more of everything at once. 

A flat threshold treats all low-stock items as equally urgent:
- A product with 3 units in stock that sells 1 unit a month has three months of stock left.
- A product with 3 units in stock that sells 3 units a day will run out tomorrow morning.

Flagging both as "low stock" without context means the warehouse either runs out of fast movers or ties up working capital reordering slow movers.

## What I built

I wrote `reorder_list(p_anchor, p_window_days, p_cover_days)` in `09_reorder_list.sql`. 

It takes three steps:
1. **Measures sales velocity:** Calculates average daily sales for each product over the last 28 days from `sale` entries in `inventory_log`.
2. **Calculates days of cover:** Divides current stock by daily sales velocity to estimate how many days remain before the product stocks out. Out-of-stock and negative stock items are treated as 0 days of cover, sorting them straight to the top.
3. **Filters and ranks:** Keeps only products with fewer than 14 days of cover (an assumed two-week supplier lead time—a working guess rather than verified business data), ordered from fewest days of cover to most.

### How I tested it

- **Performance testing:** I timed the query across 20 runs using `measure.sh`. It executed in a median time of **27.1 ms** (p95 of 29.6 ms), making it fast enough to run live whenever purchasing staff need it.
- **Data cross-check:** I verified that the sales log reflects reality by checking total logged sale units (412,645) against total units on completed and shipped orders (415,712). They match within 0.7%, confirming that the inventory log is an accurate source for sales speed.

### Why this is a ranking, not a forecast

This query is an operational ranking, not an econometric forecast:
- It assumes the next two weeks will look like the last four weeks.
- It does not predict seasonal spikes, supplier delays, or upcoming flash sales.
- Products with zero sales in the last 28 days are excluded because an item that isn't selling is not in danger of running out.
- It relies on `products.stock_quantity`, which the diagnosis showed is still unverified for 144 products until a physical count occurs.

## What it is worth to Nana

Instead of handing procurement an impossible list of 1,685 items, this gives them a short, prioritized action queue ordered by runout risk. High-velocity items get reordered before they stock out, protecting sales, while slow movers are left alone.

## What it cost

- **No schema changes:** It queries existing tables and views without modifying tables or adding indexes.
- **Fast execution:** Runs in ~27 ms on the local test copy on my laptop.
- **Zero checkout impact:** It is a read-only query that takes no row locks and does not slow down order placement.
