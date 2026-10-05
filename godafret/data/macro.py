"""FRED (Réserve fédérale de St. Louis) et BCE via Frankfurter — gratuits.

FRED : téléchargement CSV sans clé (ou API JSON si FRED_API_KEY est fournie).
Frankfurter : taux de change de référence publiés par la BCE.
"""
from __future__ import annotations

import io

import pandas as pd

from ..config import MARKET, api_key
from .cache import DAY, HOUR, cached
from .http import get_json, get_text

FRED_SERIES = {
    "DGS10": "Taux 10 ans US (%)",
    "DGS2": "Taux 2 ans US (%)",
    "DGS3MO": "Taux 3 mois US (%)",
    "T10Y2Y": "Pente 10 ans - 2 ans (%)",
    "BAMLH0A0HYM2": "Spread High Yield US (%)",
    "VIXCLS": "VIX",
    "CPIAUCSL": "Inflation CPI US (indice)",
    "UNRATE": "Chômage US (%)",
    "FEDFUNDS": "Fed Funds (%)",
    "IRLTLT01FRM156N": "Taux 10 ans France (%)",
    "ECBDFR": "Taux de dépôt BCE (%)",
}


@cached(ttl=12 * HOUR)
def fred_series(series_id: str, start: str = "2000-01-01") -> pd.Series:
    key = api_key("FRED_API_KEY")
    if key:
        data = get_json("https://api.stlouisfed.org/fred/series/observations",
                        params={"series_id": series_id, "api_key": key, "file_type": "json",
                                "observation_start": start})
        obs = pd.DataFrame(data.get("observations", []))
        if obs.empty:
            return pd.Series(dtype=float)
        s = pd.Series(pd.to_numeric(obs["value"], errors="coerce").values,
                      index=pd.to_datetime(obs["date"]), name=series_id)
    else:
        txt = get_text("https://fred.stlouisfed.org/graph/fredgraph.csv",
                       params={"id": series_id, "cosd": start})
        df = pd.read_csv(io.StringIO(txt))
        df.columns = ["date", series_id]
        s = pd.Series(pd.to_numeric(df[series_id], errors="coerce").values,
                      index=pd.to_datetime(df["date"]), name=series_id)
    return s.dropna()


def risk_free_rate() -> tuple[float, str]:
    """Taux sans risque (10 ans US) en décimal + source."""
    try:
        s = fred_series("DGS10", start=(pd.Timestamp.today() - pd.Timedelta(days=30)).strftime("%Y-%m-%d"))
        if not s.empty:
            return float(s.iloc[-1]) / 100, f"FRED DGS10 au {s.index[-1]:%d/%m/%Y}"
    except Exception:
        pass
    return MARKET.fallback_risk_free, "valeur par défaut (FRED indisponible)"


@cached(ttl=6 * HOUR)
def fx_rates(base: str = "EUR") -> dict[str, float]:
    """1 `base` = x devise. Source : BCE via Frankfurter."""
    for url in ("https://api.frankfurter.dev/v1/latest", "https://api.frankfurter.app/latest"):
        try:
            data = get_json(url, params={"base": base})
            rates = dict(data.get("rates", {}))
            rates[base] = 1.0
            return rates
        except Exception:
            continue
    return {}


def convert(amount: float, from_ccy: str, to_ccy: str) -> float | None:
    if from_ccy == to_ccy:
        return amount
    # Yahoo cote certaines places en sous-unités (GBp = pence, ZAc, ILA)
    factor = 1.0
    if from_ccy in ("GBp", "GBX"):
        from_ccy, factor = "GBP", 0.01
    rates = fx_rates("EUR")
    if from_ccy not in rates or to_ccy not in rates:
        return None
    return amount * factor / rates[from_ccy] * rates[to_ccy]


@cached(ttl=12 * HOUR)
def fx_history(base: str, currencies: tuple[str, ...], start: str = "2005-01-01") -> pd.DataFrame:
    """Historique quotidien : 1 `base` = x devise (BCE via Frankfurter, repli Yahoo)."""
    ccys = sorted({("GBP" if c in ("GBp", "GBX") else c) for c in currencies if c and c != base})
    if not ccys:
        return pd.DataFrame()
    for url in (f"https://api.frankfurter.dev/v1/{start}..", f"https://api.frankfurter.app/{start}.."):
        try:
            data = get_json(url, params={"base": base, "symbols": ",".join(ccys)}, timeout=40)
            df = pd.DataFrame(data["rates"]).T
            df.index = pd.to_datetime(df.index)
            return df.sort_index().astype(float)
        except Exception:
            continue
    try:
        from . import yahoo

        px = yahoo.prices(tuple(f"{base}{c}=X" for c in ccys), "max")
        px.columns = [c.replace(base, "", 1).replace("=X", "") for c in px.columns]
        return px
    except Exception:
        return pd.DataFrame()


def to_base_currency(prices: pd.DataFrame, currency_of: dict[str, str], base: str) -> tuple[pd.DataFrame, list[str]]:
    """Convertit chaque série de cours dans la devise de référence (le risque de change est alors inclus)."""
    need = {currency_of.get(t) for t in prices.columns} - {base, None}
    if not need:
        return prices, []
    fx = fx_history(base, tuple(sorted(need)), prices.index[0].strftime("%Y-%m-%d"))
    out, failed = prices.copy(), []
    for t in prices.columns:
        c = currency_of.get(t)
        if not c or c == base:
            continue
        c = "GBP" if c in ("GBp", "GBX") else c
        if fx.empty or c not in fx:
            failed.append(t)
            continue
        rate = fx[c].reindex(prices.index).ffill().bfill()
        out[t] = prices[t] / rate
    return out, failed
