"""Yahoo's raw fantasy API JSON is notoriously awkward: most objects are
serialized as a list of single-key dicts rather than one flat dict (an XML
carryover). These helpers flatten that shape so the fetch scripts can work
with plain dicts instead of hand-indexing lists everywhere.
"""
from __future__ import annotations

from typing import Any


def flatten_list_of_dicts(value: Any) -> dict[str, Any]:
    """Yahoo often represents an object as [{"a": 1}, {"b": 2}, ...] instead
    of {"a": 1, "b": 2}. Merge that into one dict; leave an already-flat dict
    alone.
    """
    if isinstance(value, dict):
        return value
    if isinstance(value, list):
        merged: dict[str, Any] = {}
        for item in value:
            if isinstance(item, dict):
                merged.update(item)
        return merged
    return {}


def find_first(value: Any, key: str) -> Any:
    """Depth-first search for the first occurrence of [key] anywhere in a
    nested Yahoo JSON structure (list/dict mix). Used for fields whose exact
    nesting depth varies by endpoint/response version.
    """
    if isinstance(value, dict):
        if key in value:
            return value[key]
        for v in value.values():
            found = find_first(v, key)
            if found is not None:
                return found
    elif isinstance(value, list):
        for item in value:
            found = find_first(item, key)
            if found is not None:
                return found
    return None
