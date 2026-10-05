"""Orchestration : récupère les données (avec replis) et appelle les moteurs d'analyse.
L'interface Streamlit n'appelle que ce module."""
from __future__ import annotations

import math
from concurrent.futures import ThreadPoolExecutor
from typing import Callable

import numpy as np
import pandas as pd

from .analytics import allocation, dcf, dividends, earnings, risk, screener, technical
from .analytics import indicators as ind
from .analytics.fundamentals import Fundamentals, compute, dividend_safety
from .config import LIMITS, RiskLimits, api_key
from .data import extras, macro, provider, yahoo


# ------------------------------------------------------------------ fondamentaux
def fundamentals(ticker: str, with_sec: bool = True) -> tuple[Fundamentals, dict, dict]:
    info = yahoo.info(ticker)
    st = yahoo.statements(ticker)
    # SEC EDGAR (10 ans de CA) pour les sociétés US ; sinon les 4 ans de Yahoo
    rev, src = provider.revenue_history(ticker, st) if with_sec and "." not in ticker else (pd.Series(dtype=float), "")
    f = compute(ticker, info, st, rev if not rev.empty else None, src)
    return f, info, st


def fx_factor(info: dict) -> float:
    """Conversion devise des comptes → devise de cotation (ex. ADR TSM : TWD → USD)."""
    fin, quote = info.get("financialCurrency"), info.get("currency")
    if not fin or not quote or fin == quote:
        return 1.0
    v = macro.convert(1.0, fin, quote)
    return v if v else 1.0


# ------------------------------------------------------------------ 1. screener
def screen(tickers: list[str], tolerance: str, sectors: list[str] | None = None,
           progress: Callable[[float, str], None] | None = None) -> pd.DataFrame:
    tickers = list(dict.fromkeys(t.strip().upper() for t in tickers if t.strip()))
    hist = yahoo.ohlcv_many(tuple(tickers), "2y")
    rows, done = [], 0

    def one(t):
        f, _, _ = fundamentals(t)
        years = 0
        if f.dividend_yield > 0:
            years, _ = dividends.consecutive_increases(yahoo.dividends(t))
        return screener.build_row(f, hist.get(t), years)

    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {t: ex.submit(one, t) for t in tickers}
        for t, fut in futs.items():
            try:
                rows.append(fut.result())
            except Exception as exc:  # une donnée manquante ne bloque pas tout l'écran
                rows.append({"Ticker": t, "Nom": f"erreur : {type(exc).__name__}"})
            done += 1
            if progress:
                progress(done / len(tickers), t)
    df = pd.DataFrame(rows).set_index("Ticker")
    df = df[df["Cours"].notna()] if "Cours" in df else df
    return screener.score(df, tolerance, sectors)


# ------------------------------------------------------------------ 2. DCF
def dcf_inputs(ticker: str, erp: float, g: float) -> tuple[dcf.DCFInputs, Fundamentals, dict, dict, str]:
    f, info, st = fundamentals(ticker)
    rf, rf_src = macro.risk_free_rate()
    inp = dcf.build_inputs(f, st, info, rf, erp, g, fx_factor(info))
    return inp, f, info, st, rf_src


