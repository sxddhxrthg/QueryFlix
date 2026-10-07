import { useEffect, useState } from "react";
import { api } from "../services/api";
import type { MappingSummary } from "../services/api";
import { HorizontalBarChart } from "../components/Charts";

const STATUS_NOTES: Record<string, string> = {
  EXACT: "Identical cleaned title and same release year",
  NORMALIZED: "Equal after normalisation (case, punctuation, accents, a.k.a. titles), same year",
  YEAR_MATCH: "Normalised title equal, release year off by one",
  LINK_ID: "No title match; MovieLens links.csv tmdbId equals the Netflix source_id",
  AMBIGUOUS: "Several same-name candidates and nothing to break the tie",
  UNMATCHED: "Kept, not deleted — mostly films released before 2010",
};

export default function Mapping() {
  const [data, setData] = useState<MappingSummary | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.mapping().then(setData).catch((err) => setError(err.message));
  }, []);

  if (error) return <div className="error-box">Couldn't load the mapping layer: {error}</div>;
  if (!data) return <div className="loading-dim">Loading mapping…</div>;

  const t = data.totals;
  const chart = data.byStatus.map((s) => ({ status: s.match_status, movies: Number(s.movielens_movies) }));

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Title Mapping Layer</h1>
        <p className="page-subtitle">
          Which Netflix titles correspond to the movies MovieLens users rated? One mapping row per MovieLens movie.
        </p>
      </div>

      <div className="stat-grid">
        <Stat label="MovieLens users" value={t.users} />
        <Stat label="MovieLens movies" value={t.movielens_movies} />
        <Stat label="Ratings" value={t.ratings} />
        <Stat label="Mapped to Netflix" value={t.mapped_movies} accent />
        <Stat label="Ratings on Netflix titles" value={t.ratings_on_netflix_titles} />
      </div>

      <div className="grid-2">
        <div className="card">
          <h3 className="section-title">Match status</h3>
          <table>
            <thead>
              <tr>
                <th>Status</th>
                <th>Movies</th>
                <th>Confidence</th>
                <th>Rule</th>
              </tr>
            </thead>
            <tbody>
              {data.byStatus.map((s) => (
                <tr key={s.match_status}>
                  <td><span className="badge">{s.match_status}</span></td>
                  <td>{Number(s.movielens_movies).toLocaleString()}</td>
                  <td>{s.avg_confidence}</td>
                  <td style={{ color: "var(--text-dim)", fontSize: 12.5 }}>{STATUS_NOTES[s.match_status]}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="card">
          <h3 className="section-title">Movies per status</h3>
          <HorizontalBarChart data={chart} dataKey="movies" labelKey="status" />
        </div>
      </div>

      <div className="card" style={{ marginTop: 20 }}>
        <h3 className="section-title">Matches that needed more than an exact comparison</h3>
        <div style={{ overflowX: "auto" }}>
          <table>
            <thead>
              <tr>
                <th>MovieLens title</th>
                <th>Netflix title</th>
                <th>Year</th>
                <th>Status</th>
                <th>Rule that fired</th>
              </tr>
            </thead>
            <tbody>
              {data.examples.map((e, i) => (
                <tr key={i}>
                  <td>{String(e.movielens_title)}</td>
                  <td>{String(e.netflix_title ?? "—")}</td>
                  <td>{String(e.release_year ?? "—")}</td>
                  <td>{String(e.match_status)}</td>
                  <td style={{ color: "var(--text-dim)", fontSize: 12.5 }}>{String(e.match_method)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value, accent }: { label: string; value: number; accent?: boolean }) {
  return (
    <div className="stat-card">
      <div className="stat-label">{label}</div>
      <div className={`stat-value${accent ? " accent" : ""}`}>{Number(value).toLocaleString()}</div>
    </div>
  );
}
