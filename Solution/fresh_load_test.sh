#!/usr/bin/env bash
# fresh_load_test.sh - proves the solution runs top to bottom from a clean load.
# Run from the Lab/ folder:   bash Solution/fresh_load_test.sh
# Builds a SEPARATE database (kloudkart_fresh) so your working one is untouched.
set -euo pipefail
export MSYS_NO_PATHCONV=1          # stop Git Bash rewriting /lab paths
C=kloudkart                         # the container
DB=kloudkart_fresh

echo "1/5 dropping and recreating $DB"
docker exec $C psql -U postgres -c "DROP DATABASE IF EXISTS $DB;"
docker exec $C psql -U postgres -c "CREATE DATABASE $DB;"

echo "2/5 loading the supplied schema and data"
docker exec -w /lab/Resources -i $C psql -U postgres -d $DB -v ON_ERROR_STOP=1 -f schema.sql
docker exec -w /lab/Resources -i $C psql -U postgres -d $DB -v ON_ERROR_STOP=1 -f load.sql

echo "3/5 building the solution (run_all.sql)"
docker exec -w /lab/Solution -i $C psql -U postgres -d $DB -v ON_ERROR_STOP=1 -f run_all.sql

echo "4/5 integrity checks on the fresh build"
docker exec -w /lab/Solution -i $C psql -U postgres -d $DB -f 01_integrity_checks.sql

echo "5/5 race_test.py, unmodified"
DATABASE_URL="postgresql://postgres:kloudkart@localhost:5432/$DB" python Resources/race_test.py
echo "DONE: fresh load -> solution -> race test, no manual steps"