# ------------------------------------------------------------------ 3. risque
def risk_report(holdings: dict[str, float], value: float, bench: str = "SPY", base_ccy: str = "EUR",
                limits: RiskLimits = LIMITS) -> dict:
    w = risk.normalize_weights(holdings)
    tickers = list(w.index)
    infos = yahoo.infos(tickers + [bench])
    px_long = provider.prices(tickers + [bench], "max")
    px_long = px_long[px_long.index >= "2005-01-01"]
    # Tout est converti dans la devise de référence : le risque de change est inclus dans la VaR
    px_long, fx_failed = macro.to_base_currency(px_long, {t: infos[t].get("currency") for t in infos}, base_ccy)
    px = risk.clean_prices(px_long[px_long.index >= px_long.index[-1] - pd.DateOffset(years=5)])
    missing = [t for t in tickers if t not in px.columns]
    if missing:
        raise ValueError(f"Pas assez d'historique de cours pour : {', '.join(missing)}")
    rets = risk.returns(px)

    port = risk.portfolio_series(rets, w)
    corr = risk.correlation_report(rets, w)
    sectors = risk.breakdown(w, {t: infos[t].get("sector") or ("ETF" if infos[t].get("quoteType") == "ETF" else None) for t in tickers})
    countries = risk.breakdown(w, {t: infos[t].get("country") for t in tickers})
    currencies = risk.breakdown(w, {t: infos[t].get("currency") for t in tickers})

    try:
        y10 = macro.fred_series("DGS10", "2015-01-01")
    except Exception:
        y10 = pd.Series(dtype=float)
    rate_b = risk.rate_sensitivity(px[tickers], y10)  # variation de prix (fraction) pour +100 pb
    betas = pd.Series({t: ind.beta(rets[t], rets[bench]) for t in tickers}) if bench in rets else pd.Series(dtype=float)

    var = risk.var_table(port, value)
    hist_stress = risk.stress_historical(px_long, w, bench)
    hyp_stress = risk.stress_hypothetical(w, betas, rate_b, value)
    tails = risk.tail_probabilities(port)

    adv = {}
    for t in tickers:
        vol_sh = infos[t].get("averageVolume") or infos[t].get("averageDailyVolume10Day")
        last_px = px[t].dropna().iloc[-1]
        conv = macro.convert(1.0, infos[t].get("currency") or base_ccy, base_ccy) or 1.0
        adv[t] = float(vol_sh) * float(last_px) * conv if vol_sh else float("nan")
    liq = risk.liquidity(w, value, adv, limits.participation_rate)

    cov = risk.ledoit_wolf(rets[tickers].dropna())
    rc = risk.risk_contributions(cov, w)
    vol_a = rets[tickers].std() * math.sqrt(252)
    mdd = pd.Series({t: ind.max_drawdown(px[t]) for t in tickers})
    corr_port = pd.Series({t: rets[t].corr(port) for t in tickers})
    heat = risk.heatmap_scores(w, vol_a, mdd, corr_port, liq["Note liquidité /10"], rate_b, limits)

    worst = min(hyp_stress["Impact portefeuille"].min(),
                hist_stress["Portefeuille"].min() if not hist_stress.empty else 0)
    var99 = float(var.loc[(var["Horizon"] == "1 j") & (var["Confiance"] == "99%"), "VaR historique"].iloc[0])
    checks = risk.check_limits(w, sectors, countries, var99, worst, corr["weighted_avg"],
                               float(liq["Jours pour liquider"].max(skipna=True) if liq["Jours pour liquider"].notna().any() else 0),
                               limits)

    beta_port = float((w * betas.reindex(w.index).fillna(1.0)).sum())
    rate_port = float((w * rate_b.reindex(w.index).fillna(0.0)).sum())
    foreign = float(currencies[[c for c in currencies.index if c != base_ccy]].sum())
    cand = [
        ("marché", abs(beta_port) * 0.35, f"Risque de marché (bêta {beta_port:.2f} : −{beta_port * 35:.0f} % si les actions perdent 35 %)"),
        ("concentration", max(0.0, w.max() - limits.max_single_position) * 3 + w.max() * 0.5,
         f"Concentration : {w.idxmax()} pèse {w.max():.0%}"),
        ("secteur", max(0.0, sectors.max() - limits.max_sector) * 2 + sectors.max() * 0.3,
         f"Concentration sectorielle : {sectors.idxmax()} {sectors.max():.0%}"),
        ("taux", abs(rate_port) * 2, f"Sensibilité aux taux : {rate_port * 100:+.1f} % pour +100 pb"),
        ("change", foreign * 0.10, f"Risque de change : {foreign:.0%} hors {base_ccy}"),
        ("corrélation", max(0.0, (corr["weighted_avg"] or 0) - 0.4), f"Corrélation moyenne élevée ({corr['weighted_avg']:.2f})"),
    ]
    top3 = sorted(cand, key=lambda x: -x[1])[:3]
    hedges = risk.hedging_ideas(top3, value, beta_port, foreign, rate_port, (w.idxmax(), float(w.max())))

    mu = risk.shrunk_expected_returns(rets[tickers].dropna())
    rf, _ = macro.risk_free_rate()
    opt = {m: risk.optimize_weights(cov, m, limits.max_single_position, mu, rf)
           for m in ("risk_parity", "min_variance", "max_sharpe")}

    def stats_for(weights):
        pr = risk.portfolio_series(rets, weights)
        return {"Volatilité": ind.annualized_vol(pr), "Rendement historique": float(pr.mean() * 252),
                "Sharpe": ind.sharpe(pr, rf), "Baisse max": ind.max_drawdown((1 + pr).cumprod())}

    comp = pd.DataFrame({"Actuel": stats_for(w), **{k: stats_for(v) for k, v in opt.items()}}).T
    return {"weights": w, "prices": px, "returns": rets, "port": port, "corr": corr, "sectors": sectors,
            "countries": countries, "currencies": currencies, "rate_beta": rate_b, "betas": betas, "var": var,
            "hist_stress": hist_stress, "hyp_stress": hyp_stress, "tails": tails, "liquidity": liq,
            "contrib": rc, "heat": heat, "checks": checks, "top3": top3, "hedges": hedges, "optimal": opt,
            "compare": comp, "infos": infos, "beta_port": beta_port, "rate_port": rate_port,
            "foreign_share": foreign, "y10": y10, "bench": bench, "fx_failed": fx_failed}


