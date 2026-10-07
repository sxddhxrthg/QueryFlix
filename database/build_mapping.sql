-- ============================================================
-- QueryFlix : Title mapping layer  (MovieLens movie  ->  QueryFlix title)
-- database/build_mapping.sql
--
-- Netflix and MovieLens do not share ids, so every MovieLens movie is
-- resolved through a rule cascade. Each MovieLens movie gets EXACTLY one
-- row in title_source_mapping, matched or not (nothing is deleted).
--
--   Rule  Status       Condition (Netflix side restricted to type = 'Movie')        Confidence
--   1     EXACT        cleaned title identical (case+accent sensitive) AND same year  1.00
--   2     NORMALIZED   fn_normalize_title() equal (title or a.k.a. title) AND same year 0.95
--   3     YEAR_MATCH   normalised title equal AND release year differs by exactly 1    0.80
--                      (festival year vs. release year is a common off-by-one)
--   4     LINK_ID      no title candidate at all, but MovieLens' own links.csv tmdbId   0.90
--                      equals the Netflix movie's source_id (both are TMDB movie ids)
--   -     AMBIGUOUS    several candidates at the best rule and nothing breaks the tie  0.00
--   -     UNMATCHED    no candidate by any rule                                        0.00
--
-- Tie-break: when a rule yields several Netflix candidates, the one whose
-- source_id equals the MovieLens tmdbId wins; otherwise AMBIGUOUS (we do
-- NOT blindly pick one of several same-name titles).
--
-- link_verified: for rules 1-3 we independently check the MovieLens links
-- file. 1 = tmdbId agrees with the chosen Netflix title, 0 = tmdbId points
-- elsewhere, NULL = no tmdbId. This gives a measurable precision for the
-- title matcher (see validation.sql).
-- Title matching is restricted to Movies: MovieLens only rates films, and
-- TV source_ids live in a different TMDB id namespace.
-- ============================================================

USE queryflix;

DELETE FROM title_source_mapping;

-- 1. Candidate pairs from normalised title (or a.k.a. title) with year within +-1
DROP TEMPORARY TABLE IF EXISTS tmp_cand;
CREATE TEMPORARY TABLE tmp_cand (
    movielens_movie_id INT, title_id INT, source_id INT, tmdb_id INT,
    rule_no TINYINT, via VARCHAR(10), year_diff TINYINT,
    INDEX (movielens_movie_id)
);

INSERT INTO tmp_cand
SELECT movielens_movie_id, title_id, source_id, tmdb_id,
       MIN(rule_no), SUBSTRING_INDEX(GROUP_CONCAT(via ORDER BY rule_no, via DESC), ',', 1), MIN(year_diff)
FROM (
    -- primary title
    SELECT m.movielens_movie_id, t.title_id, t.source_id, m.tmdb_id,
           CASE WHEN t.release_year = m.release_year
                     AND t.title COLLATE utf8mb4_0900_as_cs = m.title COLLATE utf8mb4_0900_as_cs THEN 1
                WHEN t.release_year = m.release_year THEN 2
                ELSE 3 END AS rule_no,
           'title' AS via,
           t.release_year - m.release_year AS year_diff
    FROM movielens_movies m
    JOIN titles t ON t.type = 'Movie'
                 AND t.norm_title = m.norm_title
                 AND t.release_year BETWEEN m.release_year - 1 AND m.release_year + 1
    UNION ALL
    -- alternate (a.k.a. / original-language) title
    SELECT m.movielens_movie_id, t.title_id, t.source_id, m.tmdb_id,
           CASE WHEN t.release_year = m.release_year
                     AND t.title COLLATE utf8mb4_0900_as_cs = m.alt_title COLLATE utf8mb4_0900_as_cs THEN 1
                WHEN t.release_year = m.release_year THEN 2
                ELSE 3 END,
           'alt_title',
           t.release_year - m.release_year
    FROM movielens_movies m
    JOIN titles t ON t.type = 'Movie'
                 AND t.norm_title = m.norm_alt_title
                 AND t.release_year BETWEEN m.release_year - 1 AND m.release_year + 1
    WHERE m.norm_alt_title IS NOT NULL
) c
GROUP BY movielens_movie_id, title_id, source_id, tmdb_id;

-- 2. Keep only the best rule per MovieLens movie and resolve ties
INSERT INTO title_source_mapping
    (movielens_movie_id, title_id, netflix_source_id, match_status, match_method,
     match_confidence, candidate_count, year_diff, link_verified)
