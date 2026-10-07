import { MOVIELENS_QUERIES } from "./registry_movielens";

export interface QueryDef {
  id: number;
  layer?: "netflix" | "movielens";   // netflix = Q1-Q15, movielens = Q16-Q30
  usesUser?: boolean;                // true -> route runs SET @user_id = ? first
  slug: string;
  title: string;
  businessQuestion: string;
  explanation: string;
  technique: string;
  sql: string;
}

// All 15 queries, migrated from the project's PostgreSQL implementation to
// MySQL 8.0+/9.x compatible SQL. See database/queries.sql for the
// standalone, commented version with full translation notes.
const NETFLIX_QUERIES: QueryDef[] = [
  {
    id: 1,
    slug: "content-distribution",
    title: "Content-type distribution",
    businessQuestion: "How much of the catalog is Movies vs. TV Shows?",
    explanation:
      "Baseline catalog composition using COUNT and GROUP BY, with a window " +
      "function computing the percentage share in the same query.",
    technique: "Aggregation + window function (SUM() OVER ())",
    sql: `SELECT type, COUNT(*) AS total_titles,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_catalog
FROM netflix
GROUP BY type`,
  },
  {
    id: 2,
    slug: "top-genres",
    title: "Top 10 genres by frequency",
    businessQuestion: "Which genres dominate the catalog?",
    explanation:
      "genres is a comma-separated multi-valued field. It's split into a JSON " +
      "array and expanded with JSON_TABLE so each genre is counted individually.",
    technique: "String manipulation \u2013 JSON_TABLE (MySQL equivalent of Postgres UNNEST)",
    sql: `SELECT TRIM(jt.genre) AS genre, COUNT(*) AS title_count
FROM netflix,
     JSON_TABLE(
        CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(genres, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
        '$[*]' COLUMNS (genre VARCHAR(100) PATH '$')
     ) AS jt
WHERE genres IS NOT NULL
GROUP BY TRIM(jt.genre)
ORDER BY title_count DESC
LIMIT 10`,
  },
  {
    id: 3,
    slug: "top-countries",
    title: "Top 10 producing countries",
    businessQuestion: "Which countries produce the most content?",
    explanation:
      "country holds multi-valued co-production strings; JSON_TABLE expands " +
      "each title's countries into individual rows before counting.",
    technique: "String manipulation \u2013 JSON_TABLE",
    sql: `SELECT TRIM(jt.country_val) AS country, COUNT(*) AS title_count
FROM netflix,
     JSON_TABLE(
        CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(netflix.country, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
        '$[*]' COLUMNS (country_val VARCHAR(100) PATH '$')
     ) AS jt
WHERE netflix.country IS NOT NULL
GROUP BY TRIM(jt.country_val)
ORDER BY title_count DESC
LIMIT 10`,
  },
  {
    id: 4,
    slug: "top-cast",
    title: "Top 10 most-credited cast members",
    businessQuestion: "Who are the most frequently credited actors across titles?",
    explanation:
      "cast_members is unnested the same way as genres/country. Note: ~1,139 " +
      "titles have mis-encoded (invalid UTF-8) bytes in non-English cast names " +
      "(Turkish/Czech/Baltic accents); MySQL's JSON_TABLE validates UTF-8 " +
      "strictly and returns NULL for those entries, which PostgreSQL's UNNEST " +
      "does not do \u2014 those NULLs are explicitly excluded here.",
    technique: "String manipulation \u2013 JSON_TABLE, with NULL/encoding-artifact handling",
    sql: `SELECT TRIM(jt.actor) AS actor, COUNT(*) AS appearances
FROM netflix,
     JSON_TABLE(
        CONCAT('["', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(cast_members, '[[:cntrl:]]', ' '), CHAR(92), CONCAT(CHAR(92),CHAR(92))), '"', CONCAT(CHAR(92),'"')), ', ', '","'), '"]'),
        '$[*]' COLUMNS (actor VARCHAR(150) PATH '$')
     ) AS jt
WHERE cast_members IS NOT NULL AND jt.actor IS NOT NULL
GROUP BY TRIM(jt.actor)
ORDER BY appearances DESC
LIMIT 10`,
  },
  {
    id: 5,
    slug: "yearly-trend",
    title: "Yearly trend of titles added",
    businessQuestion: "How has the catalog grown by year_added?",
    explanation: "Extracts the year from date_added and groups by it to show a trend line.",
    technique: "Date operations \u2013 EXTRACT(YEAR FROM ...)",
    sql: `SELECT EXTRACT(YEAR FROM date_added) AS year_added, COUNT(*) AS titles_added
FROM netflix
WHERE date_added IS NOT NULL
GROUP BY year_added
ORDER BY year_added`,
  },
  {
    id: 6,
    slug: "recent-titles",
    title: "Titles added in the last 5 years",
    businessQuestion: "How much of the catalog is recent, by content type?",
    explanation: "Filters to the most recent 5-year window relative to the latest date in the data.",
    technique: "Date operations \u2013 DATE_SUB(..., INTERVAL n YEAR)",
    sql: `SELECT type, COUNT(*) AS recent_titles
FROM netflix
WHERE date_added >= (SELECT DATE_SUB(MAX(date_added), INTERVAL 5 YEAR) FROM netflix)
GROUP BY type`,
  },
  {
    id: 7,
    slug: "top-rated",
    title: "Top 10 highest-rated titles (vote_count >= 500)",
    businessQuestion: "What are the best-reviewed titles, once low-vote noise is filtered out?",
    explanation: "A minimum vote_count threshold avoids letting a title with 1-2 votes rank above a well-reviewed one.",
    technique: "Filtering + ORDER BY",
    sql: `SELECT title, type, vote_average, vote_count
FROM netflix
WHERE vote_count >= 500
ORDER BY vote_average DESC
LIMIT 10`,
  },
  {
    id: 8,
    slug: "top-rated-per-type",
    title: "Highest-rated title per content type",
    businessQuestion: "What is the #1 Movie and #1 TV Show by rating?",
    explanation: "RANK() computes a rank inside each type partition while keeping every row, unlike GROUP BY.",
    technique: "Window function \u2013 RANK() OVER (PARTITION BY type ORDER BY vote_average DESC)",
    sql: `SELECT type, title, vote_average
FROM (
    SELECT type, title, vote_average,
           RANK() OVER (PARTITION BY type ORDER BY vote_average DESC) AS rnk
    FROM netflix
    WHERE vote_count >= 500
) ranked
WHERE rnk = 1
ORDER BY type`,
  },
  {
    id: 9,
    slug: "india-content",
    title: "Content originating from India",
    businessQuestion: "How much India-linked content exists, and how is it rated?",
    explanation: "Pattern-matches India within the (possibly multi-country) country field.",
    technique: "Pattern matching \u2013 LIKE (MySQL's default collation is already case-insensitive)",
    sql: `SELECT type, COUNT(*) AS titles, ROUND(AVG(vote_average), 2) AS avg_rating
FROM netflix
WHERE country LIKE '%India%'
GROUP BY type`,
  },
  {
    id: 10,
    slug: "movies-vs-tv",
    title: "Ratings & popularity: Movies vs TV Shows",
    businessQuestion: "Do Movies or TV Shows perform better on average?",
    explanation: "Compares three engagement metrics side by side across content types.",
    technique: "Aggregation \u2013 AVG, GROUP BY",
    sql: `SELECT type,
       ROUND(AVG(vote_average), 2) AS avg_rating,
       ROUND(AVG(popularity), 2)   AS avg_popularity,
       ROUND(AVG(vote_count))      AS avg_vote_count
FROM netflix
GROUP BY type`,
  },
  {
    id: 11,
    slug: "co-productions",
    title: "Co-productions vs single-country titles",
    businessQuestion: "How common are multi-country co-productions?",
    explanation: "Counts comma-separated elements in country to classify each title.",
    technique: "String manipulation \u2013 comma-count (MySQL equivalent of ARRAY_LENGTH)",
    sql: `SELECT
    CASE WHEN (LENGTH(country) - LENGTH(REPLACE(country, ',', '')) + 1) > 1
         THEN 'Co-production (2+ countries)'
         ELSE 'Single country' END AS production_type,
    COUNT(*) AS title_count
FROM netflix
WHERE country IS NOT NULL
GROUP BY production_type`,
  },
  {
    id: 12,
    slug: "content-categorization",
    title: "Dynamic content categorization",
    businessQuestion: "Can we flag likely content themes directly from the description text?",
    explanation:
      "A heuristic keyword-matching classifier over free-text descriptions. " +
      "This is approximate, not a validated NLP classifier \u2014 presented " +
      "honestly as such.",
    technique: "Dynamic categorization \u2013 CASE + LIKE wildcard matching",
    sql: `SELECT
    CASE
        WHEN description LIKE '%kill%' OR description LIKE '%murder%'
             OR description LIKE '%war%' OR description LIKE '%crime%'
            THEN 'Crime / Violence themed'
        WHEN description LIKE '%love%' OR description LIKE '%romance%'
            THEN 'Romance themed'
        WHEN description LIKE '%comedy%' OR description LIKE '%funny%'
            THEN 'Comedy themed'
        ELSE 'Other'
    END AS content_flag,
    COUNT(*) AS title_count
FROM netflix
WHERE description IS NOT NULL
GROUP BY content_flag
ORDER BY title_count DESC`,
  },
  {
    id: 13,
    slug: "movie-profitability",
    title: "Movie profitability (budget vs revenue)",
    businessQuestion: "Which movies were the most commercially successful?",
    explanation:
      "budget/revenue are only populated for movies; NULLIF guards against " +
      "division by zero when computing the revenue multiple.",
    technique: "Aggregation + derived columns",
    sql: `SELECT title, release_year, budget, revenue,
       (revenue - budget) AS profit,
       ROUND(revenue / NULLIF(budget, 0), 2) AS revenue_multiple
FROM netflix
WHERE type = 'Movie' AND budget > 0 AND revenue > 0
ORDER BY profit DESC
LIMIT 10`,
  },
  {
    id: 14,
    slug: "top-directors",
    title: "Top 10 most prolific directors",
    businessQuestion: "Which directors have the largest footprint on Netflix?",
    explanation: "Counts titles per director, explicitly excluding NULL/empty director values.",
    technique: "Aggregation + NULL handling",
    sql: `SELECT director, COUNT(*) AS titles_directed,
       ROUND(AVG(vote_average), 2) AS avg_rating
FROM netflix
WHERE director IS NOT NULL AND director <> ''
GROUP BY director
ORDER BY titles_directed DESC
LIMIT 10`,
  },
  {
    id: 15,
    slug: "yearly-popular",
    title: "Most popular title per year (last 10 years)",
    businessQuestion: "What was the single most-hyped release of each recent year?",
    explanation: "Ranks titles by popularity within each release_year partition and keeps only rank 1.",
    technique: "Window function \u2013 RANK() OVER (PARTITION BY release_year ORDER BY popularity DESC)",
    sql: `SELECT release_year, title, type, popularity
FROM (
    SELECT release_year, title, type, popularity,
           RANK() OVER (PARTITION BY release_year ORDER BY popularity DESC) AS rnk
    FROM netflix
    WHERE release_year >= (SELECT MAX(release_year) - 9 FROM netflix)
) ranked
WHERE rnk = 1
ORDER BY release_year DESC`,
  },
];

export const QUERIES: QueryDef[] = [
  ...NETFLIX_QUERIES.map((q) => ({ ...q, layer: "netflix" as const, usesUser: false })),
  ...MOVIELENS_QUERIES,
];

export function getQueryById(id: number): QueryDef | undefined {
  return QUERIES.find((q) => q.id === id);
}