# ------------------------------------------------------------------ 4. résultats
def earnings_report(ticker: str) -> dict:
    df, src = provider.ohlcv(ticker, "5y")
    if df.empty:
        raise ValueError("Cours indisponibles")
    info = yahoo.info(ticker)
    hist, hsrc = provider.earnings_surprises(ticker)
    an = yahoo.analyst_data(ticker)
    all_dates = yahoo.earnings_dates(ticker)
    today = pd.Timestamp.today().normalize()
    future = all_dates[all_dates.index >= today] if not all_dates.empty else pd.DataFrame()
    next_date = future.index.min() if not future.empty else None
    if next_date is None:
        cal = an.get("calendar") or {}
        ed = cal.get("Earnings Date") if isinstance(cal, dict) else None
        if ed:
            next_date = pd.Timestamp(ed[0] if isinstance(ed, (list, tuple)) else ed)

    past_dates = list(hist["date"].tail(8)) if not hist.empty else []
    bench = yahoo.ohlcv("SPY", "5y")
    react = earnings.reactions(df, past_dates, bench["Close"] if not bench.empty else None)
    spot = float(df["Close"].iloc[-1])

    imp = {}
    exps = yahoo.option_expiries(ticker)
    if exps:
        target = next_date if next_date is not None else today
        after = [e for e in exps if pd.Timestamp(e) >= target]
        if after:
            imp = earnings.implied_move(yahoo.option_chain(ticker, after[0]), spot)
            imp["expiry"] = after[0]
    stats = earnings.surprise_stats(hist)
    rev90, rev_txt = earnings.revision_signal(an.get("eps_trend"))
    try:
        tech = technical.analyze(df)
        tscore = tech.score
    except Exception:
        tscore = None
    f = compute(ticker, info, {}, None, "")
    upside = f.target_mean / spot - 1 if f.target_mean and not math.isnan(f.target_mean) else None
    moves = react["Réaction J+1"] if not react.empty else pd.Series(dtype=float)
    reco, why = earnings.recommendation(stats, rev90, imp.get("move", float("nan")), moves, tscore, upside)
    segs = extras.fmp_segments(ticker)
    news = []
    if api_key("FINNHUB_API_KEY"):
        news = extras.finnhub_news(ticker, (today - pd.Timedelta(days=21)).strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d"))
    return {"info": info, "prices": df, "price_source": src, "history": hist, "history_source": hsrc,
            "analyst": an, "next_date": next_date, "reactions": react, "implied": imp, "stats": stats,
            "revision": (rev90, rev_txt), "recommendation": reco, "why": why, "spot": spot,
            "scenarios": earnings.scenarios(spot, imp.get("move", float("nan")), moves),
            "segments": segs, "news": news[:10], "tech_score": tscore}


# ------------------------------------------------------------------ 5. allocation
def allocation_report(p: allocation.Profile) -> dict:
    w, why = allocation.target_allocation(p)
    table = allocation.implement(w, p.account)
    proxies = sorted({allocation.SLEEVES[k].proxy for k in w.index})
    px = provider.prices(proxies, "max")
    hist = allocation.historical_stats(px, w) if not px.empty else {}
    corr = None
    if hist:
        pc = hist["corr"]
        corr = pd.DataFrame({k1: {k2: pc.loc[allocation.SLEEVES[k1].proxy, allocation.SLEEVES[k2].proxy]
                                  for k2 in w.index} for k1 in w.index})
    fwd = allocation.forward_stats(w, corr)
    dca = allocation.dca_projection(p.savings, p.monthly, max(p.horizon, 1), fwd["rendement attendu"], fwd["volatilité"])
    bench = allocation.benchmark(w)
    ips = allocation.ips_markdown(p, table, fwd, hist, bench)
    return {"weights": w, "why": why, "table": table, "hist": hist, "forward": fwd, "dca": dca,
            "benchmark": bench, "ips": ips, "tax": allocation.tax_strategy(p.account),
            "rebalancing": allocation.rebalancing_rules(w)}


# ------------------------------------------------------------------ 6. technique
def technical_report(ticker: str, cost_basis: float | None = None) -> tuple[technical.TechnicalReport, str]:
    df, src = provider.ohlcv(ticker, "5y")
    if df.empty:
        raise ValueError("Cours indisponibles")
    return technical.analyze(df, cost_basis), src


# ------------------------------------------------------------------ 7. dividendes
def dividend_universe(tickers: list[str], account: str,
                      progress: Callable[[float, str], None] | None = None) -> pd.DataFrame:
    rows = []
    tickers = list(dict.fromkeys(t.strip().upper() for t in tickers if t.strip()))

    def one(t):
        f, info, _ = fundamentals(t, with_sec=False)
        divs = yahoo.dividends(t)
        inc, no_cut = dividends.consecutive_increases(divs)
        safety, why = dividend_safety(f, inc)
        dgr5 = dividends.growth_rate(divs, 5)
        eps_g = info.get("earningsGrowth")
        g5 = dividends.forecast_growth(dgr5, f.roe, f.payout_ratio, eps_g if eps_g is None else min(float(eps_g), 0.15))
        region = dividends.region_of(t)
        tax, tax_txt = dividends.tax_rate(account, region)
        return {"Ticker": t, "Nom": f.name, "Secteur": f.sector, "Pays": f.country, "Devise": f.currency,
                "Cours": f.price, "Rendement": f.dividend_yield, "Dividende annuel": f.dividend_rate,
                "Sécurité /10": safety, "Pourquoi": "; ".join(why), "Années de hausse": inc,
                "Années sans baisse": no_cut, "Taux de distribution (BPA)": f.payout_ratio,
                "Taux de distribution (FCF)": f.fcf_payout, "Dette/Capitaux propres": f.debt_to_equity,
                "Croissance div. 5 ans (hist.)": dgr5, "Croissance div. estimée 5 ans": g5,
                "Éligible PEA": dividends.pea_eligible(t), "Région fiscale": region, "Impôt effectif": tax,
                "Fiscalité": tax_txt}

    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {t: ex.submit(one, t) for t in tickers}
        for i, (t, fut) in enumerate(futs.items(), 1):
            try:
                rows.append(fut.result())
            except Exception as exc:
                rows.append({"Ticker": t, "Nom": f"erreur : {type(exc).__name__}"})
            if progress:
                progress(i / len(tickers), t)
    df = pd.DataFrame(rows).set_index("Ticker")
    if "Rendement" in df:
        df = df[df["Rendement"].fillna(0) > 0]
    if account == "PEA" and "Éligible PEA" in df:
        df = df[df["Éligible PEA"]]
    return df
