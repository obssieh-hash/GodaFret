"""Analyse technique quantitative : tendances multi-horizons, supports/résistances,
moyennes mobiles, RSI/MACD/Bollinger, volumes, figures chartistes, Fibonacci,
plan de trade (entrée, stop, objectif, ratio rendement/risque) et note finale."""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from . import indicators as ind

FIB_RATIOS = (0.236, 0.382, 0.5, 0.618, 0.786)


@dataclass
class Signal:
    name: str
    weight: float
    value: float      # -1 .. +1
    comment: str


@dataclass
class TechnicalReport:
    price: float
    atr: float
    trends: dict[str, str]
    supports: list[dict]
    resistances: list[dict]
    moving_averages: dict
    crosses: list[dict]
    oscillators: dict[str, str]
    volume: dict[str, str]
    patterns: list[dict]
    fibonacci: dict
    plan: dict
    signals: list[Signal] = field(default_factory=list)
    score: float = 0.0
    rating: str = "NEUTRE"
    frame: pd.DataFrame | None = None


# ------------------------------------------------------------------ tendances
def _trend(close: pd.Series, fast: int, slow: int, slope_len: int) -> str:
    if len(close) < slow + slope_len:
        return "indéterminée (historique court)"
    f, s = ind.sma(close, fast), ind.sma(close, slow)
    p = close.iloc[-1]
    slope = f.iloc[-1] / f.iloc[-1 - slope_len] - 1
    if p > f.iloc[-1] > s.iloc[-1] and slope > 0:
        return "haussière"
    if p < f.iloc[-1] < s.iloc[-1] and slope < 0:
        return "baissière"
    return "neutre / en transition"


def trends(close: pd.Series) -> dict[str, str]:
    weekly = close.resample("W-FRI").last().dropna()
    monthly = close.resample("ME").last().dropna()
    return {"Journalière (MM20/MM50)": _trend(close, 20, 50, 10),
            "Hebdomadaire (MM10/MM40 sem.)": _trend(weekly, 10, 40, 4),
            "Mensuelle (MM6/MM12 mois)": _trend(monthly, 6, 12, 2)}


# ------------------------------------------------------------------ pivots & niveaux
def pivots(df: pd.DataFrame, k: int = 5) -> tuple[pd.Series, pd.Series]:
    """Points hauts/bas locaux (fenêtre ±k séances)."""
    hi, lo = df["High"], df["Low"]
    win = 2 * k + 1
    is_hi = hi == hi.rolling(win, center=True, min_periods=win).max()
    is_lo = lo == lo.rolling(win, center=True, min_periods=win).min()
    return hi[is_hi], lo[is_lo]


def levels(df: pd.DataFrame, atr_value: float, lookback: int = 504, k: int = 5) -> tuple[list[dict], list[dict]]:
    """Regroupe les pivots en zones (tolérance 0,6 ATR) ; force = nombre de contacts + récence."""
    d = df.tail(lookback)
    ph, pl = pivots(d, k)
    pts = pd.concat([ph, pl]).sort_index()
    if pts.empty:
        return [], []
    tol = max(atr_value * 0.6, d["Close"].iloc[-1] * 0.005)
    clusters: list[dict] = []
    for date, lvl in sorted(pts.items(), key=lambda x: x[1]):
        if clusters and abs(lvl - clusters[-1]["mean"]) <= tol:
            c = clusters[-1]
            c["vals"].append(lvl); c["dates"].append(date)
            c["mean"] = float(np.mean(c["vals"]))
        else:
            clusters.append({"vals": [lvl], "dates": [date], "mean": float(lvl)})
    price = d["Close"].iloc[-1]
    end = d.index[-1]
    out = []
    for c in clusters:
        recency = max(0.0, 1 - (end - max(c["dates"])).days / (lookback * 1.45))
        out.append({"niveau": round(c["mean"], 2), "contacts": len(c["vals"]),
                    "dernier contact": max(c["dates"]).strftime("%d/%m/%Y"),
                    "force": round(len(c["vals"]) + 2 * recency, 2),
                    "distance": c["mean"] / price - 1})
    supports = sorted([o for o in out if o["niveau"] < price], key=lambda o: -o["niveau"])
    resist = sorted([o for o in out if o["niveau"] > price], key=lambda o: o["niveau"])
    # on garde les niveaux les plus proches parmi les plus forts
    supports = sorted(sorted(supports, key=lambda o: -o["force"])[:6], key=lambda o: -o["niveau"])[:4]
    resist = sorted(sorted(resist, key=lambda o: -o["force"])[:6], key=lambda o: o["niveau"])[:4]
    return supports, resist


