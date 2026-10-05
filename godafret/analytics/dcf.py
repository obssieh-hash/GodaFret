"""Modèle DCF (flux de trésorerie disponibles pour l'entreprise, FCFF) façon mémo M&A.

FCFF = EBIT × (1 − t) + D&A − Capex − ΔBFR
Valeur terminale : croissance perpétuelle (Gordon-Shapiro) ET multiple de sortie
(VE/EBITDA). Actualisation au CMPC (WACC) avec convention mi-année optionnelle.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field, replace

import numpy as np
import pandas as pd

from .fundamentals import (CAPEX, DA, EBITDA, INTEREST, OP_INCOME, PRETAX, REVENUE, TAX, TOTAL_DEBT,
                           WC_CHANGE, last, nz, pick)


@dataclass
class DCFInputs:
    base_revenue: float
    growth_start: float
    growth_end: float
    margin_start: float
    margin_end: float
    tax_rate: float
    da_pct: float              # D&A en % du CA
    capex_pct: float           # capex en % du CA
    nwc_pct: float             # ΔBFR en % de la variation du CA
    risk_free: float
    beta: float
    equity_risk_premium: float
    cost_of_debt: float        # avant impôt
    market_cap: float
    total_debt: float
    net_debt: float
    shares: float
    price: float
    terminal_growth: float = 0.025
    exit_multiple: float = 12.0
    years: int = 5
    mid_year: bool = True
    fx_to_price_ccy: float = 1.0   # conversion devise des comptes -> devise de cotation
    notes: list[str] = field(default_factory=list)

    @property
    def cost_of_equity(self) -> float:
        return self.risk_free + self.beta * self.equity_risk_premium

    @property
    def wacc(self) -> float:
        e, d = max(self.market_cap, 0), max(self.total_debt, 0)
        if e + d == 0:
            return self.cost_of_equity
        return e / (e + d) * self.cost_of_equity + d / (e + d) * self.cost_of_debt * (1 - self.tax_rate)


@dataclass
class DCFResult:
    projection: pd.DataFrame
    wacc: float
    pv_fcf: float
    tv_gordon: float
    tv_exit: float
    ev_gordon: float
    ev_exit: float
    value_gordon: float      # par action, devise de cotation
    value_exit: float
    value_blended: float
    upside: float
    verdict: str
    tv_share_gordon: float
    implied_multiple_gordon: float
    implied_growth_exit: float


def _hist_ratio(num: pd.Series, den: pd.Series, default: float, lo: float, hi: float) -> float:
    r = (num / den).replace([np.inf, -np.inf], np.nan).dropna()
    if r.empty:
        return default
    return float(np.clip(r.tail(4).mean(), lo, hi))


def build_inputs(f, statements: dict, info: dict, risk_free: float, erp: float,
                 terminal_growth: float = 0.025, fx_to_price_ccy: float = 1.0) -> DCFInputs:
    """Hypothèses par défaut tirées de l'historique ; toutes modifiables ensuite."""
    inc = statements.get("income", pd.DataFrame())
    bal = statements.get("balance", pd.DataFrame())
    cf = statements.get("cashflow", pd.DataFrame())
    notes = []

    rev = pick(inc, REVENUE).dropna()
    base_rev = float(rev.iloc[-1]) if not rev.empty else nz(info.get("totalRevenue"), 0.0)

    hist_g = f.revenue_cagr if not math.isnan(f.revenue_cagr) else 0.05
    analyst_g = nz(info.get("revenueGrowth"))
    g0 = hist_g if math.isnan(analyst_g) else 0.5 * hist_g + 0.5 * analyst_g
    g0 = float(np.clip(g0, -0.10, 0.30))
    g1 = float(max(terminal_growth, (g0 + terminal_growth) / 2))
    notes.append(f"Croissance an 1 = moyenne CAGR historique ({hist_g:.1%}) et croissance récente "
                 f"({'n/d' if math.isnan(analyst_g) else f'{analyst_g:.1%}'}), convergence vers {g1:.1%} en an 5.")

    opi = pick(inc, OP_INCOME)
    rev_full = pick(inc, REVENUE)
    margin_hist = _hist_ratio(opi, rev_full, nz(info.get("operatingMargins"), 0.15), -0.5, 0.7)
    margin_last = last((opi / rev_full).replace([np.inf, -np.inf], np.nan))
    m0 = margin_last if not math.isnan(margin_last) else margin_hist
    notes.append(f"Marge opérationnelle : dernière {m0:.1%}, moyenne 4 ans {margin_hist:.1%} (cible an 5).")

    pretax, tax = pick(inc, PRETAX), pick(inc, TAX)
    tax_rate = _hist_ratio(tax, pretax, 0.21, 0.10, 0.30)
    da_pct = _hist_ratio(pick(cf, DA), rev_full, 0.04, 0.0, 0.25)
    capex_pct = _hist_ratio(-pick(cf, CAPEX), rev_full, 0.05, 0.0, 0.40)
    d_rev = rev_full.diff()
    nwc_pct = _hist_ratio(-pick(cf, WC_CHANGE), d_rev, 0.05, -0.30, 0.30)

    debt = last(pick(bal, TOTAL_DEBT))
    debt = nz(info.get("totalDebt"), 0.0) if math.isnan(debt) else debt
    interest = abs(last(pick(inc, INTEREST)))
    kd = interest / debt if debt and debt > 0 and not math.isnan(interest) else risk_free + 0.015
    kd = float(np.clip(kd, risk_free, risk_free + 0.06))

    raw_beta = f.beta if not math.isnan(f.beta) else 1.0
    adj_beta = 0.67 * raw_beta + 0.33  # bêta ajusté de Blume (convention Bloomberg)
    notes.append(f"Bêta brut {raw_beta:.2f} → ajusté (Blume) {adj_beta:.2f}.")

    ev_ebitda = nz(info.get("enterpriseToEbitda"))
    exit_mult = float(np.clip(ev_ebitda, 6, 25)) if not math.isnan(ev_ebitda) and ev_ebitda > 0 else 12.0
    notes.append(f"Multiple de sortie VE/EBITDA = {exit_mult:.1f}x (multiple actuel borné 6-25x).")

    shares = f.shares if not math.isnan(f.shares) else nz(info.get("sharesOutstanding"), 0.0)
    market_cap = f.market_cap if not math.isnan(f.market_cap) else f.price * shares

    return DCFInputs(
        base_revenue=base_rev, growth_start=g0, growth_end=g1, margin_start=m0, margin_end=margin_hist,
        tax_rate=tax_rate, da_pct=da_pct, capex_pct=capex_pct, nwc_pct=nwc_pct, risk_free=risk_free,
        beta=adj_beta, equity_risk_premium=erp, cost_of_debt=kd, market_cap=market_cap / fx_to_price_ccy
        if fx_to_price_ccy else market_cap, total_debt=debt, net_debt=f.net_debt, shares=shares,
        price=f.price, terminal_growth=terminal_growth, exit_multiple=exit_mult,
        fx_to_price_ccy=fx_to_price_ccy, notes=notes)


