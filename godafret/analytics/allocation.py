"""Construction de portefeuille multi-actifs (style politique d'investissement BlackRock)."""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import pandas as pd

from ..config import TAX_FR

TOLERANCE_EQUITY = {"prudente": 0.30, "modérée": 0.55, "dynamique": 0.75, "agressive": 0.90}


@dataclass(frozen=True)
class Sleeve:
    key: str
    name: str
    asset_class: str      # Actions | Obligations | Alternatifs | Liquidités
    role: str             # Cœur | Satellite
    proxy: str            # ETF US à long historique pour les statistiques
    exp_return: float     # hypothèse prospective 10 ans (nominal, EUR)
    vol: float


SLEEVES = {
    "world": Sleeve("world", "Actions Monde développé", "Actions", "Cœur", "VT", 0.065, 0.16),
    "us": Sleeve("us", "Actions US (S&P 500)", "Actions", "Satellite", "SPY", 0.060, 0.17),
    "europe": Sleeve("europe", "Actions Europe", "Actions", "Satellite", "VGK", 0.070, 0.18),
    "em": Sleeve("em", "Actions émergentes", "Actions", "Satellite", "EEM", 0.075, 0.22),
    "small": Sleeve("small", "Petites capitalisations Monde", "Actions", "Satellite", "VB", 0.070, 0.21),
    "agg": Sleeve("agg", "Obligations agrégées €", "Obligations", "Cœur", "AGG", 0.030, 0.055),
    "short": Sleeve("short", "Obligations d'État € 1-3 ans", "Obligations", "Cœur", "SHY", 0.023, 0.015),
    "infl": Sleeve("infl", "Obligations indexées inflation €", "Obligations", "Satellite", "TIP", 0.028, 0.06),
    "gold": Sleeve("gold", "Or physique", "Alternatifs", "Satellite", "GLD", 0.040, 0.15),
    "reit": Sleeve("reit", "Immobilier coté mondial", "Alternatifs", "Satellite", "VNQ", 0.060, 0.19),
    "cash": Sleeve("cash", "Monétaire €", "Liquidités", "Cœur", "BIL", 0.020, 0.005),
}

# (ticker Yahoo, nom, frais annuels) — vérifier la disponibilité chez son courtier / assureur
ETFS = {
    "PEA": {
        "world": [("CW8.PA", "Amundi MSCI World (éligible PEA)", 0.0038), ("WPEA.PA", "iShares MSCI World Swap PEA", 0.0025)],
        "us": [("ESE.PA", "BNP Paribas Easy S&P 500", 0.0015), ("PUST.PA", "Amundi PEA Nasdaq-100", 0.0030)],
        "europe": [("MEUD.PA", "Amundi Core Stoxx Europe 600", 0.0007)],
        "em": [("PAEEM.PA", "Amundi PEA Emergents (MSCI EM ESG)", 0.0030)],
        "small": [],
    },
    "UCITS": {
        "world": [("IWDA.AS", "iShares Core MSCI World", 0.0020), ("VWCE.DE", "Vanguard FTSE All-World", 0.0019)],
        "us": [("CSPX.AS", "iShares Core S&P 500", 0.0007)],
        "europe": [("MEUD.PA", "Amundi Core Stoxx Europe 600", 0.0007)],
        "em": [("IS3N.DE", "iShares Core MSCI EM IMI", 0.0018)],
        "small": [("IUSN.DE", "iShares MSCI World Small Cap", 0.0035)],
        "agg": [("IEAG.AS", "iShares Core € Aggregate Bond", 0.0009)],
        "short": [("IBGS.AS", "iShares € Govt Bond 1-3yr", 0.0015)],
        "infl": [("IBCI.AS", "iShares € Inflation Linked Govt Bond", 0.0009)],
        "gold": [("4GLD.DE", "Xetra-Gold (ETC adossé à de l'or physique)", 0.0)],
        "reit": [("IWDP.AS", "iShares Developed Markets Property Yield", 0.0059)],
        "cash": [("XEON.DE", "Xtrackers II EUR Overnight Rate Swap", 0.0010)],
    },
}


@dataclass
class Profile:
    age: int
    income: float
    savings: float
    monthly: float
    horizon: int
    tolerance: str
    account: str
    goal: str
    emergency_months: float = 6.0
    monthly_expenses: float = 2500.0