# ------------------------------------------------------------------ moyennes mobiles
def moving_averages(close: pd.Series) -> tuple[dict, list[dict]]:
    p = close.iloc[-1]
    mas = {}
    for n in (50, 100, 200):
        v = ind.sma(close, n).iloc[-1]
        mas[f"MM{n}"] = {"valeur": round(float(v), 2) if not math.isnan(v) else None,
                         "position": "cours au-dessus" if p > v else "cours en dessous" if p < v else "—",
                         "écart": p / v - 1 if v and not math.isnan(v) else float("nan")}
    crosses = []
    for a, b in ((50, 200), (50, 100), (100, 200)):
        diff = (ind.sma(close, a) - ind.sma(close, b)).dropna()
        sign = np.sign(diff)
        ch = sign[sign != sign.shift()].iloc[1:]
        if not ch.empty:
            d, s = ch.index[-1], ch.iloc[-1]
            name = ("Golden cross" if s > 0 else "Death cross") if (a, b) == (50, 200) else (
                "croisement haussier" if s > 0 else "croisement baissier")
            crosses.append({"croisement": f"MM{a} / MM{b}", "type": name, "date": d.strftime("%d/%m/%Y"),
                            "il y a (séances)": int(len(close.loc[d:]) - 1),
                            "état actuel": f"MM{a} {'>' if diff.iloc[-1] > 0 else '<'} MM{b}"})
    return mas, crosses


# ------------------------------------------------------------------ oscillateurs
def oscillators(close: pd.Series) -> tuple[dict, dict]:
    r = ind.rsi(close).iloc[-1]
    m = ind.macd(close)
    bb = ind.bollinger(close)
    pb, bw = bb["pct_b"].iloc[-1], bb["bandwidth"]
    hist = m["hist"]
    txt = {}
    if r >= 70:
        txt["RSI (14)"] = f"{r:.0f} — surachat : le titre a beaucoup monté, risque de pause ou de repli."
    elif r <= 30:
        txt["RSI (14)"] = f"{r:.0f} — survente : vendeurs épuisés, rebond technique possible."
    elif r >= 50:
        txt["RSI (14)"] = f"{r:.0f} — zone haussière saine (acheteurs aux commandes, sans excès)."
    else:
        txt["RSI (14)"] = f"{r:.0f} — zone faible (vendeurs légèrement dominants)."
    above = m["macd"].iloc[-1] > m["signal"].iloc[-1]
    rising = hist.iloc[-1] > hist.iloc[-4] if len(hist.dropna()) > 4 else False
    txt["MACD (12,26,9)"] = (f"MACD {'au-dessus' if above else 'en dessous'} de sa ligne de signal "
                             f"({'momentum haussier' if above else 'momentum baissier'}), histogramme "
                             f"{'en hausse' if rising else 'en baisse'} ; MACD {'positif' if m['macd'].iloc[-1] > 0 else 'négatif'} "
                             f"(tendance de fond {'haussière' if m['macd'].iloc[-1] > 0 else 'baissière'}).")
    squeeze = bw.iloc[-1] <= bw.tail(126).quantile(0.1) if len(bw.dropna()) > 126 else False
    if pb > 1:
        b = "cours au-dessus de la bande haute : extension forte, souvent suivie d'une respiration."
    elif pb < 0:
        b = "cours sous la bande basse : excès baissier, rebond fréquent."
    elif pb > 0.8:
        b = "cours près de la bande haute (pression acheteuse)."
    elif pb < 0.2:
        b = "cours près de la bande basse (pression vendeuse)."
    else:
        b = "cours au milieu des bandes (pas d'excès)."
    if squeeze:
        b += " Bandes très resserrées (squeeze) : un mouvement violent se prépare."
    txt["Bandes de Bollinger (20,2)"] = f"%B = {pb:.2f} — {b}"
    raw = {"rsi": float(r), "macd_above": bool(above), "macd_rising": bool(rising),
           "macd_positive": bool(m["macd"].iloc[-1] > 0), "pct_b": float(pb), "squeeze": bool(squeeze)}
    return txt, raw


