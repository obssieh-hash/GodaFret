"""Conseiller : transforme la situation de l'investisseur en plan d'action concret
(quoi faire, dans quel ordre, combien, sur quelle enveloppe, avec quel support)."""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import pandas as pd

from . import allocation
from .allocation import ETFS, SLEEVES

LIVRET_A_CAP = 22_950.0
LDDS_CAP = 12_000.0
PEA_CAP = 150_000.0

# Réponse à « ton portefeuille perd 20 % en 3 mois, que fais-tu ? »
REACTION_SCORE = {"Je vends tout pour arrêter les pertes": 0, "Je vends une partie": 1,
                  "J'attends sans rien toucher": 2, "J'en profite pour acheter plus": 3}
EXPERIENCE_SCORE = {"Jamais investi": 0, "Un peu (livrets, assurance-vie fonds euros)": 1,
                    "Oui (actions / ETF depuis plus d'un an)": 2, "Expérimenté (plusieurs krachs vécus)": 3}


@dataclass
class Situation:
    age: int
    monthly_income: float
    monthly_expenses: float
    savings: float
    expensive_debt: float = 0.0          # crédits conso / revolving > 5 %
    short_term_project: float = 0.0      # argent nécessaire dans moins de 3 ans
    horizon: int = 10
    reaction: str = "J'attends sans rien toucher"
    experience: str = "Un peu (livrets, assurance-vie fonds euros)"
    tmi: float = 0.30                    # tranche marginale d'imposition
    pea_already: float = 0.0             # déjà versé sur un PEA
    goal: str = "Faire grossir mon patrimoine"
    emergency_months: float = 6.0


@dataclass
class Plan:
    tolerance: str
    tolerance_why: str
    steps: list[dict] = field(default_factory=list)
    placements: pd.DataFrame = field(default_factory=pd.DataFrame)
    monthly: pd.DataFrame = field(default_factory=pd.DataFrame)
    investable: float = 0.0
    monthly_invest: float = 0.0
    timing: str = ""
    rules: list[str] = field(default_factory=list)
    expected: dict = field(default_factory=dict)


def risk_profile(s: Situation) -> tuple[str, str]:
    """Profil déduit du comportement réel, pas seulement de ce que la personne déclare."""
    score = REACTION_SCORE.get(s.reaction, 2) * 2 + EXPERIENCE_SCORE.get(s.experience, 1)
    score += 2 if s.horizon >= 15 else 1 if s.horizon >= 8 else 0
    tol = "prudente" if score <= 3 else "modérée" if score <= 6 else "dynamique" if score <= 9 else "agressive"
    cap_txt = ""
    if REACTION_SCORE.get(s.reaction, 2) <= 1 and tol in ("dynamique", "agressive"):
        tol, cap_txt = "modérée", " Plafonné à « modérée » : vendre pendant une baisse est l'erreur la plus coûteuse."
    return tol, f"Score {score}/14 (réaction à une baisse, expérience, horizon) → profil {tol}.{cap_txt}"


def market_timing(above_ma200: bool | None, vix: float | None) -> tuple[float, int, str]:
    """Part investie tout de suite et nombre de mois pour étaler le reste."""
    if above_ma200 is None:
        return 0.5, 6, "Signal de marché indisponible : 50 % maintenant, le reste étalé sur 6 mois."
    stressed = vix is not None and not math.isnan(vix) and vix >= 25
    if above_ma200 and not stressed:
        return 0.5, 3, ("Marché en tendance haussière et calme : investis 50 % maintenant et le reste en 3 mois. "
                        "Historiquement, investir tout de suite gagne environ 2 fois sur 3, l'étalement réduit le regret.")
    if not above_ma200 and stressed:
        return 0.25, 6, (f"Marché sous sa moyenne 200 jours et nervosité forte (VIX {vix:.0f}) : investis 25 % maintenant "
                         "et le reste chaque mois pendant 6 mois. N'attends pas « le point bas », personne ne le connaît.")
    return 0.34, 6, "Marché incertain : investis un tiers maintenant et le reste chaque mois pendant 6 mois."


def _route(key: str, use_pea: bool) -> tuple[str, str, str]:
    """(enveloppe, ticker, nom du support) pour une poche."""
    if use_pea and ETFS["PEA"].get(key):
        t, name, _ = ETFS["PEA"][key][0]
        return "PEA", t, name
    if key in ("short", "cash"):
        return "Assurance-vie", "Fonds en euros", "Fonds en euros (capital garanti) de ton assurance-vie"
    if key in ("agg", "infl", "reit"):
        t, name, _ = ETFS["UCITS"][key][0]
        return "Assurance-vie", t, name + " (en unité de compte)"
    t, name, _ = ETFS["UCITS"][key][0]
    return "CTO", t, name


