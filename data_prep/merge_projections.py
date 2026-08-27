"""Merges the two data pipelines into the final players.json the Flutter app
bundles:
  1. screenshot_projections.json - this season's projected per-category
     numbers, hand-transcribed from the user's Yahoo pre-draft screenshots
     (see README in this directory for the expected shape).
  2. yahoo_player_pool.raw.json + yahoo_prior_season_stats.raw.json - real
     Yahoo API data, used here specifically as the FGA/FTA attempt-volume
     proxy for the projected FG%/FT% (see the plan's "FG%/FT% attempt-volume
     handling" decision: projected percentage x prior-season attempts).

Rookies with no prior NBA season have no real attempts to borrow, so their
volume is approximated from the pool's own average attempts-per-point ratio,
scaled by their projected points - a rough proxy, not a real number, kept
separate from a true prior-season figure so it's easy to tell apart later if
this needs revisiting.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


def _normalize_name(name: str) -> str:
    name = name.lower()
    name = re.sub(r"[^a-z\s]", "", name)  # drop punctuation/diacritics-as-ascii noise
    name = re.sub(r"\b(jr|sr|ii|iii|iv)\b", "", name)
    return re.sub(r"\s+", " ", name).strip()


def _slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def _build_yahoo_index(pool: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {_normalize_name(p["name"]): p for p in pool if p.get("name")}


def merge(
    screenshot_projections: list[dict[str, Any]],
    yahoo_pool: list[dict[str, Any]],
    yahoo_stats_by_id: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
    yahoo_by_name = _build_yahoo_index(yahoo_pool)
    unmatched: list[str] = []

    # First pass: attach real prior-season attempts wherever we can match.
    merged: list[dict[str, Any]] = []
    for source_rank, proj in enumerate(screenshot_projections, start=1):
        yahoo_entry = yahoo_by_name.get(_normalize_name(proj["name"]))
        prior_stats = yahoo_stats_by_id.get(yahoo_entry["yahoo_player_id"]) if yahoo_entry else None
        if yahoo_entry is None:
            unmatched.append(proj["name"])

        merged.append(
            {
                "id": _slug(proj["name"]),
                "name": proj["name"],
                "team": proj.get("team") or (yahoo_entry or {}).get("team", ""),
                "eligiblePositions": proj.get("eligiblePositions")
                or (yahoo_entry or {}).get("eligible_positions", []),
                "gp": proj["gp"],
                "fgPct": proj["fgPct"],
                "fgAttempted": (prior_stats or {}).get("fgAttempted"),
                "ftPct": proj["ftPct"],
                "ftAttempted": (prior_stats or {}).get("ftAttempted"),
                "threePM": proj["threePM"],
                "pts": proj["pts"],
                "reb": proj["reb"],
                "ast": proj["ast"],
                "stl": proj["stl"],
                "blk": proj["blk"],
                "to": proj["to"],
                "adp": proj.get("adp"),
                "sourceRank": proj.get("sourceRank", source_rank),
                "dataSource": "screenshotProjection",
                "priorSeason": prior_stats if prior_stats and prior_stats.get("pts") is not None else None,
            }
        )

    # Second pass: fill missing attempts (mostly rookies) with a pool-average
    # attempts-per-point proxy.
    with_attempts = [p for p in merged if p["fgAttempted"] and p["pts"]]
    if with_attempts:
        avg_fga_per_pt = sum(p["fgAttempted"] / p["pts"] for p in with_attempts) / len(with_attempts)
        avg_fta_per_pt = (
            sum((p["ftAttempted"] or 0) / p["pts"] for p in with_attempts if p["ftAttempted"])
            / max(1, len([p for p in with_attempts if p["ftAttempted"]]))
        )
    else:
        avg_fga_per_pt = 0.4
        avg_fta_per_pt = 0.15

    for p in merged:
        if not p["fgAttempted"]:
            p["fgAttempted"] = round(p["pts"] * avg_fga_per_pt)
        if not p["ftAttempted"]:
            p["ftAttempted"] = round(p["pts"] * avg_fta_per_pt)

    return merged, unmatched


def main() -> None:
    here = Path(__file__).parent
    screenshot_projections = json.loads((here / "screenshot_projections.json").read_text())
    yahoo_pool = json.loads((here / "yahoo_player_pool.raw.json").read_text())
    yahoo_stats = json.loads((here / "yahoo_prior_season_stats.raw.json").read_text())

    merged, unmatched = merge(screenshot_projections, yahoo_pool, yahoo_stats)

    out_path = here.parent / "assets" / "data" / "players.json"
    out_path.write_text(json.dumps(merged, indent=2))
    print(f"Wrote {len(merged)} players to {out_path}")

    if unmatched:
        print(f"\n{len(unmatched)} players had no Yahoo API match (no prior-season attempts merged):")
        for name in unmatched:
            print(f"  - {name}")


if __name__ == "__main__":
    main()
