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

export const api = {
  health: () => request<{ api: string; mysqlConnected: boolean; database: string }>("/health"),
  stats: () => request<Stats>("/stats"),
  genres: () => request<{ genre: string; title_count: number }[]>("/genres"),
  countries: () => request<{ country: string; title_count: number }[]>("/countries"),
  cast: () => request<{ actor: string; appearances: number }[]>("/cast"),
  yearlyTrends: () => request<{ year_added: number; titles_added: number }[]>("/yearly-trends"),
  queries: () => request<QuerySummary[]>("/queries"),
  queryDetail: (id: number) => request<QueryDetail>(`/queries/${id}`),
  queryResults: (id: number) => request<QueryResult>(`/queries/${id}/results`),
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
