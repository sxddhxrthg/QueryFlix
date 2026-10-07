-- ============================================================
-- QueryFlix : load runtimes (duration enrichment)
-- database/load_runtime.sql
--
-- 1. Bundled snapshot  database/enrichment/tmdb_runtime_snapshot.csv
--    (from "The Movies Dataset", Kaggle, CC0 - TMDB data collected 2017;
--    covers ~99% of MovieLens ratings and the 2010-2017 Netflix movies)
-- The optional live-API file is loaded afterwards by load_runtime_api.sql
-- and overrides the snapshot for the same TMDB id.
-- ============================================================

USE queryflix;

TRUNCATE tmdb_runtime;

LOAD DATA LOCAL INFILE 'database/enrichment/tmdb_runtime_snapshot.csv'
REPLACE INTO TABLE tmdb_runtime
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(tmdb_type, tmdb_id, runtime_minutes, seasons, episodes, episode_runtime_minutes, fetch_status, fetched_at)
SET source = 'SNAPSHOT_2017';

SELECT source, tmdb_type, COUNT(*) AS ids, ROUND(AVG(runtime_minutes)) AS avg_minutes
FROM tmdb_runtime GROUP BY source, tmdb_type;
