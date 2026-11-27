#!/usr/bin/env bash
# measure.sh - times each Kloud Kart query N times and prints first / median / p95 / worst (ms).
# Usage (Git Bash, from Lab/):   bash Solution/measure.sh 20
# Override the connection with PSQL="..." if your container name differs.
export MSYS_NO_PATHCONV=1
N="${1:-20}"
PSQL="${PSQL:-docker exec -i kloudkart psql -U postgres -d kloudkart -X -q}"

echo "== Environment =="
$PSQL -Atc "select version()"
$PSQL -Atc "select 'shared_buffers='||current_setting('shared_buffers')||'  work_mem='||current_setting('work_mem')||'  max_parallel_workers_per_gather='||current_setting('max_parallel_workers_per_gather')"
echo "runs per scenario: $N  (run 1 = 'first', may be cold; the rest are warm)"
echo

measure () {   # $1 = label, $2 = SQL
  local label="$1" sql="$2" i
  { printf '%s\n' '\timing on' '\o /dev/null'
    for ((i=1;i<=N;i++)); do printf '%s\n' "$sql"; done; } | $PSQL 2>&1 | tr -d '\r' | awk '/^Time:/{print $2}' > /tmp/mk_times.$$
  local got; got=$(wc -l < /tmp/mk_times.$$)
  if [ "$got" -lt "$N" ]; then echo "$label: only $got timings captured - check the query"; return; fi
  local first; first=$(head -1 /tmp/mk_times.$$)
  sort -n /tmp/mk_times.$$ | awk -v l="$label" -v f="$first" '
    {a[NR]=$1} END{
      m=(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2
      p=a[int(0.95*NR+0.999999)]
      printf "%-34s first %9.1f   median %9.1f   p95 %9.1f   worst %9.1f  ms\n", l, f, m, p, a[NR]}'
  rm -f /tmp/mk_times.$$
}

measure "monday_report (all customers)"   "SELECT * FROM monday_report('2026-09-01');"
measure "top 100 customers"               "SELECT * FROM monday_report('2026-09-01') WHERE spend_rank <= 100 ORDER BY spend_rank;"
measure "running total, one customer"     "SELECT * FROM v_customer_running_total WHERE customer_id = (SELECT customer_id FROM orders GROUP BY customer_id ORDER BY count(*) DESC LIMIT 1);"
measure "low_stock_rollup()"              "SELECT * FROM low_stock_rollup();"
measure "reorder_list()"                  "SELECT * FROM reorder_list('2026-09-01');"
