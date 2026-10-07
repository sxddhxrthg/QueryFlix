-- ============================================================
-- QueryFlix : Unified relational schema (Netflix catalog + MovieLens behaviour)
-- database/unified_schema.sql
--
-- Run AFTER schema.sql + seed.sql. The original `netflix` table is never
-- modified: every table below is derived from it (or from MovieLens) and
-- `titles.title_id` is a foreign key back to `netflix.show_id` for lineage.
--
--   Netflix  = CONTENT / CATALOG      -> titles, people, title_credits,
--                                        genres, title_genres,
--                                        countries, title_countries
--   MovieLens = USER / RATING BEHAVIOUR -> movielens_movies,
--                                        movielens_movie_genres,
--                                        users, ratings, tags
--   Bridge                            -> title_source_mapping, genre_crosswalk
--   Enrichment (duration)             -> tmdb_runtime  (TMDB API, keyed by TMDB id)
-- ============================================================

USE queryflix;

SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW  IF EXISTS v_user_duration_profile;
DROP VIEW  IF EXISTS v_movielens_runtime;
DROP VIEW  IF EXISTS v_title_runtime;
DROP VIEW  IF EXISTS v_title_unified;
DROP VIEW  IF EXISTS v_user_genre_profile;
DROP VIEW  IF EXISTS v_movielens_movie_stats;
DROP TABLE IF EXISTS tmdb_runtime;
DROP TABLE IF EXISTS title_source_mapping;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS ratings;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS genre_crosswalk;
DROP TABLE IF EXISTS movielens_movie_genres;
DROP TABLE IF EXISTS movielens_movies;
DROP TABLE IF EXISTS title_countries;
DROP TABLE IF EXISTS countries;
DROP TABLE IF EXISTS title_genres;
DROP TABLE IF EXISTS genres;
DROP TABLE IF EXISTS title_credits;
DROP TABLE IF EXISTS people;
DROP TABLE IF EXISTS titles;
SET FOREIGN_KEY_CHECKS = 1;

-- ------------------------------------------------------------
-- Helper functions (deterministic, no table access)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_normalize_title;
DROP FUNCTION IF EXISTS fn_list_to_json;

DELIMITER $$

