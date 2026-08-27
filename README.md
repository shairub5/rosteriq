# RosterIQ

An NBA fantasy basketball draft-night assistant, built for a 9-category
(FG%, FT%, 3PM, PTS, REB, AST, STL, BLK, TO) snake-draft league. Ranks the
live available player pool with z-scores, adapts as picks happen (by you or
anyone else), supports mid-draft punt strategies, and tracks the full draft
board - all on your phone.

Draft assistance is the first feature, not the only one: RosterIQ is meant
to grow into an ongoing roster-management tool (Yahoo sync, injury/
transaction alerts, trade evaluation).

## How the ranking works

For each of the 9 categories, player values are z-scored against the
*current* available pool (recomputed every time a player is drafted, by
anyone) - the standard approach used by most serious fantasy tools. Two
refinements:

- **FG%/FT% are volume-weighted**, not z-scored as raw percentages: each
  player's percentage is converted to an attempts-weighted "impact" value -
  `(player_pct - pool_avg_pct) * attempts` - before z-scoring, so a
  low-volume high-percentage bench player doesn't outrank a high-volume
  starter.
- **Turnovers are sign-inverted** before z-scoring, since fewer is better.

A punt-mode toggle (0-2 categories) drops those categories from the ranking
sum on the fly - no re-normalization needed, since it only affects display
scale, not rank order.

See [`docs/plan.md`](docs/plan.md) *(or ask in the repo's issue tracker)* for
the full design rationale, or the doc comments in `lib/engine/` for the
per-function detail.

## Project layout

```
lib/
  models/     Player, LeagueRosterConfig, DraftState, RankingResult, StatCategory
  engine/     Pure ranking logic - pool stats, z-scores, punt/roster-fit,
              positional-run detection, generic snake-draft position math
  state/      Riverpod providers wiring the engine to live draft state
  services/   Bundled-JSON loading, local persistence (shared_preferences)
  screens/    Home, draft setup, available pool, my roster, draft board
  widgets/    Player tiles, pick indicator, category standing bars, etc.
data_prep/    Standalone Python module: Yahoo API pull (league settings +
              prior-season stats) + screenshot-projection merge -> the JSON
              files the app bundles. Never runs on the phone.
assets/data/  players.json / league_config.json - bundled, pre-generated data
test/         Unit tests for the engine (ranking, punt, roster-fit, snake
              position, positional-run detection)
```

## Running it

Requires the Flutter SDK (a `Makefile` here assumes a sibling
`../.flutter-sdk` checkout, matching this repo's original dev setup - adjust
`FLUTTER_ROOT` in the Makefile if you're building elsewhere).

```
make install   # flutter pub get
make run       # run on a connected/simulated device
make test      # run the engine unit tests
```

## Refreshing the player data

See [`data_prep/README.md`](data_prep/README.md). In short: Yahoo's public
Fantasy API doesn't expose forward-looking player projections (only actual
season stats), so this season's projections come from a manually-curated
`screenshot_projections.json`, merged with real Yahoo league settings and
prior-season actual stats (used specifically as the FG%/FT% attempt-volume
proxy) via `python data_prep/main.py`.

## Status

Draft-night assistant: functional. Roster-management (live Yahoo sync,
injury/transaction alerts) is a placeholder screen, not yet built.
