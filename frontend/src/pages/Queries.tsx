import { useEffect, useState } from "react";
import { api } from "../services/api";
import type { QuerySummary, QueryResult } from "../services/api";

export default function Queries() {
  const [queries, setQueries] = useState<QuerySummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<Record<number, QueryResult>>({});
  const [loadingId, setLoadingId] = useState<number | null>(null);
  const [errors, setErrors] = useState<Record<number, string>>({});
  const [userId, setUserId] = useState<number>(567);

  useEffect(() => {
    api.queries().then(setQueries).catch((err) => setError(err.message));
  }, []);

  const runQuery = async (id: number) => {
    setLoadingId(id);
    setErrors((e) => ({ ...e, [id]: "" }));
    try {
      const q = queries.find((x) => x.id === id);
      const res = await api.queryResults(id, q?.usesUser ? userId : undefined);
      setResults((r) => ({ ...r, [id]: res }));
    } catch (err: any) {
      setErrors((e) => ({ ...e, [id]: err.message }));
    } finally {
      setLoadingId(null);
    }
  };

  if (error) return <div className="error-box">Couldn't load queries: {error}</div>;

  const renderCard = (q: QuerySummary) => (
    <div key={q.id} className="query-card">
      <div className="query-card-head">
        <div>
          <div className="query-num">
            Q{q.id}
            {q.usesUser && <span className="badge" style={{ marginLeft: 8 }}>user {userId}</span>}
          </div>
          <div className="query-title">{q.title}</div>
        </div>
        <button className="btn" onClick={() => runQuery(q.id)} disabled={loadingId === q.id}>
          {loadingId === q.id ? "Running…" : "Execute"}
        </button>
      </div>
      <div className="query-q">{q.businessQuestion}</div>
      <div className="query-technique">{q.technique}</div>

      {errors[q.id] && <div className="error-box" style={{ marginTop: 12 }}>{errors[q.id]}</div>}

      {results[q.id] && (
        <div style={{ marginTop: 14 }}>
          <div className="loading-dim" style={{ padding: 0, marginBottom: 8 }}>
            {results[q.id].rowCount} rows · {results[q.id].executionTimeMs}ms
            {results[q.id].userId ? ` · user ${results[q.id].userId}` : ""}
          </div>
          <ResultTable rows={results[q.id].results} />
        </div>
      )}
    </div>
  );

  const netflixQs = queries.filter((q) => q.layer !== "movielens");
  const movielensQs = queries.filter((q) => q.layer === "movielens");

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">{queries.length || 36} Business Questions</h1>
        <p className="page-subtitle">
          Every result executes live against the MySQL database — nothing here is hard-coded.
        </p>
      </div>

      <h2 className="section-title" style={{ marginTop: 8 }}>
        Layer 1 · Netflix catalog intelligence (Q1–Q15)
      </h2>
      <div className="query-list">{netflixQs.map(renderCard)}</div>

      {movielensQs.length > 0 && (
        <>
          <h2 className="section-title" style={{ marginTop: 36 }}>
            Layer 2 · User behaviour, ranking functions, duration &amp; personalization (Q16–Q36)
          </h2>
          <div className="card" style={{ display: "flex", gap: 12, alignItems: "center", marginBottom: 14 }}>
            <label htmlFor="uid" style={{ fontSize: 13.5, color: "var(--text-dim)", whiteSpace: "nowrap" }}>
              MovieLens user for Q23, Q24, Q29, Q30, Q33, Q36
            </label>
            <input
              id="uid"
              className="input"
              style={{ maxWidth: 120 }}
              type="number"
              min={1}
              max={610}
              value={userId}
              onChange={(e) => setUserId(Math.max(1, Math.min(610, Number(e.target.value) || 1)))}
            />
            <span style={{ fontSize: 12.5, color: "var(--text-dim)" }}>
              MovieLens ratings are external preference data, not Netflix user ratings.
            </span>
          </div>
          <div className="query-list">{movielensQs.map(renderCard)}</div>
        </>
      )}
    </div>
  );
}

function ResultTable({ rows }: { rows: Record<string, unknown>[] }) {
  if (!rows.length) return <div className="loading-dim">No rows returned.</div>;
  const cols = Object.keys(rows[0]);
  return (
    <div style={{ overflowX: "auto" }}>
      <table>
        <thead>
          <tr>
            {cols.map((c) => (
              <th key={c}>{c}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i}>
              {cols.map((c) => (
                <td key={c}>{String(row[c] ?? "—")}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
