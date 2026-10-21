"""
Fetches each player's games-played (GP) for their last few completed NBA
regular seasons from the NBA Stats API, and patches players.json with a
careerGpHistory field (most recent season first). The ranking engine uses
this to discount players whose current-season projection assumes full health
but whose recent history shows a pattern of missed time (see
lib/engine/pool_stats.dart:durabilityAdjustedGp).

Requires nbaId to already be patched into players.json - run
fetch_nba_player_ids.py first.

Run from the repo root (uses the venv in data_prep/):
  data_prep/venv/bin/python3 data_prep/fetch_career_gp.py
"""

import json
import time
from pathlib import Path

try:
    import requests
except ImportError:
    raise SystemExit("Install requests: data_prep/venv/bin/pip install requests")

REPO_ROOT = Path(__file__).parent.parent
PLAYERS_JSON = REPO_ROOT / "assets" / "data" / "players.json"

# How many of the most recent completed seasons to keep per player.
SEASONS_TO_KEEP = 4
RETRY_SLEEP = 5   # seconds between retries
REQUEST_SLEEP = 0.6  # seconds between players, to stay well under rate limits

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

CAREER_STATS_URL = "https://stats.nba.com/stats/playercareerstats?PlayerID={nba_id}&PerMode=Totals"


def fetch_career_gp(nba_id: int) -> list[int]:
    """Returns GP for this player's last SEASONS_TO_KEEP regular seasons,
    most recent first. Excludes the in-progress season if the API includes
    partial data for it - callers only care about *completed* seasons."""
    url = CAREER_STATS_URL.format(nba_id=nba_id)
    for attempt in range(3):
        try:
            resp = requests.get(url, headers=HEADERS, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            break
        except Exception as e:
            if attempt == 2:
                raise
            print(f"    attempt {attempt + 1} failed ({e}), retrying...")
            time.sleep(RETRY_SLEEP)

    result_set = next(
        (rs for rs in data["resultSets"] if rs["name"] == "SeasonTotalsRegularSeason"), None
    )
    if result_set is None or not result_set["rowSet"]:
        return []

    col = {h: i for i, h in enumerate(result_set["headers"])}
    rows = result_set["rowSet"]
    # Rows come oldest-first; reverse for most-recent-first, then take the
    # last SEASONS_TO_KEEP completed seasons.
    gp_by_season = [(row[col["SEASON_ID"]], row[col["GP"]]) for row in rows]
    gp_by_season.reverse()
    return [gp for _season, gp in gp_by_season[:SEASONS_TO_KEEP]]


def main() -> None:
    players: list[dict] = json.loads(PLAYERS_JSON.read_text())

    matched = 0
    skipped_no_id = 0
    for i, player in enumerate(players, start=1):
        nba_id = player.get("nbaId")
        if not nba_id:
            skipped_no_id += 1
            continue

        print(f"[{i}/{len(players)}] {player['name']}...")
        try:
            gp_history = fetch_career_gp(nba_id)
        except Exception as e:
            print(f"  failed: {e}")
            gp_history = []

        if gp_history:
            player["careerGpHistory"] = gp_history
            matched += 1
        time.sleep(REQUEST_SLEEP)

    PLAYERS_JSON.write_text(json.dumps(players, indent=2, ensure_ascii=False))
    print(f"\nPatched careerGpHistory for {matched}/{len(players)} players "
          f"({skipped_no_id} skipped, no nbaId)")


if __name__ == "__main__":
    main()
