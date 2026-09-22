import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../services/api";
import type { TitleSummary } from "../services/api";

export default function Search() {
  const [filters, setFilters] = useState({
    search: "",
    type: "",
    country: "",
    genre: "",
    director: "",
    cast: "",
    year: "",
  });
  const [results, setResults] = useState<TitleSummary[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  const runSearch = async () => {
    setLoading(true);
    setError(null);
    try {
      const params: Record<string, string> = {};
      Object.entries(filters).forEach(([k, v]) => {
        if (v) params[k] = v;
      });
      const res = await api.searchTitles(params);
      setResults(res.results);
      setTotal(res.total);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const update = (key: string) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setFilters((f) => ({ ...f, [key]: e.target.value }));

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Search Titles</h1>
        <p className="page-subtitle">Search the 32,000-title catalog directly against MySQL.</p>
      </div>

      <div className="card" style={{ marginBottom: 20 }}>
        <div className="search-filters">
          <input className="input" placeholder="Title" value={filters.search} onChange={update("search")} />
          <select className="input" value={filters.type} onChange={update("type")}>
            <option value="">Any type</option>
            <option value="Movie">Movie</option>
            <option value="TV Show">TV Show</option>
          </select>
          <input className="input" placeholder="Country" value={filters.country} onChange={update("country")} />
          <input className="input" placeholder="Genre" value={filters.genre} onChange={update("genre")} />
          <input className="input" placeholder="Director" value={filters.director} onChange={update("director")} />
          <input className="input" placeholder="Cast member" value={filters.cast} onChange={update("cast")} />
          <input className="input" placeholder="Release year" value={filters.year} onChange={update("year")} />
        </div>
        <button className="btn" onClick={runSearch} disabled={loading}>
          {loading ? "Searching\u2026" : "Search"}
        </button>
      </div>

      {error && <div className="error-box">{error}</div>}

      {results.length > 0 && (
        <div className="card">
          <h3 className="section-title">{total.toLocaleString()} results (showing {results.length})</h3>
          <table>
            <thead>
              <tr>
                <th>Title</th>
                <th>Type</th>
                <th>Year</th>
                <th>Rating</th>
                <th>Genres</th>
              </tr>
            </thead>
            <tbody>
              {results.map((r) => (
                <tr key={r.show_id} className="title-row" onClick={() => navigate(`/title/${r.show_id}`)}>
                  <td>{r.title}</td>
                  <td>
                    <span className={`type-pill ${r.type === "Movie" ? "movie" : "tv"}`}>{r.type}</span>
                  </td>
                  <td>{r.release_year}</td>
                  <td>{r.vote_average}</td>
                  <td>{r.genres}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
