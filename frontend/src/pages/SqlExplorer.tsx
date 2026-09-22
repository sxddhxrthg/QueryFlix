import { useEffect, useState } from "react";
import { api } from "../services/api";
import type { QuerySummary, QueryDetail, QueryResult } from "../services/api";

export default function SqlExplorer() {
  const [queries, setQueries] = useState<QuerySummary[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<QueryDetail | null>(null);
  const [result, setResult] = useState<QueryResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [running, setRunning] = useState(false);

  useEffect(() => {
    api.queries().then((qs) => {
      setQueries(qs);
      if (qs.length) setSelectedId(qs[0].id);
    });
  }, []);

  useEffect(() => {
    if (selectedId == null) return;
    setResult(null);
    setError(null);
    api.queryDetail(selectedId).then(setDetail).catch((err) => setError(err.message));
  }, [selectedId]);

  const execute = async () => {
    if (selectedId == null) return;
    setRunning(true);
    setError(null);
    try {
      const res = await api.queryResults(selectedId);
      setResult(res);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setRunning(false);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Query Execution</h1>
        <p className="page-subtitle">
          Read-only: only the 15 predefined SELECT queries below can be run from here.
        </p>
      </div>

      <div className="grid-2" style={{ marginBottom: 20 }}>
        <div className="card">
          <h3 className="section-title">Choose a query</h3>
          <select
            className="input"
            value={selectedId ?? ""}
            onChange={(e) => setSelectedId(Number(e.target.value))}
          >
            {queries.map((q) => (
              <option key={q.id} value={q.id}>
                Q{q.id}. {q.title}
              </option>
            ))}
          </select>
          {detail && (
            <div style={{ marginTop: 14 }}>
              <div className="query-q" style={{ marginBottom: 10 }}>{detail.businessQuestion}</div>
              <span className="badge">{detail.technique}</span>
            </div>
          )}
          <button className="btn" style={{ marginTop: 16 }} onClick={execute} disabled={running}>
            {running ? "Executing\u2026" : "Execute Query"}
          </button>
        </div>

        <div className="card">
          <h3 className="section-title">SQL Query</h3>
          {detail ? <pre className="sql-block">{detail.sql}</pre> : <div className="loading-dim">Loading\u2026</div>}
        </div>
      </div>

      <div className="card">
        <h3 className="section-title">Query Result</h3>
        {error && <div className="error-box">{error}</div>}
        {!error && !result && <div className="loading-dim">Run the query to see results here.</div>}
        {result && (
          <>
            <div className="loading-dim" style={{ padding: 0, marginBottom: 10 }}>
              {result.rowCount} rows returned in {result.executionTimeMs}ms
            </div>
            <ResultTable rows={result.results} />
          </>
        )}
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