def target_allocation(p: Profile) -> tuple[pd.Series, list[str]]:
    why = []
    eq = TOLERANCE_EQUITY.get(p.tolerance, 0.55)
    why.append(f"Tolérance {p.tolerance} → {eq:.0%} d'actions de départ.")
    if p.horizon < 3:
        eq = min(eq, 0.20); why.append("Horizon < 3 ans : actions plafonnées à 20 %.")
    elif p.horizon < 5:
        eq = min(eq, 0.40); why.append("Horizon < 5 ans : actions plafonnées à 40 %.")
    elif p.horizon >= 15 and p.tolerance != "prudente":
        eq = min(eq + 0.05, 0.95); why.append("Horizon ≥ 15 ans : +5 pts d'actions.")
    if p.age >= 60:
        eq -= 0.10; why.append("Âge ≥ 60 ans : −10 pts d'actions (capacité de récupération plus faible).")
    elif p.age <= 30 and p.horizon >= 10:
        eq += 0.05; why.append("Âge ≤ 30 ans et horizon long : +5 pts d'actions (capital humain élevé).")
    eq = float(np.clip(eq, 0.10, 0.95))

    alt = 0.05 if eq < 0.9 else 0.03
    reit = 0.05 if eq >= 0.5 else 0.0
    cash = 0.05 if p.horizon < 5 else 0.02
    bonds = max(0.0, 1 - eq - alt - reit - cash)

    w = {
        "world": eq * (0.65 if p.tolerance != "agressive" else 0.55),
        "us": eq * 0.10, "europe": eq * 0.10, "em": eq * 0.10,
        "small": eq * (0.05 if p.tolerance != "agressive" else 0.15),
        "gold": alt, "reit": reit, "cash": cash,
    }
    if p.tolerance == "prudente" or p.horizon < 5:
        w.update({"agg": bonds * 0.40, "short": bonds * 0.40, "infl": bonds * 0.20})
    else:
        w.update({"agg": bonds * 0.60, "short": bonds * 0.20, "infl": bonds * 0.20})
    s = pd.Series(w)
    s = s[s > 0.0005]
    return s / s.sum(), why


def implement(weights: pd.Series, account: str) -> pd.DataFrame:
    """Associe chaque poche à un ETF compatible avec l'enveloppe."""
    rows = []
    for k, wt in weights.items():
        sl = SLEEVES[k]
        if account == "PEA":
            lst = ETFS["PEA"].get(k)
            if lst is None:  # obligations, or, immobilier, monétaire : non éligibles au PEA
                rows.append({"Poche": sl.name, "Classe": sl.asset_class, "Rôle": sl.role, "Poids": wt,
                             "Ticker": "—", "Support": "hors PEA : fonds en euros d'assurance-vie / livrets",
                             "Frais": np.nan, "Proxy historique": sl.proxy, "key": k})
                continue
            if not lst:  # pas d'ETF PEA petites capitalisations : on bascule vers Monde
                lst = ETFS["PEA"]["world"]
        else:
            lst = ETFS["UCITS"].get(k, [])
        t, name, ter = lst[0] if lst else ("—", "—", np.nan)
        alt = ", ".join(x[0] for x in lst[1:]) if len(lst) > 1 else ""
        rows.append({"Poche": sl.name, "Classe": sl.asset_class, "Rôle": sl.role, "Poids": wt, "Ticker": t,
                     "Support": name + (f" (alternative : {alt})" if alt else ""), "Frais": ter,
                     "Proxy historique": sl.proxy, "key": k})
    df = pd.DataFrame(rows)
    return df.sort_values(["Rôle", "Poids"], ascending=[True, False]).reset_index(drop=True)


def forward_stats(weights: pd.Series, corr: pd.DataFrame | None) -> dict:
    mu = np.array([SLEEVES[k].exp_return for k in weights.index])
    vol = np.array([SLEEVES[k].vol for k in weights.index])
    if corr is not None and set(weights.index) <= set(corr.index):
        c = corr.loc[weights.index, weights.index].values
    else:
        c = np.full((len(mu), len(mu)), 0.3) + 0.7 * np.eye(len(mu))
    cov = np.outer(vol, vol) * c
    w = weights.values
    m, s = float(w @ mu), float(math.sqrt(w @ cov @ w))
    ter = 0.0025
    return {"rendement attendu": m - ter, "volatilité": s, "fourchette 80 % basse": m - ter - 1.2816 * s,
            "fourchette 80 % haute": m - ter + 1.2816 * s, "mauvaise année (1 sur 20)": m - ter - 1.645 * s,
            "très mauvaise année (1 sur 100)": m - ter - 2.326 * s}


