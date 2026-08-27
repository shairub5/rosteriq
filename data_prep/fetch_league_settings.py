"""Pulls league/roster settings from Yahoo and shapes them into the
league_config.json contract the Flutter app expects (see
lib/models/league_config.dart).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yahoo_fantasy_api as yfa

from yahoo_auth import get_oauth_session, league_key, my_draft_slot

# Yahoo's roster_positions position codes we don't want to carry into the
# app's roster-slot config (injured-list style slots aren't real "picks").
_IGNORED_POSITION_TYPES = {"IL", "IL+"}


def fetch_league_settings() -> dict[str, Any]:
    oauth = get_oauth_session()
    game = yfa.Game(oauth, "nba")
    league = game.to_league(league_key())
    settings = league.settings()

    roster_slots = []
    for position in settings.get("roster_positions", []):
        position_type = position.get("position")
        count = int(position.get("count", 0))
        if position_type in _IGNORED_POSITION_TYPES or count == 0:
            continue
        roster_slots.append({"type": position_type, "count": count})

    return {
        "teamsCount": int(settings.get("num_teams", 12)),
        "myDraftSlot": my_draft_slot(),
        "rosterSlots": roster_slots,
    }


def main() -> None:
    config = fetch_league_settings()
    out_path = Path(__file__).parent / "league_config.raw.json"
    out_path.write_text(json.dumps(config, indent=2))
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
