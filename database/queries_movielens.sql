-- ============================================================
-- QueryFlix : Layer 2 — user behaviour & personalisation (Q16 – Q30)
-- database/queries_movielens.sql
--
-- Runs on the unified model (unified_schema.sql + build_*.sql + views.sql).
-- Q1–Q15 in queries.sql are unchanged and still run on `netflix`.
-- User-specific queries use the session variable @user_id.
-- MovieLens ratings are external user-preference data, NOT Netflix ratings.
-- ============================================================

USE queryflix;
SET @user_id = 567;     -- any MovieLens userId 1..610

-- Q16. Most highly rated movies by MovieLens users (min. 50 ratings)
--      Damped (Bayesian) mean so tiny samples cannot top the chart.
SELECT m.raw_title AS movielens_title, st.n_ratings, st.avg_rating, st.bayes_rating,
       COALESCE(t.title, '— not in Netflix catalog') AS netflix_title
FROM v_movielens_movie_stats st
JOIN movielens_movies m          ON m.movielens_movie_id = st.movielens_movie_id
LEFT JOIN title_source_mapping s ON s.movielens_movie_id = st.movielens_movie_id
LEFT JOIN titles t               ON t.title_id = s.title_id
WHERE st.n_ratings >= 50
ORDER BY st.bayes_rating DESC
LIMIT 10;

-- Q17. Most-rated movies (DENSE_RANK keeps ties together)
SELECT DENSE_RANK() OVER (ORDER BY st.n_ratings DESC) AS rnk,
       m.raw_title, st.n_ratings, st.avg_rating
FROM v_movielens_movie_stats st
JOIN movielens_movies m ON m.movielens_movie_id = st.movielens_movie_id
ORDER BY st.n_ratings DESC
LIMIT 10;

-- Q18. Average MovieLens rating by genre
SELECT mg.ml_genre,
       COUNT(*)                            AS n_ratings,
       COUNT(DISTINCT r.movielens_movie_id) AS n_movies,
       ROUND(AVG(r.rating), 3)             AS avg_rating,
       RANK() OVER (ORDER BY AVG(r.rating) DESC) AS rating_rank
FROM ratings r
JOIN movielens_movie_genres mg ON mg.movielens_movie_id = r.movielens_movie_id
GROUP BY mg.ml_genre
ORDER BY avg_rating DESC;

-- Q19. Rating distribution with running (cumulative) percentage
SELECT rating,
       COUNT(*) AS n_ratings,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                    AS pct,
       ROUND(100 * SUM(COUNT(*)) OVER (ORDER BY rating) / SUM(COUNT(*)) OVER (), 2) AS cumulative_pct
FROM ratings
GROUP BY rating
ORDER BY rating;

-- Q20. Number of ratings per movie — long-tail buckets
SELECT bucket, COUNT(*) AS n_movies, SUM(n_ratings) AS ratings_in_bucket,
       ROUND(100 * SUM(n_ratings) / SUM(SUM(n_ratings)) OVER (), 2) AS pct_of_all_ratings
FROM (
    SELECT n_ratings,
           CASE WHEN n_ratings = 1   THEN '1'
                WHEN n_ratings <= 5  THEN '2-5'
                WHEN n_ratings <= 20 THEN '6-20'
                WHEN n_ratings <= 50 THEN '21-50'
                WHEN n_ratings <= 100 THEN '51-100'
                ELSE '100+' END AS bucket
    FROM v_movielens_movie_stats
) x
GROUP BY bucket
ORDER BY MIN(n_ratings);

-- Q21. User activity segments (NTILE quartiles by number of ratings)
WITH activity AS (
    SELECT user_id, COUNT(*) AS n_ratings,
           DATEDIFF(MAX(rated_at), MIN(rated_at)) AS active_span_days,
           NTILE(4) OVER (ORDER BY COUNT(*)) AS quartile
    FROM ratings
    GROUP BY user_id
)
SELECT CASE quartile WHEN 1 THEN 'Q1 light' WHEN 2 THEN 'Q2 casual'
                     WHEN 3 THEN 'Q3 regular' ELSE 'Q4 power' END AS segment,
       COUNT(*)                      AS users,
       MIN(n_ratings)                AS min_ratings,
       MAX(n_ratings)                AS max_ratings,
       ROUND(AVG(n_ratings))         AS avg_ratings,
       ROUND(AVG(active_span_days))  AS avg_active_days,
       SUM(n_ratings)                AS total_ratings