def project(inp: DCFInputs) -> pd.DataFrame:
    n = inp.years
    growth = np.linspace(inp.growth_start, inp.growth_end, n)
    margin = np.linspace(inp.margin_start, inp.margin_end, n)
    rows, prev_rev = [], inp.base_revenue
    for i in range(n):
        rev = prev_rev * (1 + growth[i])
        ebit = rev * margin[i]
        nopat = ebit * (1 - inp.tax_rate)
        da = rev * inp.da_pct
        capex = rev * inp.capex_pct
        d_nwc = (rev - prev_rev) * inp.nwc_pct
        fcff = nopat + da - capex - d_nwc
        rows.append({"Année": f"A+{i + 1}", "Croissance": growth[i], "Chiffre d'affaires": rev,
                     "Marge EBIT": margin[i], "EBIT": ebit, "Impôts": ebit * inp.tax_rate, "NOPAT": nopat,
                     "D&A": da, "Capex": capex, "Δ BFR": d_nwc, "FCFF": fcff, "EBITDA": ebit + da})
        prev_rev = rev
    return pd.DataFrame(rows).set_index("Année")


def run(inp: DCFInputs, wacc: float | None = None, g: float | None = None,
        exit_multiple: float | None = None) -> DCFResult:
    w = inp.wacc if wacc is None else wacc
    g = inp.terminal_growth if g is None else g
    mult = inp.exit_multiple if exit_multiple is None else exit_multiple
    proj = project(inp)
    t = np.arange(1, inp.years + 1) - (0.5 if inp.mid_year else 0.0)
    disc = 1 / (1 + w) ** t
    proj["Facteur d'actualisation"] = disc
    proj["FCFF actualisé"] = proj["FCFF"] * disc
    pv_fcf = float(proj["FCFF actualisé"].sum())

    n_disc = 1 / (1 + w) ** inp.years  # VT actualisée en fin d'année N
    fcf_n = float(proj["FCFF"].iloc[-1])
    ebitda_n = float(proj["EBITDA"].iloc[-1])
    tv_g = fcf_n * (1 + g) / (w - g) if w > g else float("nan")
    tv_x = ebitda_n * mult
    ev_g = pv_fcf + tv_g * n_disc
    ev_x = pv_fcf + tv_x * n_disc

    def per_share(ev):
        if not inp.shares or math.isnan(ev):
            return float("nan")
        return (ev - inp.net_debt) / inp.shares * inp.fx_to_price_ccy

    v_g, v_x = per_share(ev_g), per_share(ev_x)
    vals = [v for v in (v_g, v_x) if not math.isnan(v)]
    blended = float(np.mean(vals)) if vals else float("nan")
    upside = blended / inp.price - 1 if inp.price and not math.isnan(blended) else float("nan")
    if math.isnan(upside):
        verdict = "indéterminé"
    elif upside > 0.15:
        verdict = "SOUS-ÉVALUÉE"
    elif upside < -0.15:
        verdict = "SURÉVALUÉE"
    else:
        verdict = "CORRECTEMENT VALORISÉE"
    implied_mult = tv_g / ebitda_n if ebitda_n > 0 and not math.isnan(tv_g) else float("nan")
    # croissance perpétuelle implicite par le multiple de sortie : TV = FCF(1+g)/(w-g)
    implied_g = (tv_x * w - fcf_n) / (tv_x + fcf_n) if tv_x + fcf_n != 0 else float("nan")
    return DCFResult(projection=proj, wacc=w, pv_fcf=pv_fcf, tv_gordon=tv_g, tv_exit=tv_x, ev_gordon=ev_g,
                     ev_exit=ev_x, value_gordon=v_g, value_exit=v_x, value_blended=blended, upside=upside,
                     verdict=verdict, tv_share_gordon=(tv_g * n_disc) / ev_g if ev_g else float("nan"),
                     implied_multiple_gordon=implied_mult, implied_growth_exit=implied_g)


