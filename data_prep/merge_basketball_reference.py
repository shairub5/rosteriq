"""
Merges data_prep/basketball_reference_last2yrs.raw.json (from
scrape_basketball_reference.py) into assets/data/players.json:

  - priorSeason: the most recent completed season's real stat line, so the
    pool screen's "Last Year" view (lib/state/stats_view_mode_provider.dart)
    has something to show - previously only populated via a Yahoo API pull
    that requires live OAuth and hadn't been run, so it was null for every
    player.
  - careerGpHistory: [most-recent-season GP, season-before-that GP], the
    durability signal lib/engine/pool_stats.dart's durabilityAdjustedGp()
    uses to discount injury-prone players' z-scores.

Matches by normalized player name (same normalization as
merge_projections.py) since the bbref scrape keys on bbref's own player ids,
which we have no crosswalk for.

Run from the repo root:
  data_prep/venv/bin/python3 data_prep/merge_basketball_reference.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).parent.parent
PLAYERS_JSON = REPO_ROOT / "assets" / "data" / "players.json"
BBREF_JSON = Path(__file__).parent / "basketball_reference_last2yrs.raw.json"

# Most-recent-first; keep in sync with scrape_basketball_reference.py's SEASONS.
SEASONS_MOST_RECENT_FIRST = ["2026", "2025"]


# bbref names keep real diacritics (Jokić, Dončić, Şengün, Porziņģis, ...);
# our screenshot-transcribed names are plain ASCII. Transliterate before
# stripping, or every accented consonant (not just vowels) just vanishes and
# breaks the match (same map as fetch_nba_player_ids.py's normalize()).
_ACCENTS = {
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
    "ş": "s", "ğ": "g", "ı": "i",
    "’": "", "'": "", ".": "",
}


def _normalize_name(name: str) -> str:
    name = name.lower()
    for src, dst in _ACCENTS.items():
        name = name.replace(src, dst)
    name = re.sub(r"[^a-z\s]", "", name)
    name = re.sub(r"\b(jr|sr|ii|iii|iv)\b", "", name)
    return re.sub(r"\s+", " ", name).strip()


def _build_bbref_index(bbref: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {_normalize_name(entry["name"]): entry for entry in bbref.values()}


def merge(players: list[dict[str, Any]], bbref: dict[str, Any]) -> tuple[int, list[str]]:
    bbref_by_name = _build_bbref_index(bbref)
    matched = 0
    unmatched: list[str] = []

    for player in players:
        entry = bbref_by_name.get(_normalize_name(player["name"]))
        if entry is None:
            unmatched.append(player["name"])
            continue

        seasons = entry["seasons"]
        gp_history = [seasons[s]["gp"] for s in SEASONS_MOST_RECENT_FIRST if s in seasons]
        if gp_history:
            player["careerGpHistory"] = gp_history

        most_recent_season = next((s for s in SEASONS_MOST_RECENT_FIRST if s in seasons), None)
        if most_recent_season is not None:
            s = seasons[most_recent_season]
            # Only worth showing as "last year" if they actually played -
            # a 0-GP season (e.g. missed the whole year hurt) has nothing
            # useful to display as a stat line.
            if s["gp"] > 0:
                player["priorSeason"] = {
                    "fgPct": s["fgPct"],
                    "fgAttempted": s["fgAttempted"],
                    "ftPct": s["ftPct"],
                    "ftAttempted": s["ftAttempted"],
                    "threePM": s["threePM"],
                    "pts": s["pts"],
                    "reb": s["reb"],
                    "ast": s["ast"],
                    "stl": s["stl"],
                    "blk": s["blk"],
                    "to": s["to"],
                }

        matched += 1

    return matched, unmatched


def main() -> None:
    players: list[dict[str, Any]] = json.loads(PLAYERS_JSON.read_text())
    bbref: dict[str, Any] = json.loads(BBREF_JSON.read_text())

    matched, unmatched = merge(players, bbref)

    PLAYERS_JSON.write_text(json.dumps(players, indent=2, ensure_ascii=False))
    print(f"Matched {matched}/{len(players)} players against basketball-reference data")

    if unmatched:
        print(f"\n{len(unmatched)} players had no basketball-reference match "
              f"(likely rookies with no prior NBA season):")
        for name in unmatched:
            print(f"  - {name}")


if __name__ == "__main__":
    main()
