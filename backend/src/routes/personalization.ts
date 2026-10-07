import { Router } from "express";
import pool from "../db/pool";
import { getQueryById } from "../queries/registry";

const router = Router();

// GET /api/personalization/users - users with enough history to demo
router.get("/users", async (_req, res) => {
  try {
    const [rows]: any = await pool.query(
      `SELECT r.user_id,
              COUNT(*) AS n_ratings,
              SUM(s.title_id IS NOT NULL) AS n_ratings_on_netflix_titles,
              ROUND(AVG(r.rating), 2) AS mean_rating
       FROM ratings r
       JOIN title_source_mapping s ON s.movielens_movie_id = r.movielens_movie_id
       GROUP BY r.user_id
       ORDER BY n_ratings_on_netflix_titles DESC
       LIMIT 40`
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: "Failed to list users", detail: (err as Error).message });
  }
});

// GET /api/personalization/mapping - how MovieLens movies were matched
router.get("/mapping", async (_req, res) => {
  try {
    const [byStatus]: any = await pool.query(
      `SELECT match_status, COUNT(*) AS movielens_movies,
              SUM(link_verified = 1) AS confirmed_by_links_csv,
              ROUND(AVG(match_confidence), 2) AS avg_confidence
       FROM title_source_mapping
       GROUP BY match_status
       ORDER BY FIELD(match_status,'EXACT','NORMALIZED','YEAR_MATCH','LINK_ID','AMBIGUOUS','UNMATCHED')`
    );
    const [examples]: any = await pool.query(
      `SELECT movielens_title, netflix_title, release_year, match_status, match_method, match_confidence
       FROM (
         SELECT m.raw_title AS movielens_title, t.title AS netflix_title, t.release_year,
                s.match_status, s.match_method, s.match_confidence,
                ROW_NUMBER() OVER (PARTITION BY s.match_status ORDER BY m.raw_title) AS rn
         FROM title_source_mapping s
         JOIN movielens_movies m ON m.movielens_movie_id = s.movielens_movie_id
         LEFT JOIN titles t ON t.title_id = s.title_id
         WHERE s.match_status IN ('NORMALIZED','YEAR_MATCH','LINK_ID')
            OR s.match_method LIKE 'rejected%'
       ) x
       WHERE rn <= 5
       ORDER BY FIELD(match_status,'NORMALIZED','YEAR_MATCH','LINK_ID','UNMATCHED'), rn`
    );
    const [[totals]]: any = await pool.query(
      `SELECT (SELECT COUNT(*) FROM users) AS users,
              (SELECT COUNT(*) FROM movielens_movies) AS movielens_movies,
              (SELECT COUNT(*) FROM ratings) AS ratings,
              (SELECT COUNT(*) FROM title_source_mapping WHERE title_id IS NOT NULL) AS mapped_movies,
              (SELECT COUNT(*) FROM ratings r JOIN title_source_mapping s USING (movielens_movie_id)
                 WHERE s.title_id IS NOT NULL) AS ratings_on_netflix_titles,
              (SELECT COUNT(*) FROM tmdb_runtime WHERE fetch_status = 'OK') AS runtimes_loaded`
    );
    res.json({ totals, byStatus, examples });
  } catch (err) {
    res.status(500).json({
      error: "Mapping layer not available - run database/import.sh",
      detail: (err as Error).message,
    });
  }
});

// GET /api/personalization/:userId - genre profile (Q23) + duration profile (Q33)
//   + recommendations (Q30) + duration-aware picks (Q36)
router.get("/:userId", async (req, res) => {
  const userId = Number(req.params.userId);
  if (!Number.isInteger(userId) || userId <= 0) {
    return res.status(400).json({ error: "userId must be a positive integer" });
  }
  const profileQ = getQueryById(23)!;
  const recQ = getQueryById(30)!;
  const durationQ = getQueryById(33)!;
  const durationPicksQ = getQueryById(36)!;
  const conn = await pool.getConnection();
  try {
    const [[exists]]: any = await conn.query("SELECT COUNT(*) AS n FROM users WHERE user_id = ?", [userId]);
    if (!exists.n) return res.status(404).json({ error: `MovieLens user ${userId} not found (valid: 1-610)` });
    await conn.query("SET @user_id = ?", [userId]);
    const started = process.hrtime.bigint();
    const [profile]: any = await conn.query(profileQ.sql);
    const [durationProfile]: any = await conn.query(durationQ.sql);
    const [recommendations]: any = await conn.query(recQ.sql);
    const [durationPicks]: any = await conn.query(durationPicksQ.sql);
    const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
    res.json({
      userId,
      // mirrors the `w` CTE in Q30 (database/queries_movielens.sql)
      weights: { genre: 0.35, collaborative: 0.25, duration: 0.15, quality: 0.15, popularity: 0.1 },
      executionTimeMs: Math.round(elapsedMs),
      profile,
      durationProfile,
      durationAvailable: durationProfile.length > 0,
      recommendations,
      durationPicks,
    });
  } catch (err) {
    res.status(500).json({ error: "Personalization failed", detail: (err as Error).message });
  } finally {
    conn.release();
  }
});

export default router;
