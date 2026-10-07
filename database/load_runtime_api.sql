-- ============================================================
-- QueryFlix : load runtimes fetched live from the TMDB API (optional)
-- database/load_runtime_api.sql
--
-- Input: database/enrichment/tmdb_runtime.csv from fetch_tmdb_runtime.py.
-- Runs after load_runtime.sql; REPLACE makes API values win over the
-- 2017 snapshot for the same id, and adds newer films and TV shows.
-- ============================================================

USE queryflix;

LOAD DATA LOCAL INFILE 'database/enrichment/tmdb_runtime.csv'
REPLACE INTO TABLE tmdb_runtime
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(tmdb_type, tmdb_id, runtime_minutes, seasons, episodes, episode_runtime_minutes, fetch_status, fetched_at)
SET source = 'TMDB_API';

ANALYZE TABLE tmdb_runtime;

SELECT source, tmdb_type, fetch_status, COUNT(*) AS ids
FROM tmdb_runtime GROUP BY source, tmdb_type, fetch_status ORDER BY source, tmdb_type, fetch_status;
