import { Router } from "express";
import pool from "../db/pool";

const router = Router();

const DB_NAME = process.env.DB_NAME || "queryflix";

// Only these tables are exposed for inspection - never accept an arbitrary
// table name from the client without checking it against this allowlist,
// since it gets interpolated into DESCRIBE/SELECT statements below.
const ALLOWED_TABLES = ["netflix"];

// GET /api/database/tables - list tables with row counts
router.get("/tables", async (_req, res) => {
  try {
    const [tables]: any = await pool.query(
      `SELECT TABLE_NAME AS name, TABLE_ROWS AS approx_row_count
       FROM information_schema.tables
       WHERE table_schema = ?`,
      [DB_NAME]
    );

    const withCounts = await Promise.all(
      tables.map(async (t: any) => {
        if (!ALLOWED_TABLES.includes(t.name)) return t;
        const [[{ exact }]]: any = await pool.query(
          `SELECT COUNT(*) AS exact FROM \`${t.name}\``
        );
        return { ...t, exact_row_count: exact };
      })
    );

    res.json(withCounts);
  } catch (err) {
    res.status(500).json({ error: "Failed to list tables", detail: (err as Error).message });
  }
});

// GET /api/database/tables/:table/schema - column definitions
router.get("/tables/:table/schema", async (req, res) => {
  const table = req.params.table;
  if (!ALLOWED_TABLES.includes(table)) {
    return res.status(400).json({ error: "Table not exposed for inspection" });
  }
  try {
    const [columns]: any = await pool.query(`DESCRIBE \`${table}\``);
    res.json(columns);
  } catch (err) {
    res.status(500).json({ error: "Failed to describe table", detail: (err as Error).message });
  }
});

// GET /api/database/tables/:table - sample rows
router.get("/tables/:table", async (req, res) => {
  const table = req.params.table;
  if (!ALLOWED_TABLES.includes(table)) {
    return res.status(400).json({ error: "Table not exposed for inspection" });
  }
  const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
  try {
    const [rows]: any = await pool.query(`SELECT * FROM \`${table}\` LIMIT ?`, [limit]);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch rows", detail: (err as Error).message });
  }
});

export default router;
