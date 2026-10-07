-- ============================================================
-- QueryFlix : MovieLens ingestion
-- database/load_movielens.sql
--
-- Source: MovieLens ml-latest-small (GroupLens, generated 2018-09-26)
--   movies.csv  9,742 movies    ratings.csv 100,836 ratings (610 users)
--   links.csv   9,742 id links  tags.csv      3,683 tags
-- Files live in database/movielens/. Run from the repository root with
--   mysql --local-infile=1 --default-character-set=utf8mb4 queryflix < database/load_movielens.sql
--
-- MovieLens ratings are MovieLens users' ratings. They are NOT Netflix
-- user ratings; they are external preference data attached to the
-- Netflix catalog only where a validated title mapping exists.
-- ============================================================

USE queryflix;
SET time_zone = '+00:00';          -- timestamps are Unix epoch seconds (UTC)

SET FOREIGN_KEY_CHECKS = 0;
DELETE FROM title_source_mapping;
TRUNCATE tags; TRUNCATE ratings; TRUNCATE users;
TRUNCATE genre_crosswalk; TRUNCATE movielens_movie_genres; TRUNCATE movielens_movies;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------- movies.csv ----------------------------------------
-- raw 'Postman, The (Postino, Il) (1994)' ->
--   release_year 1994, title 'The Postman', alt_title 'Il Postino'
LOAD DATA LOCAL INFILE 'database/movielens/movies.csv'
INTO TABLE movielens_movies
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(movielens_movie_id, @raw_title, @genres)
SET raw_title    = TRIM(@raw_title),
    genres_raw   = NULLIF(@genres, '(no genres listed)'),
    release_year = CAST(REGEXP_SUBSTR(REGEXP_SUBSTR(TRIM(@raw_title), '\\((19|20)[0-9]{2}\\)$'), '[0-9]{4}') AS UNSIGNED),
    -- title without the trailing '(yyyy)' and without any '(alternate title)'
    title        = TRIM(REGEXP_REPLACE(REGEXP_REPLACE(TRIM(@raw_title), '\\s*\\((19|20)[0-9]{2}\\)$', ''), '\\s*\\(.*\\)\\s*$', '')),
    alt_title    = NULLIF(TRIM(REGEXP_REPLACE(
                       REGEXP_SUBSTR(REGEXP_REPLACE(TRIM(@raw_title), '\\s*\\((19|20)[0-9]{2}\\)$', ''), '\\(([^()]*)\\)$'),
                       '^\\((a\\.k\\.a\\. )?|\\)$', '')), '');

-- Move trailing articles to the front: 'Dark Knight, The' -> 'The Dark Knight'
UPDATE movielens_movies
SET title     = REGEXP_REPLACE(title,     '^(.*), (The|A|An|Les|Le|La|Il|El|Die|Das|Der|Los|Las|Un|Une|Das)$', '$2 $1'),
    alt_title = REGEXP_REPLACE(alt_title, '^(.*), (The|A|An|Les|Le|La|Il|El|Die|Das|Der|Los|Las|Un|Une|Das)$', '$2 $1');

-- a bracketed year range such as '(2006–2007)' is not an alternate title
UPDATE movielens_movies SET alt_title = NULL WHERE alt_title REGEXP '^[0-9 –-]+$';

UPDATE movielens_movies
SET norm_title     = fn_normalize_title(title),
    norm_alt_title = fn_normalize_title(alt_title);

-- ---------- links.csv (imdbId, tmdbId) ------------------------
DROP TEMPORARY TABLE IF EXISTS stg_links;
CREATE TEMPORARY TABLE stg_links (movielens_movie_id INT PRIMARY KEY, imdb_id VARCHAR(10), tmdb_id INT);
LOAD DATA LOCAL INFILE 'database/movielens/links.csv'
INTO TABLE stg_links
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES
(movielens_movie_id, @imdb, @tmdb)
SET imdb_id = NULLIF(TRIM(@imdb), ''), tmdb_id = NULLIF(TRIM(@tmdb), '');

UPDATE movielens_movies m JOIN stg_links l USING (movielens_movie_id)
SET m.imdb_id = l.imdb_id, m.tmdb_id = l.tmdb_id;
DROP TEMPORARY TABLE stg_links;

-- ---------- genres (pipe-separated) ---------------------------
INSERT INTO movielens_movie_genres (movielens_movie_id, ml_genre)
SELECT m.movielens_movie_id, TRIM(jt.g)
FROM movielens_movies m,
     JSON_TABLE(fn_list_to_json(m.genres_raw, '|'), '$[*]' COLUMNS (g VARCHAR(30) PATH '$')) jt
