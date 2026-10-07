-- ============================================================
-- QueryFlix : Analytical views over the unified model
-- database/views.sql
-- ============================================================

USE queryflix;

-- Per-MovieLens-movie rating statistics.
-- bayes_rating is a damped mean: (n * avg + m * C) / (n + m), where
-- C = global mean rating and m = 10 "virtual" ratings. It stops a movie
-- with one 5-star rating from outranking a movie with 300 ratings at 4.4.
CREATE OR REPLACE VIEW v_movielens_movie_stats AS
WITH g AS (SELECT AVG(rating) AS c FROM ratings)
SELECT r.movielens_movie_id,
       COUNT(*)                                            AS n_ratings,
       ROUND(AVG(r.rating), 3)                             AS avg_rating,
       ROUND(STDDEV_SAMP(r.rating), 3)                     AS stddev_rating,
       ROUND((COUNT(*) * AVG(r.rating) + 10 * g.c) / (COUNT(*) + 10), 3) AS bayes_rating
FROM ratings r CROSS JOIN g
GROUP BY r.movielens_movie_id, g.c;

-- One row per Netflix title that has a MovieLens match, with both
-- perspectives side by side (Netflix vote_average is 0-10, MovieLens 0.5-5).
CREATE OR REPLACE VIEW v_title_unified AS
SELECT t.title_id, t.title, t.type, t.release_year,
       t.popularity, t.vote_count AS netflix_vote_count, t.vote_average AS netflix_vote_average,
       s.movielens_movie_id, s.match_status, s.match_confidence,
       st.n_ratings AS ml_n_ratings, st.avg_rating AS ml_avg_rating, st.bayes_rating AS ml_bayes_rating,
       ROUND(st.avg_rating * 2, 2) AS ml_avg_rating_10          -- rescaled to 0-10 for comparison
FROM titles t
JOIN title_source_mapping s ON s.title_id = t.title_id
LEFT JOIN v_movielens_movie_stats st ON st.movielens_movie_id = s.movielens_movie_id;

-- A user's taste per catalog genre (MovieLens genres translated through
-- genre_crosswalk). Two transparent parts, each scaled 0..1:
--   volume  = movies the user rated in this genre / their most-rated genre
--   liking  = 0.5 + (user's avg in this genre - user's overall avg) / 2 * n/(n+5), clamped
--             (so +1 star above their own average = 1.0, -1 star = 0.0;
--              centring on the user's mean removes "generous rater" bias;
--              n/(n+5) pulls genres with only a few ratings back toward neutral 0.5)
--   affinity = 0.5 * volume + 0.5 * liking
CREATE OR REPLACE VIEW v_user_genre_profile AS
WITH per_genre AS (
    SELECT r.user_id, mgx.genre_id,
           COUNT(*)      AS n_rated,
           AVG(r.rating) AS avg_rating
    FROM ratings r
    JOIN (   -- DISTINCT: 'Crime' and 'Film-Noir' both map to Crime; count the movie once
          SELECT DISTINCT mg.movielens_movie_id, gx.genre_id
          FROM movielens_movie_genres mg
          JOIN genre_crosswalk gx ON gx.ml_genre = mg.ml_genre AND gx.genre_id IS NOT NULL
         ) mgx ON mgx.movielens_movie_id = r.movielens_movie_id
    GROUP BY r.user_id, mgx.genre_id
), user_mean AS (
    SELECT user_id, AVG(rating) AS mean_rating FROM ratings GROUP BY user_id
), scored AS (
    SELECT p.user_id, p.genre_id, p.n_rated, p.avg_rating, u.mean_rating,
           p.n_rated / MAX(p.n_rated) OVER (PARTITION BY p.user_id)            AS volume,
           LEAST(1, GREATEST(0, 0.5 + (p.avg_rating - u.mean_rating) / 2
                                        * p.n_rated / (p.n_rated + 5)))    AS liking
    FROM per_genre p JOIN user_mean u ON u.user_id = p.user_id
)
SELECT s.user_id, s.genre_id, g.genre_name, s.n_rated,
       ROUND(s.avg_rating, 3)                       AS avg_rating,
       ROUND(s.avg_rating - s.mean_rating, 3)       AS vs_user_mean,
       ROUND(s.volume, 4)                           AS volume,
       ROUND(s.liking, 4)                           AS liking,
       ROUND(0.5 * s.volume + 0.5 * s.liking, 4)    AS affinity
