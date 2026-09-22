import { Router } from "express";
import pool from "../db/pool";

const router = Router();

// GET /api/stats - summary cards for the dashboard
router.get("/", async (_req, res) => {
  try {
    const [[totals]]: any = await pool.query(
      `SELECT
         COUNT(*) AS total_titles,
         SUM(CASE WHEN type = 'Movie' THEN 1 ELSE 0 END) AS movies,
         SUM(CASE WHEN type = 'TV Show' THEN 1 ELSE 0 END) AS tv_shows,
         ROUND(AVG(vote_average), 2) AS avg_rating
       FROM netflix`
    );

    const [[genreCount]]: any = await pool.query(
      `SELECT COUNT(DISTINCT TRIM(jt.genre)) AS genre_count
       FROM netflix,
            JSON_TABLE(
               CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(genres, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
               '$[*]' COLUMNS (genre VARCHAR(100) PATH '$')
            ) AS jt
       WHERE genres IS NOT NULL`
    );

    const [[countryCount]]: any = await pool.query(
      `SELECT COUNT(DISTINCT TRIM(jt.country_val)) AS country_count
       FROM netflix,
            JSON_TABLE(
               CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(netflix.country, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
               '$[*]' COLUMNS (country_val VARCHAR(100) PATH '$')
            ) AS jt
       WHERE netflix.country IS NOT NULL`
    );

    res.json({
      totalTitles: totals.total_titles,
      movies: totals.movies,
      tvShows: totals.tv_shows,
      avgRating: totals.avg_rating,
      genreCount: genreCount.genre_count,
      countryCount: countryCount.country_count,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to compute stats", detail: (err as Error).message });
  }
});

export default router;