-- Title normalisation used for cross-dataset matching:
--   lower-case -> '&' becomes 'and' -> apostrophes dropped (don't -> dont)
--   -> every run of non-letter/non-digit characters becomes one space -> trim.
-- Accents are NOT stripped here: the normalised columns use the
-- accent-insensitive collation utf8mb4_0900_ai_ci, so 'amélie' = 'amelie'
-- at comparison time.
CREATE FUNCTION fn_normalize_title(t VARCHAR(500))
RETURNS VARCHAR(500) CHARSET utf8mb4
DETERMINISTIC NO SQL
BEGIN
    DECLARE s VARCHAR(500);
    IF t IS NULL THEN RETURN NULL; END IF;
    SET s = LOWER(t);
    SET s = REPLACE(s, '&', ' and ');
    SET s = REGEXP_REPLACE(s, '[\'`\\x{2018}\\x{2019}\\x{00B4}]', '');
    SET s = REGEXP_REPLACE(s, '[^\\p{L}\\p{N}]+', ' ');
    RETURN NULLIF(TRIM(s), '');
END$$

-- Turns a delimited list ("Drama, Comedy" or "Drama|Comedy") into a JSON
-- array string so JSON_TABLE() can unnest it. Quotes/backslashes/control
-- characters are escaped; ", Jr." suffixes are protected from splitting.
CREATE FUNCTION fn_list_to_json(s TEXT, sep VARCHAR(5))
RETURNS TEXT CHARSET utf8mb4
DETERMINISTIC NO SQL
BEGIN
    IF s IS NULL OR TRIM(s) = '' THEN RETURN NULL; END IF;
    SET s = REGEXP_REPLACE(s, '[[:cntrl:]]', ' ');
    SET s = REPLACE(s, ', Jr.', ' Jr.');
    SET s = REPLACE(s, ', Sr.', ' Sr.');
    SET s = REPLACE(s, CHAR(92), CONCAT(CHAR(92), CHAR(92)));
    SET s = REPLACE(s, '"', CONCAT(CHAR(92), '"'));
    RETURN CONCAT('["', REPLACE(s, sep, '","'), '"]');
END$$

DELIMITER ;

-- ------------------------------------------------------------
-- 1. CATALOG (from Netflix)
-- ------------------------------------------------------------
CREATE TABLE titles (
    title_id        INT PRIMARY KEY,                  -- canonical QueryFlix id (= netflix.show_id)
    source_id       INT,                              -- original dataset id (TMDB id; namespace differs for Movie vs TV)
    type            VARCHAR(10)   NOT NULL,
    title           VARCHAR(300)  NOT NULL,
    norm_title      VARCHAR(500),                     -- fn_normalize_title(title), used for matching
    release_year    SMALLINT,
    description     TEXT,
    language        VARCHAR(10),
    content_rating  DECIMAL(4,2),
    date_added      DATE,
    popularity      DECIMAL(10,3),
    vote_count      INT,
    vote_average    DECIMAL(4,2),
    budget          BIGINT,
    revenue         BIGINT,
    duration_raw    VARCHAR(30),
    CONSTRAINT fk_titles_netflix FOREIGN KEY (title_id) REFERENCES netflix(show_id),
    CONSTRAINT chk_titles_type CHECK (type IN ('Movie','TV Show')),
    INDEX idx_titles_match (type, norm_title(191), release_year),
    INDEX idx_titles_source (type, source_id)
) ENGINE=InnoDB;

CREATE TABLE people (
    person_id    INT AUTO_INCREMENT PRIMARY KEY,
    person_name  VARCHAR(255) NOT NULL,
    UNIQUE KEY uq_people_name (person_name)
) ENGINE=InnoDB;

CREATE TABLE title_credits (
    title_id      INT NOT NULL,
    person_id     INT NOT NULL,
    role          ENUM('Director','Cast') NOT NULL,
    credit_order  SMALLINT NOT NULL,                  -- position in the original list (1 = top billed)
    PRIMARY KEY (title_id, person_id, role),
    INDEX idx_credits_person (person_id, role),
    CONSTRAINT fk_credits_title  FOREIGN KEY (title_id)  REFERENCES titles(title_id),
    CONSTRAINT fk_credits_person FOREIGN KEY (person_id) REFERENCES people(person_id)
) ENGINE=InnoDB;

CREATE TABLE genres (
    genre_id    INT AUTO_INCREMENT PRIMARY KEY,
    genre_name  VARCHAR(60) NOT NULL,
    UNIQUE KEY uq_genres_name (genre_name)
) ENGINE=InnoDB;

CREATE TABLE title_genres (
    title_id  INT NOT NULL,
    genre_id  INT NOT NULL,
    PRIMARY KEY (title_id, genre_id),
    INDEX idx_tg_genre (genre_id),
    CONSTRAINT fk_tg_title FOREIGN KEY (title_id) REFERENCES titles(title_id),
    CONSTRAINT fk_tg_genre FOREIGN KEY (genre_id) REFERENCES genres(genre_id)
) ENGINE=InnoDB;

CREATE TABLE countries (
    country_id    INT AUTO_INCREMENT PRIMARY KEY,
    country_name  VARCHAR(100) NOT NULL,
    UNIQUE KEY uq_countries_name (country_name)
) ENGINE=InnoDB;

CREATE TABLE title_countries (
    title_id    INT NOT NULL,
    country_id  INT NOT NULL,
    PRIMARY KEY (title_id, country_id),
    INDEX idx_tc_country (country_id),
    CONSTRAINT fk_tc_title   FOREIGN KEY (title_id)   REFERENCES titles(title_id),
    CONSTRAINT fk_tc_country FOREIGN KEY (country_id) REFERENCES countries(country_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 2. USER BEHAVIOUR (from MovieLens ml-latest-small)
-- ------------------------------------------------------------
CREATE TABLE movielens_movies (
    movielens_movie_id  INT PRIMARY KEY,
    raw_title           VARCHAR(300) NOT NULL,        -- exactly as in movies.csv, e.g. 'Dark Knight, The (2008)'
    title               VARCHAR(300),                 -- cleaned: year removed, article moved -> 'The Dark Knight'
    alt_title           VARCHAR(300),                 -- bracketed alternate title, e.g. 'Se7en' from '(a.k.a. Se7en)'
    release_year        SMALLINT,                     -- NULL when movies.csv has no year
    genres_raw          VARCHAR(255),                 -- pipe-separated as in movies.csv
    norm_title          VARCHAR(500),
    norm_alt_title      VARCHAR(500),
    imdb_id             VARCHAR(10),                  -- from links.csv
    tmdb_id             INT,                          -- from links.csv (TMDB *movie* id)
    INDEX idx_ml_norm (norm_title(191), release_year),
    INDEX idx_ml_norm_alt (norm_alt_title(191), release_year),
    INDEX idx_ml_tmdb (tmdb_id)
) ENGINE=InnoDB;

CREATE TABLE movielens_movie_genres (
    movielens_movie_id  INT NOT NULL,
    ml_genre            VARCHAR(30) NOT NULL,         -- MovieLens vocabulary ('Sci-Fi', 'Children', ...)
    PRIMARY KEY (movielens_movie_id, ml_genre),
    INDEX idx_mlg_genre (ml_genre),
    CONSTRAINT fk_mlg_movie FOREIGN KEY (movielens_movie_id) REFERENCES movielens_movies(movielens_movie_id)
) ENGINE=InnoDB;

-- MovieLens and Netflix/TMDB use different genre vocabularies. This small
-- crosswalk lets a user's MovieLens genre taste be applied to the Netflix
-- catalog (needed for recommendations). genre_id NULL = no catalog
-- equivalent (e.g. IMAX is a format, not a genre).
CREATE TABLE genre_crosswalk (
    ml_genre  VARCHAR(30) PRIMARY KEY,
    genre_id  INT NULL,
    note      VARCHAR(120),
    CONSTRAINT fk_gx_genre FOREIGN KEY (genre_id) REFERENCES genres(genre_id)
) ENGINE=InnoDB;

CREATE TABLE users (
    user_id  INT PRIMARY KEY                          -- MovieLens userId (anonymous, no demographics)
) ENGINE=InnoDB;

CREATE TABLE ratings (
    user_id             INT NOT NULL,
    movielens_movie_id  INT NOT NULL,
    rating              DECIMAL(2,1) NOT NULL,
    rating_ts           INT UNSIGNED NOT NULL,        -- original Unix timestamp
    rated_at            DATETIME NOT NULL,            -- UTC, FROM_UNIXTIME(rating_ts)
    PRIMARY KEY (user_id, movielens_movie_id),
    INDEX idx_ratings_movie (movielens_movie_id, rating),
    CONSTRAINT fk_ratings_user  FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_ratings_movie FOREIGN KEY (movielens_movie_id) REFERENCES movielens_movies(movielens_movie_id),
    CONSTRAINT chk_rating_range CHECK (rating BETWEEN 0.5 AND 5.0)
) ENGINE=InnoDB;

CREATE TABLE tags (
    tag_id              INT AUTO_INCREMENT PRIMARY KEY,
    user_id             INT NOT NULL,
    movielens_movie_id  INT NOT NULL,
    tag                 VARCHAR(255) NOT NULL,
    tag_ts              INT UNSIGNED NOT NULL,
    tagged_at           DATETIME NOT NULL,
    INDEX idx_tags_movie (movielens_movie_id),
    CONSTRAINT fk_tags_user  FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_tags_movie FOREIGN KEY (movielens_movie_id) REFERENCES movielens_movies(movielens_movie_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 3. BRIDGE : one row per MovieLens movie (matched or not)
-- ------------------------------------------------------------
CREATE TABLE title_source_mapping (
    mapping_id          INT AUTO_INCREMENT PRIMARY KEY,
    movielens_movie_id  INT NOT NULL,
    title_id            INT NULL,                     -- NULL when UNMATCHED / AMBIGUOUS
    netflix_source_id   INT NULL,
    match_status        ENUM('EXACT','NORMALIZED','YEAR_MATCH','LINK_ID','AMBIGUOUS','UNMATCHED') NOT NULL,
    match_method        VARCHAR(60) NOT NULL,         -- human-readable rule that fired
    match_confidence    DECIMAL(3,2) NOT NULL,        -- 0.00 - 1.00
    candidate_count     SMALLINT NOT NULL DEFAULT 0,  -- how many Netflix candidates the rule saw
    year_diff           TINYINT NULL,                 -- netflix.release_year - movielens.release_year
    link_verified       TINYINT NULL,                 -- 1 = MovieLens links.csv tmdbId agrees, 0 = disagrees, NULL = no evidence
    UNIQUE KEY uq_map_ml (movielens_movie_id),
    INDEX idx_map_title (title_id),
    INDEX idx_map_status (match_status),
    CONSTRAINT fk_map_ml    FOREIGN KEY (movielens_movie_id) REFERENCES movielens_movies(movielens_movie_id),
    CONSTRAINT fk_map_title FOREIGN KEY (title_id) REFERENCES titles(title_id),
    CONSTRAINT chk_map_conf CHECK (match_confidence BETWEEN 0 AND 1),
    CONSTRAINT chk_map_title_status CHECK (
        (match_status IN ('AMBIGUOUS','UNMATCHED') AND title_id IS NULL) OR
        (match_status NOT IN ('AMBIGUOUS','UNMATCHED') AND title_id IS NOT NULL))
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 4. ENRICHMENT : duration (runtime) from the TMDB API
-- ------------------------------------------------------------
-- Neither permitted dataset has a usable duration (netflix.duration_raw is
-- empty for every movie and '1 Seasons' for every TV show; MovieLens has no
-- runtime). Both datasets already carry TMDB ids -- netflix.source_id and
-- MovieLens links.csv tmdbId -- so runtimes are looked up by that id:
--   SNAPSHOT_2017 : bundled, from "The Movies Dataset" (Kaggle, CC0), TMDB
--                   metadata collected in 2017 - database/enrichment/tmdb_runtime_snapshot.csv
--   TMDB_API      : optional live fetch (fetch_tmdb_runtime.py) for newer titles
--                   and TV shows; overrides the snapshot for the same id.
-- Nothing in `netflix` is overwritten. Titles/movies join to this table via
-- views (v_title_runtime, v_movielens_runtime); an empty table is valid and
-- simply makes duration "unknown" everywhere.
CREATE TABLE tmdb_runtime (
    tmdb_type                ENUM('movie','tv') NOT NULL,   -- TMDB keeps movie and TV ids in separate namespaces
    tmdb_id                  INT NOT NULL,
    runtime_minutes          SMALLINT NULL,                 -- movies
    seasons                  SMALLINT NULL,                 -- TV
    episodes                 SMALLINT NULL,                 -- TV
    episode_runtime_minutes  SMALLINT NULL,                 -- TV, typical episode length
    fetch_status             ENUM('OK','NO_RUNTIME','NOT_FOUND') NOT NULL,
    fetched_at               DATETIME NOT NULL,
    source                   ENUM('SNAPSHOT_2017','TMDB_API') NOT NULL,   -- where the runtime came from
    -- generated column: the length band used for personalisation (movies only)
    duration_band            VARCHAR(12) GENERATED ALWAYS AS (
        CASE WHEN tmdb_type <> 'movie' OR runtime_minutes IS NULL THEN NULL
             WHEN runtime_minutes < 90  THEN '< 90 min'
             WHEN runtime_minutes < 120 THEN '90-119 min'
             WHEN runtime_minutes < 150 THEN '120-149 min'
             ELSE '150+ min' END) STORED,
    PRIMARY KEY (tmdb_type, tmdb_id),
    INDEX idx_runtime_band (duration_band),
    CONSTRAINT chk_runtime_range CHECK (runtime_minutes IS NULL OR runtime_minutes BETWEEN 1 AND 1000),
    CONSTRAINT chk_episode_range CHECK (episode_runtime_minutes IS NULL OR episode_runtime_minutes BETWEEN 1 AND 600)
) ENGINE=InnoDB;