FROM activity
GROUP BY quartile
ORDER BY quartile;

-- Q22. Popular genres among users: how many users are "fans"
--      (rated 3+ movies of the genre at 4.0 or above)
WITH fan AS (
    SELECT r.user_id, mg.ml_genre
    FROM ratings r
    JOIN movielens_movie_genres mg ON mg.movielens_movie_id = r.movielens_movie_id
    WHERE r.rating >= 4.0
    GROUP BY r.user_id, mg.ml_genre
    HAVING COUNT(*) >= 3
)
SELECT ml_genre, COUNT(*) AS fan_users,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM users), 1) AS pct_of_users
FROM fan
GROUP BY ml_genre
ORDER BY fan_users DESC
LIMIT 10;

-- Q23. User preference profile for @user_id (catalog genres via crosswalk)
SELECT genre_name, n_rated, avg_rating, vs_user_mean, volume, liking, affinity,
       DENSE_RANK() OVER (ORDER BY affinity DESC) AS preference_rank   -- equal affinity = same place, no gaps
FROM v_user_genre_profile
WHERE user_id = @user_id
ORDER BY affinity DESC
LIMIT 8;

-- Q24. For each of @user_id's top-3 genres: the 3 best-rated films they have not rated yet
--      DENSE_RANK() OVER (PARTITION BY genre ...) restarts the numbering inside every genre;
--      films with the same damped rating share a place and no place number is skipped.
WITH top_genres AS (
    SELECT genre_id, genre_name, affinity FROM v_user_genre_profile
    WHERE user_id = @user_id ORDER BY affinity DESC LIMIT 3
), candidates AS (
    SELECT DISTINCT tg.genre_name, tg.affinity, mg.movielens_movie_id
    FROM top_genres tg
    JOIN genre_crosswalk gx        ON gx.genre_id = tg.genre_id
    JOIN movielens_movie_genres mg ON mg.ml_genre = gx.ml_genre
), ranked AS (
    SELECT c.genre_name, c.affinity, m.raw_title, st.n_ratings, st.bayes_rating,
           DENSE_RANK() OVER (PARTITION BY c.genre_name ORDER BY st.bayes_rating DESC) AS rank_in_genre
    FROM candidates c
    JOIN v_movielens_movie_stats st ON st.movielens_movie_id = c.movielens_movie_id
    JOIN movielens_movies m         ON m.movielens_movie_id  = c.movielens_movie_id
    WHERE st.n_ratings >= 30
      AND NOT EXISTS (SELECT 1 FROM ratings r
                      WHERE r.user_id = @user_id AND r.movielens_movie_id = c.movielens_movie_id)
)
SELECT genre_name, rank_in_genre, raw_title, n_ratings, bayes_rating
FROM ranked
WHERE rank_in_genre <= 3
ORDER BY affinity DESC, rank_in_genre, raw_title;

-- Q25. Netflix catalog titles with strong MovieLens rating activity
SELECT title, release_year, match_status, ml_n_ratings, ml_avg_rating, netflix_vote_average
FROM v_title_unified
WHERE ml_n_ratings >= 20
ORDER BY ml_n_ratings DESC
LIMIT 10;

-- Q26. High Netflix popularity AND high MovieLens activity
--      (both in the top 20% of mapped titles, via PERCENT_RANK)
WITH ranked AS (
    SELECT title, release_year, popularity, ml_n_ratings, ml_avg_rating,
           PERCENT_RANK() OVER (ORDER BY popularity)   AS pop_pct,
           PERCENT_RANK() OVER (ORDER BY ml_n_ratings) AS activity_pct
    FROM v_title_unified
    WHERE ml_n_ratings IS NOT NULL
)
SELECT title, release_year, popularity, ml_n_ratings, ml_avg_rating,
       ROUND(pop_pct, 3) AS popularity_percentile, ROUND(activity_pct, 3) AS activity_percentile
