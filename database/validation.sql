-- ============================================================
-- QueryFlix : Validation report
-- database/validation.sql
-- Every check returns: check_name | expected | actual | status (PASS/FAIL/INFO)
-- ============================================================

USE queryflix;

WITH checks AS (
    -- 1. Netflix untouched
    SELECT 1 AS n, 'Netflix rows (original table)' AS check_name, '32000' AS expected,
           (SELECT COUNT(*) FROM netflix) AS actual
    UNION ALL SELECT 2, 'Netflix movies', '16000', (SELECT COUNT(*) FROM netflix WHERE type = 'Movie')
    UNION ALL SELECT 3, 'Netflix TV shows', '16000', (SELECT COUNT(*) FROM netflix WHERE type = 'TV Show')
    -- canonical titles
    UNION ALL SELECT 4, 'Canonical titles = Netflix rows', '32000', (SELECT COUNT(*) FROM titles)
    UNION ALL SELECT 5, 'Duplicate canonical title_id', '0',
           (SELECT COUNT(*) - COUNT(DISTINCT title_id) FROM titles)
    UNION ALL SELECT 6, 'Titles with no netflix parent', '0',
           (SELECT COUNT(*) FROM titles t LEFT JOIN netflix n ON n.show_id = t.title_id WHERE n.show_id IS NULL)
    -- 2-4. MovieLens counts (ml-latest-small README)
    UNION ALL SELECT 7, 'MovieLens users', '610', (SELECT COUNT(*) FROM users)
    UNION ALL SELECT 8, 'MovieLens movies', '9742', (SELECT COUNT(*) FROM movielens_movies)
    UNION ALL SELECT 9, 'MovieLens ratings', '100836', (SELECT COUNT(*) FROM ratings)
    UNION ALL SELECT 10, 'MovieLens tags', '3683', (SELECT COUNT(*) FROM tags)
    -- 5-6. mapping coverage: every MovieLens movie has exactly one mapping row
    UNION ALL SELECT 11, 'Mapping rows = MovieLens movies', '9742', (SELECT COUNT(*) FROM title_source_mapping)
    UNION ALL SELECT 12, 'Mapped MovieLens movies', 'info',
           (SELECT COUNT(*) FROM title_source_mapping WHERE title_id IS NOT NULL)
    UNION ALL SELECT 13, 'Unmatched MovieLens movies (kept)', 'info',
           (SELECT COUNT(*) FROM title_source_mapping WHERE match_status = 'UNMATCHED')
    UNION ALL SELECT 14, 'Ambiguous MovieLens movies (kept)', 'info',
           (SELECT COUNT(*) FROM title_source_mapping WHERE match_status = 'AMBIGUOUS')
    UNION ALL SELECT 15, 'Mapped rows pointing to a non-Movie title', '0',
           (SELECT COUNT(*) FROM title_source_mapping s JOIN titles t USING (title_id) WHERE t.type <> 'Movie')
    UNION ALL SELECT 16, 'Netflix titles mapped by >1 MovieLens movie', 'info',
           (SELECT COUNT(*) FROM (SELECT title_id FROM title_source_mapping WHERE title_id IS NOT NULL
                                  GROUP BY title_id HAVING COUNT(*) > 1) x)
    -- matcher quality against MovieLens' own links.csv
    UNION ALL SELECT 17, 'Title-rule matches confirmed by links.csv', 'info',
           (SELECT COUNT(*) FROM title_source_mapping
            WHERE match_status IN ('EXACT','NORMALIZED','YEAR_MATCH') AND link_verified = 1)
    UNION ALL SELECT 18, 'Accepted matches contradicted by links.csv', '0',
           (SELECT COUNT(*) FROM title_source_mapping WHERE title_id IS NOT NULL AND link_verified = 0)
    -- 8. referential integrity (FKs are enforced; these prove it)
    UNION ALL SELECT 19, 'Orphan ratings (user)', '0',
           (SELECT COUNT(*) FROM ratings r LEFT JOIN users u USING (user_id) WHERE u.user_id IS NULL)
    UNION ALL SELECT 20, 'Orphan ratings (movie)', '0',
           (SELECT COUNT(*) FROM ratings r LEFT JOIN movielens_movies m USING (movielens_movie_id) WHERE m.movielens_movie_id IS NULL)
    UNION ALL SELECT 21, 'Orphan mapping -> titles', '0',
           (SELECT COUNT(*) FROM title_source_mapping s LEFT JOIN titles t USING (title_id)
            WHERE s.title_id IS NOT NULL AND t.title_id IS NULL)
    UNION ALL SELECT 22, 'Orphan title_genres', '0',
           (SELECT COUNT(*) FROM title_genres tg LEFT JOIN genres g USING (genre_id) WHERE g.genre_id IS NULL)
    UNION ALL SELECT 23, 'Orphan title_credits', '0',
           (SELECT COUNT(*) FROM title_credits c LEFT JOIN people p USING (person_id) WHERE p.person_id IS NULL)
    UNION ALL SELECT 24, 'Ratings outside 0.5-5.0', '0',
           (SELECT COUNT(*) FROM ratings WHERE rating NOT BETWEEN 0.5 AND 5.0)
    -- NULL / data-quality visibility (titles are kept, just counted)
    UNION ALL SELECT 25, 'Titles with NULL director (kept)', 'info', (SELECT COUNT(*) FROM netflix WHERE director IS NULL)
    UNION ALL SELECT 26, 'Titles with NULL cast (kept)', 'info', (SELECT COUNT(*) FROM netflix WHERE cast_members IS NULL)
    UNION ALL SELECT 27, 'Titles with NULL country (kept)', 'info', (SELECT COUNT(*) FROM netflix WHERE country IS NULL)
    UNION ALL SELECT 28, 'Titles with no genre (kept)', 'info',
           (SELECT COUNT(*) FROM titles t WHERE NOT EXISTS (SELECT 1 FROM title_genres tg WHERE tg.title_id = t.title_id))
    UNION ALL SELECT 29, 'Titles with NULL date_added', 'info', (SELECT COUNT(*) FROM netflix WHERE date_added IS NULL)
    UNION ALL SELECT 30, 'MovieLens movies with no ratings', 'info',
           (SELECT COUNT(*) FROM movielens_movies m
            WHERE NOT EXISTS (SELECT 1 FROM ratings r WHERE r.movielens_movie_id = m.movielens_movie_id))
    UNION ALL SELECT 31, 'Duplicate source_id (Movie vs TV namespace)', 'info',
           (SELECT COUNT(*) FROM (SELECT source_id FROM netflix GROUP BY source_id HAVING COUNT(*) > 1) x)
    UNION ALL SELECT 32, 'Duplicate source_id within same type', 'info',
           (SELECT COUNT(*) FROM (SELECT type, source_id FROM netflix GROUP BY type, source_id HAVING COUNT(*) > 1) x)
    UNION ALL SELECT 33, 'Duplicate (title, year, type) in Netflix', 'info',
           (SELECT COUNT(*) FROM (SELECT title, release_year, type FROM netflix
                                  GROUP BY title, release_year, type HAVING COUNT(*) > 1) x)
    UNION ALL SELECT 34, 'Ratings that reach a Netflix title', 'info',
           (SELECT COUNT(*) FROM ratings r JOIN title_source_mapping s USING (movielens_movie_id) WHERE s.title_id IS NOT NULL)
    -- duration enrichment (0 everywhere until fetch_tmdb_runtime.py has been run)
    UNION ALL SELECT 35, 'Netflix movies with runtime (TMDB)', 'info',
           (SELECT COUNT(*) FROM v_title_runtime WHERE type = 'Movie' AND runtime_minutes IS NOT NULL)
    UNION ALL SELECT 36, 'Netflix TV shows with seasons/episode length', 'info',
           (SELECT COUNT(*) FROM v_title_runtime WHERE type = 'TV Show' AND runtime_status = 'OK')
    UNION ALL SELECT 37, 'MovieLens movies with runtime (TMDB)', 'info',
           (SELECT COUNT(*) FROM v_movielens_runtime)
    UNION ALL SELECT 38, 'Ratings whose movie has a runtime', 'info',
           (SELECT COUNT(*) FROM ratings r JOIN v_movielens_runtime mr USING (movielens_movie_id))
    UNION ALL SELECT 40, 'Runtimes from bundled 2017 snapshot', 'info',
           (SELECT COUNT(*) FROM tmdb_runtime WHERE source = 'SNAPSHOT_2017' AND fetch_status = 'OK')
    UNION ALL SELECT 41, 'Runtimes from live TMDB API fetch', 'info',
           (SELECT COUNT(*) FROM tmdb_runtime WHERE source = 'TMDB_API' AND fetch_status = 'OK')
    UNION ALL SELECT 42, 'Users with a duration profile', 'info',
           (SELECT COUNT(DISTINCT user_id) FROM v_user_duration_profile)
    UNION ALL SELECT 39, 'Netflix title rows changed by enrichment', '0',
           (SELECT COUNT(*) FROM netflix WHERE duration_raw IS NOT NULL AND duration_raw <> '1 Seasons')
)
SELECT n AS '#', check_name, expected, actual,
       CASE WHEN expected = 'info' THEN 'INFO'
            WHEN CAST(expected AS SIGNED) = actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY n;

