# QueryFlix

Netflix Movies and TV Shows analytics platform built with Advanced SQL. An ASQL
(Advanced SQL and Modern Database Features, 21CSE742P) academic project at SRM
Institute of Science and Technology.

**Team:** Simran Sharma \u00b7 Rishav Tandon \u00b7 Siddharth Ganesh \u00b7 Alishri Poddar
**Supervisor:** Dr. R. Sathya, Department of Computing Technologies

---

## 1. Problem Statement

Netflix-style catalog data holds several important attributes \u2014 `genres`,
`country`, `cast_members` \u2014 as multi-valued, comma-separated strings inside a
single column. Basic SQL (`SELECT`, plain `GROUP BY`) interprets these
incorrectly: `GROUP BY country` treats `"United Kingdom, United States of
America"` as one unrelated category, instead of counting that title under
*both* the UK and the US. Decomposing these fields correctly, and answering
real analytical questions on top of them, is a legitimate Advanced SQL problem
that a relational database should be able to solve natively.

## 2. Proposed Solution

QueryFlix loads a real, TMDB-enriched Netflix dataset (32,000 titles \u2014
16,000 movies + 16,000 TV shows) into a single relational database and
answers 15 business questions using native SQL features: window functions,
multi-valued field decomposition, date operations, dynamic text
categorization, and aggregation \u2014 exposed through a REST API and a web
dashboard so results are always generated live, never hard-coded.

## 3. Technology Stack

| Layer | Technology |
|---|---|
| Database | MySQL 8.0+ (see note below on 9.x) |
| Backend | Node.js, Express, TypeScript, mysql2 |
| Frontend | React, TypeScript, Vite, React Router, Recharts |

> **Note on MySQL version:** the project was built and tested against
> **MySQL 8.0.46** (the version available via standard Ubuntu apt
> repositories in the build/test environment). Everything uses MySQL
> 8.0+/9.x-compatible syntax \u2014 window functions, `JSON_TABLE`, `EXTRACT`,
> `INTERVAL` are all supported unchanged from 8.0 onward \u2014 so it will run
> as-is on MySQL 9.x once you install that via Homebrew.

## 4. Architecture

```
React frontend (Vite, port 5173)
        \u2193  REST (fetch)
Node/Express backend (port 4000)
        \u2193  mysql2 connection pool
MySQL database "queryflix"
        \u2193
netflix table (32,000 rows)
```

The frontend never talks to MySQL directly \u2014 every data access goes through
the backend's REST API, using parameterized queries.

## 5. Database Schema

A single unified `netflix` table (rather than separate `movies`/`tv_shows`
tables) was used deliberately: most of the 15 business questions compare or
combine across content types, which a single table answers directly without
constant `JOIN`s or `UNION`s. This keeps the schema easy to explain in a viva.

```sql
CREATE TABLE netflix (
    show_id         INT AUTO_INCREMENT PRIMARY KEY,   -- surrogate key, see below
    source_id       INT,                              -- original dataset id
    type            VARCHAR(10)  NOT NULL,             -- 'Movie' | 'TV Show'
    title           VARCHAR(300) NOT NULL,
    director        TEXT,
    cast_members    TEXT,                              -- multi-valued, comma-separated
    country         TEXT,                              -- multi-valued, comma-separated
    date_added      DATE,
    release_year    INT,
    content_rating  DECIMAL(4,2),                       -- TMDB-style 0-10 score
    duration_raw    VARCHAR(30),                        -- unusable, see limitations
    genres          TEXT,                               -- multi-valued, comma-separated
    language        VARCHAR(10),
    description     TEXT,
    popularity      DECIMAL(10,3),
    vote_count      INT,
    vote_average    DECIMAL(4,2),
    budget          BIGINT,                             -- movies only
    revenue         BIGINT                              -- movies only
);
```

Full DDL: [`database/schema.sql`](database/schema.sql).

## 6. Dataset

Real Kaggle/TMDB-enriched CSVs: `netflix_movies_detailed_up_to_2025.csv` and
`netflix_tv_shows_detailed_up_to_2025.csv`, 16,000 rows each (32,000 total).
The cleaned, merged, import-ready file lives at
[`database/data/netflix_unified.csv`](database/data/netflix_unified.csv).

## 7. The 15 Business Questions

