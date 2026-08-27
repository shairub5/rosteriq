"""Thin wrapper around yahoo_oauth so every other module authenticates the
same way. Kept separate specifically so this whole package can later be
lifted into a scheduled AWS Lambda / GCP Cloud Run job (for injury/transaction
polling) without touching the fetch logic - only this file's token-storage
strategy would need to change (e.g. a secrets manager instead of a local
oauth2.json file).
"""
from __future__ import annotations

import json
import os
from pathlib import Path

from dotenv import load_dotenv
from yahoo_oauth import OAuth2

_ENV_LOADED = False


def _ensure_env_loaded() -> None:
    global _ENV_LOADED
    if _ENV_LOADED:
        return
    env_path = Path(__file__).parent / ".env"
    load_dotenv(env_path)
    _ENV_LOADED = True


def get_oauth_session() -> OAuth2:
    """Returns an authenticated OAuth2 session, opening a browser login the
    first time and reusing the cached token file on every run after that.
    """
    _ensure_env_loaded()
    client_id = os.environ["YAHOO_CLIENT_ID"]
    # Public Client apps don't get a secret at all - that's the whole point,
    # a native/installed app can't hold one securely. Tolerate it being blank.
    client_secret = os.environ.get("YAHOO_CLIENT_SECRET", "")
    token_file = os.environ.get("YAHOO_OAUTH_TOKEN_FILE", "oauth2.json")

    token_path = Path(__file__).parent / token_file
    if not token_path.exists():
        # yahoo_oauth writes its own file once the browser flow completes;
        # seed it with the client credentials so it knows what app to use.
        token_path.write_text(json.dumps({"consumer_key": client_id, "consumer_secret": client_secret}))

    oauth = OAuth2(None, None, from_file=str(token_path))
    if not oauth.token_is_valid():
        oauth.refresh_access_token()
    return oauth


def league_key() -> str:
    _ensure_env_loaded()
    return os.environ["YAHOO_LEAGUE_KEY"]


def my_draft_slot() -> int:
    """Your draft position, e.g. 12 for last-of-12. Pre-draft, Yahoo doesn't
    reliably expose this via the API for every league (draft order can be
    randomized at draft time), so this is read from the environment instead
    of guessed - set YAHOO_MY_DRAFT_SLOT in .env once you know it.
    """
    _ensure_env_loaded()
    return int(os.environ["YAHOO_MY_DRAFT_SLOT"])
