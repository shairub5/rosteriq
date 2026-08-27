"""Enumerates every draft-eligible player in the league via Yahoo's raw
paginated players endpoint (25 players per page - the API's own cap). This
uses direct requests rather than yahoo_fantasy_api's League.free_agents()/
taken_players(), since those are scoped to in-season roster status and
aren't the right fit for "give me the whole pre-draft player universe."
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

from yahoo_auth import get_oauth_session, league_key
from yahoo_json_helpers import find_first, flatten_list_of_dicts

BASE_URL = "https://fantasysports.yahooapis.com/fantasy/v2"
PAGE_SIZE = 25


def _parse_player(raw_player: Any) -> dict[str, Any] | None:
    flat = flatten_list_of_dicts(raw_player)
    player_id = flat.get("player_id")
    if player_id is None:
        return None

    name_field = flat.get("name", {})
    full_name = name_field.get("full") if isinstance(name_field, dict) else None

    eligible_positions_raw = flat.get("eligible_positions", [])
    eligible_positions = [
        flatten_list_of_dicts(p).get("position")
        for p in eligible_positions_raw
        if flatten_list_of_dicts(p).get("position")
    ]

    return {
        "yahoo_player_id": str(player_id),
        "name": full_name,
        "team": flat.get("editorial_team_abbr"),
        "eligible_positions": eligible_positions,
    }


def fetch_all_players() -> list[dict[str, Any]]:
    oauth = get_oauth_session()
    league = league_key()
    players: list[dict[str, Any]] = []
    start = 0

    while True:
        url = f"{BASE_URL}/league/{league}/players;start={start};count={PAGE_SIZE}?format=json"
        response = oauth.session.get(url)
        response.raise_for_status()
        payload = response.json()

        raw_players = find_first(payload, "players")
        if not raw_players:
            break
        # Yahoo returns players as a dict keyed "0", "1", ... plus a "count" key.
        page_players = [
            v.get("player") if isinstance(v, dict) else None
            for k, v in raw_players.items()
            if k != "count" and isinstance(v, dict)
        ]
        page_players = [p for p in page_players if p is not None]
        if not page_players:
            break

        for raw_player in page_players:
            parsed = _parse_player(raw_player)
            if parsed:
                players.append(parsed)

        if len(page_players) < PAGE_SIZE:
            break
        start += PAGE_SIZE
        time.sleep(0.2)  # be polite to Yahoo's rate limits

    return players


def main() -> None:
    players = fetch_all_players()
    out_path = Path(__file__).parent / "yahoo_player_pool.raw.json"
    out_path.write_text(json.dumps(players, indent=2))
    print(f"Wrote {len(players)} players to {out_path}")


if __name__ == "__main__":
    main()