def sensitivity(inp: DCFInputs, waccs: list[float] | None = None, growths: list[float] | None = None,
                method: str = "gordon") -> pd.DataFrame:
    base = inp.wacc
    waccs = waccs or [base + d for d in (-0.02, -0.01, -0.005, 0, 0.005, 0.01, 0.02)]
    if method == "gordon":
        cols = growths or [inp.terminal_growth + d for d in (-0.01, -0.005, 0, 0.005, 0.01)]
        data = {f"g = {g:.1%}": [run(inp, w, g=g).value_gordon for w in waccs] for g in cols}
    else:
        cols = growths or [inp.exit_multiple + d for d in (-4, -2, 0, 2, 4)]
        data = {f"{m:.1f}x": [run(inp, w, exit_multiple=m).value_exit for w in waccs] for m in cols}
    return pd.DataFrame(data, index=[f"CMPC {w:.1%}" for w in waccs])


def scenarios(inp: DCFInputs) -> pd.DataFrame:
    """Bear / base / bull sur croissance, marge et CMPC."""
    cases = {
        "Baissier": replace(inp, growth_start=inp.growth_start - 0.04, growth_end=inp.growth_end - 0.02,
                            margin_end=inp.margin_end - 0.03, exit_multiple=inp.exit_multiple * 0.8,
                            risk_free=inp.risk_free + 0.01),
        "Central": inp,
        "Haussier": replace(inp, growth_start=inp.growth_start + 0.03, growth_end=inp.growth_end + 0.01,
                            margin_end=inp.margin_end + 0.02, exit_multiple=inp.exit_multiple * 1.15,
                            risk_free=inp.risk_free - 0.005),
    }
    rows = []
    for name, c in cases.items():
        r = run(c)
        rows.append({"Scénario": name, "CMPC": r.wacc, "Valeur (Gordon)": r.value_gordon,
                     "Valeur (multiple)": r.value_exit, "Valeur retenue": r.value_blended, "Potentiel": r.upside})
    return pd.DataFrame(rows).set_index("Scénario")


