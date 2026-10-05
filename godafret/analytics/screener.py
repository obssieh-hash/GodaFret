"""Screening d'actions multi-facteurs (style Goldman Sachs) avec note de risque et plan d'entrée."""
from __future__ import annotations

import math

import numpy as np
import pandas as pd

from . import indicators as ind
from . import technical
from .fundamentals import Fundamentals, dividend_safety, moat_score

FACTOR_WEIGHTS = {
    "prudente":  {"Valeur": .20, "Croissance": .10, "Qualité": .30, "Dividende": .20, "Momentum": .05, "Faible risque": .15},
    "modérée":   {"Valeur": .20, "Croissance": .20, "Qualité": .30, "Dividende": .10, "Momentum": .10, "Faible risque": .10},
    "dynamique": {"Valeur": .15, "Croissance": .30, "Qualité": .25, "Dividende": .05, "Momentum": .15, "Faible risque": .10},
    "agressive": {"Valeur": .10, "Croissance": .35, "Qualité": .20, "Dividende": .00, "Momentum": .25, "Faible risque": .10},
}
MAX_RISK = {"prudente": 5.0, "modérée": 6.5, "dynamique": 8.0, "agressive": 10.0}


def _scale(x: float, lo: float, hi: float) -> float:
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return float("nan")
    return float(np.clip(1 + 9 * (x - lo) / (hi - lo), 1, 10))


def risk_score(f: Fundamentals, vol: float, mdd: float) -> tuple[float, str]:
    is_fin = "Financial" in (f.sector or "")
    comps = {
        "volatilité": (_scale(vol, 0.15, 0.60), 0.30, f"volatilité {vol:.0%}" if not math.isnan(vol) else ""),
        "bêta": (_scale(f.beta, 0.5, 2.0), 0.15, f"bêta {f.beta:.2f}" if not math.isnan(f.beta) else ""),
        "drawdown": (_scale(-mdd, 0.10, 0.60), 0.15, f"baisse max 2 ans {mdd:.0%}" if not math.isnan(mdd) else ""),
        "dette": (5.0 if is_fin else _scale(f.debt_to_equity, 0.0, 3.0), 0.15,
                  "" if is_fin or math.isnan(f.debt_to_equity) else f"dette/capitaux propres {f.debt_to_equity:.2f}"),
        "stabilité": (9.0 if (not math.isnan(f.net_margin) and f.net_margin < 0) else _scale(f.op_margin_std, 0.0, 0.10),
                      0.10, "pertes nettes" if (not math.isnan(f.net_margin) and f.net_margin < 0) else
                      (f"marges instables (σ {f.op_margin_std:.1%})" if not math.isnan(f.op_margin_std) else "")),
        "taille": (_scale(-math.log10(f.market_cap) if f.market_cap and f.market_cap > 0 else float("nan"),
                          -math.log10(200e9), -math.log10(2e9)), 0.10,
                   f"capitalisation {f.market_cap / 1e9:,.0f} Md" if f.market_cap and not math.isnan(f.market_cap) else ""),
        "valorisation": (8.0 if (math.isnan(f.pe) or f.pe <= 0 or f.pe > 60) else _scale(f.pe, 10, 60), 0.05,
                         f"PER {f.pe:.0f}" if not math.isnan(f.pe) and f.pe > 0 else "PER non significatif"),
    }
    tot_w = sum(w for v, w, _ in comps.values() if not math.isnan(v))
    score = sum(v * w for v, w, _ in comps.values() if not math.isnan(v)) / tot_w if tot_w else 5.0
    top = sorted([(v, txt) for v, w, txt in comps.values() if not math.isnan(v) and txt], reverse=True)
    hi = [t for v, t in top if v >= 6][:3]
    lo = [t for v, t in sorted(top) if v <= 3][:2]
    just = ("Risque porté par : " + ", ".join(hi) if hi else "Aucun facteur de risque majeur") + (
        ". Points rassurants : " + ", ".join(lo) if lo else "") + "."
    return round(float(score), 1), just


