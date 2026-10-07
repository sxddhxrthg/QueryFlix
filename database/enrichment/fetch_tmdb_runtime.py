#!/usr/bin/env python3
"""
QueryFlix - fetch title duration from the TMDB API (one-time enrichment).

Why: neither permitted dataset has a usable duration. netflix.duration_raw is
empty for all 16,000 movies and '1 Seasons' for all 16,000 TV shows, and
MovieLens has no runtime field. Both datasets already carry TMDB ids:
  * Netflix  : source_id (TMDB movie id for movies, TMDB TV id for shows)
  * MovieLens: links.csv tmdbId (TMDB movie id)
so each TMDB id is looked up once and written to database/enrichment/tmdb_runtime.csv,
which database/load_runtime.sql loads into the `tmdb_runtime` table.

Usage (from the repository root, Python 3.8+, no pip packages needed):

    export TMDB_API_KEY=xxxxxxxx            # "API Key" from themoviedb.org -> Settings -> API
    #   or: export TMDB_READ_TOKEN=eyJ...    # "API Read Access Token" (either one works)
    python3 database/enrichment/fetch_tmdb_runtime.py

    # quick test on 50 ids first:
    python3 database/enrichment/fetch_tmdb_runtime.py --limit 50

OPTIONAL: a bundled snapshot (tmdb_runtime_snapshot.csv, from "The Movies
Dataset", 2017) already covers ~99% of MovieLens ratings and the 2010-2017
Netflix movies, so duration personalisation works without running this.
Run it only to add 2018-2025 movies and TV shows (~26,000 ids, ~10-15 min);
ids the snapshot covers are skipped unless you pass --refresh-all.
The script is resumable: re-running it skips ids already in the output CSV,
so an interrupted run (Ctrl+C, Wi-Fi drop) just continues where it stopped.
"""

import argparse
import csv
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))          # database/
NETFLIX_CSV = os.path.join(ROOT, "data", "netflix_unified.csv")
LINKS_CSV = os.path.join(ROOT, "movielens", "links.csv")
OUT_CSV = os.path.join(ROOT, "enrichment", "tmdb_runtime.csv")
SNAPSHOT_CSV = os.path.join(ROOT, "enrichment", "tmdb_runtime_snapshot.csv")   # bundled 2017 data

API = os.environ.get("TMDB_API_BASE", "https://api.themoviedb.org/3")   # override only for testing
FIELDS = ["tmdb_type", "tmdb_id", "runtime_minutes", "seasons", "episodes",
          "episode_runtime_minutes", "fetch_status", "fetched_at"]
NULL = r"\N"                      # MySQL LOAD DATA NULL marker