def key_risks(inp: DCFInputs, res: DCFResult, f) -> list[str]:
    """Hypothèses qui pourraient faire s'effondrer le modèle."""
    risks = []
    if res.tv_share_gordon > 0.75:
        risks.append(f"{res.tv_share_gordon:.0%} de la valeur vient de la valeur terminale : le modèle dépend "
                     "surtout de ce qui se passe après 5 ans.")
    if not math.isnan(f.revenue_cagr) and inp.growth_start > f.revenue_cagr + 0.05:
        risks.append(f"Croissance projetée ({inp.growth_start:.1%}) très supérieure à l'historique "
                     f"({f.revenue_cagr:.1%}).")
    if inp.margin_end > inp.margin_start + 0.03:
        risks.append("Le modèle suppose une expansion des marges : risque d'exécution.")
    s = sensitivity(inp)
    lo, hi = float(np.nanmin(s.values)), float(np.nanmax(s.values))
    if inp.price and hi / max(lo, 1e-9) > 2:
        risks.append(f"Forte sensibilité : la juste valeur varie de {lo:,.0f} à {hi:,.0f} selon CMPC et g.")
    if not math.isnan(res.implied_multiple_gordon) and abs(res.implied_multiple_gordon - inp.exit_multiple) / inp.exit_multiple > 0.35:
        risks.append(f"Incohérence entre méthodes : Gordon implique {res.implied_multiple_gordon:.1f}x EBITDA "
                     f"contre {inp.exit_multiple:.1f}x retenu.")
    if not math.isnan(res.implied_growth_exit) and res.implied_growth_exit > 0.04:
        risks.append(f"Le multiple de sortie implique une croissance perpétuelle de {res.implied_growth_exit:.1%} "
                     "(> croissance nominale de l'économie).")
    if (res.projection["FCFF"] < 0).any():
        risks.append("FCFF négatif sur au moins une année : la valeur repose sur un redressement futur.")
    if not math.isnan(f.debt_to_equity) and f.debt_to_equity > 2:
        risks.append(f"Levier élevé (D/E {f.debt_to_equity:.1f}) : la valeur des actions est très sensible à la VE.")
    if inp.beta < 0.8:
        risks.append("Bêta faible → CMPC bas ; un re-rating du risque ferait baisser la valeur.")
    if "Financial" in (f.sector or ""):
        risks.append("Secteur financier : un DCF FCFF est peu adapté (préférer P/B, ROE, modèle de dividendes).")
    risks.append("Hausse des taux longs : +1 pt de taux sans risque = +1 pt de CMPC (voir tableau de sensibilité).")
    return risks