FROM ranked
WHERE pop_pct >= 0.8 AND activity_pct >= 0.8
ORDER BY pop_pct + activity_pct DESC
LIMIT 10;

-- Q27. Netflix vote_average vs MovieLens average (rescaled x2 to 0-10)
--      with a Pearson correlation computed in plain SQL
WITH pairs AS (
    SELECT netflix_vote_average AS x, ml_avg_rating_10 AS y
    FROM v_title_unified
    WHERE ml_n_ratings >= 5 AND netflix_vote_count >= 50
)
SELECT COUNT(*)                         AS mapped_titles_compared,
       ROUND(AVG(x), 3)                 AS avg_netflix_vote,
       ROUND(AVG(y), 3)                 AS avg_movielens_x2,
       ROUND(AVG(y - x), 3)             AS mean_difference,
       ROUND(AVG(ABS(y - x)), 3)        AS mean_abs_difference,
       ROUND((AVG(x * y) - AVG(x) * AVG(y)) / (STDDEV_POP(x) * STDDEV_POP(y)), 3) AS pearson_r
FROM pairs;

-- Q28. Titles where the two audiences disagree most
SELECT title, release_year, netflix_vote_average, ml_avg_rating_10, ml_n_ratings,
       ROUND(ml_avg_rating_10 - netflix_vote_average, 2) AS diff,
       CASE WHEN ml_avg_rating_10 > netflix_vote_average
            THEN 'MovieLens users rate higher' ELSE 'Netflix/TMDB voters rate higher' END AS direction
FROM v_title_unified
WHERE ml_n_ratings >= 10 AND netflix_vote_count >= 100
ORDER BY ABS(ml_avg_rating_10 - netflix_vote_average) DESC
LIMIT 10;

-- Q29. Personalised candidate pool for @user_id
--      Netflix movies in the user's top-3 genres that the user has not rated
--      (through the mapping). Includes 2019-2025 titles MovieLens never saw.
WITH top_genres AS (
    SELECT genre_id FROM v_user_genre_profile
    WHERE user_id = @user_id ORDER BY affinity DESC LIMIT 3
), seen AS (
    SELECT s.title_id FROM ratings r
    JOIN title_source_mapping s ON s.movielens_movie_id = r.movielens_movie_id
    WHERE r.user_id = @user_id AND s.title_id IS NOT NULL
)
SELECT CASE WHEN s.title_id IS NULL THEN 'Netflix only (no MovieLens data)'
            ELSE 'Mapped to MovieLens' END AS candidate_source,
       COUNT(DISTINCT t.title_id)          AS candidates,
       ROUND(AVG(t.vote_average), 2)       AS avg_netflix_vote,
       MIN(t.release_year)                 AS from_year,
       MAX(t.release_year)                 AS to_year
FROM titles t
JOIN title_genres tg ON tg.title_id = t.title_id
JOIN top_genres tp   ON tp.genre_id = tg.genre_id
LEFT JOIN title_source_mapping s ON s.title_id = t.title_id
LEFT JOIN seen ON seen.title_id = t.title_id
WHERE t.type = 'Movie' AND t.vote_count >= 50
  AND seen.title_id IS NULL
GROUP BY candidate_source;

