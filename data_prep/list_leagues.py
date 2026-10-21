"""One-off helper: authenticates with Yahoo (opens a browser login the first
time) and prints your current NBA fantasy league(s) with their league_key -
so you don't have to hunt for it in a URL. Run this once, copy the key you
want into .env as YAHOO_LEAGUE_KEY, then you're done with this script.
"""
from __future__ import annotations

import yahoo_fantasy_api as yfa

from yahoo_auth import get_oauth_session


def main() -> None:
    oauth = get_oauth_session()
    game = yfa.Game(oauth, "nba")

    league_ids = game.league_ids()
    if not league_ids:
        print("No NBA fantasy leagues found for this Yahoo account.")
        return

    print(f"Found {len(league_ids)} NBA league(s) for this account:\n")
    for league_key in league_ids:
        league = game.to_league(league_key)
        try:
            settings = league.settings()
            name = settings.get("name", "(unknown name)")
        except Exception as e:  # noqa: BLE001 - just want the key even if settings fetch fails
            name = f"(couldn't fetch name: {e})"
        print(f"  {league_key}   -   {name}")

    print("\nCopy the league_key for your league into data_prep/.env as YAHOO_LEAGUE_KEY.")


if __name__ == "__main__":
    main()


def res(tree, level=0) -> list[list[int]]:
    if tree.left is None and tree.right is None:
        return [[tree.val]]
    if tree.left is None:
        left = [tree.val] + res(tree.right, level+1)
    if tree.right is None:
        right = [tree.val] + res(tree.left, level+1)
    return [[tree.val]].append(left).append(right)
