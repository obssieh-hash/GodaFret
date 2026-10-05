"""Façade unique : choisit la meilleure source disponible, avec repli automatique."""
from __future__ import annotations

import pandas as pd

from ..config import api_key
from . import extras, macro, sec, yahoo


def ohlcv(ticker: str, period: str = "5y") -> tuple[pd.DataFrame, str]:
    df = yahoo.ohlcv(ticker, period)
    if not df.empty:
        return df, "Yahoo Finance"
    df = extras.stooq_ohlcv(ticker)
    if not df.empty:
        years = {"1y": 1, "2y": 2, "5y": 5, "10y": 10}.get(period, 5)
        return df[df.index >= df.index[-1] - pd.DateOffset(years=years)], "Stooq"
    return pd.DataFrame(), "aucune"


def prices(tickers: list[str], period: str = "5y") -> pd.DataFrame:
    df = yahoo.prices(tuple(tickers), period)
    missing = [t for t in tickers if t not in df.columns or df[t].dropna().empty]
    for t in missing:  # repli ligne à ligne
        alt, _ = ohlcv(t, period)
        if not alt.empty:
            df = df.join(alt["Close"].rename(t), how="outer") if not df.empty else alt[["Close"]].rename(columns={"Close": t})
    return df.sort_index()


def revenue_history(ticker: str, statements: dict | None = None) -> tuple[pd.Series, str]:
    """Chiffre d'affaires annuel : SEC (jusqu'à 10 ans) sinon Yahoo (4 ans)."""
    sec_df = sec.annual_fundamentals(ticker)
    if not sec_df.empty and "revenue" in sec_df and sec_df["revenue"].notna().sum() >= 4:
        return sec_df["revenue"].dropna(), "SEC EDGAR (10-K)"
    st = statements if statements is not None else yahoo.statements(ticker)
    inc = st.get("income", pd.DataFrame()) if st else pd.DataFrame()
    for col in ("Total Revenue", "Operating Revenue"):
        if col in inc:
            return inc[col].dropna(), "Yahoo Finance"
    return pd.Series(dtype=float), "indisponible"


def earnings_surprises(ticker: str) -> tuple[pd.DataFrame, str]:
    """Historique BPA publié vs attendu, du plus ancien au plus récent.
    Colonnes : date, eps_estimate, eps_actual, surprise_pct."""
    df = yahoo.earnings_dates(ticker)
    if not df.empty:
        past = df[df["eps_actual"].notna()].copy()
        if not past.empty:
            past = past.reset_index(names="date")
            return past[["date", "eps_estimate", "eps_actual", "surprise_pct"]], "Yahoo Finance"
    fh = extras.finnhub_earnings(ticker)
    if not fh.empty:
        out = pd.DataFrame({"date": fh["period"], "eps_estimate": fh["estimate"], "eps_actual": fh["actual"],
                            "surprise_pct": fh["surprisePercent"]})
        return out, "Finnhub (date = fin de trimestre)"
    av = extras.alphavantage_earnings(ticker)
    if not av.empty:
        out = pd.DataFrame({"date": av["reportedDate"], "eps_estimate": av["estimatedEPS"],
                            "eps_actual": av["reportedEPS"], "surprise_pct": av["surprisePercentage"]})
        return out, "Alpha Vantage"
    return pd.DataFrame(), "indisponible"


def status() -> list[dict]:
    """Teste chaque source (utilisé sur la page d'accueil)."""
    checks = []

    def run(name, free, needs_key, fn):
        if needs_key and not api_key(needs_key):
            checks.append({"API": name, "Gratuit": free, "Statut": f"clé {needs_key} non fournie (optionnel)"})
            return
        try:
            ok = fn()
            checks.append({"API": name, "Gratuit": free, "Statut": "OK" if ok else "réponse vide"})
        except Exception as exc:
            checks.append({"API": name, "Gratuit": free, "Statut": f"erreur : {type(exc).__name__}"})

    run("Yahoo Finance (yfinance)", "oui, sans clé", None, lambda: not yahoo.ohlcv("SPY", "1mo").empty)
    run("SEC EDGAR XBRL", "oui, sans clé", None, lambda: bool(sec.ticker_to_cik()))
    run("FRED (St. Louis Fed)", "oui, sans clé", None, lambda: not macro.fred_series("DGS10", "2025-01-01").empty)
    run("BCE via Frankfurter (change)", "oui, sans clé", None, lambda: bool(macro.fx_rates()))
    run("Stooq (secours cours)", "oui, sans clé", None, lambda: not extras.stooq_ohlcv("SPY").empty)
    run("Finnhub", "oui, clé gratuite", "FINNHUB_API_KEY", lambda: not extras.finnhub_earnings("AAPL").empty)
    run("Alpha Vantage", "oui, clé gratuite (25/jour)", "ALPHAVANTAGE_API_KEY",
        lambda: not extras.alphavantage_earnings("IBM").empty)
    run("Financial Modeling Prep", "clé gratuite / payant", "FMP_API_KEY",
        lambda: bool(extras.fmp_price_target("AAPL")))
    return checks
