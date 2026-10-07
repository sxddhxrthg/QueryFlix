import { useEffect, useState } from "react";
import { api } from "../services/api";
import type { DemoUser, PersonalizationResult } from "../services/api";
import { HorizontalBarChart } from "../components/Charts";

export default function Personalization() {
  const [users, setUsers] = useState<DemoUser[]>([]);
  const [userId, setUserId] = useState<number>(567);
  const [data, setData] = useState<PersonalizationResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = (id: number) => {
    setLoading(true);
    setError(null);
    api
      .personalization(id)
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    api.demoUsers().then(setUsers).catch(() => setUsers([]));
    load(567);
  }, []);

  const profileChart = (data?.profile ?? []).map((p) => ({
    genre: p.genre_name,
    affinity: Number(p.affinity),
  }));
  const durationChart = (data?.durationProfile ?? []).map((d) => ({
    band: d.duration_band,
    affinity: Number(d.affinity),
  }));
  // favourite band = DENSE_RANK 1 in Q33
  const favBand = (data?.durationProfile ?? []).find((d) => Number(d.preference_rank) === 1);

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Personalization</h1>
        <p className="page-subtitle">
          SQL-driven hybrid recommendations: a MovieLens user's taste applied to the Netflix catalog.
        </p>
      </div>

      <div className="card" style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
        <label htmlFor="user" style={{ fontSize: 13.5, color: "var(--text-dim)" }}>MovieLens user</label>
        <input
          id="user"
          className="input"
          type="number"
          min={1}
          max={610}
          style={{ maxWidth: 110 }}
          value={userId}
          onChange={(e) => setUserId(Number(e.target.value))}
          onKeyDown={(e) => e.key === "Enter" && load(userId)}
        />
        <button className="btn" onClick={() => load(userId)} disabled={loading}>
          {loading ? "Scoring…" : "Recommend"}
        </button>
        {users.length > 0 && (
          <select
            className="input"
            style={{ maxWidth: 280 }}
            value=""
            onChange={(e) => {
              const id = Number(e.target.value);
              setUserId(id);
              load(id);
            }}
          >
            <option value="">Pick a user with rich history…</option>
            {users.map((u) => (
              <option key={u.user_id} value={u.user_id}>
                User {u.user_id} · {u.n_ratings} ratings · {u.n_ratings_on_netflix_titles} on Netflix titles
              </option>
            ))}
          </select>
        )}
      </div>

      {error && <div className="error-box" style={{ marginTop: 16 }}>{error}</div>}

      {data && (
        <>
          <div className="grid-2" style={{ marginTop: 20 }}>
            <div className="card">
              <h3 className="section-title">User {data.userId}: genre affinity (0–1)</h3>
              <HorizontalBarChart data={profileChart} dataKey="affinity" labelKey="genre" />
            </div>
            <div className="card">
              <h3 className="section-title">How the score is built</h3>
              <table>
                <tbody>
                  <tr><td>Genre match</td><td>{data.weights.genre}</td><td className="dim">avg affinity of the title's genres</td></tr>
                  <tr><td>Collaborative</td><td>{data.weights.collaborative}</td><td className="dim">ratings by the 30 most similar users</td></tr>
                  <tr><td>Duration match</td><td>{data.weights.duration}</td><td className="dim">affinity for the title's length band (0.5 if unknown)</td></tr>
                  <tr><td>Quality</td><td>{data.weights.quality}</td><td className="dim">MovieLens damped mean, else Netflix vote</td></tr>
                  <tr><td>Popularity</td><td>{data.weights.popularity}</td><td className="dim">log-scaled Netflix popularity</td></tr>
                </tbody>
              </table>
              <h3 className="section-title" style={{ marginTop: 20 }}>
                Preferred film length{favBand ? `: ${favBand.duration_band}` : ""}
              </h3>
              {favBand && (
                <p style={{ fontSize: 12.5, color: "var(--text-dim)", margin: "0 0 8px" }}>
                  {favBand.n_rated} films rated in this band (avg {favBand.avg_minutes} min). Affinity per band:
                </p>
              )}
              {data.durationAvailable ? (
                <HorizontalBarChart data={durationChart} dataKey="affinity" labelKey="band" />
              ) : (
                <p style={{ fontSize: 12.5, color: "var(--text-dim)" }}>
                  Runtimes not loaded yet — run database/enrichment/fetch_tmdb_runtime.py, then database/import.sh.
                  Until then duration counts as neutral (0.5) for every title.
                </p>
              )}
              <p style={{ fontSize: 12.5, color: "var(--text-dim)", marginTop: 12 }}>
                A transparent SQL scoring rule (Q30), not a trained ML model. Computed live in {data.executionTimeMs} ms.
              </p>
            </div>
          </div>

          <div className="card" style={{ marginTop: 20 }}>
            <h3 className="section-title">Top 10 Netflix movies for user {data.userId}</h3>
            <div style={{ overflowX: "auto" }}>
              <table>
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Title</th>
                    <th>Year</th>
                    <th>Length</th>
                    <th>Score</th>
                    <th>Genre</th>
                    <th>Collab.</th>
                    <th>Duration</th>
                    <th>Quality</th>
                    <th>Popularity</th>
                    <th>Because you like</th>
                  </tr>
                </thead>
                <tbody>
                  {data.recommendations.map((r) => (
                    <tr key={r.rec_rank}>
                      <td>{r.rec_rank}</td>
                      <td>{r.title}</td>
                      <td>{r.release_year}</td>
                      <td>{r.runtime_minutes ? `${r.runtime_minutes} min` : "—"}</td>
                      <td style={{ color: "var(--accent)", fontWeight: 650 }}>{Number(r.recommendation_score).toFixed(3)}</td>
                      <td>{r.genre_match}</td>
                      <td>{r.collaborative}</td>
                      <td>{r.duration_match}</td>
                      <td>{r.quality}</td>
                      <td>{r.popularity}</td>
                      <td style={{ color: "var(--text-dim)", fontSize: 12.5 }}>{r.because_you_like ?? "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
          {data.durationPicks.length > 0 && (
            <div className="card" style={{ marginTop: 20 }}>
              <h3 className="section-title">
                In your favourite length{favBand ? ` (${favBand.duration_band})` : ""}: top 3 per genre
              </h3>
              <p style={{ fontSize: 12.5, color: "var(--text-dim)", marginTop: -4 }}>
                Q36 · unseen Netflix movies in the user's favourite length band and top-3 genres, ranked with
                DENSE_RANK() OVER (PARTITION BY genre) — tied films share a place.
              </p>
              <div style={{ overflowX: "auto" }}>
                <table>
                  <thead>
                    <tr>
                      <th>Genre</th>
                      <th>Rank</th>
                      <th>Title</th>
                      <th>Year</th>
                      <th>Length</th>
                      <th>Rating</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.durationPicks.map((p, i) => (
                      <tr key={i}>
                        <td>{p.genre_name}</td>
                        <td>{p.rank_in_genre}</td>
                        <td>{p.title}</td>
                        <td>{p.release_year}</td>
                        <td>{p.runtime_minutes} min</td>
                        <td>{p.vote_average}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
