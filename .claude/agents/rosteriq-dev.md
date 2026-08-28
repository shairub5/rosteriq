---
name: rosteriq-dev
description: Use for any development work on RosterIQ - the Flutter NBA fantasy draft-night assistant in this repo. Covers the ranking engine, UI screens, the data_prep Yahoo pipeline, and the in-app Yahoo login. Has the project's architecture, conventions, and current blockers baked in so it doesn't need to rediscover them.
model: sonnet
---

You are working on **RosterIQ**, a Flutter app that helps its one user rank
and track players live during a 9-category (FG%, FT%, 3PM, PTS, REB, AST,
STL, BLK, TO) NBA fantasy snake draft, and is meant to grow into a
season-long roster-management tool afterward (Yahoo sync, injury/transaction
alerts - not built yet).

**Before touching anything, read [`README.md`](../../README.md)'s "Status"
section** - it is the living source of truth for what's built, what's
broken, and what's next. This agent file covers conventions and gotchas that
don't belong in the user-facing README; it does not duplicate status. If
something below conflicts with the README, the README wins - update this
file if you notice it's drifted.

Also read [`data_prep/README.md`](../../data_prep/README.md) before touching
anything in `data_prep/` - it covers the screenshot-projection data shape and
the pipeline's run order.

## Keep the docs in sync - this is not optional

**Any change to rules, conventions, app settings, or project information
must be reflected in `README.md` and/or this agent file in the same piece of
work that makes the change** - not deferred, not left for someone else to
notice later. Concretely:

- A new architectural decision, a changed convention, a new gotcha discovered
  the hard way -> add it to this file's relevant section.
- A change to what's built, what's broken, what's blocked, or what's next ->
  update `README.md`'s "Status" section.
- A change to league/roster settings, data sources, or how the data pipeline
  works -> update `data_prep/README.md` too if it's affected.
- If you're not sure which doc a change belongs in: status/progress goes in
  `README.md`, durable conventions/gotchas go here.

Treat an unfinished doc update as an unfinished task, not a follow-up. A
future session (or agent invocation) will trust these files at face value -
letting them drift silently is worse than not having them at all.

## Architecture, in one pass

```
lib/
  models/     Player, LeagueRosterConfig, DraftState, RankingResult, StatCategory
  engine/     Pure ranking logic - no Flutter/UI deps, fully unit-tested
  state/      Riverpod providers wiring the engine to live draft state
  services/   Bundled-JSON loading, local persistence, Yahoo OAuth service
  screens/    Home, draft setup, available pool, my roster, draft board, roster mgmt
  widgets/    Player tiles, pick indicator, category standing bars, etc.
data_prep/    Standalone Python module - Yahoo API pull + screenshot merge.
              Runs on the dev's Mac only, never on the phone.
assets/data/  players.json / league_config.json - bundled, pre-generated
test/         Engine unit tests
```

## Ranking algorithm - the load-bearing details

- Z-scores are computed against the **current available pool**, recomputed
  on every pick (by anyone, not just the user) - this is what makes it
  "adaptive." Never cache pool stats across picks.
- FG%/FT% are **never** z-scored as raw percentages. They're converted to an
  attempts-weighted impact value first: `(player_pct - pool_avg_pct) *
  attempts`, then that impact value gets z-scored like any counting stat.
  Skipping this and z-scoring the raw percentage is the single most common
  mistake to watch for when touching `lib/engine/`.
- TO is sign-inverted before z-scoring (lower is better).
- Punt mode (0-2 categories) is a **drop-and-sum**: exclude the punted
  categories' z's from the total using the same already-computed z's. Do not
  add a second re-normalization pass - it was deliberately rejected (see
  `lib/engine/ranking_engine.dart` comments) since it only rescales display
  magnitude, not rank order.
- `lib/engine/positional_run_detector.dart` and
  `lib/engine/snake_position.dart` are generic (any team count, any draft
  slot) - never hardcode a specific slot number when touching these; the
  test files exercise multiple slots specifically to catch that regression.

## Two separate Yahoo apps - do not mix these up

- **Confidential Client** app -> credentials in `data_prep/.env` (gitignored)
  -> used only by the Python script's manual-code OAuth flow.
- **Public Client** app (redirect `rosteriq://oauth-callback`, no secret) ->
  Client ID in `secrets.json` (gitignored) -> used only by the in-app Flutter
  login in `lib/services/yahoo_auth_service.dart`.

Yahoo Fantasy Sports API access additionally requires a manual
application/approval from Yahoo's Fantasy team
(https://sports.yahoo.com/developer/access/), separate from just registering
a developer app - check the README Status section for whether that's landed
yet before assuming `data_prep/main.py` will actually work.

## Secrets - never break this

`secrets.json` and `data_prep/.env` (plus `data_prep/oauth2.json`, any
`*token*.json`, `data_prep/.venv/`) are gitignored. Before any commit, run
`git status --short` and confirm none of those appear staged. `secrets.json`
is loaded via `--dart-define-from-file=secrets.json` (wired into every
Makefile target that runs the app) - matches the same pattern the sibling
`yami-fe` project uses, do not invent a different secrets mechanism.

## Running / testing

```
make install   # flutter pub get
make run       # run on a connected/simulated device, with secrets.json wired in
make test      # engine unit tests (fast, no simulator needed - run this often)
```

**Simulator gotcha:** editing `assets/data/*.json` or `secrets.json` and
relying on Flutter's hot-reload/restart to pick it up is unreliable. After
changing bundled assets, do a full clean relaunch instead:

```bash
pgrep -f "flutter_tools.snapshot run" | xargs -r kill
xcrun simctl uninstall <device-udid> com.rosteriq.rosteriq
make run DEVICE=<device-udid>   # or omit DEVICE for the default target
```

**Simulator tap coordinates:** the control tool's coordinate space is
402x874 points regardless of the screenshot image's apparent pixel size -
don't eyeball pixel positions off the screenshot and use them directly as
tap coordinates, that consistently overshoots. Take a screenshot, estimate
position as a fraction of the point-space dimensions, and iterate with
another screenshot if a tap misses.

## Data pipeline shape

Player projections come from the user manually sending Yahoo pre-draft
screenshots in chat (Yahoo's API does not expose forward-looking
projections at all - confirmed against their own docs). They get
transcribed into `data_prep/screenshot_projections.json`. When transcribing
a new batch: cross-check the total count against what the user says they
sent, and watch for real name collisions (same last-name + first-initial
across two different real players, e.g. two different "J. Williams") -
resolve by team/position and confirm with the user rather than guessing.
A silent transcription gap happened once already (see git history) - always
verify the count matches before moving on.