def historical_stats(proxy_prices: pd.DataFrame, weights: pd.Series) -> dict:
    """Backtest mensuel rééquilibré sur les proxys (USD, long historique)."""
    cols = {k: SLEEVES[k].proxy for k in weights.index}
    px = proxy_prices[[c for c in set(cols.values()) if c in proxy_prices]].resample("ME").last()
    r = px.pct_change(fill_method=None).dropna()
    if r.empty:
        return {}
    w = pd.Series({cols[k]: 0.0 for k in weights.index})
    for k, wt in weights.items():
        w[cols[k]] += wt
    w = w[w.index.isin(r.columns)]
    w = w / w.sum()
    port = r[w.index] @ w
    nav = (1 + port).cumprod()
    yearly = (1 + port).groupby(port.index.year).prod() - 1
    yearly = yearly[[y for y in yearly.index if (port.index.year == y).sum() == 12]]
    roll = (1 + port).rolling(12).apply(np.prod, raw=True).dropna() - 1
    years = len(port) / 12
    return {"période": f"{port.index[0]:%m/%Y} → {port.index[-1]:%m/%Y}",
            "rendement annualisé": float(nav.iloc[-1] ** (1 / years) - 1),
            "volatilité": float(port.std() * math.sqrt(12)),
            "pire année civile": float(yearly.min()) if not yearly.empty else float("nan"),
            "année de la pire perte": int(yearly.idxmin()) if not yearly.empty else None,
            "meilleure année civile": float(yearly.max()) if not yearly.empty else float("nan"),
            "pire période de 12 mois": float(roll.min()), "baisse maximale": float((nav / nav.cummax() - 1).min()),
            "rendement 12 mois : 10e centile": float(roll.quantile(0.1)),
            "rendement 12 mois : 90e centile": float(roll.quantile(0.9)),
            "série": nav, "annuel": yearly, "corr": r.corr()}


def dca_projection(initial: float, monthly: float, years: int, mu: float, vol: float, n: int = 5000,
                   seed: int = 3) -> pd.DataFrame:
    """Plan d'investissement programmé : percentiles de valeur par année (Monte-Carlo log-normal)."""
    rng = np.random.default_rng(seed)
    months = years * 12
    m_mu = math.log(1 + mu) / 12 - 0.5 * (vol ** 2) / 12
    m_sd = vol / math.sqrt(12)
    shocks = rng.normal(m_mu, m_sd, size=(n, months))
    v = np.full(n, initial, dtype=float)
    rows = []
    for t in range(months):
        v = v * np.exp(shocks[:, t]) + monthly
        if (t + 1) % 12 == 0:
            y = (t + 1) // 12
            rows.append({"Année": y, "Versé": initial + monthly * (t + 1), "Pessimiste (10 %)": np.percentile(v, 10),
                         "Médian": np.percentile(v, 50), "Optimiste (90 %)": np.percentile(v, 90)})
    return pd.DataFrame(rows).set_index("Année")


def tax_strategy(account: str) -> list[str]:
    pfu = TAX_FR.pfu
    common = ["Privilégier des ETF capitalisants (pas de dividende imposable chaque année).",
              "Rééquilibrer d'abord avec les nouveaux versements plutôt qu'en vendant (pas de plus-value réalisée)."]
    if account == "PEA":
        return [f"Ne pas retirer avant {TAX_FR.pea_min_years} ans : ensuite, seuls {TAX_FR.social:.1%} de prélèvements "
                "sociaux sur les gains (pas d'impôt sur le revenu).",
                "Plafond de versements : 150 000 € (PEA) + 225 000 € (PEA-PME), cumul limité à 225 000 €.",
                "Les arbitrages à l'intérieur du PEA ne sont pas imposés : rééquilibrer y est gratuit fiscalement.",
                "Partie obligataire / or / immobilier : à loger dans une assurance-vie (fonds en euros, UC)."] + common
    if account == "Assurance-vie":
        return ["Après 8 ans : abattement annuel de 4 600 € (9 200 € pour un couple) sur les gains retirés.",
                f"Au-delà : 7,5 % d'impôt (versements ≤ 150 000 €) + {TAX_FR.social_life_insurance:.1%} de PS.",
                "Transmission : 152 500 € par bénéficiaire hors succession (primes versées avant 70 ans).",
                "Les arbitrages internes ne sont pas imposés ; vérifier les frais de gestion du contrat (< 0,6 %/an)."] + common
    if account == "PER":
        return ["Versements déductibles du revenu imposable (plafond ≈ 10 % des revenus professionnels).",
                "Intéressant si ta tranche marginale d'imposition est ≥ 30 % aujourd'hui et plus basse à la retraite.",
                "Argent bloqué jusqu'à la retraite (sauf achat de la résidence principale et accidents de la vie).",
                "Choisir la gestion libre avec ETF ; éviter la gestion pilotée trop chère."] + common
    return [f"CTO : dividendes et plus-values taxés à la flat tax de {pfu:.1%} (ou option barème IR).",
            "Utiliser les moins-values pour compenser les plus-values (reportables 10 ans).",
            "Remplir d'abord le PEA (actions européennes / ETF éligibles) puis l'assurance-vie, le CTO en dernier.",
            "Actions US : remplir le formulaire W-8BEN (retenue à la source ramenée à 15 %)."] + common


