#!/usr/bin/env bash
# QueryFlix: builds the full unified database from scratch.
# Run from the repository root:   bash database/import.sh
#
# Step 1-2  Netflix layer (unchanged original table + 15 queries)
# Step 3-7  Unified layer (normalised catalog, MovieLens, title mapping, views)
# Step 8    Validation report  -> database/validation_report.txt
#
# Asks for the MySQL password ONCE (or export MYSQL_PWD beforehand).
# Windows: run this from Git Bash, or use database\import.bat from Command Prompt.

set -euo pipefail

MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

if [ -z "${MYSQL_PWD+x}" ]; then
  read -r -s -p "MySQL password for ${MYSQL_USER} (empty if none): " MYSQL_PWD; echo
fi

# Password goes in a private temporary option file (works on every MySQL
# version and on Windows Git Bash; MYSQL_PWD is deprecated in newer clients).
# (relative path on purpose: Git Bash would rewrite a /tmp path for mysql.exe)
CNF="database/.mysql_import.cnf"
trap 'rm -f "$CNF"' EXIT
: > "$CNF"
chmod 600 "$CNF"
printf '[client]\npassword="%s"\n' "$MYSQL_PWD" > "$CNF"
unset MYSQL_PWD

# utf8mb4 on the client is essential: without it LOAD DATA mangles
# accented names (e.g. 'Roel Reiné' -> 'Roel Rein?').
MYSQL=(mysql --defaults-extra-file="$CNF" --local-infile=1 --default-character-set=utf8mb4
       -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER")

echo "==> [1/8] Enabling local_infile (needed by LOAD DATA LOCAL INFILE)..."
"${MYSQL[@]}" -e "SET GLOBAL local_infile = 1;"

echo "==> [2/8] Netflix schema + 32,000 rows..."
"${MYSQL[@]}" < database/schema.sql
"${MYSQL[@]}" queryflix < database/seed.sql

echo "==> [3/8] Unified schema (tables, FKs, helper functions)..."
"${MYSQL[@]}" queryflix < database/unified_schema.sql

echo "==> [4/8] Normalising Netflix into titles / people / genres / countries (~30s)..."
"${MYSQL[@]}" queryflix < database/build_catalog.sql

echo "==> [5/8] Loading MovieLens (movies, links, ratings, tags)..."
"${MYSQL[@]}" queryflix < database/load_movielens.sql

echo "==> [6/8] Building the title mapping layer..."
"${MYSQL[@]}" queryflix < database/build_mapping.sql

echo "==> [6b] Loading runtimes (bundled 2017 TMDB snapshot)..."
"${MYSQL[@]}" queryflix < database/load_runtime.sql
if [ -f database/enrichment/tmdb_runtime.csv ]; then
  echo "==> [6c] Loading runtimes fetched from the TMDB API (newer titles, TV)..."
  "${MYSQL[@]}" queryflix < database/load_runtime_api.sql
else
  echo "==> [6c] Optional: no database/enrichment/tmdb_runtime.csv (live TMDB fetch) - snapshot only."
fi

echo "==> [7/8] Creating analytical views..."
"${MYSQL[@]}" queryflix < database/views.sql

echo "==> [8/8] Validation report..."
"${MYSQL[@]}" -t queryflix < database/validation.sql | tee database/validation_report.txt

echo "==> Creating the app-specific queryflix user (matches backend/.env.example)..."
"${MYSQL[@]}" <<'SQL'
CREATE USER IF NOT EXISTS 'queryflix'@'localhost' IDENTIFIED BY 'change_me';
CREATE USER IF NOT EXISTS 'queryflix'@'127.0.0.1' IDENTIFIED BY 'change_me';
GRANT ALL PRIVILEGES ON queryflix.* TO 'queryflix'@'localhost';
GRANT ALL PRIVILEGES ON queryflix.* TO 'queryflix'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

echo "==> Done. Update backend/.env with the queryflix user's real password."
