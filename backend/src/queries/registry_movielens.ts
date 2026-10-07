import type { QueryDef } from "./registry";

// Q16-Q36: MovieLens behaviour, ranking functions, duration and personalisation.
// Generated from database/queries_movielens.sql (keep the two in sync).
// Queries with usesUser = true read the session variable @user_id, which the
// route sets on the same connection (SET @user_id = ?) before executing.
export const MOVIELENS_QUERIES: QueryDef[] = [
  {
    id: 16,
    layer: "movielens",
    usesUser: false,
    slug: "top-rated-movielens",
    title: "Most highly rated movies (MovieLens)",
    businessQuestion: "Which movies do MovieLens users rate highest, once tiny samples are damped?",
    explanation: "Averages are shrunk toward the global mean (Bayesian average, m = 10) so a film with one 5-star rating cannot top the chart. Shows whether each film exists in the Netflix catalog.",
    technique: "View + Bayesian average + LEFT JOIN through mapping",
    sql: `SELECT m.raw_title AS movielens_title, st.n_ratings, st.avg_rating, st.bayes_rating,
       COALESCE(t.title, '— not in Netflix catalog') AS netflix_title
FROM v_movielens_movie_stats st
JOIN movielens_movies m          ON m.movielens_movie_id = st.movielens_movie_id
LEFT JOIN title_source_mapping s ON s.movielens_movie_id = st.movielens_movie_id
LEFT JOIN titles t               ON t.title_id = s.title_id
WHERE st.n_ratings >= 50
ORDER BY st.bayes_rating DESC
LIMIT 10`,
  },
  {
    id: 17,
    layer: "movielens",
    usesUser: false,
    slug: "most-rated",
    title: "Most-rated movies",
    businessQuestion: "Which movies attract the most ratings?",
    explanation: "Rating volume per movie with DENSE_RANK so ties share a rank.",
    technique: "DENSE_RANK() OVER",
    sql: `SELECT DENSE_RANK() OVER (ORDER BY st.n_ratings DESC) AS rnk,
       m.raw_title, st.n_ratings, st.avg_rating
FROM v_movielens_movie_stats st
JOIN movielens_movies m ON m.movielens_movie_id = st.movielens_movie_id
ORDER BY st.n_ratings DESC
LIMIT 10`,
  },
  {
    id: 18,
    layer: "movielens",
    usesUser: false,
    slug: "rating-by-genre",
    title: "Average rating by genre",
    businessQuestion: "How do users rate each genre on average?",
    explanation: "Pipe-separated MovieLens genres were decomposed into movielens_movie_genres at load time; ratings are joined and averaged per genre and ranked.",
    technique: "Normalised bridge table + RANK() OVER",
    sql: `SELECT mg.ml_genre,
       COUNT(*)                            AS n_ratings,
       COUNT(DISTINCT r.movielens_movie_id) AS n_movies,
       ROUND(AVG(r.rating), 3)             AS avg_rating,
       RANK() OVER (ORDER BY AVG(r.rating) DESC) AS rating_rank
FROM ratings r
JOIN movielens_movie_genres mg ON mg.movielens_movie_id = r.movielens_movie_id
GROUP BY mg.ml_genre
ORDER BY avg_rating DESC`,
  },
  {
    id: 19,
    layer: "movielens",
    usesUser: false,
    slug: "rating-distribution",
    title: "Rating distribution",
    businessQuestion: "How are the 0.5–5.0 star ratings distributed?",
    explanation: "Share of each rating value plus a running cumulative percentage.",
    technique: "SUM(COUNT(*)) OVER (ORDER BY ...) running total",
    sql: `SELECT rating,
       COUNT(*) AS n_ratings,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                    AS pct,
       ROUND(100 * SUM(COUNT(*)) OVER (ORDER BY rating) / SUM(COUNT(*)) OVER (), 2) AS cumulative_pct
FROM ratings
GROUP BY rating
ORDER BY rating`,
  },
  {
    id: 20,
    layer: "movielens",
    usesUser: false,
    slug: "ratings-per-movie",
    title: "Ratings per movie (long tail)",
    businessQuestion: "How concentrated is rating activity across movies?",
    explanation: "Movies bucketed by number of ratings; shows how few titles receive most of the ratings.",
    technique: "CASE bucketing + window percentage",
    sql: `SELECT bucket, COUNT(*) AS n_movies, SUM(n_ratings) AS ratings_in_bucket,
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
ORDER BY MIN(n_ratings)`,
  },
  {
    id: 21,
    layer: "movielens",
    usesUser: false,
    slug: "user-activity",
    title: "User activity segments",
    businessQuestion: "How active are users, and how do light and power users differ?",
    explanation: "Users split into quartiles by rating count with NTILE(4), with activity span from timestamps.",
    technique: "NTILE(4) OVER + DATEDIFF on timestamps",
    sql: `WITH activity AS (
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
ORDER BY quartile`,
  },
  {
    id: 22,
    layer: "movielens",
    usesUser: false,
    slug: "popular-genres-users",
    title: "Popular genres among users",
    businessQuestion: "Which genres have the most fans?",
    explanation: "A user counts as a genre fan if they rated 3+ films of it at 4.0 or above.",
    technique: "CTE + GROUP BY ... HAVING",
    sql: `WITH fan AS (
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
LIMIT 10`,
  },
  {
    id: 23,
    layer: "movielens",
    usesUser: true,
    slug: "user-profile",
    title: "User preference profile",
    businessQuestion: "What does this user like?",
    explanation: "v_user_genre_profile combines volume (how much of the genre they watch) and liking (their genre average vs their own mean) into a 0–1 affinity, in catalog genres via genre_crosswalk.",
    technique: "View with window functions + crosswalk + DENSE_RANK()",
    sql: `SELECT genre_name, n_rated, avg_rating, vs_user_mean, volume, liking, affinity,
       DENSE_RANK() OVER (ORDER BY affinity DESC) AS preference_rank   -- equal affinity = same place, no gaps
FROM v_user_genre_profile
WHERE user_id = @user_id
ORDER BY affinity DESC
LIMIT 8`,
  },
  {
    id: 24,
    layer: "movielens",
    usesUser: true,
    slug: "user-genre-top3",
    title: "Top 3 unseen films per favourite genre",
    businessQuestion: "For each of this user's top-3 genres, which 3 best-rated films haven't they seen?",
    explanation: "DENSE_RANK() OVER (PARTITION BY genre ORDER BY damped rating) restarts the numbering inside every genre; tied films share a place and no number is skipped.",
    technique: "DENSE_RANK() PARTITION BY + NOT EXISTS anti-join",
    sql: `WITH top_genres AS (
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
ORDER BY affinity DESC, rank_in_genre, raw_title`,
  },
  {
    id: 25,
    layer: "movielens",
    usesUser: false,
    slug: "catalog-with-activity",
    title: "Netflix titles with strong MovieLens activity",
    businessQuestion: "Which Netflix catalog titles are most rated by MovieLens users?",
    explanation: "Uses v_title_unified, which joins titles → title_source_mapping → rating stats.",
    technique: "Mapping-layer join (view)",
    sql: `SELECT title, release_year, match_status, ml_n_ratings, ml_avg_rating, netflix_vote_average
FROM v_title_unified
WHERE ml_n_ratings >= 20
ORDER BY ml_n_ratings DESC
LIMIT 10`,
  },
  {
    id: 26,
    layer: "movielens",
    usesUser: false,
    slug: "popular-and-active",
    title: "High Netflix popularity + high MovieLens activity",
    businessQuestion: "Which titles are hits on both sides?",
    explanation: "PERCENT_RANK on Netflix popularity and on MovieLens rating count; keeps titles in the top 20% of both.",
    technique: "PERCENT_RANK() OVER",
    sql: `WITH ranked AS (
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
LIMIT 10`,
  },
  {
    id: 27,
    layer: "movielens",
    usesUser: false,
    slug: "netflix-vs-movielens",
    title: "Netflix vote vs MovieLens rating",
    businessQuestion: "Do Netflix/TMDB voters and MovieLens users agree?",
    explanation: "MovieLens average rescaled ×2 to 0–10, compared with vote_average; Pearson correlation computed in plain SQL.",
    technique: "Statistical aggregation (Pearson r in SQL)",
    sql: `WITH pairs AS (
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
FROM pairs`,
  },
  {
    id: 28,
    layer: "movielens",
    usesUser: false,
    slug: "biggest-disagreements",
    title: "Largest rating disagreements",
    businessQuestion: "Where do the two audiences disagree most?",
    explanation: "Absolute difference between the two scores for titles with enough votes on both sides.",
    technique: "Derived columns + ABS ordering",
    sql: `SELECT title, release_year, netflix_vote_average, ml_avg_rating_10, ml_n_ratings,
       ROUND(ml_avg_rating_10 - netflix_vote_average, 2) AS diff,
       CASE WHEN ml_avg_rating_10 > netflix_vote_average
            THEN 'MovieLens users rate higher' ELSE 'Netflix/TMDB voters rate higher' END AS direction
FROM v_title_unified
WHERE ml_n_ratings >= 10 AND netflix_vote_count >= 100
ORDER BY ABS(ml_avg_rating_10 - netflix_vote_average) DESC
LIMIT 10`,
  },
  {
    id: 29,
    layer: "movielens",
    usesUser: true,
    slug: "candidate-pool",
    title: "Personalised candidate pool",
    businessQuestion: "How many Netflix titles could we recommend to this user?",
    explanation: "Netflix movies in the user's top-3 genres they haven't rated, split into titles with MovieLens evidence and Netflix-only titles (incl. 2019–2025).",
    technique: "CTE + anti-join (LEFT JOIN ... IS NULL)",
    sql: `WITH top_genres AS (
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
GROUP BY candidate_source`,
  },
  {
    id: 30,
    layer: "movielens",
    usesUser: true,
    slug: "hybrid-recommendations",
    title: "Hybrid recommendation score",
    businessQuestion: "What should this user watch next, and why?",
    explanation: "Transparent score = 0.35 genre match + 0.25 collaborative (30 most similar users) + 0.15 duration match + 0.15 quality + 0.10 popularity. Duration is neutral (0.5) when a title's runtime is unknown. SQL scoring rule, not an ML model.",
    technique: "Multi-CTE hybrid scoring: user similarity + genre + duration + popularity",
    sql: `WITH
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
LIMIT 10`,
  },
  {
    id: 31,
    layer: "movielens",
    usesUser: false,
    slug: "runtime-by-genre",
    title: "Movie length by genre",
    businessQuestion: "Which genres make the longest films?",
    explanation: "Runtime (from the TMDB enrichment table, joined by TMDB id) averaged per genre, with the share of 150+ minute films and a RANK by length.",
    technique: "Enrichment join + conditional AVG + RANK() OVER",
    sql: `SELECT g.genre_name,
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
ORDER BY length_rank`,
  },
  {
    id: 32,
    layer: "movielens",
    usesUser: false,
    slug: "length-vs-rating",
    title: "Does length affect ratings?",
    businessQuestion: "Do longer films get rated higher by Netflix/TMDB voters and by MovieLens users?",
    explanation: "Each audience is aggregated per duration band in its own CTE and the two are joined side by side (MovieLens rescaled ×2 to 0–10).",
    technique: "Two aggregating CTEs joined on a generated column (duration_band)",
    sql: `WITH ml AS (
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
ORDER BY FIELD(nf.duration_band, '< 90 min', '90-119 min', '120-149 min', '150+ min')`,
  },
  {
    id: 33,
    layer: "movielens",
    usesUser: true,
    slug: "user-duration-profile",
    title: "User duration preference",
    businessQuestion: "Does this user prefer short, standard or long films?",
    explanation: "v_user_duration_profile: volume + liking per length band, the same formula as the genre profile, with small-sample damping.",
    technique: "View with window functions + DENSE_RANK()",
    sql: `SELECT duration_band, n_rated, avg_minutes, avg_rating, vs_user_mean, volume, liking, affinity,
       DENSE_RANK() OVER (ORDER BY affinity DESC) AS preference_rank
FROM v_user_duration_profile
WHERE user_id = @user_id
ORDER BY FIELD(duration_band, '< 90 min', '90-119 min', '120-149 min', '150+ min')`,
  },
  {
    id: 34,
    layer: "movielens",
    usesUser: false,
    slug: "ranking-functions-compared",
    title: "ROW_NUMBER vs RANK vs DENSE_RANK",
    businessQuestion: "How do the three ranking functions treat ties?",
    explanation: "Same ordering, three functions. Three films tie at 8.5: RANK gives 1,1,1 then jumps to 4; DENSE_RANK gives 1,1,1 then 2; ROW_NUMBER numbers every row. Uses a named WINDOW clause.",
    technique: "ROW_NUMBER() · RANK() · DENSE_RANK() · WINDOW clause",
    sql: `SELECT title, release_year, vote_average,
       ROW_NUMBER() OVER (ORDER BY vote_average DESC, title) AS row_no,
       RANK()       OVER w AS rank_no,
       DENSE_RANK() OVER w AS dense_rank_no
FROM titles
WHERE type = 'Movie' AND vote_count >= 500
WINDOW w AS (ORDER BY vote_average DESC)
ORDER BY vote_average DESC, title
LIMIT 15`,
  },
  {
    id: 35,
    layer: "movielens",
    usesUser: false,
    slug: "top3-per-genre",
    title: "Top 3 titles in each of the 6 biggest genres",
    businessQuestion: "What are the best-rated titles inside each major genre?",
    explanation: "DENSE_RANK twice: genres ranked by size, then titles ranked inside each genre. A tie for a place shows every tied title.",
    technique: "Nested DENSE_RANK() with PARTITION BY",
    sql: `WITH genre_size AS (
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
ORDER BY size_rank, rank_in_genre, title`,
  },
  {
    id: 36,
    layer: "movielens",
    usesUser: true,
    slug: "duration-aware-picks",
    title: "Duration-aware picks",
    businessQuestion: "Which unseen Netflix movies match this user's favourite film length and genres?",
    explanation: "Takes the user's favourite length band (Q33) and top-3 genres (Q23), keeps unseen Netflix movies in that band, and ranks the top 3 per genre with DENSE_RANK.",
    technique: "Duration personalisation + DENSE_RANK() PARTITION BY",
    sql: `WITH fav_band AS (
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
ORDER BY affinity DESC, rank_in_genre, title`,
  },
];
