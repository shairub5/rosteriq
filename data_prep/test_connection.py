"""Diagnostic: hits the simplest possible Yahoo Fantasy endpoint (game
metadata for NBA) which needs valid OAuth but NO league/team membership at
all. If this works but list_leagues.py doesn't, the issue is "no league/team
yet this season," not an app permissions problem.
"""
from __future__ import annotations

import yahoo_fantasy_api as yfa

from yahoo_auth import get_oauth_session


def main() -> None:
    oauth = get_oauth_session()
    game = yfa.Game(oauth, "nba")

    game_id = game.game_id()
    print(f"Success - resolved current NBA game_id: {game_id}")
    print("This confirms your OAuth token + app permissions are working fine.")
    print("If list_leagues.py still fails, it's specifically about league/team")
    print("membership for this season, not the app's API access.")


if __name__ == "__main__":
    main()
