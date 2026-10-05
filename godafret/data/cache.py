"""Cache disque simple (pickle + TTL) pour ménager les quotas des API gratuites."""
from __future__ import annotations

import functools
import hashlib
import os
import pickle
import time
from pathlib import Path

CACHE_DIR = Path(os.environ.get("GODAFRET_CACHE", Path.home() / ".cache" / "godafret"))


def _path(key: str) -> Path:
    return CACHE_DIR / (hashlib.sha256(key.encode()).hexdigest() + ".pkl")


def get(key: str, ttl: float):
    p = _path(key)
    try:
        if p.exists() and time.time() - p.stat().st_mtime < ttl:
            with p.open("rb") as f:
                return pickle.load(f)
    except Exception:
        pass
    return None


def put(key: str, value) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = _path(key).with_suffix(".tmp")
        with tmp.open("wb") as f:
            pickle.dump(value, f)
        tmp.replace(_path(key))
    except Exception:
        pass


def cached(ttl: float):
    """Décorateur : ne met en cache que les résultats non vides."""

    def deco(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            key = f"{fn.__module__}.{fn.__qualname__}:{args!r}:{sorted(kwargs.items())!r}"
            hit = get(key, ttl)
            if hit is not None:
                return hit
            value = fn(*args, **kwargs)
            empty = value is None or (hasattr(value, "empty") and value.empty) or (
                isinstance(value, (dict, list)) and not value
            )
            if not empty:
                put(key, value)
            return value

        return wrapper

    return deco


HOUR = 3600
DAY = 24 * HOUR
