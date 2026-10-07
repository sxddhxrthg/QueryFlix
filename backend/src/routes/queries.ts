import { Router } from "express";
import pool from "../db/pool";
import { QUERIES, getQueryById } from "../queries/registry";

const router = Router();

// GET /api/queries - list all 36 business questions (metadata only, no execution)
router.get("/", (_req, res) => {
  res.json(
    QUERIES.map(({ id, layer, usesUser, slug, title, businessQuestion, explanation, technique }) => ({
      id,
      layer,
      usesUser,
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

export const DEFAULT_USER_ID = 567;

// GET /api/queries/:id/results?userId=567 - actually execute the query against MySQL.
// User-specific queries (Q23, Q24, Q29, Q30) read @user_id, which is set on the
// same pooled connection first; the id is validated as an integer (no SQL
// is ever built from client text).
router.get("/:id/results", async (req, res) => {
  const q = getQueryById(Number(req.params.id));
  if (!q) return res.status(404).json({ error: "Query not found" });

  const userId = req.query.userId === undefined ? DEFAULT_USER_ID : Number(req.query.userId);
  if (q.usesUser && (!Number.isInteger(userId) || userId <= 0)) {
    return res.status(400).json({ error: "userId must be a positive integer" });
  }

  const conn = await pool.getConnection();
  const startedAt = process.hrtime.bigint();
  try {
    if (q.usesUser) await conn.query("SET @user_id = ?", [userId]);
    const [rows]: any = await conn.query(q.sql);
    const elapsedMs = Number(process.hrtime.bigint() - startedAt) / 1e6;
    res.json({
      id: q.id,
      title: q.title,
      userId: q.usesUser ? userId : undefined,
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
  } finally {
    conn.release();
  }
});

export default router;