def build_row(f: Fundamentals, ohlcv: pd.DataFrame | None, div_years: int = 0) -> dict:
    close = ohlcv["Close"] if ohlcv is not None and not ohlcv.empty else pd.Series(dtype=float)
    r = close.pct_change(fill_method=None).dropna()
    vol = ind.annualized_vol(r.tail(252)) if len(r) > 60 else float("nan")
    mdd = ind.max_drawdown(close.tail(504)) if not close.empty else float("nan")
    mom = float(close.iloc[-22] / close.iloc[-252] - 1) if len(close) >= 252 else float("nan")
    price = float(close.iloc[-1]) if not close.empty else f.price

    moat, moat_pts, moat_why = moat_score(f)
    safety, safety_why = dividend_safety(f, div_years)
    risk, risk_why = risk_score(f, vol, mdd)

    central = f.target_mean if f.n_analysts >= 3 and not math.isnan(f.target_mean) else price * 1.07
    s = vol if not math.isnan(vol) else 0.30
    bull, bear = central * math.exp(0.8416 * s), central * math.exp(-0.8416 * s)

    plan = {}
    if ohlcv is not None and len(ohlcv) >= 220:
        a = float(ind.atr(ohlcv).iloc[-1])
        sup, res = technical.levels(ohlcv, a)
        plan = technical.trade_plan(ohlcv, sup, res, a, technical.fibonacci(ohlcv))

    rev = f.revenue.tail(6) if f.revenue is not None else pd.Series(dtype=float)
    return {
        "Ticker": f.ticker, "Nom": f.name, "Secteur": f.sector, "Pays": f.country, "Devise": f.currency,
        "Cours": price, "Capitalisation (Md)": f.market_cap / 1e9 if not math.isnan(f.market_cap) else np.nan,
        "PER": f.pe if f.pe and f.pe > 0 else np.nan, "PER prévisionnel": f.forward_pe,
        "CA CAGR": f.revenue_cagr, "Années de CA": f.revenue_years, "Source CA": f.revenue_source,
        "CA historique": {d.year: v for d, v in rev.items()},
        "Dette/Capitaux propres": f.debt_to_equity, "ROIC": f.roic, "Marge op.": f.operating_margin,
        "Rendement": f.dividend_yield, "Sécurité dividende /10": safety, "Années de hausse du dividende": div_years,
        "Avantage concurrentiel": moat, "Note moat /10": moat_pts, "Pourquoi (moat)": "; ".join(moat_why),
        "Objectif 12 m baissier": bear, "Objectif 12 m central": central, "Objectif 12 m haussier": bull,
        "Analystes (bas/haut)": f"{f.target_low:.2f} / {f.target_high:.2f}" if f.n_analysts else "—",
        "Nb analystes": f.n_analysts, "Note de risque /10": risk, "Justification risque": risk_why,
        "Volatilité": vol, "Bêta": f.beta, "Momentum 12-1 m": mom,
        "Zone d'entrée": plan.get("zone d'entrée", "—"), "Stop-loss": plan.get("stop-loss", np.nan),
        "Objectif technique": plan.get("objectif", np.nan), "R/R": plan.get("ratio rendement/risque", np.nan),
    }


def _pct_rank(s: pd.Series, ascending: bool = True) -> pd.Series:
    return s.rank(pct=True, ascending=ascending).fillna(0.5)


def score(df: pd.DataFrame, tolerance: str, sectors: list[str] | None = None) -> pd.DataFrame:
    if df.empty:
        return df
    out = df.copy()
    sector_pe = out.groupby("Secteur")["PER"].transform("median")
    out["PER médian secteur"] = sector_pe
    out["PER vs secteur"] = out["PER"] / sector_pe - 1
    out["Valeur"] = _pct_rank(-out["PER vs secteur"])
    out["Croissance"] = _pct_rank(out["CA CAGR"])
    out["Qualité"] = _pct_rank(out["Note moat /10"])
    out["Dividende"] = _pct_rank(out["Rendement"].fillna(0) * out["Sécurité dividende /10"].fillna(0))
    out["Momentum"] = _pct_rank(out["Momentum 12-1 m"])
    out["Faible risque"] = _pct_rank(-out["Note de risque /10"])
    w = FACTOR_WEIGHTS[tolerance]
    out["Score global"] = sum(out[k] * v for k, v in w.items()) * 100
    out["Éligible"] = out["Note de risque /10"] <= MAX_RISK[tolerance]
    if sectors:
        out["Éligible"] &= out["Secteur"].isin(sectors)
    return out.sort_values(["Éligible", "Score global"], ascending=False)


def allocate(top: pd.DataFrame, amount: float, max_weight: float = 0.15) -> pd.DataFrame:
    """Pondération inverse à la volatilité, plafonnée (taille de position façon risk manager)."""
    out = top.copy()
    if out.empty:
        return out
    max_weight = max(max_weight, 1.0 / len(out))
    inv = 1 / out["Volatilité"].replace(0, np.nan).fillna(out["Volatilité"].median() or 0.3)
    w = inv / inv.sum()
    for _ in range(20):
        over = w > max_weight
        if not over.any():
            break
        excess = (w[over] - max_weight).sum()
        w[over] = max_weight
        w[~over] += excess * w[~over] / w[~over].sum()
    out["Poids"] = w
    out["Montant"] = w * amount
    out["Nb d'actions"] = np.floor(out["Montant"] / out["Cours"])
    return out
