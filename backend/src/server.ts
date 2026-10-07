import express from "express";
import cors from "cors";
import dotenv from "dotenv";

import healthRouter from "./routes/health";
import statsRouter from "./routes/stats";
import titlesRouter from "./routes/titles";
import dimensionsRouter from "./routes/dimensions";
import queriesRouter from "./routes/queries";
import databaseRouter from "./routes/database";
import personalizationRouter from "./routes/personalization";

dotenv.config();

const app = express();
const PORT = Number(process.env.PORT) || 4000;
const CORS_ORIGIN = process.env.CORS_ORIGIN || "http://localhost:5173";

app.use(cors({ origin: CORS_ORIGIN }));
app.use(express.json());

app.use("/api/health", healthRouter);
app.use("/api/stats", statsRouter);
app.use("/api/titles", titlesRouter);
app.use("/api", dimensionsRouter); // exposes /api/genres, /api/countries, /api/cast, /api/yearly-trends
app.use("/api/queries", queriesRouter);
app.use("/api/database", databaseRouter);
app.use("/api/personalization", personalizationRouter);

// Structured 404
app.use((req, res) => {
  res.status(404).json({ error: "Not found", path: req.originalUrl });
});

// Structured error handler - the app must not crash on a single bad request
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error("Unhandled error:", err);
  res.status(500).json({ error: "Internal server error", detail: err.message });
});

app.listen(PORT, () => {
  console.log(`QueryFlix API listening on http://localhost:${PORT}`);
});
