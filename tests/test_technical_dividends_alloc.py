import numpy as np
import pandas as pd

from godafret.analytics import allocation, dividends, earnings, technical
from tests.conftest import make_dividends, make_ohlcv


def test_technical_report_consistency():
    for seed in range(6):
        df = make_ohlcv(seed=seed, n=900)
        rep = technical.analyze(df, cost_basis=float(df["Close"].iloc[-300]))
        p = rep.plan
        assert p["stop-loss"] < p["entrée"] < p["objectif"]
        assert -1 <= rep.score <= 1
        assert rep.rating in ("ACHAT FORT", "ACHAT", "NEUTRE", "VENTE", "VENTE FORTE")
        assert all(s["niveau"] < rep.price for s in rep.supports)
        assert all(r["niveau"] > rep.price for r in rep.resistances)


def test_strong_uptrend_is_bullish():
    df = make_ohlcv(seed=3, n=900, drift=1.2, vol=0.15)
    rep = technical.analyze(df)
    assert rep.trends["Journalière (MM20/MM50)"] in ("haussière", "neutre / en transition")
    assert rep.score > 0


def test_consecutive_increases_ignores_special_dividend():
    d = make_dividends(years=12)
    inc, no_cut = dividends.consecutive_increases(d)
    assert inc == 11 and no_cut == 11
    special = pd.concat([d, pd.Series([5.0], index=[pd.Timestamp("2024-12-20")])]).sort_index()
    assert dividends.consecutive_increases(special)[0] == 11
    assert abs(dividends.growth_rate(d, 5) - 0.07) < 1e-9


def test_dividend_cut_breaks_streak():
    d = make_dividends(years=8)
    d[d.index.year == 2023] *= 0.5
    inc, _ = dividends.consecutive_increases(d)
    assert inc == 2  # coupe en 2023, puis hausses en 2024 et 2025


def test_drip_beats_cash():
    p = dividends.drip_projection(100_000, 0.04, 0.05, 0.05, 0.3, years=10)
    assert p["Écart DRIP vs sans"].iloc[-1] > 0
    assert p["Valeur avec DRIP"].is_monotonic_increasing


def test_pea_eligibility():
    assert dividends.pea_eligible("TTE.PA") and dividends.pea_eligible("ALV.DE")
    assert not dividends.pea_eligible("NESN.SW") and not dividends.pea_eligible("JNJ")
    assert not dividends.pea_eligible("ULVR.L")


def test_allocation_profiles():
    for tol in allocation.TOLERANCE_EQUITY:
        for acc in ("PEA", "CTO", "Assurance-vie", "PER"):
            p = allocation.Profile(age=35, income=50_000, savings=20_000, monthly=500, horizon=15, tolerance=tol,
                                   account=acc, goal="retraite")
            w, _ = allocation.target_allocation(p)
            assert abs(w.sum() - 1) < 1e-9 and (w >= 0).all()
            t = allocation.implement(w, acc)
            assert abs(t["Poids"].sum() - 1) < 1e-9
            if acc == "PEA":
                assert (t.loc[t["Classe"] == "Obligations", "Ticker"] == "—").all()
    short = allocation.Profile(30, 40_000, 10_000, 100, 2, "agressive", "CTO", "achat")
    w, _ = allocation.target_allocation(short)
    eq = sum(v for k, v in w.items() if allocation.SLEEVES[k].asset_class == "Actions")
    assert eq <= 0.20 + 1e-9


def test_dca_percentiles_ordered():
    d = allocation.dca_projection(10_000, 500, 10, 0.06, 0.12, n=2000)
    assert (d["Pessimiste (10 %)"] < d["Médian"]).all() and (d["Médian"] < d["Optimiste (90 %)"]).all()
    assert d["Versé"].iloc[-1] == 10_000 + 500 * 120


def test_earnings_reactions_and_implied_move():
    df = make_ohlcv(seed=1, n=600)
    dates = [df.index[100], df.index[300]]
    r = earnings.reactions(df, dates)
    c = df["Close"]
    assert abs(r["Réaction J+1"].iloc[0] - (c.iloc[101] / c.iloc[99] - 1)) < 1e-12
    calls = pd.DataFrame({"strike": [95, 100, 105], "bid": [6, 3, 1], "ask": [6.2, 3.2, 1.2],
                          "lastPrice": [6, 3, 1], "impliedVolatility": [0.3, 0.3, 0.3]})
    puts = pd.DataFrame({"strike": [95, 100, 105], "bid": [1, 2.8, 6], "ask": [1.2, 3.0, 6.2],
                         "lastPrice": [1, 3, 6], "impliedVolatility": [0.3, 0.3, 0.3]})
    m = earnings.implied_move({"calls": calls, "puts": puts}, 100)
    assert m["strike"] == 100 and abs(m["move"] - 0.06) < 1e-12


def test_trade_plan_never_skips_nearby_resistance():
    df = make_ohlcv(seed=2, n=900)
    price = float(df["Close"].iloc[-1])
    sup = [{"niveau": round(price * 0.98, 2)}]
    res = [{"niveau": round(price * 1.01, 2)}, {"niveau": round(price * 1.25, 2)}]
    fib = technical.fibonacci(df)
    plan = technical.trade_plan(df, sup, res, price * 0.02, fib)
    # résistance à +1 % : pas d'achat sur repli, plan sur cassure avec objectif = résistance suivante
    assert "cassure" in plan["type de configuration"] and plan["alerte"]
    assert plan["entrée"] > res[0]["niveau"] and plan["objectif"] == res[1]["niveau"]
    assert plan["stop-loss"] < plan["entrée"] < plan["objectif"]