# ------------------------------------------------------------------ volumes
def volume_analysis(df: pd.DataFrame) -> tuple[dict, dict]:
    v, c = df["Volume"], df["Close"]
    if v.tail(60).sum() == 0:
        return {"Volumes": "volumes indisponibles"}, {"updown": 1.0, "obv_div": 0}
    ratio = v.tail(20).mean() / v.tail(100).mean()
    chg = c.diff().tail(50)
    up = v.tail(50)[chg > 0].sum()
    down = v.tail(50)[chg < 0].sum()
    updown = up / down if down > 0 else 2.0
    o = ind.obv(df)
    obv_slope = np.polyfit(np.arange(50), o.tail(50).values, 1)[0]
    px_slope = np.polyfit(np.arange(50), c.tail(50).values, 1)[0]
    div = 0
    if obv_slope > 0 and px_slope < 0:
        div = 1
    elif obv_slope < 0 and px_slope > 0:
        div = -1
    txt = {
        "Activité": f"volume 20 j = {ratio:.2f}x la moyenne 100 j "
                    f"({'participation en hausse' if ratio > 1.15 else 'participation en baisse' if ratio < 0.85 else 'participation normale'}).",
        "Acheteurs / vendeurs": f"volume des séances haussières / baissières (50 j) = {updown:.2f} → "
                                f"{'acheteurs dominants' if updown > 1.2 else 'vendeurs dominants' if updown < 0.8 else 'équilibre'}.",
        "OBV": ("divergence haussière : le volume accumule pendant que le prix baisse (accumulation)." if div == 1 else
                "divergence baissière : le prix monte sans soutien du volume (distribution)." if div == -1 else
                "l'OBV confirme le mouvement du prix."),
    }
    return txt, {"updown": float(updown), "obv_div": div, "ratio": float(ratio)}


