import { Router } from "express";
import pool from "../db/pool";

const router = Router();

// GET /api/titles?search=&type=&country=&genre=&director=&cast=&year=&page=&limit=
router.get("/", async (req, res) => {
  try {
    const { search, type, country, genre, director, cast, year } = req.query;
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
    const offset = (page - 1) * limit;

    const where: string[] = [];
    const params: any[] = [];

    if (search) {
      where.push("title LIKE ?");
      params.push(`%${search}%`);
    }
    if (type) {
      where.push("type = ?");
      params.push(type);
    }
    if (country) {
      where.push("country LIKE ?");
      params.push(`%${country}%`);
    }
    if (genre) {
      where.push("genres LIKE ?");
      params.push(`%${genre}%`);
    }
    if (director) {
      where.push("director LIKE ?");
      params.push(`%${director}%`);
    }
    if (cast) {
      where.push("cast_members LIKE ?");
      params.push(`%${cast}%`);
    }
    if (year) {
      where.push("release_year = ?");
      params.push(Number(year));
    }

    const whereClause = where.length ? `WHERE ${where.join(" AND ")}` : "";

    const [countRows]: any = await pool.query(
      `SELECT COUNT(*) AS total FROM netflix ${whereClause}`,
      params
    );
    const total = countRows[0].total;

    const [rows]: any = await pool.query(
      `SELECT show_id, type, title, release_year, vote_average, popularity, genres, country
       FROM netflix ${whereClause}
       ORDER BY popularity DESC
       LIMIT ? OFFSET ?`,
      [...params, limit, offset]
    );

    res.json({ total, page, limit, results: rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Search failed", detail: (err as Error).message });
  }
});

// GET /api/titles/:id
router.get("/:id", async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: "Invalid title id" });
    }
    // duration comes from the TMDB enrichment view (NULL until runtimes are fetched)
    const [rows]: any = await pool.query(
      `SELECT n.*, vr.runtime_minutes, vr.seasons, vr.episodes, vr.episode_runtime_minutes
       FROM netflix n
       LEFT JOIN v_title_runtime vr ON vr.title_id = n.show_id
       WHERE n.show_id = ?`,
      [id]
    );
    if (!rows.length) {
      return res.status(404).json({ error: "Title not found" });
    }
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to fetch title", detail: (err as Error).message });
  }
});

export default router;