| # | Question | Technique |
|---|---|---|
| 1 | Content-type distribution (Movies vs TV Shows) | Aggregation + window function |
| 2 | Top 10 genres by frequency | `JSON_TABLE` (multi-valued field decomposition) |
| 3 | Top 10 producing countries | `JSON_TABLE` |
| 4 | Top 10 most-credited cast members | `JSON_TABLE` + NULL/encoding handling |
| 5 | Yearly trend of titles added | `EXTRACT(YEAR FROM ...)` |
| 6 | Titles added in the last 5 years | `DATE_SUB(..., INTERVAL ...)` |
| 7 | Top 10 highest-rated titles (vote_count \u2265 500) | Filtering + `ORDER BY` |
| 8 | Highest-rated title per content type | `RANK() OVER (PARTITION BY ...)` |
| 9 | Content originating from India | `LIKE` pattern matching |
| 10 | Ratings & popularity: Movies vs TV Shows | Aggregation |
| 11 | Co-productions vs single-country titles | Comma-count string manipulation |
| 12 | Dynamic content categorization from descriptions | `CASE` + `LIKE` |
| 13 | Movie profitability (budget vs revenue) | Aggregation + derived columns |
| 14 | Top 10 most prolific directors | Aggregation + NULL handling |
| 15 | Most popular title per year (last 10 years) | `RANK() OVER (PARTITION BY release_year ...)` |

Full SQL with comments: [`database/queries.sql`](database/queries.sql). The
same queries are also defined in
[`backend/src/queries/registry.ts`](backend/src/queries/registry.ts) so the
frontend can display and execute them dynamically.

## 8. Advanced SQL Techniques Used

- **Window functions** \u2014 `RANK() OVER (PARTITION BY ...)` for per-group ranking (Q8, Q15)
- **Multi-valued field decomposition** \u2014 `JSON_TABLE()`, MySQL's equivalent of PostgreSQL's `STRING_TO_ARRAY()`/`UNNEST()` (Q2, Q3, Q4)
- **Date operations** \u2014 `EXTRACT()`, `DATE_SUB(..., INTERVAL ...)` (Q5, Q6)
- **Dynamic categorization** \u2014 `CASE` + `LIKE` wildcard pattern matching (Q12)
- **Derived calculations** \u2014 computed profit/ratio columns, `NULLIF` guards (Q13)
- **Aggregation** \u2014 `COUNT`, `AVG`, `GROUP BY` throughout
- **NULL handling** \u2014 explicit exclusion where NULLs would corrupt a ranking (Q4, Q14)

## 9. Setup Instructions (macOS)

### 9.1 Check what you already have

```bash
# Is MySQL already installed via Homebrew?
brew list | grep mysql

# Is a MySQL server already running?
mysql --version
brew services list | grep mysql
```

If nothing is installed:

```bash
brew install mysql
brew services start mysql
```

If MySQL is already installed but not running:

```bash
brew services start mysql
```

### 9.2 Set up the database

From the repository root:

```bash
bash database/import.sh
```

This creates the `queryflix` database, the schema, loads all 32,000 rows,
and creates a `queryflix` MySQL user. **Update the password** it creates
(`change_me` by default \u2014 edit `database/import.sh` or run an `ALTER USER`
afterward) and put the real one in `backend/.env`.

### 9.3 Inspect the database yourself

```bash
mysql -u root -p
```
```sql
SHOW DATABASES;
USE queryflix;
SHOW TABLES;
DESCRIBE netflix;
SELECT COUNT(*) FROM netflix;
SELECT * FROM netflix LIMIT 20;
```

A GUI (MySQL Workbench, TablePlus, Sequel Ace) works too \u2014 the app doesn't
depend on one, but any of them can connect to the same local MySQL instance.

### 9.4 Backend

```bash
cd backend
cp .env.example .env   # edit DB_PASSWORD to match what you set in 9.2
npm install
npm run dev
```

Verify: `curl http://localhost:4000/api/health` should report
`"mysqlConnected": true`.

### 9.5 Frontend

```bash
cd frontend
cp .env.example .env   # defaults to http://localhost:4000/api, fine as-is
npm install
npm run dev
```

Open **http://localhost:5173**.

