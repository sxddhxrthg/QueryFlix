-- ============================================================
-- QueryFlix : MySQL business-problem queries (migrated from PostgreSQL)
-- database/queries.sql
--
-- Translation notes (Postgres -> MySQL):
--   STRING_TO_ARRAY()/UNNEST()  -> JSON_TABLE() splitting a comma-list
--                                   converted into a JSON array
--   ILIKE                       -> LIKE (MySQL's default collation,
--                                   utf8mb4_0900_ai_ci, is already
--                                   case-insensitive)
--   RANK() OVER (PARTITION BY)  -> unchanged; native in MySQL 8.0+
--   EXTRACT(YEAR FROM ...)      -> unchanged; native in MySQL
--   CURRENT_DATE - INTERVAL     -> DATE_SUB(..., INTERVAL n YEAR)
--   ARRAY_LENGTH(...)           -> comma-count via
--                                   (LENGTH(x)-LENGTH(REPLACE(x,',',''))+1)
-- ============================================================

USE queryflix;

-- Q1. Content-type distribution
SELECT type, COUNT(*) AS total_titles,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_catalog
FROM netflix
GROUP BY type;

-- Q2. Top 10 genres by frequency
SELECT TRIM(jt.genre) AS genre, COUNT(*) AS title_count
FROM netflix,
     JSON_TABLE(
        CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(genres, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
        '$[*]' COLUMNS (genre VARCHAR(100) PATH '$')
     ) AS jt
WHERE genres IS NOT NULL
GROUP BY TRIM(jt.genre)
ORDER BY title_count DESC
LIMIT 10;

-- Q3. Top 10 producing countries
SELECT TRIM(jt.country_val) AS country, COUNT(*) AS title_count
FROM netflix,
     JSON_TABLE(
        CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(netflix.country, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
        '$[*]' COLUMNS (country_val VARCHAR(100) PATH '$')
     ) AS jt
WHERE netflix.country IS NOT NULL
GROUP BY TRIM(jt.country_val)
ORDER BY title_count DESC
LIMIT 10;

-- Q4. Top 10 most-credited cast members
-- NOTE: ~1,139 titles have cast_members values with invalid/mis-encoded
-- UTF-8 bytes in non-English names (mostly Turkish/Czech/Baltic accented
-- characters). MySQL's JSON_TABLE validates UTF-8 strictly and returns
-- NULL for those unparseable entries (PostgreSQL's UNNEST does not
-- perform this validation, so it did not surface there) -- this is a
-- genuine MySQL vs PostgreSQL behavioral difference, not a query bug.
-- We exclude the resulting NULLs explicitly rather than silently
-- letting them pollute the top-10 ranking.
SELECT TRIM(jt.actor) AS actor, COUNT(*) AS appearances
FROM netflix,
     JSON_TABLE(
        CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(cast_members, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
        '$[*]' COLUMNS (actor VARCHAR(150) PATH '$')
     ) AS jt
WHERE cast_members IS NOT NULL AND jt.actor IS NOT NULL
GROUP BY TRIM(jt.actor)
ORDER BY appearances DESC
LIMIT 10;

-- Q5. Yearly trend of titles added
SELECT EXTRACT(YEAR FROM date_added) AS year_added, COUNT(*) AS titles_added
FROM netflix
WHERE date_added IS NOT NULL
GROUP BY year_added
ORDER BY year_added;

-- Q6. Titles added in the last 5 years
SELECT type, COUNT(*) AS recent_titles
FROM netflix
WHERE date_added >= (SELECT DATE_SUB(MAX(date_added), INTERVAL 5 YEAR) FROM netflix)
GROUP BY type;

-- Q7. Top 10 highest-rated titles (vote_count >= 500)
SELECT title, type, vote_average, vote_count
FROM netflix
WHERE vote_count >= 500
ORDER BY vote_average DESC
LIMIT 10;

-- Q8. Highest-rated title per content type
SELECT type, title, vote_average
FROM (
    SELECT type, title, vote_average,
           RANK() OVER (PARTITION BY type ORDER BY vote_average DESC) AS rnk
    FROM netflix
    WHERE vote_count >= 500
) ranked
WHERE rnk = 1
ORDER BY type;

-- Q9. Content originating from India
SELECT type, COUNT(*) AS titles, ROUND(AVG(vote_average), 2) AS avg_rating
FROM netflix
WHERE country LIKE '%India%'
GROUP BY type;

-- Q10. Ratings & popularity: Movies vs TV Shows
SELECT type,
       ROUND(AVG(vote_average), 2) AS avg_rating,
       ROUND(AVG(popularity), 2)   AS avg_popularity,
       ROUND(AVG(vote_count))      AS avg_vote_count
FROM netflix
GROUP BY type;

-- Q11. Co-productions vs single-country titles
SELECT
    CASE WHEN (LENGTH(country) - LENGTH(REPLACE(country, ',', '')) + 1) > 1
         THEN 'Co-production (2+ countries)'
         ELSE 'Single country' END AS production_type,
    COUNT(*) AS title_count
FROM netflix
WHERE country IS NOT NULL
GROUP BY production_type;

-- Q12. Dynamic content categorization from description
SELECT
    CASE
        WHEN description LIKE '%kill%' OR description LIKE '%murder%'
             OR description LIKE '%war%' OR description LIKE '%crime%'
            THEN 'Crime / Violence themed'
        WHEN description LIKE '%love%' OR description LIKE '%romance%'
            THEN 'Romance themed'
        WHEN description LIKE '%comedy%' OR description LIKE '%funny%'
            THEN 'Comedy themed'
        ELSE 'Other'
    END AS content_flag,
    COUNT(*) AS title_count
FROM netflix
WHERE description IS NOT NULL
GROUP BY content_flag
ORDER BY title_count DESC;

-- Q13. Movie profitability (budget vs revenue)
SELECT title, release_year, budget, revenue,
       (revenue - budget) AS profit,
       ROUND(revenue / NULLIF(budget, 0), 2) AS revenue_multiple
FROM netflix
WHERE type = 'Movie' AND budget > 0 AND revenue > 0
ORDER BY profit DESC
LIMIT 10;

-- Q14. Top 10 most prolific directors
SELECT director, COUNT(*) AS titles_directed,
       ROUND(AVG(vote_average), 2) AS avg_rating
FROM netflix
WHERE director IS NOT NULL AND director <> ''
GROUP BY director
ORDER BY titles_directed DESC
LIMIT 10;

-- Q15. Most popular title per year (last 10 release years)
SELECT release_year, title, type, popularity
FROM (
    SELECT release_year, title, type, popularity,
           RANK() OVER (PARTITION BY release_year ORDER BY popularity DESC) AS rnk
    FROM netflix
    WHERE release_year >= (SELECT MAX(release_year) - 9 FROM netflix)
) ranked
WHERE rnk = 1
ORDER BY release_year DESC;
