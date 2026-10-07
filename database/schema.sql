-- ============================================================
-- QueryFlix : MySQL schema (migrated from PostgreSQL)
-- database/schema.sql
-- ============================================================
-- NOTE ON VERSION: the requested target was "MySQL 9.x compatible SQL".
-- The environment this was built/tested in only has MySQL 8.0.46
-- available via the standard Ubuntu apt repositories (MySQL 9.x is not
-- yet in Ubuntu's apt channel at the time of writing). Everything below
-- uses MySQL 8.0/8.4/9.x-compatible syntax (window functions, JSON_TABLE,
-- EXTRACT, INTERVAL are all supported from 8.0 onward), so it will run
-- unchanged on MySQL 9.x once that's available via Homebrew on your Mac.

CREATE DATABASE IF NOT EXISTS queryflix
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

USE queryflix;

-- derived tables (unified_schema.sql) reference netflix; disable FK checks for the drop
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS netflix;
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE netflix (
    show_id         INT AUTO_INCREMENT PRIMARY KEY,   -- surrogate key (see data-quality note)
    source_id        INT,                              -- original TMDB/Kaggle id, not globally unique
    type            VARCHAR(10)      NOT NULL,
    title           VARCHAR(300)     NOT NULL,
    director        TEXT,
    cast_members    TEXT,                              -- comma-separated, multi-valued
    country         TEXT,                              -- comma-separated, multi-valued
    date_added      DATE,
    release_year    INT,
    content_rating  DECIMAL(4,2),                       -- TMDB-style rating score (0-10)
    duration_raw    VARCHAR(30),                        -- kept as-is; see data-quality note (unusable)
    genres          TEXT,                               -- comma-separated, multi-valued
    language        VARCHAR(10),
    description     TEXT,
    popularity      DECIMAL(10,3),
    vote_count      INT,
    vote_average    DECIMAL(4,2),
    budget          BIGINT,                             -- movies only
    revenue         BIGINT,                             -- movies only
    CONSTRAINT chk_netflix_type CHECK (type IN ('Movie','TV Show'))
) ENGINE=InnoDB;

CREATE INDEX idx_netflix_type ON netflix(type);
CREATE INDEX idx_netflix_release_year ON netflix(release_year);
CREATE INDEX idx_netflix_date_added ON netflix(date_added);
CREATE FULLTEXT INDEX idx_netflix_title_ft ON netflix(title);
