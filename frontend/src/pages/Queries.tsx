import { useEffect, useState } from "react";
import { api } from "../services/api";
import type { QuerySummary, QueryResult } from "../services/api";

export default function Queries() {
  const [queries, setQueries] = useState<QuerySummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<Record<number, QueryResult>>({});
  const [loadingId, setLoadingId] = useState<number | null>(null);
  const [errors, setErrors] = useState<Record<number, string>>({});

  useEffect(() => {
    api.queries().then(setQueries).catch((err) => setError(err.message));
  }, []);

  const runQuery = async (id: number) => {
    setLoadingId(id);
    setErrors((e) => ({ ...e, [id]: "" }));
    try {
      const res = await api.queryResults(id);
      setResults((r) => ({ ...r, [id]: res }));
    } catch (err: any) {
      setErrors((e) => ({ ...e, [id]: err.message }));
    } finally {
      setLoadingId(null);
    }
  };

  if (error) return <div className="error-box">Couldn't load queries: {error}</div>;

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">15 Business Questions</h1>
        <p className="page-subtitle">
          Every result executes live against the MySQL database \u2014 nothing here is hard-coded.
        </p>
      </div>

      <div className="query-list">
        {queries.map((q) => (
          <div key={q.id} className="query-card">
            <div className="query-card-head">
              <div>
                <div className="query-num">Q{q.id}</div>
                <div className="query-title">{q.title}</div>
              </div>
              <button className="btn" onClick={() => runQuery(q.id)} disabled={loadingId === q.id}>
                {loadingId === q.id ? "Running\u2026" : "Execute"}
              </button>
            </div>
            <div className="query-q">{q.businessQuestion}</div>
            <div className="query-technique">{q.technique}</div>

            {errors[q.id] && <div className="error-box" style={{ marginTop: 12 }}>{errors[q.id]}</div>}

            {results[q.id] && (
              <div style={{ marginTop: 14 }}>
                <div className="loading-dim" style={{ padding: 0, marginBottom: 8 }}>
                  {results[q.id].rowCount} rows \u00b7 {results[q.id].executionTimeMs}ms
                </div>
                <ResultTable rows={results[q.id].results} />
              </div>
            )}
          </div>
        ))}
      </div>
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
                <td key={c}>{String(row[c] ?? "\u2014")}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
