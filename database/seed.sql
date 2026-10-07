-- ============================================================
-- QueryFlix : Data import
-- database/seed.sql
--
-- This does NOT contain 32,000 INSERT statements -- that would be both
-- huge and slow. Instead it documents the bulk-import method used
-- (LOAD DATA INFILE) against the cleaned, unified CSV at
-- database/data/netflix_unified.csv (source_id, type, title, director,
-- cast_members, country, date_added, release_year, content_rating,
-- duration_raw, genres, language, description, popularity, vote_count,
-- vote_average, budget, revenue -- 18 columns, no show_id column since
-- that's an AUTO_INCREMENT surrogate key generated on insert).
--
-- MySQL's secure_file_priv setting restricts which directory
-- LOAD DATA INFILE can read from (check with
-- SHOW VARIABLES LIKE 'secure_file_priv';). On most Homebrew MySQL
-- installs on macOS this defaults to an empty string (no restriction),
-- in which case you can point LOAD DATA directly at this file's path.
-- If it's restricted, either copy the CSV into that directory first,
-- or use `mysql --local-infile=1` with LOAD DATA LOCAL INFILE instead
-- (see database/import.sh, which handles both cases automatically).
-- ============================================================

USE queryflix;

LOAD DATA LOCAL INFILE 'database/data/netflix_unified.csv'
INTO TABLE netflix
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\r\n'
(source_id, type, title, director, cast_members, country, date_added, release_year,
 content_rating, duration_raw, genres, language, description, popularity, vote_count,
 vote_average, budget, revenue);

-- Sanity checks -- expect 32000 / 16000 / 16000:
SELECT COUNT(*) AS total_rows FROM netflix;
SELECT type, COUNT(*) FROM netflix GROUP BY type;