def simplify(w: pd.Series, base: float, min_amount: float = 1_500.0) -> pd.Series:
    """Petits montants : fusionne les poches trop petites pour valoir le coût d'une ligne
    (actions → Monde, le reste → fonds en euros / obligations courtes)."""
    w = w.copy()
    for k in sorted(w.index, key=lambda x: w[x]):
        if k in ("world", "short") or w[k] * base >= min_amount:
            continue
        dest = "world" if SLEEVES[k].asset_class == "Actions" else "short"
        w[dest] = w.get(dest, 0.0) + w[k]
        w = w.drop(k)
    return w / w.sum()


def build_plan(s: Situation, above_ma200: bool | None = None, vix: float | None = None,
               corr: pd.DataFrame | None = None) -> Plan:
    tol, why = risk_profile(s)
    plan = Plan(tolerance=tol, tolerance_why=why)
    cash = max(s.savings, 0.0)
    n = 1

    def step(title, action, amount, where, reason):
        nonlocal n
        plan.steps.append({"Étape": n, "Quoi": title, "Action": action, "Montant": amount, "Où": where, "Pourquoi": reason})
        n += 1

    # 1. Dettes chères
    if s.expensive_debt > 0:
        pay = min(cash, s.expensive_debt)
        cash -= pay
        step("Rembourser les crédits chers", "Rembourse tes crédits à la consommation / revolving par anticipation.",
             pay, "Ta banque", "Un crédit à 6-20 % coûte plus que ce qu'un placement rapporte : c'est un gain garanti.")

    # 2. Épargne de précaution
    target = s.emergency_months * s.monthly_expenses
    reserve = min(cash, target)
    cash -= reserve
    la = min(reserve, LIVRET_A_CAP)
    step("Épargne de précaution", f"Garde {s.emergency_months:.0f} mois de dépenses disponibles à tout moment.",
         reserve, f"Livret A ({la:,.0f} €)" + (f" + LDDS ({min(reserve - la, LDDS_CAP):,.0f} €)" if reserve > la else ""),
         "Sans elle, le moindre imprévu t'oblige à vendre tes placements au pire moment. Ne jamais l'investir en bourse.")
    missing_reserve = max(0.0, target - reserve)

    # 3. Projets à court terme
    if s.short_term_project > 0:
        proj = min(cash, s.short_term_project)
        cash -= proj
        step("Projet de moins de 3 ans", "Mets l'argent du projet à l'abri des variations de la bourse.", proj,
             "LDDS / fonds en euros / compte à terme", "En 3 ans, la bourse peut perdre 30 % : cet argent ne doit pas y aller.")

    plan.investable = cash
    # 4. Allocation investie
    p = allocation.Profile(age=s.age, income=s.monthly_income * 12, savings=cash, monthly=0, horizon=s.horizon,
                           tolerance=tol, account="CTO", goal=s.goal, monthly_expenses=s.monthly_expenses)
    w, _ = allocation.target_allocation(p)
    w = simplify(w, cash + 12 * 0.8 * max(0.0, s.monthly_income - s.monthly_expenses))
    plan.expected = allocation.forward_stats(w, corr)
    pea_room = max(0.0, PEA_CAP - s.pea_already)
    rows, pea_used = [], 0.0
    for k, wt in w.sort_values(ascending=False).items():
        amt = wt * cash
        env, t, name = _route(k, True)
        if env == "PEA" and pea_used + amt > pea_room:  # plafond PEA dépassé → le reste sur CTO
            over = pea_used + amt - pea_room
            if amt - over > 0:
                rows.append({"Enveloppe": "PEA", "Poche": SLEEVES[k].name, "Support": name, "Ticker": t,
                             "Poids": wt * (amt - over) / amt, "Montant": amt - over, "Rôle": SLEEVES[k].role})
            env, t, name = _route(k, False)
            rows.append({"Enveloppe": env, "Poche": SLEEVES[k].name, "Support": name, "Ticker": t,
                         "Poids": wt * over / amt, "Montant": over, "Rôle": SLEEVES[k].role})
            pea_used = pea_room
            continue
        if env == "PEA":
            pea_used += amt
        rows.append({"Enveloppe": env, "Poche": SLEEVES[k].name, "Support": name, "Ticker": t, "Poids": wt,
                     "Montant": amt, "Rôle": SLEEVES[k].role})
    plan.placements = pd.DataFrame(rows)

    # PER si la fiscalité s'y prête
    if s.tmi >= 0.30 and s.age < 58 and s.horizon >= 8 and cash > 0:
        per = min(0.10 * s.monthly_income * 12, 0.15 * cash)
        step("Option PER (impôts)", f"Tu peux loger {per:,.0f} € de la poche Actions Monde dans un PER plutôt que sur le PEA.",
             per, "PER individuel en gestion libre (ETF Monde)",
             f"Économie d'impôt immédiate ≈ {per * s.tmi:,.0f} € (TMI {s.tmi:.0%}), mais argent bloqué jusqu'à la retraite.")

    timing_now, months, timing_txt = market_timing(above_ma200, vix)
    plan.timing = timing_txt
    if cash > 0:
        for env in ("PEA", "Assurance-vie", "CTO"):
            sub = plan.placements[plan.placements["Enveloppe"] == env]
            if sub.empty:
                continue
            total = sub["Montant"].sum()
            opening = {"PEA": "Ouvre un PEA chez un courtier en ligne à frais bas (pas en banque traditionnelle).",
                       "Assurance-vie": "Ouvre une assurance-vie en ligne sans frais d'entrée, avec fonds en euros et ETF.",
                       "CTO": "Ouvre un compte-titres chez un courtier en ligne à frais bas ; remplis le formulaire W-8BEN."}[env]
            step(f"Investir sur le {env}", opening + " Puis achète : " + ", ".join(
                f"{r.Ticker} ({r.Montant:,.0f} €)" for r in sub.itertuples()), total, env,
                 "Ordre : PEA (fiscalité la plus faible après 5 ans) → assurance-vie → CTO." if env == "PEA" else
                 "Fiscalité allégée après 8 ans ; idéal pour la partie prudente." if env == "Assurance-vie" else
                 "Pour ce qui ne rentre pas dans le PEA (or, petites capitalisations, dépassement du plafond).")
        step("Rythme d'investissement", timing_txt, cash * timing_now, "Toutes les enveloppes",
             f"Puis {cash * (1 - timing_now) / months:,.0f} € par mois pendant {months} mois, répartis comme ci-dessus.")

    # 5. Versements mensuels
    capacity = max(0.0, s.monthly_income - s.monthly_expenses)
    if missing_reserve > 0:
        to_reserve = min(capacity * 0.5, missing_reserve)
        step("Compléter la précaution", f"Chaque mois, mets {to_reserve:,.0f} € sur le Livret A jusqu'à atteindre "
             f"{target:,.0f} €.", to_reserve, "Livret A / LDDS", "La sécurité d'abord, la performance ensuite.")
        capacity -= to_reserve
    plan.monthly_invest = round(capacity * 0.8, -1)
    if plan.monthly_invest > 0 and not plan.placements.empty:
        m = plan.placements.groupby(["Enveloppe", "Ticker", "Support"], as_index=False)["Poids"].sum()
        m["Par mois"] = (m["Poids"] / m["Poids"].sum() * plan.monthly_invest).round(0)
        plan.monthly = m
        step("Investir chaque mois", f"Programme un virement automatique de {plan.monthly_invest:,.0f} € le lendemain de ta paie "
             "et achète les mêmes ETF chaque mois, quoi qu'il arrive.", plan.monthly_invest, "PEA / assurance-vie / CTO",
             "Garder 20 % de ta capacité d'épargne pour vivre ; la régularité bat le choix du bon moment.")

    plan.rules = [
        "Ne jamais vendre pendant une baisse : c'est prévu, une année sur cinq est négative.",
        f"Si les actions baissent de plus de 20 %, remets-toi à {sum(v for k, v in w.items() if SLEEVES[k].asset_class == 'Actions'):.0%} "
        "d'actions en achetant (rééquilibrage) — c'est là que se fait la performance.",
        "Aucune action individuelle au-delà de 10 % du total ; les « paris » ne dépassent pas 10 % du portefeuille.",
        "Revoir le plan une fois par an (même date), pas tous les jours.",
        "Ne jamais investir sur un conseil de réseau social, une crypto « garantie » ou une promesse de rendement > 8 %/an sans risque : c'est une arnaque.",
    ]
    return plan