## 10. API Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | API + MySQL connectivity check |
| GET | `/api/stats` | Dashboard summary cards |
| GET | `/api/titles` | Search/filter titles (query params: search, type, country, genre, director, cast, year, page, limit) |
| GET | `/api/titles/:id` | Full detail for one title |
| GET | `/api/genres` | All genres with counts |
| GET | `/api/countries` | Top 30 countries with counts |
| GET | `/api/cast` | Top 30 credited cast members |
| GET | `/api/yearly-trends` | Titles added per year |
| GET | `/api/queries` | List all 15 business questions (metadata only) |
| GET | `/api/queries/:id` | One question's metadata + SQL |
| GET | `/api/queries/:id/results` | Execute one question live and return results |
| GET | `/api/database/tables` | List tables + row counts |
| GET | `/api/database/tables/:table/schema` | Column definitions for a table |
| GET | `/api/database/tables/:table` | Sample rows from a table |

Only `SELECT` queries from a fixed registry can be executed \u2014 there is no
arbitrary SQL execution endpoint, and the `:table` parameter on the database
inspection routes is checked against an explicit allowlist (`netflix`) before
being interpolated into any SQL.

## 11. Data-Quality Findings (please read before your viva)

These were discovered by actually inspecting the real dataset, not assumed
in advance \u2014 documenting them honestly is part of the project, not a defect
to hide.

1. **`show_id` collisions.** The original dataset's `show_id` repeats across
   the movies and TV shows source files (397 overlapping values) and even
   9 times within the TV shows file alone. Fixed with a surrogate
   `AUTO_INCREMENT show_id`, preserving the original value as `source_id`.
2. **`duration` is unusable.** Empty for all 16,000 movies, and a constant
   `"1 Seasons"` for all 16,000 TV shows. Dropped from analysis; `vote_count`
   and `popularity` are used as the meaningful engagement metrics instead.
3. **No classic categorical rating.** This dataset has no PG-13/TV-MA style
   field \u2014 only a numeric 0\u201310 TMDB-style score. The "common ratings"
   business question was reframed around this numeric score instead.
4. **`budget`/`revenue` are movie-only.** Profitability analysis (Q13) is
   scoped to `type = 'Movie'` with `NULLIF` guarding the ratio calculation
   against division by zero.
5. **Mis-encoded cast-member names.** ~1,139 titles have invalid-UTF-8 byte
   sequences in non-English cast names (Turkish/Czech/Baltic accented
   characters). MySQL's `JSON_TABLE` validates UTF-8 strictly and returns
   `NULL` for those entries where PostgreSQL's `UNNEST` did not surface the
   issue \u2014 a genuine MySQL vs PostgreSQL behavioral difference, handled by
   explicitly excluding the resulting NULLs (see the comment in Q4 of
   `database/queries.sql`).

## 12. Known Limitations

- The keyword-based content categorization (Q12) is a heuristic, not a
  validated NLP classifier \u2014 it flags likely themes from description text,
  nothing more.
- Yearly addition counts (Q5) are dataset-derived (exactly 2,000 titles per
  year for 16 years) and should not be read as organic historical Netflix
  catalog growth \u2014 the dataset was evidently constructed with an even
  per-year distribution.
- This is a Netflix/TMDB-enriched public dataset, not Netflix's actual
  internal catalog data.
- The frontend prioritizes desktop layout (this is an academic
  presentation/demo project); it is responsive down to tablet width but not
  deeply optimized for small mobile screens.

## 13. Legacy: PostgreSQL Implementation

An earlier version of this project (for the PBL-II / First Review milestone)
used PostgreSQL. That implementation is preserved, unmodified, for reference
and traceability \u2014 not part of the active application:

- Schema: legacy PostgreSQL `01_schema.sql`
- Queries: legacy PostgreSQL `02_queries.sql`
- Review pack PDF with live-executed results at that stage

All 15 query results were cross-validated between the PostgreSQL and MySQL
implementations before the MySQL version was finalized (see \u00a711 item 5 for
the one legitimate discrepancy found and resolved during that comparison).

## 14. Academic Project Information

- **Course:** 21CSE742P \u2014 Advanced SQL and Modern Database Features
- **Institution:** SRM Institute of Science and Technology, Kattankulathur
- **Department:** Computing Technologies
- **Semester:** VII, July\u2013November 2026
