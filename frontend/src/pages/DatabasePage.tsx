import { useEffect, useState } from "react";
import { api } from "../services/api";
import type { TableInfo, ColumnInfo } from "../services/api";

export default function DatabasePage() {
  const [tables, setTables] = useState<TableInfo[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [columns, setColumns] = useState<ColumnInfo[]>([]);
  const [sample, setSample] = useState<Record<string, unknown>[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .tables()
      .then((t) => {
        setTables(t);
        if (t.length) setSelected(t[0].name);
      })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(() => {
    if (!selected) return;
    Promise.all([api.tableSchema(selected), api.tableSample(selected, 15)])
      .then(([cols, rows]) => {
        setColumns(cols);
        setSample(rows);
      })
      .catch((err) => setError(err.message));
  }, [selected]);

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Database</h1>
        <p className="page-subtitle">
          Live inspection of the <code>queryflix</code> MySQL database.
        </p>
      </div>

      {error && <div className="error-box">{error}</div>}

      <div className="card" style={{ marginBottom: 20 }}>
        <h3 className="section-title">Tables</h3>
        <table>
          <thead>
            <tr>
              <th>Table</th>
              <th>Row Count</th>
            </tr>
          </thead>
          <tbody>
            {tables.map((t) => (
              <tr
                key={t.name}
                className="title-row"
                onClick={() => setSelected(t.name)}
                style={{ background: selected === t.name ? "rgba(224,38,63,0.06)" : undefined }}
              >
                <td>{t.name}</td>
                <td>{(t.exact_row_count ?? t.approx_row_count).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {selected && (
        <>
          <div className="card" style={{ marginBottom: 20 }}>
            <h3 className="section-title">Schema: {selected}</h3>
            <table>
              <thead>
                <tr>
                  <th>Column</th>
                  <th>Type</th>
                  <th>Nullable</th>
                  <th>Key</th>
                </tr>
              </thead>
              <tbody>
                {columns.map((c) => (
                  <tr key={c.Field}>
                    <td>{c.Field}</td>
                    <td>
                      <code>{c.Type}</code>
                    </td>
                    <td>{c.Null}</td>
                    <td>{c.Key || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="card">
            <h3 className="section-title">Sample rows</h3>
            <div style={{ overflowX: "auto" }}>
              <table>
                <thead>
                  <tr>
                    {sample[0] &&
                      Object.keys(sample[0])
                        .slice(0, 8)
                        .map((k) => <th key={k}>{k}</th>)}
                  </tr>
                </thead>
                <tbody>
                  {sample.map((row, i) => (
                    <tr key={i}>
                      {Object.keys(row)
                        .slice(0, 8)
                        .map((k) => (
                          <td key={k}>{String((row as any)[k] ?? "—").slice(0, 60)}</td>
                        ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
