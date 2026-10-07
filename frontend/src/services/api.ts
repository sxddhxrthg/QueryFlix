const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4000/api";

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function request<T>(path: string): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`);
  } catch (err) {
    throw new ApiError(
      "Could not reach the QueryFlix API. Is the backend running on port 4000?",
      0
    );
  }
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const body = await res.json();
      detail = body.error || body.detail || detail;
    } catch {
      /* ignore parse failure */
    }
    throw new ApiError(detail, res.status);
  }
  return res.json() as Promise<T>;
}

export interface Stats {
  totalTitles: number;
  movies: number;
  tvShows: number;
  avgRating: number;
  genreCount: number;
  countryCount: number;
}

export interface QuerySummary {
  id: number;
  layer?: "netflix" | "movielens";
  usesUser?: boolean;
  slug: string;
  title: string;
  businessQuestion: string;
  explanation: string;
  technique: string;
}

export interface QueryDetail extends QuerySummary {
  sql: string;
}

export interface QueryResult {
  id: number;
  title: string;
  userId?: number;
  rowCount: number;
  executionTimeMs: number;
  results: Record<string, unknown>[];
}

export interface TitleSummary {
  show_id: number;
  type: string;
  title: string;
  release_year: number;
  vote_average: string;
  popularity: string;
  genres: string;
  country: string;
}

export interface TitleDetail {
  show_id: number;
  source_id: number;
  type: string;
  title: string;
  director: string | null;
  cast_members: string | null;
  country: string | null;
  date_added: string | null;
  release_year: number | null;
  content_rating: string | null;
  duration_raw: string | null;
  genres: string | null;
  language: string | null;
  description: string | null;
  popularity: string | null;
  vote_count: number | null;
  vote_average: string | null;
  budget: number | null;
  revenue: number | null;
  // duration enrichment (TMDB); null until runtimes are fetched
  runtime_minutes?: number | null;
  seasons?: number | null;
  episodes?: number | null;
  episode_runtime_minutes?: number | null;
}

export interface TableInfo {
  name: string;
  approx_row_count: number;
  exact_row_count?: number;
}

export interface ColumnInfo {
  Field: string;
  Type: string;
  Null: string;
  Key: string;
  Default: string | null;
  Extra: string;
}

export interface MappingSummary {
  totals: {
    users: number;
    movielens_movies: number;
    ratings: number;
    mapped_movies: number;
    ratings_on_netflix_titles: number;
    runtimes_loaded: number;
  };
  byStatus: {
    match_status: string;
    movielens_movies: number;
    confirmed_by_links_csv: string | null;
    avg_confidence: string;
  }[];
  examples: Record<string, unknown>[];
}

export interface GenreAffinity {
  genre_name: string;
  n_rated: number;
  avg_rating: string;
  vs_user_mean: string;
  volume: string;
  liking: string;
  affinity: string;
  preference_rank: number;
}

export interface DurationAffinity {
  duration_band: string;
  n_rated: number;
  avg_minutes: number;
  avg_rating: string;
  vs_user_mean: string;
  volume: string;
  liking: string;
  affinity: string;
  preference_rank: number;
}

export interface Recommendation {
  rec_rank: number;
  title: string;
  release_year: number;
  runtime_minutes: number | null;
  duration_match: string;
  evidence: string;
  recommendation_score: number | string;
  genre_match: string;
  collaborative: string;
  quality: string;
  popularity: string;
  similar_users_who_rated: number;
  because_you_like: string | null;
}

export interface DurationPick {
  genre_name: string;
  rank_in_genre: number;
  title: string;
  release_year: number;
  runtime_minutes: number;
  duration_band: string;
  vote_average: string;
}

export interface PersonalizationResult {
  userId: number;
  weights: { genre: number; collaborative: number; duration: number; quality: number; popularity: number };
  executionTimeMs: number;
  profile: GenreAffinity[];
  durationProfile: DurationAffinity[];
  durationAvailable: boolean;
  recommendations: Recommendation[];
  durationPicks: DurationPick[];
}

export interface DemoUser {
  user_id: number;
  n_ratings: number;
  n_ratings_on_netflix_titles: string;
  mean_rating: string;
}

export const api = {
  health: () => request<{ api: string; mysqlConnected: boolean; database: string }>("/health"),
  stats: () => request<Stats>("/stats"),
  genres: () => request<{ genre: string; title_count: number }[]>("/genres"),
  countries: () => request<{ country: string; title_count: number }[]>("/countries"),
  cast: () => request<{ actor: string; appearances: number }[]>("/cast"),
  yearlyTrends: () => request<{ year_added: number; titles_added: number }[]>("/yearly-trends"),
  queries: () => request<QuerySummary[]>("/queries"),
  queryDetail: (id: number) => request<QueryDetail>(`/queries/${id}`),
  queryResults: (id: number, userId?: number) =>
    request<QueryResult>(`/queries/${id}/results${userId ? `?userId=${userId}` : ""}`),
  mapping: () => request<MappingSummary>("/personalization/mapping"),
  demoUsers: () => request<DemoUser[]>("/personalization/users"),
  personalization: (userId: number) => request<PersonalizationResult>(`/personalization/${userId}`),
  searchTitles: (params: Record<string, string>) => {
    const qs = new URLSearchParams(params).toString();
    return request<{ total: number; page: number; limit: number; results: TitleSummary[] }>(
      `/titles?${qs}`
    );
  },
  titleDetail: (id: number) => request<TitleDetail>(`/titles/${id}`),
  tables: () => request<TableInfo[]>("/database/tables"),
  tableSchema: (table: string) => request<ColumnInfo[]>(`/database/tables/${table}/schema`),
  tableSample: (table: string, limit = 20) =>
    request<Record<string, unknown>[]>(`/database/tables/${table}?limit=${limit}`),
};
