"""Données de marché synthétiques : permettent de tester tout le pipeline sans réseau."""
from __future__ import annotations

import numpy as np
import pandas as pd
import pytest


def make_ohlcv(seed: int = 0, n: int = 1500, drift: float = 0.10, vol: float = 0.25, start: float = 100.0,
               end: str = "2026-09-30") -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    idx = pd.bdate_range(end=end, periods=n)
    r = rng.normal(drift / 252 - 0.5 * vol ** 2 / 252, vol / np.sqrt(252), n)
    close = start * np.exp(np.cumsum(r))
    spread = np.abs(rng.normal(0, vol / np.sqrt(252) * 0.6, n)) * close
    high = close + spread
    low = close - spread
    open_ = np.r_[close[0], close[:-1]]
    high = np.maximum.reduce([high, open_, close])
    low = np.minimum.reduce([low, open_, close])
    volume = rng.integers(1_000_000, 5_000_000, n).astype(float)
    return pd.DataFrame({"Open": open_, "High": high, "Low": low, "Close": close, "Volume": volume}, index=idx)


def make_statements(rev0: float = 100e9, growth: float = 0.08, margin: float = 0.25) -> dict:
    dates = pd.to_datetime(["2022-12-31", "2023-12-31", "2024-12-31", "2025-12-31"])
    rev = np.array([rev0 * (1 + growth) ** i for i in range(4)])
    inc = pd.DataFrame({"Total Revenue": rev, "Operating Income": rev * margin, "EBITDA": rev * (margin + 0.05),
                        "Net Income": rev * margin * 0.8, "Interest Expense": rev * 0.005,
                        "Pretax Income": rev * margin * 0.97, "Tax Provision": rev * margin * 0.97 * 0.2},
                       index=dates)
    bal = pd.DataFrame({"Total Debt": [30e9] * 4, "Stockholders Equity": [60e9, 65e9, 70e9, 75e9],
                        "Cash Cash Equivalents And Short Term Investments": [20e9] * 4,
                        "Invested Capital": [90e9, 95e9, 100e9, 105e9], "Ordinary Shares Number": [1e9] * 4},
                       index=dates)
    cf = pd.DataFrame({"Operating Cash Flow": rev * 0.28, "Capital Expenditure": -rev * 0.05,
                       "Free Cash Flow": rev * 0.23, "Depreciation And Amortization": rev * 0.05,
                       "Change In Working Capital": -rev * 0.005, "Cash Dividends Paid": -rev * 0.06},
                      index=dates)
    return {"income": inc, "balance": bal, "cashflow": cf}


def make_info(t: str, price: float, sector: str = "Technology", ccy: str = "USD") -> dict:
    return {"shortName": f"{t} Corp", "sector": sector, "industry": "Software", "country": "United States",
            "currency": ccy, "financialCurrency": ccy, "currentPrice": price, "marketCap": price * 1e9,
            "sharesOutstanding": 1e9, "trailingPE": 25.0, "forwardPE": 22.0, "beta": 1.1, "dividendRate": price * 0.02,
            "payoutRatio": 0.4, "returnOnEquity": 0.25, "grossMargins": 0.55, "operatingMargins": 0.25,
            "profitMargins": 0.2, "averageVolume": 3e6, "targetMeanPrice": price * 1.1, "targetHighPrice": price * 1.4,
            "targetLowPrice": price * 0.8, "numberOfAnalystOpinions": 20, "enterpriseToEbitda": 15.0,
            "revenueGrowth": 0.08, "earningsGrowth": 0.1, "quoteType": "EQUITY"}


def make_dividends(years: int = 12, start: float = 0.5, growth: float = 0.07) -> pd.Series:
    dates, vals = [], []
    for y in range(2026 - years, 2027):
        amt = start * (1 + growth) ** (y - (2026 - years))
        for m in (2, 5, 8, 11):
            d = pd.Timestamp(year=y, month=m, day=15)
            if d < pd.Timestamp("2026-10-01"):
                dates.append(d); vals.append(amt)
    return pd.Series(vals, index=pd.DatetimeIndex(dates))


