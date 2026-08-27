"""Pulls last completed season's ACTUAL stats (including FGA/FTA - the
attempt-volume proxy the ranking engine's FG%/FT% impact formula needs) for a
list of Yahoo player ids, via yahoo_fantasy_api's League.player_stats, which
already resolves Yahoo's numeric stat ids to display names for us.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yahoo_fantasy_api as yfa

from yahoo_auth import get_oauth_session, league_key

# yahoo_fantasy_api batches player_stats requests; keep batches modest to
# stay well under Yahoo's URL-length/rate limits.
_BATCH_SIZE = 25

# Display names vary slightly by league stat-category configuration - this
# maps the handful of spellings actually seen in practice to our field names.
# Confirm against the real stat_categories() output during the spike and
# extend as needed.
_FIELD_ALIASES: dict[str, list[str]] = {
    "fg_pct": ["FG%", "Field Goal Percentage"],
    "fga": ["FGA", "Field Goals Attempted"],
    "ft_pct": ["FT%", "Free Throw Percentage"],
    "fta": ["FTA", "Free Throws Attempted"],
    "three_pm": ["3PTM", "3-point Shots Made", "3PM"],
    "pts": ["PTS", "Points"],
    "reb": ["REB", "Rebounds", "Total Rebounds"],
    "ast": ["AST", "Assists"],
    "stl": ["ST", "STL", "Steals"],
    "blk": ["BLK", "Blocks"],
    "to": ["TO", "Turnovers"],
}


def _extract(stats: dict[str, Any], field: str) -> float | None:
    for alias in _FIELD_ALIASES[field]:
        if alias in stats:
            try:
                return float(stats[alias])
            except (TypeError, ValueError):
                return None
    return None


def fetch_prior_season_stats(player_ids: list[str], season_year: int) -> dict[str, dict[str, Any]]:
    oauth = get_oauth_session()
    game = yfa.Game(oauth, "nba")
    league = game.to_league(league_key())

    results: dict[str, dict[str, Any]] = {}
    for i in range(0, len(player_ids), _BATCH_SIZE):
        batch = player_ids[i : i + _BATCH_SIZE]
        stats_batch = league.player_stats(batch, req_type="season", season=season_year)
        for player_stats in stats_batch:
            player_id = str(player_stats.get("player_id"))
            results[player_id] = {
                "fgPct": _extract(player_stats, "fg_pct"),
                "fgAttempted": _extract(player_stats, "fga"),
                "ftPct": _extract(player_stats, "ft_pct"),
                "ftAttempted": _extract(player_stats, "fta"),
                "threePM": _extract(player_stats, "three_pm"),
                "pts": _extract(player_stats, "pts"),
                "reb": _extract(player_stats, "reb"),
                "ast": _extract(player_stats, "ast"),
                "stl": _extract(player_stats, "stl"),
                "blk": _extract(player_stats, "blk"),
                "to": _extract(player_stats, "to"),
            }
    return results


def main() -> None:
    pool_path = Path(__file__).parent / "yahoo_player_pool.raw.json"
    players = json.loads(pool_path.read_text())
    player_ids = [p["yahoo_player_id"] for p in players]

    # Adjust to the actual most-recently-completed NBA season at run time.
    stats = fetch_prior_season_stats(player_ids, season_year=2025)

    out_path = Path(__file__).parent / "yahoo_prior_season_stats.raw.json"
    out_path.write_text(json.dumps(stats, indent=2))
    print(f"Wrote prior-season stats for {len(stats)} players to {out_path}")


if __name__ == "__main__":
    main()
