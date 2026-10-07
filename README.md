<div align="center">

# 🎬 QueryFlix

### Netflix Catalog + MovieLens Behaviour — Unified in MySQL

**Advanced SQL • MySQL • React • TypeScript • Node.js**

<br>

[![MySQL](https://img.shields.io/badge/MySQL-8.x-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://www.mysql.com/)
[![React](https://img.shields.io/badge/React-TypeScript-61DAFB?style=for-the-badge&logo=react&logoColor=black)](https://react.dev/)
[![Node.js](https://img.shields.io/badge/Node.js-Express-339933?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org/)
[![Vite](https://img.shields.io/badge/Vite-8.x-646CFF?style=for-the-badge&logo=vite&logoColor=white)](https://vite.dev/)

<br>

[![Titles](https://img.shields.io/badge/Netflix%20titles-32%2C000-red?style=flat-square)](#6-dataset)
[![Ratings](https://img.shields.io/badge/MovieLens%20ratings-100%2C836-blue?style=flat-square)](#151-datasets)
[![Queries](https://img.shields.io/badge/Business%20Questions-36-purple?style=flat-square)](#154-layer-2-questions-q16q36)
[![Validation](https://img.shields.io/badge/Validation-0%20FAIL-success?style=flat-square)](#152-build-order-all-sql-run-by-importsh)

<br>

> **QueryFlix unifies a 32,000-title Netflix catalog with 100,836 MovieLens user ratings in one MySQL database, answers 36 business questions with advanced SQL (window functions incl. RANK / DENSE_RANK, JSON_TABLE, CTEs, views), and turns each user's history into transparent genre- and duration-aware recommendations.**

<br>

**Windows users:** see [`RUN_ON_WINDOWS.md`](RUN_ON_WINDOWS.md)

</div>

---


Netflix Movies and TV Shows analytics platform built with Advanced SQL. An ASQL
(Advanced SQL and Modern Database Features, 21CSE742P) academic project at SRM
Institute of Science and Technology.

**Team:** Simran Sharma · Rishav Tandon · Siddharth Ganesh · Alishri Poddar
**Supervisor:** Dr. R. Sathya, Department of Computing Technologies

---

## 1. Problem Statement

Netflix-style catalog data holds several important attributes — `genres`,
`country`, `cast_members` — as multi-valued, comma-separated strings inside a
single column. Basic SQL (`SELECT`, plain `GROUP BY`) interprets these
incorrectly: `GROUP BY country` treats `"United Kingdom, United States of
America"` as one unrelated category, instead of counting that title under
*both* the UK and the US. Decomposing these fields correctly, and answering
real analytical questions on top of them, is a legitimate Advanced SQL problem
that a relational database should be able to solve natively.

## 2. Proposed Solution

QueryFlix loads a real, TMDB-enriched Netflix dataset (32,000 titles —
16,000 movies + 16,000 TV shows) into a single relational database and
answers 15 business questions using native SQL features: window functions,
multi-valued field decomposition, date operations, dynamic text
categorization, and aggregation — exposed through a REST API and a web
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
> 8.0+/9.x-compatible syntax — window functions, `JSON_TABLE`, `EXTRACT`,
> `INTERVAL` are all supported unchanged from 8.0 onward — so it will run
> as-is on MySQL 9.x once you install that via Homebrew.

## 4. Architecture

```
React frontend (Vite, port 5173)
        ↓  REST (fetch)
Node/Express backend (port 4000)
        ↓  mysql2 connection pool
MySQL database "queryflix"
        ↓
Netflix (catalog: WHAT content exists)      MovieLens (behaviour: WHAT users like)
  netflix (32,000 rows, untouched)            movielens_movies · users · ratings · tags
        ↓ normalise                                 │
  titles · people · title_credits                   │
  genres · title_genres                             │
  countries · title_countries                       │
        └──────────── title_source_mapping ─────────┘   (+ genre_crosswalk)
                              ↓
          views: v_title_unified · v_movielens_movie_stats · v_user_genre_profile
                              ↓
          Q1–Q15 catalog analytics · Q16–Q36 behaviour, ranking, duration + personalisation
```

See **§15 Unified Netflix + MovieLens layer** for the full design.

The frontend never talks to MySQL directly — every data access goes through
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
| 7 | Top 10 highest-rated titles (vote_count ≥ 500) | Filtering + `ORDER BY` |
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

- **Window functions** — `RANK() OVER (PARTITION BY ...)` for per-group ranking (Q8, Q15); `DENSE_RANK()` in Q17, Q23, Q24, Q33, Q34, Q35, Q36 (see §15.8)
- **Multi-valued field decomposition** — `JSON_TABLE()`, MySQL's equivalent of PostgreSQL's `STRING_TO_ARRAY()`/`UNNEST()` (Q2, Q3, Q4)
- **Date operations** — `EXTRACT()`, `DATE_SUB(..., INTERVAL ...)` (Q5, Q6)
- **Dynamic categorization** — `CASE` + `LIKE` wildcard pattern matching (Q12)
- **Derived calculations** — computed profit/ratio columns, `NULLIF` guards (Q13)
- **Aggregation** — `COUNT`, `AVG`, `GROUP BY` throughout
- **NULL handling** — explicit exclusion where NULLs would corrupt a ranking (Q4, Q14)

## 9. Setup Instructions (macOS)

> **Windows?** Follow [`RUN_ON_WINDOWS.md`](RUN_ON_WINDOWS.md) — it uses `database\import.bat` in Command Prompt.

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

This asks for your MySQL password once, then builds everything (~35 s):
the Netflix table (32,000 rows), the normalised catalog, MovieLens
(610 users · 9,742 movies · 100,836 ratings · 3,683 tags), the title
mapping, the views, and writes `database/validation_report.txt`. It also
creates a `queryflix` MySQL user. **Update the password** it creates
(`change_me` by default — edit `database/import.sh` or run an `ALTER USER`
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

A GUI (MySQL Workbench, TablePlus, Sequel Ace) works too — the app doesn't
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
| GET | `/api/queries` | List all 36 business questions (metadata only) |
| GET | `/api/queries/:id` | One question's metadata + SQL |
| GET | `/api/queries/:id/results` | Execute one question live and return results |
| GET | `/api/database/tables` | List tables + row counts |
| GET | `/api/database/tables/:table/schema` | Column definitions for a table |
| GET | `/api/database/tables/:table` | Sample rows from a table |
| GET | `/api/queries/:id/results?userId=567` | Q23/Q24/Q29/Q30/Q33/Q36 run for the given MovieLens user |
| GET | `/api/personalization/mapping` | Mapping totals, per-status counts, example matches |
| GET | `/api/personalization/users` | Users with the richest history (for demos) |
| GET | `/api/personalization/:userId` | Genre profile (Q23) + duration profile (Q33) + top-10 recommendations (Q30) + duration-aware picks (Q36) |

Only `SELECT` queries from a fixed registry can be executed — there is no
arbitrary SQL execution endpoint, and the `:table` parameter on the database
inspection routes is checked against an explicit allowlist (all project tables and views) before
being interpolated into any SQL.

## 11. Data-Quality Findings (please read before your viva)

These were discovered by actually inspecting the real dataset, not assumed
in advance — documenting them honestly is part of the project, not a defect
to hide.

1. **`show_id` collisions.** The original dataset's `show_id` repeats across
   the movies and TV shows source files (397 overlapping values) and even
   9 times within the TV shows file alone. Fixed with a surrogate
   `AUTO_INCREMENT show_id`, preserving the original value as `source_id`.
2. **`duration` is unusable.** Empty for all 16,000 movies, and a constant
   `"1 Seasons"` for all 16,000 TV shows. Dropped from analysis; `vote_count`
   and `popularity` are used as the meaningful engagement metrics instead.
3. **No classic categorical rating.** This dataset has no PG-13/TV-MA style
   field — only a numeric 0–10 TMDB-style score. The "common ratings"
   business question was reframed around this numeric score instead.
4. **`budget`/`revenue` are movie-only.** Profitability analysis (Q13) is
   scoped to `type = 'Movie'` with `NULLIF` guarding the ratio calculation
   against division by zero.
5. **"Mis-encoded" cast-member names were a load bug, not a data problem.**
   The CSV is valid UTF-8. Earlier loads ran `LOAD DATA` without a
   character set, so on clients defaulting to `latin1` accented names
   (Turkish/Czech/Portuguese) were double-encoded and `JSON_TABLE` then
   returned NULL for them. Fixed by adding `CHARACTER SET utf8mb4` to
   `seed.sql` and `--default-character-set=utf8mb4` in `import.sh`;
   names like *Roel Reiné* and titles like *GH dúo* now load correctly and
   Q4 no longer produces a NULL row.

## 12. Known Limitations

- The keyword-based content categorization (Q12) is a heuristic, not a
  validated NLP classifier — it flags likely themes from description text,
  nothing more.
- Yearly addition counts (Q5) are dataset-derived (exactly 2,000 titles per
  year for 16 years) and should not be read as organic historical Netflix
  catalog growth — the dataset was evidently constructed with an even
  per-year distribution.
- This is a Netflix/TMDB-enriched public dataset, not Netflix's actual
  internal catalog data.
- The frontend prioritizes desktop layout (this is an academic
  presentation/demo project); it is responsive down to tablet width but not
  deeply optimized for small mobile screens.

## 13. Legacy: PostgreSQL Implementation

An earlier version of this project (for the PBL-II / First Review milestone)
used PostgreSQL. That implementation is preserved, unmodified, for reference
and traceability — not part of the active application:

- Schema: legacy PostgreSQL `01_schema.sql`
- Queries: legacy PostgreSQL `02_queries.sql`
- Review pack PDF with live-executed results at that stage

All 15 query results were cross-validated between the PostgreSQL and MySQL
implementations before the MySQL version was finalized (see §11 item 5 for
the one legitimate discrepancy found and resolved during that comparison).

## 14. Academic Project Information

- **Course:** 21CSE742P — Advanced SQL and Modern Database Features
- **Institution:** SRM Institute of Science and Technology, Kattankulathur
- **Department:** Computing Technologies
- **Semester:** VII, July–November 2026

---

## 15. Unified Netflix + MovieLens layer

**Story.** Netflix tells us *what content exists*. MovieLens tells us *what
users rate and prefer*. The mapping layer answers *which Netflix title is the
movie a user rated*. Advanced SQL then finds patterns, and the
personalisation layer suggests *what a user might prefer next*.

> MovieLens ratings are MovieLens users' ratings. They are **not** Netflix
> user ratings. They are external preference data attached to the Netflix
> catalog only where a validated title match exists.

### 15.1 Datasets (exactly two)

| Dataset | Role | Size |
|---|---|---|
| Netflix Movies & TV Shows till 2025 (Kaggle) | Catalog | 32,000 titles (16k movies + 16k TV), release years 2010–2025 |
| MovieLens `ml-latest-small` (GroupLens) | User behaviour | 610 users, 9,742 movies, 100,836 ratings, 3,683 tags, 1996–2018 |

MovieLens files live in `database/movielens/` (with GroupLens' README and
licence terms). No TMDB API or third dataset is used.

### 15.2 Build order (all SQL, run by `import.sh`)

| File | What it does |
|---|---|
| `schema.sql`, `seed.sql` | Original `netflix` table (never modified afterwards) |
| `unified_schema.sql` | 15 tables with PK/FK/CHECK constraints + 2 deterministic helper functions |
| `build_catalog.sql` | `netflix` → `titles`, `people`, `title_credits`, `genres`, `title_genres`, `countries`, `title_countries` via `JSON_TABLE … FOR ORDINALITY` |
| `load_movielens.sql` | `LOAD DATA` of the four MovieLens CSVs; parses `"Postman, The (Postino, Il) (1994)"` into title *The Postman*, a.k.a. *Il Postino*, year 1994 |
| `build_mapping.sql` | Rule cascade that fills `title_source_mapping` |
| `views.sql` | `v_movielens_movie_stats`, `v_title_unified`, `v_user_genre_profile` |
| `load_runtime.sql` | Loads `database/enrichment/tmdb_runtime.csv` into `tmdb_runtime` (skipped if the CSV isn't there yet) |
| `queries_movielens.sql` | Q16–Q36 |
| `validation.sql` | 39 checks + matcher precision/recall |

### 15.3 Title mapping rules

`fn_normalize_title()` lower-cases, turns `&` into `and`, drops apostrophes,
collapses all punctuation to single spaces; comparison uses the
accent-insensitive collation `utf8mb4_0900_ai_ci` (so *Amélie* = *Amelie*).
Only Netflix **movies** are candidates (MovieLens has no TV, and TV
`source_id`s are a different TMDB id space).

| Status | Rule | Confidence | Count |
|---|---|---|---|
| EXACT | identical cleaned title + same year | 1.00 | 1,527 |
| NORMALIZED | normalised title (or a.k.a. title) + same year | 0.95 | 41 |
| YEAR_MATCH | normalised title, year ±1 | 0.80 | 97 |
| LINK_ID | no title match, but MovieLens `links.csv` tmdbId = Netflix `source_id` | 0.90 | 65 |
| AMBIGUOUS | several candidates, no tie-break | 0 | 0 |
| UNMATCHED | kept, with a reason (7,516 were released before 2010) | 0 | 8,012 |

Same-name collisions are not blindly accepted: when several Netflix titles
share a name and year the tmdbId breaks the tie, and when MovieLens'
own `links.csv` says a title match is a *different* film (e.g. *Sherlock
Holmes (2009)* vs a 2010 film of the same name) the match is re-pointed or
rejected. Measured against `links.csv`, the title rules alone reach
**99.52 % precision and 96.24 % recall**; the final mapping covers all 1,730
linkable movies (88.7 % of MovieLens movies released 2010+).

### 15.4 Layer-2 questions (Q16–Q36)

| # | Question | Technique |
|---|---|---|
| 16 | Most highly rated movies | Bayesian (damped) mean in a view |
| 17 | Most-rated movies | `DENSE_RANK()` |
| 18 | Average rating by genre | Bridge table + `RANK()` |
| 19 | Rating distribution | Running total `SUM(COUNT(*)) OVER (ORDER BY …)` |
| 20 | Ratings per movie (long tail) | `CASE` buckets + window % |
| 21 | User activity segments | `NTILE(4)`, `DATEDIFF` on timestamps |
| 22 | Popular genres among users | CTE + `HAVING` |
| 23 | User preference profile | View with window functions + crosswalk + `DENSE_RANK()` |
| 24 | Top 3 unseen films in each of the user's top genres | `DENSE_RANK() OVER (PARTITION BY genre)` + `NOT EXISTS` |
| 25 | Netflix titles with strong MovieLens activity | Mapping-layer view |
| 26 | Popular on Netflix **and** active on MovieLens | `PERCENT_RANK()` |
| 27 | Netflix vote vs MovieLens rating (r = 0.73) | Pearson correlation in SQL |
| 28 | Biggest disagreements | Derived columns |
| 29 | Personalised candidate pool | Anti-join |
| 30 | Hybrid recommendation score | Multi-CTE scoring |
| 31 | Movie length by genre | Enrichment join + `RANK()` |
| 32 | Does length affect ratings? (both audiences) | Two CTEs joined on a generated column |
| 33 | User duration preference | View with window functions + `DENSE_RANK()` |
| 34 | ROW_NUMBER vs RANK vs DENSE_RANK on real ties | All three ranking functions + named `WINDOW` clause |
| 35 | Top 3 titles in each of the 6 biggest genres | Nested `DENSE_RANK()` (genres by size, titles per genre) |
| 36 | Duration-aware picks for a user | Favourite length band + top genres + `DENSE_RANK()` per genre |

### 15.5 Recommendation score (Q30)

```
score = 0.35 × genre_match     avg affinity of the title's genres (v_user_genre_profile)
      + 0.25 × collaborative   weighted ratings of the 30 most similar users
      + 0.15 × duration_match  affinity for the title's length band (v_user_duration_profile),
                               0.5 (neutral) when the title's runtime is unknown
      + 0.15 × quality         MovieLens damped mean / 5, else Netflix vote_average / 10
      + 0.10 × popularity      ln(1 + popularity) / ln(1 + max popularity)
```

Genre affinity = 0.5 × volume (share of the user's most-watched genre) +
0.5 × liking (genre average vs the user's own mean, so harsh and generous
raters are comparable, damped by n/(n+5) so a handful of ratings can't make a
favourite). Duration affinity uses the same formula per length band. User similarity = (1 − mean |Δrating| / 4.5) ×
n / (n + 10) over ≥ 10 co-rated movies. The weights sit in the `w` CTE of
Q30. This is a **transparent SQL-driven hybrid scoring rule, not a trained
machine-learning model**.

### 15.6 Honest limitations of the integration

- MovieLens small covers 1996–2018; the Netflix catalog covers 2010–2025.
  Only 1,730 of 9,742 MovieLens movies (and 9,168 of 100,836 ratings)
  reach a Netflix title. User *profiles* still use every rating a user made.
- Titles with MovieLens evidence get a collaborative score; Netflix-only
  titles (2019–2025) get 0 for that part, so they rank lower.
- Genre vocabularies differ; `genre_crosswalk` maps them (e.g. *Children* →
  *Family*, *Sci-Fi* → *Science Fiction*, *IMAX* → none).

### 15.7 Duration enrichment

**Why.** Duration is a useful personalisation signal (some users prefer
short films, some epics), but neither dataset has it: `duration_raw` is
empty for every movie and `'1 Seasons'` for every TV show, and MovieLens has
no runtime. Both datasets already store **TMDB ids** (`netflix.source_id`,
MovieLens `links.csv → tmdbId`), so runtime is looked up by those ids. This
is an *enrichment of existing records by their own ids*, not a dataset of
new titles, and no Netflix row is changed (validation check 39).

**Where the runtimes come from.**

| Source | Covers | How it gets in |
|---|---|---|
| `SNAPSHOT_2017` (bundled) | 13,700 films: 9,518 MovieLens movies (**99.4 % of all ratings**) + 5,811 Netflix movies (2010–2017) | `database/enrichment/tmdb_runtime_snapshot.csv`, extracted from *The Movies Dataset* (Rounak Banik, Kaggle, CC0 public domain: TMDB metadata collected 2017, built as the MovieLens companion). Loaded automatically. |
| `TMDB_API` (optional) | Netflix 2018–2025 movies and all TV shows | `fetch_tmdb_runtime.py` with a free TMDB key; overrides the snapshot for the same id. |

So **duration personalisation works out of the box**: all 610 users get a
duration profile. Netflix movies released after 2017, and TV shows, count as
"unknown length" (neutral 0.5) until the optional fetch is run.

**Data flow.**

```
netflix.source_id ─┐                                         ┌─ v_title_runtime ──── Q31, Q32, Q36, title page
                   ├─ snapshot CSV (+ optional API CSV) ─ tmdb_runtime ─┤
links.csv tmdbId ──┘                                         └─ v_movielens_runtime ─ v_user_duration_profile ─ Q33, Q30, Q36
```

`tmdb_runtime` is keyed by `(tmdb_type, tmdb_id)`, because TMDB movie and TV
ids are separate namespaces. It has a **stored generated column**
`duration_band` (`< 90`, `90-119`, `120-149`, `150+ min`), a `source`
column, and CHECK constraints on the minute ranges.

**How duration personalises.**

- `v_user_duration_profile` gives each user an affinity per length band, using
  the same volume + liking formula as genres.
- In Q30, a title in the user's favourite band scores up to 1; a band they never
  watch scores 0; an unknown length scores 0.5.
- Q36 lists the best unseen films in the user's favourite band, top 3 per genre.

For example, user 567 prefers 90–119 min films, so *Moneyball* (133 min) drops
from #1 to #5 once duration counts.

**Finding (Q32):** longer films are rated higher by *both* audiences.
Netflix/TMDB voters go from 6.05 (under 90 min) to 6.99 (150+ min), and
MovieLens users from 6.67 to 7.74 on the same 0–10 scale.

**Optional: add newer films and TV shows** (needs a free TMDB key, about 10–15 min):
```bash
export TMDB_API_KEY=your_key_here          # Windows cmd: set TMDB_API_KEY=your_key_here
python3 database/enrichment/fetch_tmdb_runtime.py
bash database/import.sh                     # Windows: database\import.bat
```

> **Note for the viva:** the original requirement said "Netflix + MovieLens
> only, no TMDB". The duration enrichment is a deliberate, documented
> extension that adds one column (runtime) to existing titles by their
> existing ids. Get your supervisor's OK.

### 15.8 Ranking functions: RANK vs DENSE_RANK vs ROW_NUMBER

All three number rows in a given order; they differ only on **ties**
(Q34 shows them side by side on real data):

| vote_average | ROW_NUMBER | RANK | DENSE_RANK |
|---|---|---|---|
| 8.50 (Interstellar) | 1 | 1 | 1 |
| 8.50 (Parasite) | 2 | 1 | 1 |
| 8.50 (Your Name.) | 3 | 1 | 1 |
| 8.41 (next film) | 4 | **4** | **2** |

`RANK` leaves gaps after ties; `DENSE_RANK` doesn't. QueryFlix uses
`DENSE_RANK` wherever "top N per group" should keep every tied item and
never skip a place:

| Query | Use of `DENSE_RANK` |
|---|---|
| Q17 | Most-rated movies (equal rating counts share a place) |
| Q23 / Q33 | Order of a user's favourite genres / length bands |
| Q24 | Top 3 unseen films **per genre** (`PARTITION BY genre`) |
| Q35 | Genres ranked by size, then top 3 titles inside each (nested) |
| Q36 | Top 3 duration-matched picks per genre |
