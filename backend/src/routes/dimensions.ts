import { Router } from "express";
import pool from "../db/pool";

const router = Router();

const unnestFragment = (col: string, alias: string) => `
  netflix,
     JSON_TABLE(
        CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(${col}, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
        '$[*]' COLUMNS (${alias} VARCHAR(150) PATH '$')
     ) AS jt
`;

// GET /api/genres - all genres with counts
router.get("/genres", async (_req, res) => {
  try {
    const [rows]: any = await pool.query(
      `SELECT TRIM(jt.genre) AS genre, COUNT(*) AS title_count
       FROM ${unnestFragment("genres", "genre")}
       WHERE genres IS NOT NULL
       GROUP BY TRIM(jt.genre)
       ORDER BY title_count DESC`
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch genres", detail: (err as Error).message });
  }
});

// GET /api/countries - all countries with counts
router.get("/countries", async (_req, res) => {
  try {
    const [rows]: any = await pool.query(
      `SELECT TRIM(jt.country_val) AS country, COUNT(*) AS title_count
       FROM netflix,
            JSON_TABLE(
               CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(netflix.country, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
               '$[*]' COLUMNS (country_val VARCHAR(100) PATH '$')
            ) AS jt
       WHERE netflix.country IS NOT NULL
       GROUP BY TRIM(jt.country_val)
       ORDER BY title_count DESC
       LIMIT 30`
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch countries", detail: (err as Error).message });
  }
});

// GET /api/cast - top credited cast members
router.get("/cast", async (_req, res) => {
  try {
    const [rows]: any = await pool.query(
      `SELECT TRIM(jt.actor) AS actor, COUNT(*) AS appearances
       FROM ${unnestFragment("cast_members", "actor")}
       WHERE cast_members IS NOT NULL AND jt.actor IS NOT NULL
       GROUP BY TRIM(jt.actor)
       ORDER BY appearances DESC
       LIMIT 30`
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch cast", detail: (err as Error).message });
  }
});

// GET /api/yearly-trends
router.get("/yearly-trends", async (_req, res) => {
  try {
    const [rows]: any = await pool.query(
      `SELECT EXTRACT(YEAR FROM date_added) AS year_added, COUNT(*) AS titles_added
       FROM netflix
       WHERE date_added IS NOT NULL
       GROUP BY year_added
       ORDER BY year_added`
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch yearly trends", detail: (err as Error).message });
  }
});

export default router;