WHERE m.genres_raw IS NOT NULL;

-- MovieLens genre -> catalog genre (documented, not hidden)
INSERT INTO genre_crosswalk (ml_genre, genre_id, note)
SELECT x.ml_genre, g.genre_id, x.note
FROM (
          SELECT 'Action' ml_genre, 'Action' catalog_genre, 'same name' note
    UNION ALL SELECT 'Adventure',   'Adventure',       'same name'
    UNION ALL SELECT 'Animation',   'Animation',       'same name'
    UNION ALL SELECT 'Children',    'Family',          'MovieLens "Children" ~ TMDB "Family"'
    UNION ALL SELECT 'Comedy',      'Comedy',          'same name'
    UNION ALL SELECT 'Crime',       'Crime',           'same name'
    UNION ALL SELECT 'Documentary', 'Documentary',     'same name'
    UNION ALL SELECT 'Drama',       'Drama',           'same name'
    UNION ALL SELECT 'Fantasy',     'Fantasy',         'same name'
    UNION ALL SELECT 'Film-Noir',   'Crime',           'noir treated as a crime sub-genre'
    UNION ALL SELECT 'Horror',      'Horror',          'same name'
    UNION ALL SELECT 'IMAX',        NULL,              'screen format, not a genre'
    UNION ALL SELECT 'Musical',     'Music',           'MovieLens "Musical" ~ TMDB "Music"'
    UNION ALL SELECT 'Mystery',     'Mystery',         'same name'
    UNION ALL SELECT 'Romance',     'Romance',         'same name'
    UNION ALL SELECT 'Sci-Fi',      'Science Fiction', 'renamed'
    UNION ALL SELECT 'Thriller',    'Thriller',        'same name'
    UNION ALL SELECT 'War',         'War',             'same name'
    UNION ALL SELECT 'Western',     'Western',         'same name'
) x
LEFT JOIN genres g ON g.genre_name = x.catalog_genre;

-- ---------- ratings.csv ---------------------------------------
DROP TEMPORARY TABLE IF EXISTS stg_ratings;
CREATE TEMPORARY TABLE stg_ratings (user_id INT, movielens_movie_id INT, rating DECIMAL(2,1), rating_ts INT UNSIGNED);
LOAD DATA LOCAL INFILE 'database/movielens/ratings.csv'
INTO TABLE stg_ratings
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES
(user_id, movielens_movie_id, rating, rating_ts);

INSERT INTO users (user_id)
SELECT DISTINCT user_id FROM stg_ratings;          -- users who only tagged are added below

INSERT INTO ratings (user_id, movielens_movie_id, rating, rating_ts, rated_at)
SELECT user_id, movielens_movie_id, rating, rating_ts, FROM_UNIXTIME(rating_ts)
FROM stg_ratings;
DROP TEMPORARY TABLE stg_ratings;

-- ---------- tags.csv ------------------------------------------
DROP TEMPORARY TABLE IF EXISTS stg_tags;
CREATE TEMPORARY TABLE stg_tags (user_id INT, movielens_movie_id INT, tag VARCHAR(255), tag_ts INT UNSIGNED);
LOAD DATA LOCAL INFILE 'database/movielens/tags.csv'
INTO TABLE stg_tags
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
(user_id, movielens_movie_id, tag, tag_ts);

-- every tagging user is a MovieLens user; add any who never rated
INSERT IGNORE INTO users (user_id) SELECT DISTINCT user_id FROM stg_tags;

INSERT INTO tags (user_id, movielens_movie_id, tag, tag_ts, tagged_at)
SELECT user_id, movielens_movie_id, TRIM(tag), tag_ts, FROM_UNIXTIME(tag_ts)
FROM stg_tags;
DROP TEMPORARY TABLE stg_tags;

SELECT 'movielens_movies' AS table_name, COUNT(*) AS row_count FROM movielens_movies
UNION ALL SELECT 'movielens_movie_genres', COUNT(*) FROM movielens_movie_genres
UNION ALL SELECT 'genre_crosswalk', COUNT(*) FROM genre_crosswalk
UNION ALL SELECT 'users', COUNT(*) FROM users
UNION ALL SELECT 'ratings', COUNT(*) FROM ratings
UNION ALL SELECT 'tags', COUNT(*) FROM tags;