-- Q30. SQL-driven HYBRID recommendation score for @user_id
--
--   score = 0.35 * genre_match      content-based : avg affinity of the title's genres (v_user_genre_profile)
--         + 0.25 * collaborative    collaborative : weighted rating given by the 30 most similar users
--         + 0.15 * duration_match   content-based : user's affinity for the title's length band
--                                                   (v_user_duration_profile); 0.5 = neutral when the
--                                                   title's runtime is unknown / not fetched yet
--         + 0.15 * quality          rating        : MovieLens damped mean / 5, else Netflix vote_average / 10
--         + 0.10 * popularity       popularity    : ln(1+popularity) / ln(1+max popularity)
--
--   similarity(me, other) = (1 - mean |rating diff| / 4.5) * n_common / (n_common + 10),
--   over movies both rated, requiring n_common >= 10.
--   Weights are plain constants in the `w` CTE — change them there.
--   This is a transparent SQL scoring rule, NOT a trained machine-learning model.
WITH
w AS (SELECT 0.35 AS w_genre, 0.25 AS w_collab, 0.15 AS w_duration, 0.15 AS w_quality, 0.10 AS w_pop),
me AS (SELECT movielens_movie_id, rating FROM ratings WHERE user_id = @user_id),
seen AS (
    SELECT s.title_id FROM me
    JOIN title_source_mapping s ON s.movielens_movie_id = me.movielens_movie_id
    WHERE s.title_id IS NOT NULL
),
neighbours AS (
    SELECT r.user_id,
           (1 - AVG(ABS(r.rating - me.rating)) / 4.5) * COUNT(*) / (COUNT(*) + 10) AS sim
    FROM ratings r JOIN me ON me.movielens_movie_id = r.movielens_movie_id
    WHERE r.user_id <> @user_id
    GROUP BY r.user_id
    HAVING COUNT(*) >= 10
    ORDER BY sim DESC
    LIMIT 30
),
collab AS (
    SELECT s.title_id,
           (SUM(nb.sim * r.rating) / SUM(nb.sim) / 5) * COUNT(*) / (COUNT(*) + 2) AS collab_score,
           COUNT(*) AS n_neighbours
    FROM neighbours nb
    JOIN ratings r ON r.user_id = nb.user_id
    JOIN title_source_mapping s ON s.movielens_movie_id = r.movielens_movie_id AND s.title_id IS NOT NULL
    GROUP BY s.title_id
),
prof AS (SELECT genre_id, genre_name, affinity FROM v_user_genre_profile WHERE user_id = @user_id),
dprof AS (SELECT duration_band, affinity FROM v_user_duration_profile WHERE user_id = @user_id),
genre_match AS (
    SELECT tg.title_id,
           AVG(COALESCE(p.affinity, 0)) AS genre_score,
           GROUP_CONCAT(CASE WHEN p.affinity >= 0.5 THEN p.genre_name END
                        ORDER BY p.affinity DESC SEPARATOR ', ') AS liked_genres
    FROM title_genres tg LEFT JOIN prof p ON p.genre_id = tg.genre_id
    GROUP BY tg.title_id
),
maxpop AS (SELECT LN(1 + MAX(popularity)) AS lmax FROM titles WHERE type = 'Movie'),
scored AS (
    SELECT t.title_id, t.title, t.release_year, gm.liked_genres,
           gm.genre_score,
           COALESCE(c.collab_score, 0)                                         AS collab_score,
           COALESCE(st.bayes_rating / 5, t.vote_average / 10)                  AS quality_score,
           LN(1 + t.popularity) / mp.lmax                                      AS popularity_score,
           CASE WHEN rt.duration_band IS NULL THEN 0.5          -- runtime unknown: neutral
                ELSE COALESCE(dp.affinity, 0) END                              AS duration_score,
           rt.runtime_minutes,
           c.n_neighbours,
           IF(s.title_id IS NULL, 'Netflix only', 'Netflix + MovieLens')       AS evidence
    FROM titles t
    JOIN genre_match gm ON gm.title_id = t.title_id
    CROSS JOIN maxpop mp
    LEFT JOIN collab c ON c.title_id = t.title_id
    LEFT JOIN title_source_mapping s ON s.title_id = t.title_id
    LEFT JOIN v_movielens_movie_stats st ON st.movielens_movie_id = s.movielens_movie_id
    LEFT JOIN tmdb_runtime rt ON rt.tmdb_type = 'movie' AND rt.tmdb_id = t.source_id
    LEFT JOIN dprof dp ON dp.duration_band = rt.duration_band
    LEFT JOIN seen ON seen.title_id = t.title_id
    WHERE t.type = 'Movie' AND t.vote_count >= 50
      AND seen.title_id IS NULL
)
SELECT ROW_NUMBER() OVER (ORDER BY
           w.w_genre * genre_score + w.w_collab * collab_score + w.w_duration * duration_score
         + w.w_quality * quality_score + w.w_pop * popularity_score DESC) AS rec_rank,
       title, release_year, runtime_minutes, evidence,
       ROUND(w.w_genre * genre_score + w.w_collab * collab_score + w.w_duration * duration_score
           + w.w_quality * quality_score + w.w_pop * popularity_score, 4) AS recommendation_score,
       ROUND(genre_score, 3)      AS genre_match,
       ROUND(collab_score, 3)     AS collaborative,
       ROUND(duration_score, 3)   AS duration_match,
       ROUND(quality_score, 3)    AS quality,
       ROUND(popularity_score, 3) AS popularity,
       COALESCE(n_neighbours, 0)  AS similar_users_who_rated,
       liked_genres               AS because_you_like
