"""
Scrapes the last 2 completed NBA seasons' full stat lines for every player in
the league from basketball-reference.com's team pages, as an independent
(non-Yahoo, no-auth-required) source of real season totals.

Approach: basketball-reference doesn't have a single "every player" page with
season totals, but each team's season page (/teams/{TEAM}/{YEAR}.html) has a
"totals_stats" table with every player who appeared for that team that
season. Iterating all 30 teams x 2 seasons and keying by each player's stable
basketball-reference player id (e.g. "doncilu01", from the /players/d/doncilu01.html
link) naturally reconstructs full-season totals even for players traded
mid-season, by summing their per-team rows for that season.

Respects robots.txt (Crawl-delay: 3 for User-agent: *) - sequential requests,
3s+ delay between them, no disallowed paths are touched (/gamelog/, /splits/,
etc. aren't needed here).

Run from the repo root (uses the venv in data_prep/):
  data_prep/venv/bin/python3 data_prep/scrape_basketball_reference.py
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path

try:
    import requests
except ImportError:
    raise SystemExit("Install requests: data_prep/venv/bin/pip install requests")

REPO_ROOT = Path(__file__).parent.parent
OUT_PATH = Path(__file__).parent / "basketball_reference_last2yrs.raw.json"

# bbref's own 3-letter abbreviations - a few differ from Yahoo/NBA.com's
# (Brooklyn=BRK not BKN, Charlotte=CHO not CHA, Phoenix=PHO not PHX).
TEAMS = [
    "ATL", "BOS", "BRK", "CHO", "CHI", "CLE", "DAL", "DEN", "DET", "GSW",
    "HOU", "IND", "LAC", "LAL", "MEM", "MIA", "MIL", "MIN", "NOP", "NYK",
    "OKC", "ORL", "PHI", "PHO", "POR", "SAC", "SAS", "TOR", "UTA", "WAS",
]

# bbref season pages are named after the year the season *ends* in
# (2025-26 season -> .../2026.html). Update these two each offseason.
SEASONS = [2025, 2026]

CRAWL_DELAY = 3.5  # seconds between requests - robots.txt asks for >= 3
RETRY_SLEEP = 8

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
}

ROW_RE = re.compile(r"<tr[^>]*>.*?</tr>", re.S)
# Cell content up to the closing </td> - NOT up to the next "<", because
# league-leader stats are wrapped in <strong>...</strong> (and names in
# <a>...</a>), which would otherwise read as an empty string.
CELL_RE = re.compile(r'data-stat="([a-z0-9_]+)"[^>]*>(.*?)</td>', re.S)
TAG_RE = re.compile(r"<[^>]+>")
PLAYER_ID_RE = re.compile(r'data-append-csv="([a-z0-9]+)"')


def _strip_tags(html: str) -> str:
    return TAG_RE.sub("", html).strip()


def fetch_team_totals(team: str, season: int) -> str:
    url = f"https://www.basketball-reference.com/teams/{team}/{season}.html"
    for attempt in range(3):
        try:
            resp = requests.get(url, headers=HEADERS, timeout=30)
            if resp.status_code == 404:
                return ""  # team didn't exist / no data for that season
            resp.raise_for_status()
            # The server doesn't always declare charset, so requests can
            # mis-guess (e.g. Latin-1), mangling accented names like
            # "Jokić"/"Dončić" into mojibake - force UTF-8 explicitly.
            resp.encoding = "utf-8"
            return resp.text
        except Exception as e:
            if attempt == 2:
                raise
            print(f"    attempt {attempt + 1} failed ({e}), retrying...")
            time.sleep(RETRY_SLEEP)
    return ""


def parse_totals_table(html: str) -> list[dict]:
    match = re.search(r'<table[^>]*id="totals_stats".*?</table>', html, re.S)
    if not match:
        return []
    table = match.group(0)
    rows = []
    for row_html in ROW_RE.findall(table):
        player_id_match = PLAYER_ID_RE.search(row_html)
        if not player_id_match:
            continue  # header/footer rows have no data-append-csv
        stats = {stat: _strip_tags(content) for stat, content in CELL_RE.findall(row_html)}
        name_match = re.search(r'>([^<]+)</a>', row_html)
        rows.append(
            {
                "playerId": player_id_match.group(1),
                "name": name_match.group(1) if name_match else stats.get("name_display", ""),
                "games": int(stats.get("games") or 0),
                "fg": int(stats.get("fg") or 0),
                "fga": int(stats.get("fga") or 0),
                "fg3": int(stats.get("fg3") or 0),
                "ft": int(stats.get("ft") or 0),
                "fta": int(stats.get("fta") or 0),
                "trb": int(stats.get("trb") or 0),
                "ast": int(stats.get("ast") or 0),
                "stl": int(stats.get("stl") or 0),
                "blk": int(stats.get("blk") or 0),
                "tov": int(stats.get("tov") or 0),
                "pts": int(stats.get("pts") or 0),
            }
        )
    return rows


def scrape_all() -> dict[str, dict]:
    # {playerId: {name, seasons: {season: {aggregated totals}}}}
    players: dict[str, dict] = {}

    for season in SEASONS:
        # Accumulate per-player totals for this season across all teams,
        # so a mid-season trade sums correctly into one season total.
        season_totals: dict[str, dict] = {}

        for i, team in enumerate(TEAMS, start=1):
            print(f"[{season}] ({i}/{len(TEAMS)}) {team}...")
            html = fetch_team_totals(team, season)
            time.sleep(CRAWL_DELAY)
            if not html:
                print(f"  no data for {team} {season}, skipping")
                continue

            for row in parse_totals_table(html):
                pid = row["playerId"]
                acc = season_totals.setdefault(
                    pid,
                    {"name": row["name"], "games": 0, "fg": 0, "fga": 0, "fg3": 0,
                     "ft": 0, "fta": 0, "trb": 0, "ast": 0, "stl": 0, "blk": 0,
                     "tov": 0, "pts": 0},
                )
                for key in ("games", "fg", "fga", "fg3", "ft", "fta", "trb", "ast", "stl", "blk", "tov", "pts"):
                    acc[key] += row[key]

        for pid, totals in season_totals.items():
            entry = players.setdefault(pid, {"name": totals["name"], "seasons": {}})
            entry["seasons"][str(season)] = {
                "gp": totals["games"],
                "fgPct": round(totals["fg"] / totals["fga"], 4) if totals["fga"] else 0.0,
                "fgAttempted": totals["fga"],
                "ftPct": round(totals["ft"] / totals["fta"], 4) if totals["fta"] else 0.0,
                "ftAttempted": totals["fta"],
                "threePM": totals["fg3"],
                "pts": totals["pts"],
                "reb": totals["trb"],
                "ast": totals["ast"],
                "stl": totals["stl"],
                "blk": totals["blk"],
                "to": totals["tov"],
            }

    return players


def main() -> None:
    players = scrape_all()
    OUT_PATH.write_text(json.dumps(players, indent=2, ensure_ascii=False))
    print(f"\nWrote {len(players)} players' last-2-season totals to {OUT_PATH}")


if __name__ == "__main__":
    main()