WITH best AS (
    SELECT c.*,
           MIN(rule_no) OVER (PARTITION BY movielens_movie_id)                AS best_rule
    FROM tmp_cand c
), at_best AS (
    SELECT b.*,
           COUNT(*)                     OVER (PARTITION BY movielens_movie_id) AS n_cand,
           SUM(source_id <=> tmdb_id)   OVER (PARTITION BY movielens_movie_id) AS n_link
    FROM best b
    WHERE rule_no = best_rule
)
SELECT movielens_movie_id,
       title_id,
       source_id,
       ELT(rule_no, 'EXACT', 'NORMALIZED', 'YEAR_MATCH'),
       CONCAT(ELT(rule_no, 'exact title', 'normalised title', 'normalised title'),
              IF(via = 'alt_title', ' (a.k.a.)', ''),
              ELT(rule_no, ' + same year', ' + same year', ' + year +-1'),
              IF(n_cand > 1, ' + tmdb tie-break', '')),
       ELT(rule_no, 1.00, 0.95, 0.80),
       n_cand,
       year_diff,
       CASE WHEN tmdb_id IS NULL THEN NULL WHEN tmdb_id = source_id THEN 1 ELSE 0 END
FROM at_best
WHERE n_cand = 1
   OR (n_link = 1 AND source_id = tmdb_id);

-- 2b. Veto: a title match whose MovieLens tmdbId points to a DIFFERENT film
--     is a same-name collision (e.g. 'Sherlock Holmes (2009)' vs a 2010
--     film of the same name). If the linked film is in the catalog we
--     re-point to it (LINK_ID), otherwise the match is rejected (UNMATCHED).
UPDATE title_source_mapping s
JOIN movielens_movies m ON m.movielens_movie_id = s.movielens_movie_id
LEFT JOIN titles t2     ON t2.type = 'Movie' AND t2.source_id = m.tmdb_id
SET s.match_method      = IF(t2.title_id IS NULL,
                             CONCAT('rejected ', LOWER(s.match_status), ' match: tmdb link points elsewhere'),
                             CONCAT('tmdb link overrides ', LOWER(s.match_status), ' title match')),
    s.match_status      = IF(t2.title_id IS NULL, 'UNMATCHED', 'LINK_ID'),
    s.title_id          = t2.title_id,
    s.netflix_source_id = t2.source_id,
    s.match_confidence  = IF(t2.title_id IS NULL, 0.00, 0.90),
    s.year_diff         = IF(t2.title_id IS NULL, NULL, t2.release_year - m.release_year),
    s.link_verified     = IF(t2.title_id IS NULL, 0, 1)
WHERE s.link_verified = 0;

-- 3. AMBIGUOUS: candidates existed but no unique winner
INSERT INTO title_source_mapping
    (movielens_movie_id, title_id, netflix_source_id, match_status, match_method,
     match_confidence, candidate_count)
SELECT c.movielens_movie_id, NULL, NULL, 'AMBIGUOUS',
       'several same-title candidates, no tie-break', 0.00, COUNT(*)
FROM tmp_cand c
WHERE c.movielens_movie_id NOT IN (SELECT movielens_movie_id FROM title_source_mapping)
GROUP BY c.movielens_movie_id;

-- 4. LINK_ID: no title candidate at all, but MovieLens links.csv tmdbId
--    points at a Netflix movie (title differs, e.g. translated title)
INSERT INTO title_source_mapping
    (movielens_movie_id, title_id, netflix_source_id, match_status, match_method,
     match_confidence, candidate_count, year_diff, link_verified)
SELECT m.movielens_movie_id, t.title_id, t.source_id, 'LINK_ID',
       'MovieLens links.csv tmdbId = Netflix source_id', 0.90, 1,
       CASE WHEN m.release_year IS NULL THEN NULL
            ELSE GREATEST(-99, LEAST(99, t.release_year - m.release_year)) END,
       1
FROM movielens_movies m
JOIN titles t ON t.type = 'Movie' AND t.source_id = m.tmdb_id
WHERE m.movielens_movie_id NOT IN (SELECT movielens_movie_id FROM title_source_mapping);

-- 5. UNMATCHED: everything else is kept, explicitly
INSERT INTO title_source_mapping
    (movielens_movie_id, title_id, netflix_source_id, match_status, match_method,
     match_confidence, candidate_count)
SELECT m.movielens_movie_id, NULL, NULL, 'UNMATCHED',
       CASE WHEN m.release_year IS NULL THEN 'no year in MovieLens title, no link'
            WHEN m.release_year < 2009 THEN 'released before Netflix catalog window (2010-2025)'
            ELSE 'no Netflix title with same name/year' END,
       0.00, 0
FROM movielens_movies m
WHERE m.movielens_movie_id NOT IN (SELECT movielens_movie_id FROM title_source_mapping);

DROP TEMPORARY TABLE tmp_cand;

SELECT match_status, COUNT(*) AS movielens_movies,
       SUM(link_verified = 1) AS link_agrees, SUM(link_verified = 0) AS link_disagrees
FROM title_source_mapping
GROUP BY match_status
ORDER BY FIELD(match_status, 'EXACT','NORMALIZED','YEAR_MATCH','LINK_ID','AMBIGUOUS','UNMATCHED');