def rebalancing_rules(weights: pd.Series) -> list[str]:
    return ["Calendrier : revue complète une fois par an (même date chaque année) + contrôle trimestriel.",
            "Déclencheur absolu : une poche s'écarte de plus de 5 points de sa cible → rééquilibrer.",
            "Déclencheur relatif : une petite poche (< 10 %) s'écarte de plus de 25 % de sa cible "
            "(ex. or à 5 % → seuils 3,75 % / 6,25 %).",
            "Ordre des opérations : 1) nouveaux versements vers les poches sous-pondérées ; 2) arbitrages dans les "
            "enveloppes non fiscalisées (PEA, AV) ; 3) ventes sur CTO en dernier.",
            "Krach > 20 % : rééquilibrer vers la cible actions (acheter ce qui a baissé) — c'est la règle qui "
            "crée la performance à long terme."]


def benchmark(weights: pd.Series) -> str:
    eq = sum(wt for k, wt in weights.items() if SLEEVES[k].asset_class == "Actions")
    bd = sum(wt for k, wt in weights.items() if SLEEVES[k].asset_class == "Obligations")
    other = 1 - eq - bd
    return (f"{eq:.0%} MSCI ACWI (dividendes réinvestis, en EUR) + {bd:.0%} Bloomberg Euro Aggregate + "
            f"{other:.0%} €STR")


def ips_markdown(p: Profile, alloc: pd.DataFrame, fwd: dict, hist: dict, bench: str) -> str:
    eq = alloc.loc[alloc["Classe"] == "Actions", "Poids"].sum()
    bd = alloc.loc[alloc["Classe"] == "Obligations", "Poids"].sum()
    lines = [
        "# Politique d'investissement (IPS)",
        "",
        f"**Investisseur** : {p.age} ans — revenu {p.income:,.0f} €/an — épargne investie {p.savings:,.0f} € — "
        f"versement mensuel {p.monthly:,.0f} € — enveloppe : {p.account}",
        f"**Objectif** : {p.goal} — **horizon** {p.horizon} ans — **tolérance au risque** : {p.tolerance}",
        "",
        "## 1. Allocation stratégique",
        f"Actions {eq:.0%} · Obligations {bd:.0%} · Alternatifs/liquidités {1 - eq - bd:.0%}",
        "",
        "| Poche | Rôle | Poids | Support |",
        "|---|---|---|---|",
    ]
    for _, r in alloc.iterrows():
        lines.append(f"| {r['Poche']} | {r['Rôle']} | {r['Poids']:.1%} | {r['Ticker']} — {r['Support']} |")
    lines += [
        "",
        "## 2. Rendement et risque attendus",
        f"- Rendement annuel attendu (net de frais) : **{fwd['rendement attendu']:.1%}**, fourchette 80 % sur un an : "
        f"{fwd['fourchette 80 % basse']:.1%} à {fwd['fourchette 80 % haute']:.1%}",
        f"- Mauvaise année (1 sur 20) : **{fwd['mauvaise année (1 sur 20)']:.1%}** ; volatilité {fwd['volatilité']:.1%}",
    ]
    if hist:
        lines.append(f"- Historique ({hist['période']}) : {hist['rendement annualisé']:.1%}/an, pire année "
                     f"{hist['pire année civile']:.1%} ({hist['année de la pire perte']}), baisse maximale "
                     f"{hist['baisse maximale']:.1%}")
    lines += ["", "## 3. Indice de référence", bench, "", "## 4. Règles de rééquilibrage"]
    lines += [f"- {r}" for r in rebalancing_rules(alloc['Poids'])]
    lines += ["", "## 5. Fiscalité"] + [f"- {r}" for r in tax_strategy(p.account)]
    lines += ["", "## 6. Règles de conduite",
              f"- Épargne de précaution conservée hors marché : {p.emergency_months:.0f} mois de dépenses "
              f"({p.emergency_months * p.monthly_expenses:,.0f} €).",
              "- Aucune ligne individuelle > 10 % ; satellites ≤ 30 % du total.",
              "- Ne jamais vendre sous le coup de l'émotion : toute modification de l'allocation stratégique "
              "nécessite un changement de situation personnelle, pas un mouvement de marché.",
              "- Revue de cette politique : chaque année ou à chaque événement de vie majeur."]
    return "\n".join(lines)
