import { useEffect, useState } from "react";
import { api } from "../services/api";
import type { Stats, MappingSummary } from "../services/api";
import { HorizontalBarChart, SplitDonut, TrendLineChart } from "../components/Charts";

export default function Dashboard() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [genres, setGenres] = useState<any[]>([]);
  const [countries, setCountries] = useState<any[]>([]);
  const [trends, setTrends] = useState<any[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [mapping, setMapping] = useState<MappingSummary | null>(null);

  useEffect(() => {
    Promise.all([api.stats(), api.genres(), api.countries(), api.yearlyTrends()])
      .then(([s, g, c, t]) => {
        setStats(s);
        setGenres(g.slice(0, 8));
        setCountries(c.slice(0, 8));
        setTrends(t);
      })
      .catch((err) => setError(err.message));
    // unified layer is optional: the dashboard still works if it isn't built yet
    api.mapping().then(setMapping).catch(() => setMapping(null));
  }, []);

  if (error) {
    return (
      <div className="error-box">
        Couldn't load dashboard data: {error}
      </div>
    );
  }

  if (!stats) return <div className="loading-dim">Loading dashboard…</div>;

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">QueryFlix</h1>
        <p className="page-subtitle">Netflix catalog intelligence + MovieLens user behaviour, unified in MySQL</p>
      </div>

      <div className="stat-grid">
        <StatCard label="Total Titles" value={stats.totalTitles.toLocaleString()} />
        <StatCard label="Movies" value={stats.movies.toLocaleString()} />
        <StatCard label="TV Shows" value={stats.tvShows.toLocaleString()} />
        <StatCard label="Countries" value={stats.countryCount.toLocaleString()} />
        <StatCard label="Genres" value={stats.genreCount.toLocaleString()} />
        <StatCard label="Avg Rating" value={stats.avgRating} accent />
      </div>

      {mapping && (
        <div className="stat-grid">
          <StatCard label="MovieLens Users" value={mapping.totals.users.toLocaleString()} />
          <StatCard label="MovieLens Movies" value={mapping.totals.movielens_movies.toLocaleString()} />
          <StatCard label="Ratings" value={mapping.totals.ratings.toLocaleString()} />
          <StatCard label="Mapped to Netflix" value={mapping.totals.mapped_movies.toLocaleString()} accent />
          <StatCard label="Ratings on Netflix titles" value={mapping.totals.ratings_on_netflix_titles.toLocaleString()} />
          <StatCard label="Runtimes (TMDB)" value={Number(mapping.totals.runtimes_loaded ?? 0).toLocaleString()} />
        </div>
      )}

      <div className="grid-2">
        <div className="card">
          <h3 className="section-title">Movies vs TV Shows</h3>
          <SplitDonut movies={stats.movies} tvShows={stats.tvShows} />
        </div>
        <div className="card">
          <h3 className="section-title">Top Genres</h3>
          <HorizontalBarChart data={genres} dataKey="title_count" labelKey="genre" />
        </div>
      </div>

      <div className="grid-2">
        <div className="card">
          <h3 className="section-title">Top Countries</h3>
          <HorizontalBarChart data={countries} dataKey="title_count" labelKey="country" />
        </div>
        <div className="card">
          <h3 className="section-title">Content Added by Year</h3>
          <TrendLineChart data={trends} dataKey="titles_added" labelKey="year_added" />
        </div>
      </div>
    </div>
  );
}

function StatCard({ label, value, accent }: { label: string; value: string | number; accent?: boolean }) {
  return (
    <div className="stat-card">
      <div className="stat-label">{label}</div>
      <div className={`stat-value${accent ? " accent" : ""}`}>{value}</div>
    </div>
  );
}