# ------------------------------------------------------------------ figures chartistes
def patterns(df: pd.DataFrame, lookback: int = 250, k: int = 5) -> list[dict]:
    d = df.tail(lookback)
    ph, pl = pivots(d, k)
    close = d["Close"].iloc[-1]
    found: list[dict] = []
    highs, lows = list(ph.items()), list(pl.items())

    def between_min(a, b):
        return float(d.loc[a:b, "Low"].min())

    def between_max(a, b):
        return float(d.loc[a:b, "High"].max())

    # Double sommet / double creux (deux derniers pivots)
    if len(highs) >= 2:
        (d1, h1), (d2, h2) = highs[-2], highs[-1]
        neck = between_min(d1, d2)
        if abs(h1 / h2 - 1) < 0.03 and len(d.loc[d1:d2]) >= 10 and neck < min(h1, h2) * 0.95:
            confirmed = close < neck
            found.append({"figure": "Double sommet", "biais": "baissier", "ligne de cou": round(neck, 2),
                          "objectif": round(neck - (max(h1, h2) - neck), 2),
                          "statut": "confirmée (cassure)" if confirmed else "en formation"})
    if len(lows) >= 2:
        (d1, l1), (d2, l2) = lows[-2], lows[-1]
        neck = between_max(d1, d2)
        if abs(l1 / l2 - 1) < 0.03 and len(d.loc[d1:d2]) >= 10 and neck > max(l1, l2) * 1.05:
            confirmed = close > neck
            found.append({"figure": "Double creux", "biais": "haussier", "ligne de cou": round(neck, 2),
                          "objectif": round(neck + (neck - min(l1, l2)), 2),
                          "statut": "confirmée (cassure)" if confirmed else "en formation"})
    # Épaule-tête-épaule (3 derniers pivots hauts)
    if len(highs) >= 3:
        (a, ls), (b, hd), (c_, rs) = highs[-3:]
        if hd > ls * 1.03 and hd > rs * 1.03 and abs(ls / rs - 1) < 0.05:
            neck = (between_min(a, b) + between_min(b, c_)) / 2
            found.append({"figure": "Épaule-tête-épaule", "biais": "baissier", "ligne de cou": round(neck, 2),
                          "objectif": round(neck - (hd - neck), 2),
                          "statut": "confirmée (cassure)" if close < neck else "en formation"})
    if len(lows) >= 3:
        (a, ls), (b, hd), (c_, rs) = lows[-3:]
        if hd < ls * 0.97 and hd < rs * 0.97 and abs(ls / rs - 1) < 0.05:
            neck = (between_max(a, b) + between_max(b, c_)) / 2
            found.append({"figure": "Épaule-tête-épaule inversée", "biais": "haussier", "ligne de cou": round(neck, 2),
                          "objectif": round(neck + (neck - hd), 2),
                          "statut": "confirmée (cassure)" if close > neck else "en formation"})
    # Tasse avec anse (sur ~6-12 mois)
    w = d.tail(min(len(d), 200))
    if len(w) >= 80:
        left_i = int(np.argmax(w["High"].values[: len(w) // 2]))
        rim = w["High"].iloc[left_i]
        after = w.iloc[left_i:]
        bottom_i = int(np.argmin(after["Low"].values))
        bottom = after["Low"].iloc[bottom_i]
        depth = 1 - bottom / rim
        right = after.iloc[bottom_i:]
        if 0.12 <= depth <= 0.35 and len(right) >= 15:
            right_peak = right["High"].max()
            handle = right.loc[right["High"].idxmax():]
            pullback = 1 - handle["Low"].min() / right_peak if len(handle) > 1 else 0
            if right_peak >= rim * 0.95 and 0.02 <= pullback <= 0.12 and 5 <= len(handle) <= 30:
                found.append({"figure": "Tasse avec anse", "biais": "haussier", "ligne de cou": round(rim, 2),
                              "objectif": round(rim * (1 + depth), 2),
                              "statut": "confirmée (cassure)" if close > rim else "anse en formation"})
    return found


# ------------------------------------------------------------------ Fibonacci
def fibonacci(df: pd.DataFrame, lookback: int = 252) -> dict:
    d = df.tail(lookback)
    hi_d, lo_d = d["High"].idxmax(), d["Low"].idxmin()
    hi, lo = float(d["High"].max()), float(d["Low"].min())
    up = lo_d < hi_d  # mouvement de référence haussier
    rng = hi - lo
    lv = {f"{r:.1%}": round(hi - r * rng if up else lo + r * rng, 2) for r in FIB_RATIOS}
    ext = {"127.2%": round(lo + 1.272 * rng, 2) if up else round(hi - 1.272 * rng, 2),
           "161.8%": round(lo + 1.618 * rng, 2) if up else round(hi - 1.618 * rng, 2)}
    return {"sens": "retracement d'une hausse" if up else "rebond dans une baisse", "plus haut": round(hi, 2),
            "date plus haut": hi_d.strftime("%d/%m/%Y"), "plus bas": round(lo, 2),
            "date plus bas": lo_d.strftime("%d/%m/%Y"), "niveaux": lv, "extensions": ext}


# ------------------------------------------------------------------ plan de trade
def trade_plan(df: pd.DataFrame, supports: list[dict], resistances: list[dict], atr_value: float,
               fib: dict, cost_basis: float | None = None) -> dict:
    price = float(df["Close"].iloc[-1])
    s1 = next((s["niveau"] for s in supports if price - s["niveau"] <= 3 * atr_value), None)
    if s1 is not None:
        entry_lo, entry_hi = max(s1, price - 1.0 * atr_value), price
        entry = round((entry_lo + entry_hi) / 2, 2)
        stop = round(min(s1 - 0.5 * atr_value, entry - 1.5 * atr_value), 2)
        basis = f"sous le support {s1} (−0,5 ATR)"
    else:
        entry_lo, entry_hi = price - 0.5 * atr_value, price
        entry = round(price - 0.25 * atr_value, 2)
        stop = round(entry - 2 * atr_value, 2)
        basis = "2 ATR sous l'entrée (pas de support proche)"
    risk = entry - stop
    above = [r["niveau"] for r in resistances if r["niveau"] > entry]
    ext = fib["extensions"]["127.2%"]
    if above:
        target, tbasis = above[0], f"première résistance {above[0]}"
    elif ext > entry and (ext - entry) / risk >= 1.5:
        target, tbasis = ext, "extension de Fibonacci 127,2 %"
    else:
        target, tbasis = round(entry + 2.5 * risk, 2), "2,5 × le risque (aucune résistance au-dessus)"
    target2 = above[1] if len(above) > 1 else (ext if ext > target else round(entry + 3.5 * risk, 2))
    rr = (target - entry) / risk if risk > 0 else float("nan")
    setup = "achat sur repli (zone de support)"
    alert = ""
    if above and rr < 1.5:
        # Rendement/risque insuffisant sous la résistance : plan alternatif sur cassure
        r1 = above[0]
        b_entry = round(r1 + 0.25 * atr_value, 2)
        b_stop = round(r1 - 1.0 * atr_value, 2)
        b_target = above[1] if len(above) > 1 else round(b_entry + 2.5 * (b_entry - b_stop), 2)
        alert = (f"Résistance {r1} trop proche (rendement/risque {rr:.2f}) : ne pas acheter ici. "
                 f"Attendre une clôture au-dessus de {r1}.")
        entry_lo, entry_hi, entry, stop, target, target2 = b_entry, b_entry + 0.5 * atr_value, b_entry, b_stop, b_target, \
            (above[2] if len(above) > 2 else round(b_entry + 3.5 * (b_entry - b_stop), 2))
        risk = entry - stop
        basis = f"1 ATR sous la résistance cassée ({r1})"
        tbasis = "résistance suivante" if len(above) > 1 else "2,5 × le risque"
        rr = (target - entry) / risk
        setup = f"achat sur cassure de {r1}"
    hh = float(df["High"].tail(22).max())
    plan = {"cours": round(price, 2), "type de configuration": setup, "zone d'entrée": f"{entry_lo:.2f} – {entry_hi:.2f}",
            "entrée": entry, "stop-loss": stop, "justification stop": basis, "objectif": round(target, 2),
            "justification objectif": tbasis, "objectif 2": round(target2, 2), "risque par action": round(risk, 2),
            "risque %": risk / entry, "gain potentiel %": target / entry - 1,
            "ratio rendement/risque": round(rr, 2) if risk > 0 else float("nan"),
            "stop suiveur (Chandelier 3 ATR)": round(hh - 3 * atr_value, 2)}
    if alert:
        plan["alerte"] = alert
    if cost_basis:
        plan["ta position : plus/moins-value"] = price / cost_basis - 1
        plan["ta position : stop conseillé"] = round(max(stop, hh - 3 * atr_value), 2)
    return plan


def position_size(capital: float, risk_per_trade: float, entry: float, stop: float, max_weight: float = 0.10) -> dict:
    """Taille de position : on risque `risk_per_trade` du capital entre entrée et stop."""
    per_share = entry - stop
    if per_share <= 0:
        return {}
    qty = math.floor(capital * risk_per_trade / per_share)
    qty = min(qty, math.floor(capital * max_weight / entry))
    return {"quantité": qty, "montant": qty * entry, "poids": qty * entry / capital,
            "perte max si stop": qty * per_share}


# ------------------------------------------------------------------ synthèse
def analyze(df: pd.DataFrame, cost_basis: float | None = None) -> TechnicalReport:
    if len(df) < 220:
        raise ValueError("Il faut au moins ~1 an de cours (220 séances) pour l'analyse technique.")
    close = df["Close"]
    a = float(ind.atr(df).iloc[-1])
    tr = trends(close)
    sup, res = levels(df, a)
    mas, crosses = moving_averages(close)
    osc_txt, osc = oscillators(close)
    vol_txt, vol = volume_analysis(df)
    pats = patterns(df)
    fib = fibonacci(df)
    plan = trade_plan(df, sup, res, a, fib, cost_basis)

    sig: list[Signal] = []
    tv = {"haussière": 1, "baissière": -1}
    for (k, v), w in zip(tr.items(), (1.0, 1.5, 1.5)):
        sig.append(Signal(f"Tendance {k.split(' ')[0].lower()}", w, tv.get(v, 0), v))
    p = close.iloc[-1]
    m200 = mas["MM200"]["valeur"]
    if m200:
        sig.append(Signal("Cours vs MM200", 1.0, 1 if p > m200 else -1, mas["MM200"]["position"]))
    m50 = mas["MM50"]["valeur"]
    if m50 and m200:
        sig.append(Signal("MM50 vs MM200", 1.0, 1 if m50 > m200 else -1, "golden cross actif" if m50 > m200 else "death cross actif"))
    r = osc["rsi"]
    rsi_v = -0.5 if r >= 75 else 1 if r <= 25 else 0.5 if r >= 50 else -0.5
    sig.append(Signal("RSI", 0.75, rsi_v, f"{r:.0f}"))
    sig.append(Signal("MACD", 1.0, (0.5 if osc["macd_above"] else -0.5) + (0.5 if osc["macd_rising"] else -0.5),
                      "au-dessus du signal" if osc["macd_above"] else "sous le signal"))
    pb = osc["pct_b"]
    sig.append(Signal("Bollinger %B", 0.5, -1 if pb > 1.05 else 1 if pb < -0.05 else 0, f"{pb:.2f}"))
    ud = vol["updown"]
    sig.append(Signal("Volume acheteurs/vendeurs", 0.75, 1 if ud > 1.2 else -1 if ud < 0.8 else 0, f"{ud:.2f}"))
    sig.append(Signal("OBV", 0.5, vol["obv_div"], "divergence" if vol["obv_div"] else "confirmation"))
    for pt in pats:
        v = (1 if pt["biais"] == "haussier" else -1) * (1 if "confirmée" in pt["statut"] else 0.4)
        sig.append(Signal(pt["figure"], 1.0, v, pt["statut"]))
    rr = plan["ratio rendement/risque"]
    sig.append(Signal("Rendement/risque", 0.75, 1 if rr >= 2.5 else 0.5 if rr >= 2 else -0.5 if rr < 1.2 else 0, f"{rr}"))

    total_w = sum(s.weight for s in sig)
    score = sum(s.weight * s.value for s in sig) / total_w if total_w else 0.0
    rating = ("ACHAT FORT" if score >= 0.5 else "ACHAT" if score >= 0.2 else "NEUTRE" if score > -0.2
              else "VENTE" if score > -0.5 else "VENTE FORTE")

    frame = df.copy()
    for n in (50, 100, 200):
        frame[f"MM{n}"] = ind.sma(close, n)
    frame = frame.join(ind.bollinger(close)[["upper", "lower"]]).join(ind.macd(close))
    frame["RSI"] = ind.rsi(close)
    return TechnicalReport(price=float(p), atr=a, trends=tr, supports=sup, resistances=res, moving_averages=mas,
                           crosses=crosses, oscillators=osc_txt, volume=vol_txt, patterns=pats, fibonacci=fib,
                           plan=plan, signals=sig, score=float(score), rating=rating, frame=frame)
