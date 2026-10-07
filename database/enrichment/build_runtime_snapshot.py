#!/usr/bin/env python3
"""
QueryFlix - build the bundled runtime snapshot (duration) from "The Movies Dataset".

Source: "The Movies Dataset" by Rounak Banik (Kaggle, CC0 Public Domain),
        file movies_metadata.csv - TMDB metadata for 45,466 films, collected
        from the TMDB API in July 2017 as the companion to MovieLens.
        https://www.kaggle.com/datasets/rounakbanik/the-movies-dataset

Only the films QueryFlix needs are kept (Netflix movies by source_id + every
MovieLens movie by links.csv tmdbId), and only the runtime, so the bundled
file stays small. Output has the same columns as fetch_tmdb_runtime.py:

    database/enrichment/tmdb_runtime_snapshot.csv

Usage (from the repository root; needs only the Python standard library):

    python3 database/enrichment/build_runtime_snapshot.py path/to/movies_metadata.csv

You do NOT need to run this - the output CSV is already in the repository.
It is here so the snapshot can be rebuilt and checked.
"""

import csv
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))          # database/
NETFLIX_CSV = os.path.join(ROOT, "data", "netflix_unified.csv")
LINKS_CSV = os.path.join(ROOT, "movielens", "links.csv")
OUT_CSV = os.path.join(ROOT, "enrichment", "tmdb_runtime_snapshot.csv")
SNAPSHOT_DATE = "2017-07-26 00:00:00"        # when The Movies Dataset was collected
NULL = r"\N"


def needed_movie_ids():
    ids = set()
    with open(NETFLIX_CSV, newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if row[1] == "Movie" and row[0].isdigit():
                ids.add(int(row[0]))
    with open(LINKS_CSV, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["tmdbId"].strip().isdigit():
                ids.add(int(row["tmdbId"]))
    return ids


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    needed = needed_movie_ids()
    runtimes = {}
    with open(sys.argv[1], newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if not row.get("id", "").isdigit():
                continue                              # a few malformed rows in the source
            tmdb_id = int(row["id"])
            if tmdb_id not in needed or tmdb_id in runtimes:
                continue
            try:
                rt = int(float(row.get("runtime") or 0))
            except ValueError:
                rt = 0
            if 1 <= rt <= 1000:                       # 0 / blank = unknown in the source
                runtimes[tmdb_id] = rt

    with open(OUT_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["tmdb_type", "tmdb_id", "runtime_minutes", "seasons", "episodes",
                    "episode_runtime_minutes", "fetch_status", "fetched_at"])
        for tmdb_id in sorted(runtimes):
            w.writerow(["movie", tmdb_id, runtimes[tmdb_id], NULL, NULL, NULL, "OK", SNAPSHOT_DATE])
    print(f"{len(runtimes):,} of {len(needed):,} needed movie ids have a runtime -> {os.path.relpath(OUT_CSV)}")


if __name__ == "__main__":
    main()
