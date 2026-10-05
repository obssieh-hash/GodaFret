"""Préparation des résultats trimestriels (style note pré-résultats JPMorgan)."""
from __future__ import annotations

import math

import numpy as np
import pandas as pd


def reactions(prices: pd.DataFrame, dates: list[pd.Timestamp], bench: pd.Series | None = None) -> pd.DataFrame:
    """Réaction du cours autour de chaque publication.

    Fenêtre = clôture de la veille → clôture du lendemain : couvre les deux cas
    (publication avant l'ouverture ou après la clôture). Inclut la réaction
    relative à l'indice et la dérive à 5 séances.
    """
    close = prices["Close"] if isinstance(prices, pd.DataFrame) else prices
    rows = []
    for d in dates:
        d = pd.Timestamp(d).normalize()
        before = close[close.index < d]
        after = close[close.index > d]
        if before.empty or after.empty:
            continue
        p0, p1 = before.iloc[-1], after.iloc[0]
        p5 = after.iloc[min(4, len(after) - 1)]
        row = {"Date": d.date(), "Réaction J+1": p1 / p0 - 1, "Dérive J+5": p5 / p0 - 1}
        if bench is not None and not bench.empty:
            b0 = bench[bench.index < d]
            b1 = bench[bench.index > d]
            if not b0.empty and not b1.empty:
                row["Réaction vs indice"] = row["Réaction J+1"] - (b1.iloc[0] / b0.iloc[-1] - 1)
        rows.append(row)
    return pd.DataFrame(rows)


def implied_move(chain: dict, spot: float) -> dict:
    """Mouvement implicite = prix du straddle à la monnaie / cours (≈ 0,8 × σ attendue)."""
    calls, puts = chain.get("calls"), chain.get("puts")
    if calls is None or puts is None or calls.empty or puts.empty or not spot:
        return {}
    k = calls.loc[(calls["strike"] - spot).abs().idxmin(), "strike"]

    def mid(df):
        row = df[df["strike"] == k]
        if row.empty:
            return float("nan")
        r = row.iloc[0]
        bid, ask, lastp = r.get("bid", np.nan), r.get("ask", np.nan), r.get("lastPrice", np.nan)
        if bid and ask and not math.isnan(bid) and not math.isnan(ask) and ask > 0:
            return (bid + ask) / 2
        return lastp

    c, p = mid(calls), mid(puts)
    if math.isnan(c) or math.isnan(p):
        return {}
    straddle = c + p
    iv_c = calls.loc[calls["strike"] == k, "impliedVolatility"]
    iv = float(iv_c.iloc[0]) if not iv_c.empty else float("nan")
    return {"strike": float(k), "call": c, "put": p, "straddle": straddle, "move": straddle / spot,
            "iv_atm": iv}


def surprise_stats(hist: pd.DataFrame) -> dict:
    h = hist.dropna(subset=["eps_actual", "eps_estimate"]).tail(8)
    if h.empty:
        return {}
    beat = (h["eps_actual"] > h["eps_estimate"]).mean()
    avg_surprise = h["surprise_pct"].mean() if "surprise_pct" in h else float("nan")
    return {"quarters": len(h), "beat_rate": float(beat), "avg_surprise_pct": float(avg_surprise)}


def revision_signal(eps_trend: pd.DataFrame | None) -> tuple[float, str]:
    """Révisions du consensus du trimestre en cours sur 30 et 90 jours."""
    if eps_trend is None or eps_trend.empty or "0q" not in eps_trend.index:
        return float("nan"), "révisions indisponibles"
    row = eps_trend.loc["0q"]
    cur = row.get("current")
    d90 = row.get("90daysAgo")
    d30 = row.get("30daysAgo")
    if cur is None or d90 in (None, 0) or pd.isna(d90):
        return float("nan"), "révisions indisponibles"
    rev90 = cur / d90 - 1 if d90 > 0 else float("nan")
    rev30 = cur / d30 - 1 if d30 and d30 > 0 else float("nan")
    txt = (f"consensus BPA du trimestre {'relevé' if rev90 > 0 else 'abaissé'} de {abs(rev90):.1%} sur 90 j"
           + (f" et {'+' if rev30 >= 0 else ''}{rev30:.1%} sur 30 j" if not math.isnan(rev30) else ""))
    return float(rev90), txt


def recommendation(stats: dict, rev90: float, implied: float, hist_moves: pd.Series, tech_score: float | None,
                   valuation_upside: float | None) -> tuple[str, list[str]]:
    """Acheter avant / vendre avant / attendre, avec justification."""
    pts, why = 0.0, []
    br = stats.get("beat_rate")
    if br is not None:
        if br >= 0.75:
            pts += 1; why.append(f"bat le consensus {br:.0%} du temps")
        elif br <= 0.4:
            pts -= 1; why.append(f"déçoit souvent ({br:.0%} de battements seulement)")
    if not math.isnan(rev90):
        if rev90 > 0.02:
            pts += 1; why.append("révisions haussières des analystes")
        elif rev90 < -0.02:
            pts -= 1; why.append("révisions baissières des analystes")
    avg_abs = float(hist_moves.abs().mean()) if hist_moves is not None and not hist_moves.empty else float("nan")
    if not math.isnan(implied) and not math.isnan(avg_abs):
        if implied > avg_abs * 1.25:
            why.append(f"options chères : mouvement implicite {implied:.1%} > moyenne historique {avg_abs:.1%} "
                       "(favorise la vente de volatilité, pas l'achat d'options)")
        elif implied < avg_abs * 0.8:
            why.append(f"options bon marché : implicite {implied:.1%} < historique {avg_abs:.1%} "
                       "(achat de straddle intéressant)")
    if hist_moves is not None and len(hist_moves) >= 4:
        pos = (hist_moves > 0).mean()
        if pos >= 0.75:
            pts += 0.5; why.append(f"le titre a monté après {pos:.0%} des dernières publications")
        elif pos <= 0.25:
            pts -= 0.5; why.append(f"le titre a baissé après {1 - pos:.0%} des dernières publications")
    if tech_score is not None and not math.isnan(tech_score):
        pts += 0.5 if tech_score > 0.2 else -0.5 if tech_score < -0.2 else 0
    if valuation_upside is not None and not math.isnan(valuation_upside):
        if valuation_upside < -0.15:
            pts -= 0.5; why.append("valorisation tendue : peu de marge en cas de déception")
    if pts >= 1.5:
        return "ACHETER AVANT", why
    if pts <= -1.5:
        return "VENDRE / ALLÉGER AVANT", why
    return "ATTENDRE LA PUBLICATION", why


def scenarios(spot: float, implied: float, hist_moves: pd.Series) -> dict:
    move = implied if implied and not math.isnan(implied) else (
        float(hist_moves.abs().mean()) if hist_moves is not None and not hist_moves.empty else 0.05)
    up = float(hist_moves[hist_moves > 0].mean()) if hist_moves is not None and (hist_moves > 0).any() else move
    dn = float(hist_moves[hist_moves < 0].mean()) if hist_moves is not None and (hist_moves < 0).any() else -move
    return {"haussier": {"variation": max(move, up), "cours": spot * (1 + max(move, up))},
            "baissier": {"variation": min(-move, dn), "cours": spot * (1 + min(-move, dn))}}