FROM scored CROSS JOIN w
ORDER BY recommendation_score DESC
LIMIT 10;

-- ============================================================
-- Duration layer (Q31 – Q33) — uses tmdb_runtime (TMDB enrichment).
-- Before the runtimes are fetched these return empty / NULL results.
-- ============================================================

-- Q31. Movie length by genre
--      (avg / shortest / longest runtime per genre + share of 150+ min epics)
SELECT g.genre_name,
       COUNT(*)                                        AS movies_with_runtime,
       ROUND(AVG(vr.runtime_minutes))                  AS avg_minutes,
       MIN(vr.runtime_minutes)                         AS shortest,
       MAX(vr.runtime_minutes)                         AS longest,
       ROUND(100 * AVG(vr.duration_band = '150+ min'), 1) AS pct_150_plus,
       RANK() OVER (ORDER BY AVG(vr.runtime_minutes) DESC) AS length_rank
FROM v_title_runtime vr
JOIN title_genres tg ON tg.title_id = vr.title_id
JOIN genres g        ON g.genre_id = tg.genre_id
WHERE vr.type = 'Movie' AND vr.runtime_minutes IS NOT NULL
GROUP BY g.genre_name
HAVING COUNT(*) >= 30
ORDER BY length_rank;

-- Q32. Does length affect ratings? Both audiences, per duration band
--      (MovieLens users via links.csv tmdbId; Netflix/TMDB voters via source_id)
WITH ml AS (
    SELECT mr.duration_band, COUNT(*) AS ml_ratings, AVG(r.rating) AS ml_avg
    FROM ratings r
    JOIN v_movielens_runtime mr ON mr.movielens_movie_id = r.movielens_movie_id
    GROUP BY mr.duration_band
), nf AS (
    SELECT duration_band, COUNT(*) AS netflix_movies, AVG(t.vote_average) AS nf_avg
    FROM v_title_runtime vr JOIN titles t ON t.title_id = vr.title_id
    WHERE vr.type = 'Movie' AND vr.duration_band IS NOT NULL AND t.vote_count >= 50
    GROUP BY duration_band
)
SELECT nf.duration_band,
       nf.netflix_movies,
       ROUND(nf.nf_avg, 2)       AS netflix_avg_vote_0_10,
       ml.ml_ratings             AS movielens_ratings,
       ROUND(ml.ml_avg * 2, 2)   AS movielens_avg_x2_0_10
FROM nf LEFT JOIN ml ON ml.duration_band = nf.duration_band
ORDER BY FIELD(nf.duration_band, '< 90 min', '90-119 min', '120-149 min', '150+ min');

-- Q33. Duration preference profile for @user_id
SELECT duration_band, n_rated, avg_minutes, avg_rating, vs_user_mean, volume, liking, affinity,
       DENSE_RANK() OVER (ORDER BY affinity DESC) AS preference_rank
FROM v_user_duration_profile
WHERE user_id = @user_id
ORDER BY FIELD(duration_band, '< 90 min', '90-119 min', '120-149 min', '150+ min');

-- ============================================================
-- Ranking functions & duration-aware personalisation (Q34 – Q36)
-- ============================================================

