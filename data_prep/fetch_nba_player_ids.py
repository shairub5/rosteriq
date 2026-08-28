"""
Fetches NBA player IDs across recent seasons, builds a name→id lookup, and
patches players.json with a nbaId field.

Headshot URL: https://cdn.nba.com/headshots/nba/latest/260x190/{nbaId}.png

Outputs:
  assets/data/nba_player_ids.json  — full list for all ~550 recent players
  assets/data/players.json          — patched in-place with "nbaId" on each entry

Run from the repo root (uses the venv in data_prep/):
  data_prep/venv/bin/python3 data_prep/fetch_nba_player_ids.py
"""

import json
import re
import time
from pathlib import Path

try:
    import requests
except ImportError:
    raise SystemExit("Install requests: data_prep/venv/bin/pip install requests")

REPO_ROOT = Path(__file__).parent.parent
PLAYERS_JSON = REPO_ROOT / "assets" / "data" / "players.json"
OUTPUT_JSON = REPO_ROOT / "assets" / "data" / "nba_player_ids.json"

SEASONS = ["2018-19", "2019-20", "2020-21", "2021-22", "2022-23", "2023-24", "2024-25"]
RETRY_SLEEP = 5   # seconds between retries
SEASON_SLEEP = 2  # seconds between seasons

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Referer": "https://www.nba.com/",
    "Origin": "https://www.nba.com",
    "Accept": "application/json, text/plain, */*",
    "x-nba-stats-origin": "stats",
    "x-nba-stats-token": "true",
}

HEADSHOT_URL = "https://cdn.nba.com/headshots/nba/latest/260x190/{nba_id}.png"


def normalize(name: str) -> str:
    """Lowercase, strip accents, punctuation, and generational suffixes."""
    name = name.lower().strip()
    replacements = {
        "é": "e", "è": "e", "ê": "e", "ë": "e",
        "á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
        "í": "i", "ì": "i", "î": "i", "ï": "i",
        "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o", "ő": "o",
        "ú": "u", "ù": "u", "û": "u", "ü": "u", "ű": "u", "ů": "u",
        "ý": "y", "ÿ": "y",
        "ç": "c", "ñ": "n",
        "ć": "c", "č": "c", "š": "s", "ž": "z", "đ": "d", "ř": "r",
        "ā": "a", "ē": "e", "ī": "i", "ō": "o", "ū": "u",
        "ņ": "n", "ģ": "g", "ļ": "l", "ķ": "k",
        "’": "", "’": "", ".": "",
    }
    for src, dst in replacements.items():
        name = name.replace(src, dst)
    name = re.sub(r"\s+(jr|sr|ii|iii|iv)$", "", name)
    return re.sub(r"\s+", " ", name).strip()


def fetch_all_players() -> dict[int, dict]:
    """Returns {nba_id: {name, slug, team, toYear}} fetched across all seasons."""
    all_players: dict[int, dict] = {}

    for season in SEASONS:
        url = (
            f"https://stats.nba.com/stats/commonallplayers"
            f"?IsOnlyCurrentSeason=1&LeagueID=00&Season={season}"
        )
        for attempt in range(3):
            try:
                resp = requests.get(url, headers=HEADERS, timeout=45)
                resp.raise_for_status()
                data = resp.json()
                break
            except Exception as e:
                if attempt == 2:
                    raise
                print(f"    attempt {attempt + 1} failed ({e}), retrying...")
                time.sleep(RETRY_SLEEP)

        result_set = data["resultSets"][0]
        col = {h: i for i, h in enumerate(result_set["headers"])}
        rows = result_set["rowSet"]
        year = int(season[:4])

        for row in rows:
            pid = row[col["PERSON_ID"]]
            all_players[pid] = {
                "name": row[col["DISPLAY_FIRST_LAST"]],
                "slug": row[col["PLAYER_SLUG"]] or "",
                "team": row[col["TEAM_ABBREVIATION"]] or "",
                "toYear": year,
            }

        print(f"  {season}: {len(rows)} players (total unique: {len(all_players)})")
        time.sleep(SEASON_SLEEP)

    return all_players


def build_lookup(players: dict[int, dict]) -> dict[str, int]:
    """Returns {normalized_name: nba_id}. Most-recent player wins on collision."""
    lookup: dict[str, int] = {}
    for nba_id, info in sorted(players.items(), key=lambda kv: kv[1]["toYear"]):
        key = normalize(info["name"])
        lookup[key] = nba_id  # later seasons overwrite older — always newest wins
    return lookup


def patch_players_json(lookup: dict[str, int], raw: dict[int, dict]) -> tuple[int, int]:
    """Adds nbaId to each player in players.json. Returns (matched, total)."""
    players: list[dict] = json.loads(PLAYERS_JSON.read_text())
    matched = 0
    for player in players:
        nba_id = try_match(player["name"], lookup, raw)
        player["nbaId"] = nba_id
        if nba_id:
            matched += 1
    PLAYERS_JSON.write_text(json.dumps(players, indent=2, ensure_ascii=False))
    return matched, len(players)


def try_match(name: str, lookup: dict[str, int], raw: dict[int, dict]) -> int | None:
    """Full name match, then last-name-only fallback for abbreviated first names."""
    key = normalize(name)
    if key in lookup:
        return lookup[key]
    # Abbreviated first name ("T. Hendricks") — match on last name if unambiguous
    parts = key.split()
    if len(parts) >= 2 and len(parts[0]) <= 2:
        last = " ".join(parts[1:])
        matches = [nid for nid, info in raw.items()
                   if normalize(info["name"]).endswith(" " + last)
                   or normalize(info["name"]) == last]
        if len(matches) == 1:
            return matches[0]
    return None


def main() -> None:
    print(f"Fetching NBA players across {len(SEASONS)} seasons...")
    players = fetch_all_players()
    print(f"\nTotal unique players: {len(players)}")

    lookup = build_lookup(players)

    # Save full lookup as an asset the app can load at runtime
    output = {
        "generatedAt": __import__("datetime").datetime.utcnow().isoformat() + "Z",
        "headshotUrl": HEADSHOT_URL,
        "players": sorted(
            [
                {
                    "nbaId": nba_id,
                    "name": info["name"],
                    "slug": info["slug"],
                    "team": info["team"],
                    "toYear": info["toYear"],
                }
                for nba_id, info in players.items()
            ],
            key=lambda p: p["name"],
        ),
    }
    OUTPUT_JSON.write_text(json.dumps(output, indent=2, ensure_ascii=False))
    print(f"Saved {len(players)} entries → {OUTPUT_JSON.relative_to(REPO_ROOT)}")

    # Patch players.json with nbaId
    matched, total = patch_players_json(lookup, players)
    unmatched = total - matched
    print(f"\npatched players.json: {matched}/{total} matched")
    if unmatched:
        players_list: list[dict] = json.loads(PLAYERS_JSON.read_text())
        misses = [p["name"] for p in players_list if not p.get("nbaId")]
        print(f"  Unmatched ({unmatched}):")
        for name in misses:
            print(f"    - {name}")


if __name__ == "__main__":
    main()
