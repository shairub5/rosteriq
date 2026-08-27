# data_prep

One-time (rerunnable) pipeline that produces the two JSON files the Flutter
app bundles: `../assets/data/players.json` and `../assets/data/league_config.json`.
Runs on your Mac, not on the phone - the app itself makes no network calls.

Kept as a standalone Python package (own venv, own requirements) specifically
so it can later move to a scheduled AWS Lambda / GCP Cloud Run job for
injury-report/transaction polling, without needing to touch the Flutter side.

## Setup

```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in your Yahoo app credentials + league key + draft slot
```

`.env` and any OAuth token file are gitignored - never commit them.

## Screenshot projections

Before running `main.py`, create `screenshot_projections.json` in this
directory: a list of objects shaped like

```json
{
  "name": "Victor Wembanyama",
  "team": "SAS",
  "eligiblePositions": ["C"],
  "gp": 68,
  "fgPct": 0.519,
  "ftPct": 0.823,
  "threePM": 130,
  "pts": 1750,
  "reb": 774,
  "ast": 230,
  "stl": 69,
  "blk": 230,
  "to": 188,
  "adp": 2.3
}
```

This is the file Claude produces from the Yahoo pre-draft screenshots sent
in chat - see `../assets/data/players.json` for a small hand-built sample in
the same shape (minus the Yahoo-sourced `fgAttempted`/`ftAttempted`, which
`main.py` fills in).

## Running

```
python main.py
```

This fetches league settings, the full player pool, and prior-season actual
stats from Yahoo, then merges everything into `assets/data/players.json` /
`league_config.json`. Re-run any time the screenshot projections change or
closer to draft night for fresher prior-season data.

Individual steps can also be run on their own (`fetch_league_settings.py`,
`fetch_player_pool.py`, `fetch_stats.py`, `merge_projections.py`) - useful
for debugging one stage without re-hitting the whole API.

## Known open item

Field-name aliases in `fetch_stats.py` (`_FIELD_ALIASES`) were written from
Yahoo's documented stat categories but not yet verified against a real
response - confirm the actual `display_name` values your league's
`stat_categories()` returns on first run and extend the alias lists if any
category comes back empty.
