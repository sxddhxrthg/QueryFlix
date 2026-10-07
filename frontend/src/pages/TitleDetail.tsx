import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api } from "../services/api";
import type { TitleDetail as TitleDetailType } from "../services/api";

export default function TitleDetail() {
  const { id } = useParams();
  const [title, setTitle] = useState<TitleDetailType | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    api
      .titleDetail(Number(id))
      .then(setTitle)
      .catch((err) => setError(err.message));
  }, [id]);

  if (error) return <div className="error-box">{error}</div>;
  if (!title) return <div className="loading-dim">Loading…</div>;

  return (
    <div>
      <Link to="/search" className="back-link">
        ← Back to search
      </Link>
      <div className="page-header">
        <h1 className="page-title">{title.title}</h1>
        <span className={`type-pill ${title.type === "Movie" ? "movie" : "tv"}`}>{title.type}</span>
      </div>

      <div className="detail-grid">
        <div className="card">
          <h3 className="section-title">Description</h3>
          <p style={{ color: "var(--text-dim)", lineHeight: 1.6, fontSize: 14 }}>
            {title.description || "No description available."}
          </p>

          <h3 className="section-title" style={{ marginTop: 20 }}>Cast &amp; Crew</h3>
          <Kv label="Director" value={title.director} />
          <Kv label="Cast" value={title.cast_members} />
        </div>

        <div className="card">
          <h3 className="section-title">Details</h3>
          <Kv label="Release year" value={title.release_year} />
          {title.type === "Movie" ? (
            <Kv label="Duration" value={title.runtime_minutes ? `${title.runtime_minutes} min` : null} />
          ) : (
            <Kv
              label="Duration"
              value={
                title.seasons || title.episode_runtime_minutes
                  ? [
                      title.seasons && `${title.seasons} season${title.seasons > 1 ? "s" : ""}`,
                      title.episodes && `${title.episodes} episodes`,
                      title.episode_runtime_minutes && `~${title.episode_runtime_minutes} min/episode`,
                    ]
                      .filter(Boolean)
                      .join(" · ")
                  : null
              }
            />
          )}
          <Kv label="Date added" value={title.date_added?.slice(0, 10)} />
          <Kv label="Genres" value={title.genres} />
          <Kv label="Country" value={title.country} />
          <Kv label="Language" value={title.language} />
          <Kv label="Rating" value={title.vote_average} />
          <Kv label="Popularity" value={title.popularity} />
          <Kv label="Vote count" value={title.vote_count} />
          {title.budget != null && <Kv label="Budget" value={`$${Number(title.budget).toLocaleString()}`} />}
          {title.revenue != null && <Kv label="Revenue" value={`$${Number(title.revenue).toLocaleString()}`} />}
        </div>
      </div>
    </div>
  );
}

function Kv({ label, value }: { label: string; value: unknown }) {
  return (
    <div className="kv-row">
      <span className="kv-label">{label}</span>
      <span>{value != null && value !== "" ? String(value) : "—"}</span>
    </div>
  );
}
