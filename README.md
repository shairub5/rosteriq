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

See the doc comments in `lib/engine/` for the per-function detail on the
ranking math.

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

## Status (as of 2026-08-28)

**Done:**
- Home screen -> Draft Setup (name the other 11 teams) -> Draft Night
  (Pool / My Roster / Board tabs). Draft Night is fully functional: tap to
  draft-by-me or draft-by-other-team, live-recomputed z-score rankings, punt
  toggle (0-2 categories), Sort dropdown (Our Ranking / Source Rank) and
  Stats dropdown (Projected / Last Year) side by side, roster-fit warning
  badges, positional-run banner, generic snake-draft pick indicator.
- Ranking engine fully unit-tested (17 tests: `test/*.dart`) - z-scores,
  FG%/FT% volume weighting, TO inversion, punt drop-and-sum, roster-fit,
  positional-run detection, snake-position math for arbitrary draft slots.
- 296 players loaded into `assets/data/players.json`, transcribed from Yahoo
  pre-draft screenshots into `data_prep/screenshot_projections.json`.
  **Known gap:** every player's `fgAttempted`/`ftAttempted` is currently `0`
  (no real prior-season data merged yet), so FG%/FT% contribute nothing to
  the live ranking right now - it's effectively a 7-cat ranking until the
  Yahoo data pull below actually runs.
- Basketball app icon (`assets/icon/app_icon.png`, via flutter_launcher_icons).
- `data_prep/` Python module built (Yahoo OAuth, league settings fetch,
  prior-season stats fetch, projection merge) - **not yet successfully run**,
  see blocker below.
- In-app Yahoo login (`lib/services/yahoo_auth_service.dart`,
  `lib/screens/roster_management_screen.dart`) - connect/store-token only,
  no API calls made with the token yet (that's future "Manage Roster" work:
  live sync, injury/transaction alerts). Built but not yet tested end-to-end
  on a device/simulator.
- Repo pushed: https://github.com/shairub5/rosteriq (verified no secrets
  committed - `secrets.json`, `data_prep/.env`, `data_prep/oauth2.json`,
  `.venv/` are all gitignored).

**Current blocker:** the Yahoo Fantasy Sports API requires a separate manual
application/approval from Yahoo's Fantasy team beyond just registering a
developer app (see https://sports.yahoo.com/developer/access/) - submitted,
awaiting their review, no ETA. Two Yahoo apps exist for two different
purposes:
- **Confidential Client** (`data_prep/.env`) - for the Python script's
  manual-code OAuth flow. This is the one the pending approval is for.
- **Public Client** (`secrets.json`, redirect `rosteriq://oauth-callback`) -
  for the in-app Flutter login. Client ID has been added to `secrets.json`
  by the user; the actual in-app login flow has not been test-run yet.

**Still open / next steps:**
1. Test the in-app Yahoo login on the simulator (`make run`, go to Manage
   Roster, tap Connect to Yahoo) - was in progress when this note was
   written.
2. Once Yahoo approval lands: run `python data_prep/main.py` to pull real
   league settings + prior-season stats, fixing the FG%/FT% gap above.
3. Test on a physical iPhone (only simulator-tested so far).
4. Full mock-draft dry run (all 12 teams' picks, punt toggling mid-draft,
   positional-run banner, roster-fit flags as slots fill).