-- Q34. ROW_NUMBER vs RANK vs DENSE_RANK on the same ordering
--      Top-rated movies (vote_count >= 500); several films tie on vote_average.
--        ROW_NUMBER : every row gets its own number (ties broken by title)  1,2,3,4
--        RANK       : ties share a number, then numbers are SKIPPED         1,1,1,4
--        DENSE_RANK : ties share a number, NO numbers skipped               1,1,1,2
--      Uses a named WINDOW clause so RANK and DENSE_RANK share one definition.
SELECT title, release_year, vote_average,
       ROW_NUMBER() OVER (ORDER BY vote_average DESC, title) AS row_no,
       RANK()       OVER w AS rank_no,
       DENSE_RANK() OVER w AS dense_rank_no
FROM titles
WHERE type = 'Movie' AND vote_count >= 500
WINDOW w AS (ORDER BY vote_average DESC)
ORDER BY vote_average DESC, title
LIMIT 15;

-- Q35. Top 3 titles in each of the 6 biggest genres
--      DENSE_RANK twice: once to rank genres by size, once to rank titles inside
--      each genre. A tie for 3rd place shows every tied title, not an arbitrary one.
WITH genre_size AS (
    SELECT tg.genre_id, g.genre_name, COUNT(*) AS n_titles,
           DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS size_rank
    FROM title_genres tg
    JOIN genres g ON g.genre_id = tg.genre_id
    GROUP BY tg.genre_id, g.genre_name
), ranked AS (
    SELECT gs.genre_name, gs.size_rank, t.title, t.type, t.vote_average, t.vote_count,
           DENSE_RANK() OVER (PARTITION BY gs.genre_id ORDER BY t.vote_average DESC) AS rank_in_genre
    FROM genre_size gs
    JOIN title_genres tg ON tg.genre_id = gs.genre_id
    JOIN titles t        ON t.title_id  = tg.title_id
    WHERE gs.size_rank <= 6 AND t.vote_count >= 500
)
SELECT size_rank AS genre_size_rank, genre_name, rank_in_genre, title, type, vote_average, vote_count
FROM ranked
WHERE rank_in_genre <= 3
ORDER BY size_rank, rank_in_genre, title;

-- Q36. Duration-aware picks for @user_id
--      Takes the user's favourite length band (Q33) and top-3 genres (Q23), keeps
--      Netflix movies in that band the user has not rated, and lists the top 3 per
--      genre with DENSE_RANK. Duration personalisation and ranking in one query.
WITH fav_band AS (
    SELECT duration_band FROM v_user_duration_profile
    WHERE user_id = @user_id ORDER BY affinity DESC LIMIT 1
), top_genres AS (
    SELECT genre_id, genre_name, affinity FROM v_user_genre_profile
    WHERE user_id = @user_id ORDER BY affinity DESC LIMIT 3
), seen AS (
    SELECT DISTINCT s.title_id
    FROM ratings r
    JOIN title_source_mapping s ON s.movielens_movie_id = r.movielens_movie_id
    WHERE r.user_id = @user_id AND s.title_id IS NOT NULL
), ranked AS (
    SELECT tg.genre_name, tg.affinity, t.title, t.release_year,
           rt.runtime_minutes, rt.duration_band, t.vote_average, t.vote_count,
           DENSE_RANK() OVER (PARTITION BY tg.genre_id ORDER BY t.vote_average DESC) AS rank_in_genre
    FROM top_genres tg
    JOIN title_genres g   ON g.genre_id = tg.genre_id
    JOIN titles t         ON t.title_id = g.title_id AND t.type = 'Movie' AND t.vote_count >= 200
    JOIN tmdb_runtime rt  ON rt.tmdb_type = 'movie' AND rt.tmdb_id = t.source_id
    JOIN fav_band fb      ON fb.duration_band = rt.duration_band
    LEFT JOIN seen        ON seen.title_id = t.title_id
    WHERE seen.title_id IS NULL
)
SELECT genre_name, rank_in_genre, title, release_year, runtime_minutes, duration_band, vote_average
FROM ranked
WHERE rank_in_genre <= 3
ORDER BY affinity DESC, rank_in_genre, title;
