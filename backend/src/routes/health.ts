import { Router } from "express";
import { checkConnection } from "../db/pool";

const router = Router();

// GET /api/health
router.get("/", async (_req, res) => {
  const dbConnected = await checkConnection();
  const dbName = process.env.DB_NAME || "queryflix";

  res.status(dbConnected ? 200 : 503).json({
    api: "running",
    mysqlConnected: dbConnected,
    database: dbName,
    timestamp: new Date().toISOString(),
  });
});

export default router;
