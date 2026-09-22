import { Router } from "express";
import pool from "../db/pool";
import { QUERIES, getQueryById } from "../queries/registry";

const router = Router();

// GET /api/queries - list all 15 business questions (metadata only, no execution)
router.get("/", (_req, res) => {
  res.json(
    QUERIES.map(({ id, slug, title, businessQuestion, explanation, technique }) => ({
      id,
      slug,
      title,
      businessQuestion,
      explanation,
      technique,
    }))
  );
});

// GET /api/queries/:id - metadata + raw SQL for one question
router.get("/:id", (req, res) => {
  const q = getQueryById(Number(req.params.id));
  if (!q) return res.status(404).json({ error: "Query not found" });
  res.json(q);
});

// GET /api/queries/:id/results - actually execute the query against MySQL
router.get("/:id/results", async (req, res) => {
  const q = getQueryById(Number(req.params.id));
  if (!q) return res.status(404).json({ error: "Query not found" });

  const startedAt = process.hrtime.bigint();
  try {
    const [rows]: any = await pool.query(q.sql);
    const elapsedMs = Number(process.hrtime.bigint() - startedAt) / 1e6;
    res.json({
      id: q.id,
      title: q.title,
      rowCount: rows.length,
      executionTimeMs: Math.round(elapsedMs * 100) / 100,
      results: rows,
    });
  } catch (err) {
    console.error(`Query ${q.id} execution failed:`, err);
    res.status(500).json({
      error: "Query execution failed",
      detail: (err as Error).message,
    });
  }
});

export default router;
