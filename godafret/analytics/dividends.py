"""Stratégie dividendes (style fonds de dotation) : sécurité, croissance, revenus, DRIP."""
from __future__ import annotations

import math

import numpy as np
import pandas as pd

from ..config import TAX_FR


def regular_annual(divs: pd.Series) -> pd.DataFrame:
    """Par année civile complète : total versé (hors exceptionnels) et plus gros versement régulier."""
    if divs is None or divs.empty:
        return pd.DataFrame(columns=["total", "max_regular", "count"])
    d = divs[divs > 0]
    rows = {}
    for year, s in d.groupby(d.index.year):
        med = s.median()
        regular = s[s <= 2.0 * med] if len(s) > 1 else s  # exclut les dividendes exceptionnels
        rows[year] = {"total": float(regular.sum()), "max_regular": float(regular.max()), "count": len(regular)}
    df = pd.DataFrame(rows).T.sort_index()
    this_year = pd.Timestamp.today().year
    return df[df.index < this_year]  # année en cours incomplète exclue


def consecutive_increases(divs: pd.Series) -> tuple[int, int]:
    """(années consécutives de hausse, années consécutives sans baisse)."""
    a = regular_annual(divs)
    if len(a) < 2:
        return 0, 0
    # Versement régulier max par an : robuste au décalage de calendrier des paiements
    v = a["max_regular"].values
    inc = no_cut = 0
    counting_inc = True
    for i in range(len(v) - 1, 0, -1):
        if v[i] >= v[i - 1] * 0.995:
            no_cut += 1
            if counting_inc and v[i] > v[i - 1] * 1.001:
                inc += 1
            else:
                counting_inc = False
        else:
            break
    return inc, no_cut


def growth_rate(divs: pd.Series, years: int = 5) -> float:
    a = regular_annual(divs)
    if len(a) < years + 1:
        return float("nan")
    t = a["total"]
    first, last = t.iloc[-years - 1], t.iloc[-1]
    if first <= 0 or last <= 0:
        return float("nan")
    return (last / first) ** (1 / years) - 1


def forecast_growth(hist_dgr: float, roe: float, payout: float, eps_growth: float | None = None) -> float:
    """Croissance du dividende estimée à 5 ans : moyenne de la croissance historique,
    de la croissance soutenable (ROE × (1 − taux de distribution)) et de la croissance
    du BPA attendue, bornée à [−5 %, 15 %]."""
    cands = []
    if not math.isnan(hist_dgr):
        cands.append(hist_dgr)
    if roe is not None and payout is not None and not math.isnan(roe) and not math.isnan(payout) and 0 < payout < 1.2:
        cands.append(min(roe, 0.40) * max(0.0, 1 - payout))
    if eps_growth is not None and not math.isnan(eps_growth):
        cands.append(eps_growth)
    if not cands:
        return float("nan")
    g = float(np.mean(cands))
    if payout is not None and not math.isnan(payout) and payout > 0.9:
        g = min(g, 0.02)  # peu de marge de hausse
    return float(np.clip(g, -0.05, 0.15))


def tax_rate(account: str, region: str) -> tuple[float, str]:
    """Taux d'imposition effectif annuel sur les dividendes (France 2026)."""
    pfu, ps = TAX_FR.pfu, TAX_FR.social
    us = TAX_FR.us_withholding_treaty
    if account == "PEA":
        if region in ("US", "NON-EU"):
            return 0.0, "NON ÉLIGIBLE au PEA (société hors UE/EEE) : à détenir sur CTO ou via un ETF éligible PEA"
        return 0.0, "aucun impôt tant que l'argent reste dans le PEA ; à la sortie (> 5 ans) : 18,6 % de PS sur les gains"
    if account == "Assurance-vie":
        return 0.0, ("dividendes capitalisés dans le contrat (via unités de compte/ETF) ; à la sortie après 8 ans : "
                     "abattement 4 600 € / 9 200 €, puis 7,5 % + 17,2 % de PS sur les gains")
    if account == "PER":
        return 0.0, "capitalisation sans impôt ; sortie imposée (versements au barème IR, gains au PFU)"
    if region == "US":
        return us + ps, (f"CTO : {us:.0%} retenus aux US (formulaire W-8BEN), crédit d'impôt imputé sur l'IR de "
                         f"12,8 % (l'excédent est perdu) + {ps:.1%} de PS ≈ {us + ps:.1%}")
    if region == "FR":
        return pfu, f"CTO : flat tax {pfu:.1%} (ou option barème IR avec abattement de 40 %)"
    return pfu + 0.05, (f"CTO : flat tax {pfu:.1%} + retenue étrangère partiellement récupérable "
                        "(variable selon le pays : Suisse 35 %, Allemagne 26,4 %...)")


