-- ============================================================
-- QueryFlix : Netflix Movies & TV Shows Analysis (PostgreSQL)
-- 01_schema.sql -- table creation
-- ============================================================

DROP TABLE IF EXISTS netflix;

CREATE TABLE netflix (
    show_id         SERIAL PRIMARY KEY,    -- surrogate key (see data-quality note)
    source_id       INTEGER,               -- original TMDB/Kaggle id, not globally unique
    type            VARCHAR(10)      NOT NULL CHECK (type IN ('Movie','TV Show')),
    title           VARCHAR(300)     NOT NULL,
    director        TEXT,
    cast_members    TEXT,                  -- comma-separated, multi-valued
    country         TEXT,                  -- comma-separated, multi-valued
    date_added      DATE,
    release_year    INTEGER,
    content_rating  NUMERIC(4,2),          -- TMDB-style rating score (0-10)
    duration_raw    VARCHAR(30),           -- kept as-is; see data-quality note
    genres          TEXT,                  -- comma-separated, multi-valued
    language        VARCHAR(10),
    description     TEXT,
    popularity      NUMERIC(10,3),
    vote_count      INTEGER,
    vote_average    NUMERIC(4,2),
    budget          BIGINT,                -- movies only
    revenue         BIGINT                 -- movies only
);

CREATE INDEX idx_netflix_type ON netflix(type);
CREATE INDEX idx_netflix_release_year ON netflix(release_year);
CREATE INDEX idx_netflix_date_added ON netflix(date_added);
