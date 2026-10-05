"""Session HTTP avec retries et timeout."""
from __future__ import annotations

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

_session: requests.Session | None = None


def session() -> requests.Session:
    global _session
    if _session is None:
        s = requests.Session()
        retry = Retry(total=3, backoff_factor=0.8, status_forcelist=(429, 500, 502, 503, 504),
                      allowed_methods=("GET",))
        s.mount("https://", HTTPAdapter(max_retries=retry))
        s.headers["User-Agent"] = "Mozilla/5.0 (GodaFret investment research)"
        _session = s
    return _session


def get_json(url: str, params: dict | None = None, headers: dict | None = None, timeout: float = 20):
    r = session().get(url, params=params, headers=headers, timeout=timeout)
    r.raise_for_status()
    return r.json()


def get_text(url: str, params: dict | None = None, headers: dict | None = None, timeout: float = 20) -> str:
    r = session().get(url, params=params, headers=headers, timeout=timeout)
    r.raise_for_status()
    return r.text