EU_SUFFIXES = (".PA", ".AS", ".DE", ".F", ".MI", ".MC", ".BR", ".LS", ".HE", ".CO", ".ST", ".VI", ".IR", ".OL")


def region_of(ticker: str) -> str:
    if "." not in ticker:
        return "US"
    if ticker.endswith(".PA"):
        return "FR"
    return "EU" if ticker.endswith(EU_SUFFIXES) else "NON-EU"


def pea_eligible(ticker: str) -> bool:
    """Actions de sociétés UE/EEE (Norvège incluse) ; Royaume-Uni et Suisse exclus."""
    return region_of(ticker) in ("FR", "EU")


def drip_projection(capital: float, yield_: float, div_growth: float, price_growth: float, tax: float,
                    years: int = 10, monthly_add: float = 0.0) -> pd.DataFrame:
    """Projection avec et sans réinvestissement des dividendes (intérêts composés)."""
    rows = []
    v_drip = v_cash = capital
    y = yield_
    cum_cash = 0.0
    invested = capital
    for t in range(1, years + 1):
        gross = v_drip * y
        net = gross * (1 - tax)
        add = 12 * monthly_add
        v_drip = v_drip * (1 + price_growth) + net + add
        gross_c = v_cash * y
        cum_cash += gross_c * (1 - tax)
        v_cash = v_cash * (1 + price_growth) + add
        invested += add
        y = y * (1 + div_growth) / (1 + price_growth)  # rendement sur valeur de marché
        rows.append({"Année": t, "Capital investi": invested, "Valeur avec DRIP": v_drip,
                     "Dividendes nets de l'année (DRIP)": net, "Revenu mensuel net (DRIP)": net / 12,
                     "Valeur sans DRIP": v_cash, "Dividendes cumulés encaissés (sans DRIP)": cum_cash,
                     "Écart DRIP vs sans": v_drip - (v_cash + cum_cash)})
    return pd.DataFrame(rows).set_index("Année")


def build_portfolio(df: pd.DataFrame, n: int = 18, sector_cap: float = 0.25, min_safety: float = 6.0) -> pd.DataFrame:
    """Sélection diversifiée : les plus sûrs d'abord, plafond par secteur, poids pondérés par la sécurité."""
    cand = df[(df["Sécurité /10"] >= min_safety) & (df["Rendement"] > 0)].sort_values(
        ["Sécurité /10", "Rendement"], ascending=False)
    max_per_sector = max(1, int(math.floor(sector_cap * n)))
    chosen, count = [], {}
    for t, row in cand.iterrows():
        s = row["Secteur"]
        if count.get(s, 0) >= max_per_sector:
            continue
        chosen.append(t)
        count[s] = count.get(s, 0) + 1
        if len(chosen) >= n:
            break
    out = df.loc[chosen].copy()
    if out.empty:
        return out
    w = out["Sécurité /10"] ** 2
    out["Poids"] = w / w.sum()
    # plafonnement secteur par itération
    for _ in range(10):
        sec = out.groupby("Secteur")["Poids"].transform("sum")
        over = sec > sector_cap + 1e-9
        if not over.any():
            break
        out.loc[over, "Poids"] *= sector_cap / sec[over]
        out["Poids"] /= out["Poids"].sum()
    return out


def ranking(df: pd.DataFrame) -> pd.DataFrame:
    """Du plus sûr au plus agressif (sécurité décroissante puis rendement croissant)."""
    out = df.sort_values(["Sécurité /10", "Rendement"], ascending=[False, True]).copy()
    out["Profil"] = pd.cut(out["Sécurité /10"], bins=[-1, 4, 6, 8, 10.1],
                           labels=["Agressif", "Rendement élevé", "Équilibré", "Très sûr"])
    return out