FROM scored s
JOIN genres g ON g.genre_id = s.genre_id;

-- ------------------------------------------------------------
-- Duration (runtime) views — read from tmdb_runtime (TMDB enrichment).
-- If tmdb_runtime is empty these return NULL/no rows and every query that
-- uses them still runs.
-- ------------------------------------------------------------

-- Netflix titles with their duration. TMDB keeps movie and TV ids in
-- separate namespaces, so the join includes the type.
CREATE OR REPLACE VIEW v_title_runtime AS
SELECT t.title_id, t.type, t.title,
       r.runtime_minutes, r.duration_band,
       r.seasons, r.episodes, r.episode_runtime_minutes,
       COALESCE(r.fetch_status, 'NOT_FETCHED') AS runtime_status,
       r.source                                AS runtime_source
FROM titles t
LEFT JOIN tmdb_runtime r
       ON r.tmdb_type = IF(t.type = 'Movie', 'movie', 'tv')
      AND r.tmdb_id   = t.source_id;

-- MovieLens movies with their duration (via links.csv tmdbId). This covers
-- ALL MovieLens movies, not only the 1,730 mapped ones, so a user's
-- duration taste is learned from their whole rating history.
CREATE OR REPLACE VIEW v_movielens_runtime AS
SELECT m.movielens_movie_id, m.tmdb_id, r.runtime_minutes, r.duration_band
FROM movielens_movies m
JOIN tmdb_runtime r ON r.tmdb_type = 'movie' AND r.tmdb_id = m.tmdb_id
WHERE r.runtime_minutes IS NOT NULL;

-- A user's taste per duration band, same transparent formula as genres:
--   volume  = movies rated in this band / movies rated in their most-watched band
--   liking  = 0.5 + (avg rating in band - user's overall avg) / 2 * n/(n+5), clamped to 0..1
--   affinity = 0.5 * volume + 0.5 * liking
CREATE OR REPLACE VIEW v_user_duration_profile AS
WITH per_band AS (
    SELECT r.user_id, mr.duration_band,
           COUNT(*)                   AS n_rated,
           AVG(r.rating)              AS avg_rating,
           AVG(mr.runtime_minutes)    AS avg_minutes
    FROM ratings r
    JOIN v_movielens_runtime mr ON mr.movielens_movie_id = r.movielens_movie_id
    GROUP BY r.user_id, mr.duration_band
), user_mean AS (
    SELECT user_id, AVG(rating) AS mean_rating FROM ratings GROUP BY user_id
), scored AS (
    SELECT p.*, u.mean_rating,
           p.n_rated / MAX(p.n_rated) OVER (PARTITION BY p.user_id)              AS volume,
           LEAST(1, GREATEST(0, 0.5 + (p.avg_rating - u.mean_rating) / 2
                                        * p.n_rated / (p.n_rated + 5)))           AS liking
    FROM per_band p JOIN user_mean u ON u.user_id = p.user_id
)
SELECT user_id, duration_band, n_rated,
       ROUND(avg_rating, 3)                  AS avg_rating,
       ROUND(avg_minutes)                    AS avg_minutes,
       ROUND(avg_rating - mean_rating, 3)    AS vs_user_mean,
       ROUND(volume, 4)                      AS volume,
       ROUND(liking, 4)                      AS liking,
       ROUND(0.5 * volume + 0.5 * liking, 4) AS affinity
FROM scored;

-- Refresh optimizer statistics after the bulk loads. Without this, a freshly
-- built database can pick poor join orders (Q30 went from ~0.6 s to ~30 s).
ANALYZE TABLE titles, title_genres, genres, title_credits, people, countries, title_countries,
              movielens_movies, movielens_movie_genres, genre_crosswalk, users, ratings, tags,
              title_source_mapping, tmdb_runtime;
