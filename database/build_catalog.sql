-- ============================================================
-- QueryFlix : Netflix -> normalised catalog tables
-- database/build_catalog.sql
--
-- Reads the untouched `netflix` table and fills titles, people,
-- title_credits, genres, title_genres, countries, title_countries.
-- Multi-valued comma strings are decomposed with JSON_TABLE(... FOR ORDINALITY).
-- NULL/empty lists simply produce no child rows: the title itself is always kept.
-- ============================================================

USE queryflix;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE title_credits; TRUNCATE people;
TRUNCATE title_genres;  TRUNCATE genres;
TRUNCATE title_countries; TRUNCATE countries;
DELETE FROM title_source_mapping;
DELETE FROM titles;
SET FOREIGN_KEY_CHECKS = 1;

-- 1. Canonical titles: one row per Netflix record, same id, nothing dropped.
INSERT INTO titles (title_id, source_id, type, title, norm_title, release_year, description,
                    language, content_rating, date_added, popularity, vote_count,
                    vote_average, budget, revenue, duration_raw)
SELECT show_id, source_id, type, title, fn_normalize_title(title), release_year, description,
       language, content_rating, date_added, popularity, vote_count,
       vote_average, budget, revenue, duration_raw
FROM netflix;

-- 2. Genres. 'Unknown' is a placeholder in the source, not a genre: those
--    titles are kept, they just get no title_genres row.
INSERT INTO genres (genre_name)
SELECT DISTINCT TRIM(jt.g)
FROM netflix,
     JSON_TABLE(fn_list_to_json(genres, ', '), '$[*]' COLUMNS (g VARCHAR(60) PATH '$')) jt
WHERE jt.g IS NOT NULL AND TRIM(jt.g) NOT IN ('', 'Unknown');

INSERT INTO title_genres (title_id, genre_id)
SELECT DISTINCT n.show_id, g.genre_id
FROM netflix n,
     JSON_TABLE(fn_list_to_json(n.genres, ', '), '$[*]' COLUMNS (g VARCHAR(60) PATH '$')) jt
JOIN genres g ON g.genre_name = TRIM(jt.g);

-- 3. Countries.
INSERT INTO countries (country_name)
SELECT DISTINCT TRIM(jt.c)
FROM netflix,
     JSON_TABLE(fn_list_to_json(country, ', '), '$[*]' COLUMNS (c VARCHAR(100) PATH '$')) jt
WHERE jt.c IS NOT NULL AND TRIM(jt.c) <> '';

INSERT INTO title_countries (title_id, country_id)
SELECT DISTINCT n.show_id, c.country_id
FROM netflix n,
     JSON_TABLE(fn_list_to_json(n.country, ', '), '$[*]' COLUMNS (c VARCHAR(100) PATH '$')) jt
JOIN countries c ON c.country_name = TRIM(jt.c);

-- 4. People + credits (directors and cast share one people table).
DROP TEMPORARY TABLE IF EXISTS tmp_credits;
CREATE TEMPORARY TABLE tmp_credits AS
SELECT n.show_id AS title_id, 'Director' AS role, jt.ord AS credit_order, TRIM(jt.name) AS person_name
FROM netflix n,
     JSON_TABLE(fn_list_to_json(n.director, ', '), '$[*]'
                COLUMNS (ord FOR ORDINALITY, name VARCHAR(255) PATH '$')) jt
WHERE jt.name IS NOT NULL AND TRIM(jt.name) <> ''
UNION ALL
SELECT n.show_id, 'Cast', jt.ord, TRIM(jt.name)
FROM netflix n,
     JSON_TABLE(fn_list_to_json(n.cast_members, ', '), '$[*]'
                COLUMNS (ord FOR ORDINALITY, name VARCHAR(255) PATH '$')) jt
WHERE jt.name IS NOT NULL AND TRIM(jt.name) <> '';

INSERT INTO people (person_name)
SELECT DISTINCT person_name FROM tmp_credits;

-- A name can repeat inside one list; keep its first (best-billed) position.
INSERT INTO title_credits (title_id, person_id, role, credit_order)
SELECT c.title_id, p.person_id, c.role, MIN(c.credit_order)
FROM tmp_credits c
JOIN people p ON p.person_name = c.person_name
GROUP BY c.title_id, p.person_id, c.role;

DROP TEMPORARY TABLE tmp_credits;

SELECT 'titles' AS table_name, COUNT(*) AS row_count FROM titles
UNION ALL SELECT 'genres', COUNT(*) FROM genres
UNION ALL SELECT 'title_genres', COUNT(*) FROM title_genres
UNION ALL SELECT 'countries', COUNT(*) FROM countries
UNION ALL SELECT 'title_countries', COUNT(*) FROM title_countries
UNION ALL SELECT 'people', COUNT(*) FROM people
UNION ALL SELECT 'title_credits', COUNT(*) FROM title_credits;
