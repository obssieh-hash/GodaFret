"""Fournisseurs optionnels à clé gratuite (Finnhub, Alpha Vantage, FMP) et Stooq.

Chaque fonction renvoie un objet vide si la clé est absente ou si l'appel échoue,
pour que l'outil fonctionne toujours avec les sources sans clé.
"""
from __future__ import annotations

import io
import logging

import pandas as pd

from ..config import api_key
from .cache import DAY, HOUR, cached
from .http import get_json, get_text

log = logging.getLogger(__name__)


# ---------------------------------------------------------------- Finnhub (60 req/min gratuit)
def _finnhub(path: str, **params):
    key = api_key("FINNHUB_API_KEY")
    if not key:
        return None
    try:
        return get_json(f"https://finnhub.io/api/v1/{path}", params={**params, "token": key})
    except Exception as exc:
        log.warning("finnhub %s: %s", path, exc)
        return None


@cached(ttl=12 * HOUR)
def finnhub_earnings(ticker: str) -> pd.DataFrame:
    data = _finnhub("stock/earnings", symbol=ticker)
    if not data:
        return pd.DataFrame()
    df = pd.DataFrame(data)
    df["period"] = pd.to_datetime(df["period"])
    return df.sort_values("period")


@cached(ttl=12 * HOUR)
def finnhub_calendar(ticker: str, start: str, end: str) -> pd.DataFrame:
    data = _finnhub("calendar/earnings", symbol=ticker, **{"from": start, "to": end})
    rows = (data or {}).get("earningsCalendar", [])
    return pd.DataFrame(rows)


@cached(ttl=12 * HOUR)
def finnhub_recommendations(ticker: str) -> pd.DataFrame:
    data = _finnhub("stock/recommendation", symbol=ticker)
    return pd.DataFrame(data or [])


@cached(ttl=HOUR)
def finnhub_news(ticker: str, start: str, end: str) -> list[dict]:
    return _finnhub("company-news", symbol=ticker, **{"from": start, "to": end}) or []


# ---------------------------------------------------------------- Alpha Vantage (25 req/jour)
@cached(ttl=DAY)
def alphavantage_earnings(ticker: str) -> pd.DataFrame:
    key = api_key("ALPHAVANTAGE_API_KEY")
    if not key:
        return pd.DataFrame()
    try:
        data = get_json("https://www.alphavantage.co/query",
                        params={"function": "EARNINGS", "symbol": ticker, "apikey": key})
    except Exception as exc:
        log.warning("alphavantage %s: %s", ticker, exc)
        return pd.DataFrame()
    df = pd.DataFrame(data.get("quarterlyEarnings", []))
    if df.empty:
        return df
    for c in ("reportedEPS", "estimatedEPS", "surprise", "surprisePercentage"):
        if c in df:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    df["reportedDate"] = pd.to_datetime(df["reportedDate"])
    return df.sort_values("reportedDate")


# ---------------------------------------------------------------- Financial Modeling Prep
def _fmp(path: str, **params):
    key = api_key("FMP_API_KEY")
    if not key:
        return None
    try:
        return get_json(f"https://financialmodelingprep.com/stable/{path}", params={**params, "apikey": key})
    except Exception as exc:
        log.warning("fmp %s: %s", path, exc)
        return None


@cached(ttl=DAY)
def fmp_segments(ticker: str) -> pd.DataFrame:
    """Chiffre d'affaires par segment produit (plans FMP payants selon l'offre)."""
    data = _fmp("revenue-product-segmentation", symbol=ticker, period="annual")
    if not data or not isinstance(data, list):
        return pd.DataFrame()
    rows = {}
    for rec in data:
        date = rec.get("date") or rec.get("fiscalYear")
        seg = rec.get("data") if isinstance(rec.get("data"), dict) else None
        if date and seg:
            rows[str(date)] = seg
    df = pd.DataFrame(rows).T
    if df.empty:
        return df
    df.index = pd.to_datetime(df.index, errors="coerce")
    return df.sort_index().apply(pd.to_numeric, errors="coerce")


@cached(ttl=DAY)
def fmp_price_target(ticker: str) -> dict:
    data = _fmp("price-target-consensus", symbol=ticker)
    return data[0] if isinstance(data, list) and data else {}


# ---------------------------------------------------------------- Stooq (secours pour les cours)
@cached(ttl=6 * HOUR)
def stooq_ohlcv(ticker: str) -> pd.DataFrame:
    sym = ticker.lower()
    if "." not in sym:
        sym += ".us"
    try:
        txt = get_text("https://stooq.com/q/d/l/", params={"s": sym, "i": "d"})
        df = pd.read_csv(io.StringIO(txt), parse_dates=["Date"], index_col="Date")
    except Exception as exc:
        log.warning("stooq %s: %s", ticker, exc)
        return pd.DataFrame()
    need = ["Open", "High", "Low", "Close", "Volume"]
    if not set(need) <= set(df.columns):
        return pd.DataFrame()
    return df[need].dropna(subset=["Close"])
