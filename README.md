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

- Sort by ADP in the available pool screen (ascending, nulls last); ADP
  value shown inline on each tile when ADP sort is active.
- Roster Slot Composition View on My Roster screen: structured
  Starters/Bench slot layout (PG, SG, G, SF, PF, F, C, UTIL x3, BN x3)
  with player name or "Empty" per slot, using the same greedy assignment
  logic as the roster-fit warning badge.
- Mock Draft Analyzer (4th tab, "Analyzer"): paste a full snake draft,
  pick your slot, and get per-pick swap suggestions showing which better
  player was on the board at each of your selections and the z-score gain.
- NBA schedule features (5th tab, "Playoffs"):
  - `assets/data/nba_schedule.json` bundles per-team game dates and back-to-back
    flags. Currently a placeholder with 3 games per team; replace with real
    2026-27 data when available (season Oct 2026 – Apr 2027, fantasy playoffs
    2027-03-15 to 2027-04-11).
  - `lib/services/schedule_service.dart` / `lib/state/schedule_provider.dart`:
    loads and exposes the schedule via a Riverpod `FutureProvider`.
  - Playoff Schedule screen: ranks available pool players by games in the
    fantasy playoff window, grouped into tiers (Elite 15+, Good 13-14,
    Average 11-12, Weak <11), with per-player B2B counts and z-score shown.
  - "Games This Week" badge on each player tile in the Pool screen: colored
    chip (green=3+, yellow=2, grey=0-1) showing how many games the player's
    team plays in the current Mon-Sun week. Null/hidden while schedule loads.
  - Back-to-back warning chip ("B2B" in orange) on player tile title row when
    the team plays tonight AND tomorrow (load-management risk signal).

- Category radar chart on My Roster screen: 9-axis spider chart
  (CustomPainter, no extra package) visualises team z-scores per category.
  Scale: center = 0, outer ring = +3, clamped at ±4.
- Trade Evaluator tab (6th tab, "Trade", `Icons.swap_horiz`): pick players
  to give/get with a searchable per-column list; shows per-category z-score
  delta and a "you win X categories, lose Y, tie Z" summary. Engine logic in
  `lib/engine/trade_evaluator.dart`.
- Waiver Wire Advisor (Need Impact sort mode): pool screen sort dropdown now
  has a "Need Impact" option that reorders players by how much they fill your
  weakest categories. Score = weighted sum of player z-scores where weight =
  max(0, -teamStanding[cat]). Stored on `RankingResult.needImpact`, computed
  inside `computeRankings`. Engine logic in `lib/engine/waiver_advisor.dart`.
- Onboarding: 3-page PageView shown on first launch (gated by
  `shared_preferences` key `onboarding_complete`). Explains draft assistant,
  z-score ranking, and punt strategy.
- Draft Recap screen: accessible via "Recap" button on the Board tab. Shows
  your picks in pick order with current z-scores, the radar chart, per-
  category A–F grades, strengths/weaknesses summary, and a copy-to-clipboard
  text summary.

- Playoff schedule strength integrated into the "Need" ranking column:
  - `lib/state/settings_provider.dart` — `AppSettings` (schedule boost weight,
    positional need weight, playoff start/end ISO dates) persisted via
    `shared_preferences`. Exposed as `settingsProvider` (StateNotifierProvider).
  - `lib/engine/ranking_engine.dart` — `computeRankings()` now accepts optional
    `playoffGamesByTeam`, `scheduleBoostWeight`, and `positionalNeedWeight`.
    `needAdjustedZ = puntAdjustedZ + (positionalNeedWeight * positionalBonus) + (scheduleBoostWeight * playoffBonus)`.
    Playoff bonus is 0..1 normalised across the pool; teams not in the map get
    neutral 0.5; inactive when schedule hasn't loaded (null map).
  - `lib/state/ranking_provider.dart` — watches `scheduleProvider` and
    `settingsProvider`; builds `playoffGamesByTeam` from `gamesInWindow()` using
    the configured playoff window; passes all new params to `computeRankings()`.
  - `lib/screens/available_pool_screen.dart` — "Need" column header shows
    "pos+sched" subtitle when `scheduleBoostWeight > 0`.
  - `lib/screens/settings_screen.dart` — Settings screen with Fantasy Playoffs
    section (date pickers for window start/end, live top-3 team preview),
    Ranking Weights section (sliders for schedule boost and positional need),
    and Draft section (reset button). Accessible via the settings gear icon added
    to every tab's AppBar.

- Persistent "My Team" saved roster (post-draft in-season mode):
  - `lib/state/saved_roster_provider.dart` — `SavedRosterNotifier` persists
    player IDs to `shared_preferences` key `saved_roster_player_ids` as a
    JSON list. Exposes `savedRosterProvider` (AsyncNotifierProvider) and
    `savedRosterPlayersProvider` (convenience Provider resolving IDs to Player
    objects).
  - Draft Recap screen (`lib/screens/draft_recap_screen.dart`) — "Save My
    Team" / "Update Saved Team" FilledButton writes the draft picks to the
    saved roster. Shows a confirmation snackbar and a replacement warning when
    a roster is already saved.
  - My Team screen (`lib/screens/my_team_screen.dart`) — new 3rd tab ("My
    Team", `Icons.group`) in the shell. Shows the category radar chart,
    per-player z-scores with remove (drop) and placeholder replace buttons,
    and an "Add Player" dialog with name search. Empty state directs the user
    to the Recap screen to save a team.
  - Trade Evaluator (`lib/screens/trade_evaluator_screen.dart`) — auto-
    populates "You Give" from the saved roster when one exists; shows a teal
    banner "Using your saved team · N players". Falls back to the active draft
    roster if no saved team.
  - Waiver Wire / Need Impact (`lib/state/ranking_provider.dart`) — uses the
    saved roster as the need-impact baseline when the draft is either empty or
    complete (in-season mode); uses the live draft roster during an active
    draft. A teal info banner in the Pool screen ("Showing Need Impact vs.
    your saved team") appears when a saved team exists and no draft is active.

**Still open / next steps:**
1. Test the in-app Yahoo login on the simulator (`make run`, go to Manage
   Roster, tap Connect to Yahoo) - was in progress when this note was
   written.
2. Once Yahoo approval lands: run `python data_prep/main.py` to pull real
   league settings + prior-season stats, fixing the FG%/FT% gap above.
3. Test on a physical iPhone (only simulator-tested so far).
4. Full mock-draft dry run (all 12 teams' picks, punt toggling mid-draft,
   positional-run banner, roster-fit flags as slots fill).
