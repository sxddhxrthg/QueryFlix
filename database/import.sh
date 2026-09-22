#!/usr/bin/env bash
# QueryFlix: creates the database, schema, and loads the real dataset.
# Run from the repository root: bash database/import.sh
#
# Assumes a local MySQL server is running and you can connect as root
# (or edit MYSQL_USER below to a user with CREATE DATABASE privileges).

set -euo pipefail

MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

echo "==> Creating schema..."
mysql --local-infile=1 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p < database/schema.sql

echo "==> Enabling local_infile on the server for this session (required by LOAD DATA LOCAL INFILE)..."
mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p -e "SET GLOBAL local_infile = 1;"

echo "==> Loading data (this can take ~10-20s for 32,000 rows)..."
mysql --local-infile=1 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p queryflix < database/seed.sql

echo "==> Creating the app-specific queryflix user (matches backend/.env.example)..."
mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p <<'SQL'
CREATE USER IF NOT EXISTS 'queryflix'@'localhost' IDENTIFIED BY 'change_me';
GRANT ALL PRIVILEGES ON queryflix.* TO 'queryflix'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "==> Done. Update backend/.env with the queryflix user's real password."
