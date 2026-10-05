"""Yahoo Finance (via yfinance) — gratuit, sans clé.

Couvre : cours historiques OHLCV, profil et ratios, états financiers (4 ans),
dividendes, historique des résultats et surprises, consensus, objectifs des
analystes, chaînes d'options (mouvement implicite).
"""
from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor

import pandas as pd

from .cache import DAY, HOUR, cached

log = logging.getLogger(__name__)


def _yf():
    import yfinance as yf

    return yf


def _close_frame(raw: pd.DataFrame, tickers: list[str]) -> pd.DataFrame:
    if raw is None or raw.empty:
        return pd.DataFrame()
    if isinstance(raw.columns, pd.MultiIndex):
        lvl0 = raw.columns.get_level_values(0)
        field = "Close" if "Close" in lvl0 else "Adj Close"
        out = raw[field]
    else:
        out = raw[["Close"]].rename(columns={"Close": tickers[0]})
    out = out.copy()
    out.index = pd.to_datetime(out.index).tz_localize(None)
    return out.dropna(how="all")


@cached(ttl=6 * HOUR)
def prices(tickers: tuple[str, ...], period: str = "5y") -> pd.DataFrame:
    """Cours de clôture ajustés (dividendes + splits), une colonne par ticker."""
    tickers = list(dict.fromkeys(t.upper().strip() for t in tickers if t.strip()))
    if not tickers:
        return pd.DataFrame()
    raw = _yf().download(tickers, period=period, auto_adjust=True, progress=False, threads=True)
    return _close_frame(raw, tickers)


@cached(ttl=6 * HOUR)
def ohlcv(ticker: str, period: str = "5y", interval: str = "1d") -> pd.DataFrame:
    df = _yf().Ticker(ticker).history(period=period, interval=interval, auto_adjust=True)
    if df is None or df.empty:
        return pd.DataFrame()
    df = df[["Open", "High", "Low", "Close", "Volume"]].copy()
    df.index = pd.to_datetime(df.index).tz_localize(None)
    return df.dropna(subset=["Close"])


@cached(ttl=DAY)
def info(ticker: str) -> dict:
    try:
        data = _yf().Ticker(ticker).info or {}
    except Exception as exc:  # Yahoo renvoie parfois 404/401 de façon transitoire
        log.warning("info %s: %s", ticker, exc)
        data = {}
    return dict(data)


def infos(tickers: list[str], workers: int = 8) -> dict[str, dict]:
    with ThreadPoolExecutor(max_workers=workers) as ex:
        return dict(zip(tickers, ex.map(info, tickers)))


def _normalize_statement(df: pd.DataFrame | None) -> pd.DataFrame:
    """Lignes = dates (croissantes), colonnes = postes comptables."""
    if df is None or df.empty:
        return pd.DataFrame()
    out = df.T.copy()
    out.index = pd.to_datetime(out.index)
    out = out.sort_index()
    out = out.apply(pd.to_numeric, errors="coerce")
    return out.dropna(how="all")


@cached(ttl=DAY)
def statements(ticker: str, quarterly: bool = False) -> dict[str, pd.DataFrame]:
    t = _yf().Ticker(ticker)
    try:
        if quarterly:
            raw = {"income": t.quarterly_income_stmt, "balance": t.quarterly_balance_sheet,
                   "cashflow": t.quarterly_cashflow}
        else:
            raw = {"income": t.income_stmt, "balance": t.balance_sheet, "cashflow": t.cashflow}
    except Exception as exc:
        log.warning("statements %s: %s", ticker, exc)
        return {}
    out = {k: _normalize_statement(v) for k, v in raw.items()}
    return out if any(not v.empty for v in out.values()) else {}


@cached(ttl=DAY)
def dividends(ticker: str) -> pd.Series:
    s = _yf().Ticker(ticker).dividends
    if s is None or s.empty:
        return pd.Series(dtype=float)
    s = s.copy()
    s.index = pd.to_datetime(s.index).tz_localize(None)
    return s.astype(float)


@cached(ttl=12 * HOUR)
def earnings_dates(ticker: str, limit: int = 16) -> pd.DataFrame:
    """Dates de publication passées et futures avec BPA estimé / publié / surprise."""
    try:
        df = _yf().Ticker(ticker).get_earnings_dates(limit=limit)
    except Exception as exc:
        log.warning("earnings_dates %s: %s", ticker, exc)
        return pd.DataFrame()
    if df is None or df.empty:
        return pd.DataFrame()
    df = df.copy()
    idx = pd.to_datetime(df.index)
    df.index = idx.tz_convert("America/New_York").tz_localize(None) if idx.tz is not None else idx
    df = df.rename(columns={"EPS Estimate": "eps_estimate", "Reported EPS": "eps_actual",
                            "Surprise(%)": "surprise_pct"})
    return df.sort_index()


@cached(ttl=12 * HOUR)
def analyst_data(ticker: str) -> dict:
    """Consensus BPA / CA, révisions, objectifs de cours, historique des surprises."""
    t = _yf().Ticker(ticker)
    out: dict = {}
    for name in ("earnings_estimate", "revenue_estimate", "eps_trend", "earnings_history",
                 "growth_estimates", "analyst_price_targets", "calendar", "recommendations"):
        try:
            val = getattr(t, name)
            if val is not None and not (hasattr(val, "empty") and val.empty):
                out[name] = val
        except Exception as exc:
            log.info("%s %s: %s", name, ticker, exc)
    return out


@cached(ttl=HOUR)
def option_expiries(ticker: str) -> tuple[str, ...]:
    try:
        return tuple(_yf().Ticker(ticker).options)
    except Exception:
        return ()


@cached(ttl=HOUR)
def option_chain(ticker: str, expiry: str) -> dict[str, pd.DataFrame]:
    try:
        ch = _yf().Ticker(ticker).option_chain(expiry)
        return {"calls": ch.calls, "puts": ch.puts}
    except Exception as exc:
        log.warning("option_chain %s %s: %s", ticker, expiry, exc)
        return {}


@cached(ttl=6 * HOUR)
def ohlcv_many(tickers: tuple[str, ...], period: str = "2y") -> dict[str, pd.DataFrame]:
    """OHLCV pour plusieurs tickers en un seul appel."""
    tickers = list(dict.fromkeys(tickers))
    if not tickers:
        return {}
    raw = _yf().download(tickers, period=period, auto_adjust=True, progress=False, threads=True,
                         group_by="ticker")
    out = {}
    if raw is None or raw.empty:
        return out
    for t in tickers:
        try:
            df = raw[t] if isinstance(raw.columns, pd.MultiIndex) else raw
        except KeyError:
            continue
        df = df[["Open", "High", "Low", "Close", "Volume"]].dropna(subset=["Close"]).copy()
        if df.empty:
            continue
        df.index = pd.to_datetime(df.index).tz_localize(None)
        out[t] = df
    return out
