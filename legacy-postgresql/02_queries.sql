-- ============================================================
-- QueryFlix : Netflix Movies & TV Shows Analysis (PostgreSQL)
-- 02_queries.sql -- the 15 business-problem queries
-- ============================================================

-- Q1. Content-type distribution: Movies vs TV Shows
-- Technique: Aggregation (COUNT, GROUP BY)
SELECT type, COUNT(*) AS total_titles,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_catalog
FROM netflix
GROUP BY type;

-- Q2. Top 10 genres by frequency across the whole catalog
-- Technique: String manipulation -- STRING_TO_ARRAY() + UNNEST()
SELECT TRIM(genre) AS genre, COUNT(*) AS title_count
FROM netflix, UNNEST(STRING_TO_ARRAY(genres, ',')) AS genre
WHERE genres IS NOT NULL
GROUP BY TRIM(genre)
ORDER BY title_count DESC
LIMIT 10;

-- Q3. Top 10 countries producing content
-- Technique: String manipulation -- UNNEST on multi-valued country field
SELECT TRIM(c) AS country, COUNT(*) AS title_count
FROM netflix, UNNEST(STRING_TO_ARRAY(country, ',')) AS c
WHERE country IS NOT NULL
GROUP BY TRIM(c)
ORDER BY title_count DESC
LIMIT 10;

-- Q4. Top 10 most frequently credited cast members
-- Technique: String manipulation -- UNNEST on cast_members
SELECT TRIM(actor) AS actor, COUNT(*) AS appearances
FROM netflix, UNNEST(STRING_TO_ARRAY(cast_members, ',')) AS actor
WHERE cast_members IS NOT NULL
GROUP BY TRIM(actor)
ORDER BY appearances DESC
LIMIT 10;

-- Q5. Yearly trend of titles added to Netflix (by date_added)
-- Technique: Date operations -- EXTRACT(YEAR FROM ...)
SELECT EXTRACT(YEAR FROM date_added)::INT AS year_added, COUNT(*) AS titles_added
FROM netflix
WHERE date_added IS NOT NULL
GROUP BY year_added
ORDER BY year_added;

-- Q6. Titles added in the last 5 years (recency filter)
-- Technique: Date operations -- CURRENT_DATE - INTERVAL
SELECT type, COUNT(*) AS recent_titles
FROM netflix
WHERE date_added >= (SELECT MAX(date_added) FROM netflix) - INTERVAL '5 years'
GROUP BY type;

-- Q7. Top 10 highest-rated titles overall (with a minimum vote threshold
--     so a title with only 1-2 votes can't top the list)
-- Technique: Filtering + ORDER BY
SELECT title, type, vote_average, vote_count
FROM netflix
WHERE vote_count >= 500
ORDER BY vote_average DESC
LIMIT 10;

-- Q8. Highest-rated Movie and highest-rated TV Show, using a window function
-- Technique: Window function -- RANK() OVER (PARTITION BY ... ORDER BY ...)
SELECT type, title, vote_average, rnk
FROM (
    SELECT type, title, vote_average,
           RANK() OVER (PARTITION BY type ORDER BY vote_average DESC) AS rnk
    FROM netflix
    WHERE vote_count >= 500
) ranked
WHERE rnk = 1
ORDER BY type;

-- Q9. Content originating from India: volume and average rating
-- Technique: Pattern matching -- ILIKE on a multi-valued field
SELECT type, COUNT(*) AS titles, ROUND(AVG(vote_average), 2) AS avg_rating
FROM netflix
WHERE country ILIKE '%India%'
GROUP BY type;

-- Q10. Average rating and average popularity: Movies vs TV Shows
-- Technique: Aggregation (AVG, GROUP BY)
SELECT type,
       ROUND(AVG(vote_average), 2) AS avg_rating,
       ROUND(AVG(popularity), 2)   AS avg_popularity,
       ROUND(AVG(vote_count))      AS avg_vote_count
FROM netflix
GROUP BY type;

-- Q11. Multi-country co-productions vs single-country titles
-- Technique: String manipulation -- ARRAY_LENGTH(STRING_TO_ARRAY())
SELECT
    CASE WHEN ARRAY_LENGTH(STRING_TO_ARRAY(country, ','), 1) > 1
         THEN 'Co-production (2+ countries)'
         ELSE 'Single country' END AS production_type,
    COUNT(*) AS title_count
FROM netflix
WHERE country IS NOT NULL
GROUP BY production_type;

-- Q12. Dynamic content categorization from the description text
-- Technique: Dynamic categorization -- CASE + ILIKE wildcard matching
SELECT
    CASE
        WHEN description ILIKE '%kill%' OR description ILIKE '%murder%'
             OR description ILIKE '%war%' OR description ILIKE '%crime%'
            THEN 'Crime / Violence themed'
        WHEN description ILIKE '%love%' OR description ILIKE '%romance%'
            THEN 'Romance themed'
        WHEN description ILIKE '%comedy%' OR description ILIKE '%funny%'
            THEN 'Comedy themed'
        ELSE 'Other'
    END AS content_flag,
    COUNT(*) AS title_count
FROM netflix
WHERE description IS NOT NULL
GROUP BY content_flag
ORDER BY title_count DESC;

-- Q13. Movie profitability: budget vs revenue (movies only, budget/revenue > 0)
-- Technique: Aggregation + derived column
SELECT title, release_year, budget, revenue,
       (revenue - budget) AS profit,
       ROUND(revenue::NUMERIC / NULLIF(budget, 0), 2) AS revenue_multiple
FROM netflix
WHERE type = 'Movie' AND budget > 0 AND revenue > 0
ORDER BY profit DESC
LIMIT 10;

-- Q14. Top 10 most prolific directors (by number of titles)
-- Technique: Aggregation, NULL handling
SELECT director, COUNT(*) AS titles_directed,
       ROUND(AVG(vote_average), 2) AS avg_rating
FROM netflix
WHERE director IS NOT NULL AND director <> ''
GROUP BY director
ORDER BY titles_directed DESC
LIMIT 10;

-- Q15. Most popular title of each of the last 10 release years
-- Technique: Window function -- RANK() OVER (PARTITION BY release_year ...)
SELECT release_year, title, type, popularity
FROM (
    SELECT release_year, title, type, popularity,
           RANK() OVER (PARTITION BY release_year ORDER BY popularity DESC) AS rnk
    FROM netflix
    WHERE release_year >= (SELECT MAX(release_year) FROM netflix) - 9
) ranked
WHERE rnk = 1
ORDER BY release_year DESC;