-- Mapping breakdown
SELECT match_status, match_method, COUNT(*) AS movielens_movies,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM title_source_mapping
GROUP BY match_status, match_method
ORDER BY FIELD(match_status,'EXACT','NORMALIZED','YEAR_MATCH','LINK_ID','AMBIGUOUS','UNMATCHED'), movielens_movies DESC;

-- Title matcher precision / recall, measured against MovieLens links.csv.
-- Ground truth = MovieLens movies whose tmdbId is a Netflix movie source_id.
WITH truth AS (
    SELECT m.movielens_movie_id, t.title_id AS true_title_id
    FROM movielens_movies m JOIN titles t ON t.type = 'Movie' AND t.source_id = m.tmdb_id
), title_rule AS (   -- what the title rules alone decided (before the link veto)
    SELECT movielens_movie_id, title_id FROM title_source_mapping
    WHERE match_status IN ('EXACT','NORMALIZED','YEAR_MATCH')
       OR match_method LIKE '%overrides%' OR match_method LIKE 'rejected%'
)
SELECT (SELECT COUNT(*) FROM truth)                                            AS linkable_movies,
       (SELECT COUNT(*) FROM title_rule)                                       AS title_rule_decisions,
       (SELECT COUNT(*) FROM title_source_mapping WHERE match_method LIKE 'rejected%'
                                               OR match_method LIKE '%overrides%') AS vetoed_by_link,
       (SELECT COUNT(*) FROM title_source_mapping s JOIN truth USING (movielens_movie_id)
         WHERE s.match_status IN ('EXACT','NORMALIZED','YEAR_MATCH') AND s.title_id = truth.true_title_id) AS correct_title_matches,
       ROUND(100 * (SELECT COUNT(*) FROM title_source_mapping WHERE match_status IN ('EXACT','NORMALIZED','YEAR_MATCH') AND link_verified = 1)
             / (SELECT COUNT(*) FROM title_source_mapping
                WHERE (match_status IN ('EXACT','NORMALIZED','YEAR_MATCH') AND link_verified IS NOT NULL)
                   OR match_method LIKE 'rejected%' OR match_method LIKE '%overrides%'), 2) AS title_rule_precision_pct,
       ROUND(100 * (SELECT COUNT(*) FROM title_source_mapping s JOIN truth USING (movielens_movie_id)
                    WHERE s.match_status IN ('EXACT','NORMALIZED','YEAR_MATCH') AND s.title_id = truth.true_title_id)
             / (SELECT COUNT(*) FROM truth), 2)                                AS title_rule_recall_pct,
       ROUND(100 * (SELECT COUNT(*) FROM title_source_mapping s JOIN truth USING (movielens_movie_id)
                    WHERE s.title_id = truth.true_title_id)
             / (SELECT COUNT(*) FROM truth), 2)                                AS final_recall_pct;

-- Why most MovieLens movies stay unmatched: release-year coverage
SELECT CASE WHEN m.release_year IS NULL THEN 'no year'
            WHEN m.release_year < 2010 THEN 'before 2010 (outside Netflix catalog years)'
            ELSE '2010 or later' END AS movielens_release_window,
       COUNT(*) AS movielens_movies,
       SUM(s.title_id IS NOT NULL) AS mapped,
       ROUND(100 * SUM(s.title_id IS NOT NULL) / COUNT(*), 1) AS pct_mapped
FROM movielens_movies m JOIN title_source_mapping s USING (movielens_movie_id)
GROUP BY movielens_release_window
ORDER BY movielens_movies DESC;
