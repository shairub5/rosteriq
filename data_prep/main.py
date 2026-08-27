"""Orchestrates the full data-prep pipeline, in order:
  1. Fetch league settings/roster config from Yahoo -> league_config.json
  2. Fetch the full draft-eligible player pool from Yahoo
  3. Fetch prior-season actual stats (incl. FGA/FTA) for that pool
  4. Merge with screenshot_projections.json -> assets/data/players.json

Run once before draft night, and again any time the screenshot projections
or league settings change. Requires .env (copy from .env.example) and
screenshot_projections.json to already exist in this directory.
"""
from __future__ import annotations

import json
from pathlib import Path

import fetch_league_settings
import fetch_player_pool
import fetch_stats
import merge_projections

HERE = Path(__file__).parent


def main() -> None:
    print("1/4 Fetching league settings...")
    config = fetch_league_settings.fetch_league_settings()
    (HERE.parent / "assets" / "data" / "league_config.json").write_text(json.dumps(config, indent=2))
    print(f"    {config['teamsCount']} teams, draft slot {config['myDraftSlot']}, "
          f"{len(config['rosterSlots'])} roster slot types")

    print("2/4 Fetching full player pool...")
    players = fetch_player_pool.fetch_all_players()
    (HERE / "yahoo_player_pool.raw.json").write_text(json.dumps(players, indent=2))
    print(f"    {len(players)} players")

    print("3/4 Fetching prior-season actual stats...")
    player_ids = [p["yahoo_player_id"] for p in players]
    stats = fetch_stats.fetch_prior_season_stats(player_ids, season_year=2025)
    (HERE / "yahoo_prior_season_stats.raw.json").write_text(json.dumps(stats, indent=2))
    print(f"    stats for {len(stats)} players")

    print("4/4 Merging with screenshot projections...")
    screenshot_projections = json.loads((HERE / "screenshot_projections.json").read_text())
    merged, unmatched = merge_projections.merge(screenshot_projections, players, stats)
    (HERE.parent / "assets" / "data" / "players.json").write_text(json.dumps(merged, indent=2))
    print(f"    {len(merged)} players merged into assets/data/players.json")
    if unmatched:
        print(f"    {len(unmatched)} unmatched (see merge_projections output above for names)")

    print("\nDone. Re-run `flutter pub get` / restart the app to pick up the new bundled data.")


if __name__ == "__main__":
    main()