@pytest.fixture
def fake_market(monkeypatch, tmp_path):
    """Remplace toutes les sources réseau par des données synthétiques déterministes."""
    monkeypatch.setenv("GODAFRET_CACHE", str(tmp_path))
    from godafret.data import cache, extras, macro, sec, yahoo

    monkeypatch.setattr(cache, "CACHE_DIR", tmp_path)
    universe = {}

    def ohlcv_for(t):
        if t not in universe:
            seed = sum(map(ord, t)) % 1000
            base = make_ohlcv(seed=seed, n=5200, drift=0.09, vol=0.18 if t in ("SPY", "VT", "ACWI") else 0.28)
            universe[t] = base
        return universe[t]

    def fake_ohlcv(t, period="5y", interval="1d"):
        df = ohlcv_for(t)
        years = {"1mo": 0.1, "1y": 1, "2y": 2, "5y": 5, "10y": 10, "20y": 20}.get(period, 20)
        return df[df.index >= df.index[-1] - pd.DateOffset(days=int(365 * years))]

    def fake_prices(tickers, period="5y"):
        return pd.DataFrame({t: fake_ohlcv(t, period)["Close"] for t in tickers})

    monkeypatch.setattr(yahoo, "ohlcv", fake_ohlcv)
    monkeypatch.setattr(yahoo, "prices", fake_prices)
    monkeypatch.setattr(yahoo, "ohlcv_many", lambda ts, period="2y": {t: fake_ohlcv(t, period) for t in ts})
    sectors = ["Technology", "Healthcare", "Financial Services", "Consumer Defensive", "Energy"]
    monkeypatch.setattr(yahoo, "info", lambda t: make_info(t, float(ohlcv_for(t)["Close"].iloc[-1]),
                                                           sectors[sum(map(ord, t)) % len(sectors)]))
    monkeypatch.setattr(yahoo, "infos", lambda ts, workers=8: {t: yahoo.info(t) for t in ts})
    monkeypatch.setattr(yahoo, "statements", lambda t, quarterly=False: make_statements())
    monkeypatch.setattr(yahoo, "dividends", lambda t: make_dividends())
    ed_idx = pd.to_datetime(["2024-10-24", "2025-01-30", "2025-04-24", "2025-07-24", "2025-10-23",
                             "2026-01-29", "2026-04-23", "2026-07-23", "2026-10-22"])
    ed = pd.DataFrame({"eps_estimate": [1.0 + 0.05 * i for i in range(9)],
                       "eps_actual": [1.05 + 0.05 * i for i in range(8)] + [np.nan],
                       "surprise_pct": [5.0] * 8 + [np.nan]}, index=ed_idx)
    monkeypatch.setattr(yahoo, "earnings_dates", lambda t, limit=16: ed)
    eps_trend = pd.DataFrame({"current": [1.5], "7daysAgo": [1.49], "30daysAgo": [1.47], "60daysAgo": [1.45],
                              "90daysAgo": [1.42]}, index=["0q"])
    monkeypatch.setattr(yahoo, "analyst_data", lambda t: {"eps_trend": eps_trend})
    monkeypatch.setattr(yahoo, "option_expiries", lambda t: ("2026-10-23", "2026-11-20"))

    def chain(t, e):
        spot = float(ohlcv_for(t)["Close"].iloc[-1])
        strikes = np.round(np.linspace(spot * 0.8, spot * 1.2, 21), 2)
        calls = pd.DataFrame({"strike": strikes, "bid": np.maximum(spot - strikes, 0) + spot * 0.03,
                              "ask": np.maximum(spot - strikes, 0) + spot * 0.032, "lastPrice": 1.0,
                              "impliedVolatility": 0.4})
        puts = pd.DataFrame({"strike": strikes, "bid": np.maximum(strikes - spot, 0) + spot * 0.03,
                             "ask": np.maximum(strikes - spot, 0) + spot * 0.032, "lastPrice": 1.0,
                             "impliedVolatility": 0.4})
        return {"calls": calls, "puts": puts}

    monkeypatch.setattr(yahoo, "option_chain", chain)
    y_idx = pd.bdate_range(end="2026-09-30", periods=3000)
    y = pd.Series(4 + np.cumsum(np.random.default_rng(1).normal(0, 0.05, 3000)), index=y_idx)
    monkeypatch.setattr(macro, "fred_series", lambda sid, start="2000-01-01": y[y.index >= start])
    fx_idx = pd.bdate_range(end="2026-09-30", periods=5300)
    monkeypatch.setattr(macro, "fx_history", lambda base, ccys, start="2005-01-01": pd.DataFrame(
        {c: 1.1 + 0.05 * np.sin(np.arange(len(fx_idx)) / 200) for c in ccys}, index=fx_idx))
    monkeypatch.setattr(macro, "fx_rates", lambda base="EUR": {"EUR": 1.0, "USD": 1.17, "GBP": 0.87, "CHF": 0.94})
    monkeypatch.setattr(sec, "annual_fundamentals", lambda t, years=10: pd.DataFrame(
        {"revenue": [80e9 * 1.08 ** i for i in range(8)]}, index=pd.to_datetime([f"{y}-12-31" for y in range(2018, 2026)])))
    for name in ("finnhub_earnings", "alphavantage_earnings", "fmp_segments", "stooq_ohlcv"):
        monkeypatch.setattr(extras, name, lambda *a, **k: pd.DataFrame())
    return universe