def collect_ids():
    """Every (tmdb_type, tmdb_id) the project needs, de-duplicated."""
    ids = set()
    with open(NETFLIX_CSV, newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            source_id, kind = row[0], row[1]
            if source_id.isdigit():
                ids.add(("movie" if kind == "Movie" else "tv", int(source_id)))
    with open(LINKS_CSV, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["tmdbId"].strip().isdigit():
                ids.add(("movie", int(row["tmdbId"])))
    return ids


def already_done(include_snapshot=True):
    """Ids already in the API output (resume) and, unless --refresh-all,
    ids the bundled snapshot already covers with a runtime."""
    done = set()
    files = [OUT_CSV] + ([SNAPSHOT_CSV] if include_snapshot else [])
    for path in files:
        if os.path.exists(path):
            with open(path, newline="", encoding="utf-8") as f:
                for row in csv.DictReader(f):
                    done.add((row["tmdb_type"], int(row["tmdb_id"])))
    return done


def auth():
    key, token = os.environ.get("TMDB_API_KEY"), os.environ.get("TMDB_READ_TOKEN")
    if not key and not token:
        sys.exit("Set TMDB_API_KEY or TMDB_READ_TOKEN first (free at themoviedb.org -> Settings -> API).")
    return key, token


def get_json(url, key, token, retries=6):
    if key:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode({"api_key": key})
    headers = {"Accept": "application/json"}
    if token and not key:
        headers["Authorization"] = f"Bearer {token}"
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code == 401:
                sys.exit("TMDB rejected the key (401). Check TMDB_API_KEY / TMDB_READ_TOKEN.")
            if e.code == 429:                                   # rate limited: wait as told
                time.sleep(float(e.headers.get("Retry-After", 2)) + 0.5)
                continue
            time.sleep(1.5 * (attempt + 1))
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"gave up after {retries} attempts: {url.split('?')[0]}")


def positive(v):
    return v if isinstance(v, int) and v > 0 else None


def fetch_one(kind, tmdb_id, key, token):
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    data = get_json(f"{API}/{kind}/{tmdb_id}", key, token)
    row = {"tmdb_type": kind, "tmdb_id": tmdb_id, "runtime_minutes": NULL, "seasons": NULL,
           "episodes": NULL, "episode_runtime_minutes": NULL, "fetched_at": now}
    if data is None:
        row["fetch_status"] = "NOT_FOUND"
        return row
    if kind == "movie":
        rt = positive(data.get("runtime"))
        row["runtime_minutes"] = rt if rt else NULL
        row["fetch_status"] = "OK" if rt else "NO_RUNTIME"
    else:
        seasons, episodes = positive(data.get("number_of_seasons")), positive(data.get("number_of_episodes"))
        ep_times = [t for t in (data.get("episode_run_time") or []) if positive(t)]
        ep_rt = sorted(ep_times)[len(ep_times) // 2] if ep_times else None      # median listed length
        if not ep_rt:                                                           # newer TMDB records
            last = data.get("last_episode_to_air") or {}
            ep_rt = positive(last.get("runtime"))
        row["seasons"] = seasons or NULL
        row["episodes"] = episodes or NULL
        row["episode_runtime_minutes"] = ep_rt or NULL
        row["fetch_status"] = "OK" if (seasons or ep_rt) else "NO_RUNTIME"
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=0, help="only fetch this many ids (for a test run)")
    ap.add_argument("--workers", type=int, default=8, help="parallel requests (TMDB allows ~40/s)")
    ap.add_argument("--refresh-all", action="store_true",
                    help="also re-fetch ids the bundled 2017 snapshot already covers")
    args = ap.parse_args()

    key, token = auth()
    get_json(f"{API}/movie/550", key, token)       # probe once: a bad key fails here, not 40,000 times
    todo = sorted(collect_ids() - already_done(include_snapshot=not args.refresh_all))
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(todo):,} TMDB ids to fetch -> {os.path.relpath(OUT_CSV)}")
    if not todo:
        return

    new_file = not os.path.exists(OUT_CSV)
    lock = threading.Lock()
    counts = {"OK": 0, "NO_RUNTIME": 0, "NOT_FOUND": 0, "ERROR": 0}
    started = time.time()
    with open(OUT_CSV, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, lineterminator="\n")
        if new_file:
            writer.writeheader()
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(fetch_one, k, i, key, token): (k, i) for k, i in todo}
            for n, fut in enumerate(as_completed(futures), 1):
                try:
                    row = fut.result()
                except Exception as e:           # network gave up: skip, a re-run will retry it
                    counts["ERROR"] += 1
                    print(f"  ! {futures[fut]}: {e}", file=sys.stderr)
                    continue
                with lock:
                    writer.writerow(row)
                    counts[row["fetch_status"]] += 1
                    if n % 500 == 0:
                        f.flush()
                        rate = n / (time.time() - started)
                        print(f"  {n:,}/{len(todo):,}  ({rate:.0f}/s, ~{(len(todo) - n) / rate / 60:.1f} min left)  {counts}")
    print(f"Done in {(time.time() - started) / 60:.1f} min: {counts}")
    if counts["ERROR"]:
        print("Some ids failed on the network - just run the script again to retry them.")
    print("Next: bash database/import.sh   (or load only: mysql ... queryflix < database/load_runtime.sql)")


if __name__ == "__main__":
    main()
