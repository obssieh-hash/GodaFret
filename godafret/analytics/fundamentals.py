"""Ratios fondamentaux à partir des états financiers normalisés et du profil Yahoo."""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from .indicators import cagr


def pick(df: pd.DataFrame, names: list[str]) -> pd.Series:
    """Première colonne disponible parmi `names` (les libellés Yahoo varient)."""
    if df is None or df.empty:
        return pd.Series(dtype=float)
    for n in names:
        if n in df.columns and df[n].notna().any():
            return df[n]
    return pd.Series(dtype=float)


def last(s: pd.Series) -> float:
    s = s.dropna() if s is not None else pd.Series(dtype=float)
    return float(s.iloc[-1]) if not s.empty else float("nan")


def nz(x, default=float("nan")) -> float:
    try:
        x = float(x)
        return default if math.isnan(x) or math.isinf(x) else x
    except (TypeError, ValueError):
        return default


REVENUE = ["Total Revenue", "Operating Revenue"]
OP_INCOME = ["Operating Income", "EBIT"]
EBITDA = ["EBITDA", "Normalized EBITDA"]
NET_INCOME = ["Net Income", "Net Income Common Stockholders"]
INTEREST = ["Interest Expense", "Interest Expense Non Operating"]
PRETAX = ["Pretax Income"]
TAX = ["Tax Provision"]
DA = ["Depreciation And Amortization", "Depreciation Amortization Depletion", "Reconciled Depreciation"]
OCF = ["Operating Cash Flow", "Cash Flow From Continuing Operating Activities"]
CAPEX = ["Capital Expenditure"]
FCF = ["Free Cash Flow"]
DIVIDENDS_PAID = ["Cash Dividends Paid", "Common Stock Dividend Paid"]
WC_CHANGE = ["Change In Working Capital"]
TOTAL_DEBT = ["Total Debt"]
EQUITY = ["Stockholders Equity", "Common Stock Equity", "Total Equity Gross Minority Interest"]
CASH = ["Cash Cash Equivalents And Short Term Investments", "Cash And Cash Equivalents"]
INVESTED_CAPITAL = ["Invested Capital"]
SHARES = ["Ordinary Shares Number", "Share Issued"]


@dataclass
class Fundamentals:
    ticker: str
    name: str = ""
    sector: str = "Inconnu"
    industry: str = ""
    country: str = "Inconnu"
    currency: str = "USD"
    price: float = float("nan")
    market_cap: float = float("nan")
    pe: float = float("nan")
    forward_pe: float = float("nan")
    beta: float = float("nan")
    dividend_yield: float = 0.0
    dividend_rate: float = 0.0
    payout_ratio: float = float("nan")
    fcf_payout: float = float("nan")
    debt_to_equity: float = float("nan")
    net_debt: float = float("nan")
    roe: float = float("nan")
    roic: float = float("nan")
    gross_margin: float = float("nan")
    operating_margin: float = float("nan")
    net_margin: float = float("nan")
    interest_coverage: float = float("nan")
    revenue_cagr: float = float("nan")
    revenue_years: int = 0
    revenue: pd.Series = field(default_factory=lambda: pd.Series(dtype=float))
    revenue_source: str = ""
    op_margin_std: float = float("nan")
    fcf: float = float("nan")
    avg_volume: float = float("nan")
    target_mean: float = float("nan")
    target_high: float = float("nan")
    target_low: float = float("nan")
    n_analysts: int = 0
    recommendation: str = ""
    shares: float = float("nan")

    def as_row(self) -> dict:
        d = {k: v for k, v in self.__dict__.items() if not isinstance(v, pd.Series)}
        return d


def compute(ticker: str, info: dict, st: dict, revenue: pd.Series | None = None,
            revenue_source: str = "") -> Fundamentals:
    inc = st.get("income", pd.DataFrame()) if st else pd.DataFrame()
    bal = st.get("balance", pd.DataFrame()) if st else pd.DataFrame()
    cf = st.get("cashflow", pd.DataFrame()) if st else pd.DataFrame()

    f = Fundamentals(ticker=ticker)
    f.name = info.get("shortName") or info.get("longName") or ticker
    f.sector = info.get("sector") or ("ETF" if info.get("quoteType") == "ETF" else "Inconnu")
    f.industry = info.get("industry") or ""
    f.country = info.get("country") or "Inconnu"
    f.currency = info.get("currency") or "USD"
    f.price = nz(info.get("currentPrice") or info.get("regularMarketPrice") or info.get("previousClose"))
    f.market_cap = nz(info.get("marketCap"))
    f.pe = nz(info.get("trailingPE"))
    f.forward_pe = nz(info.get("forwardPE"))
    f.beta = nz(info.get("beta"))
    f.shares = nz(info.get("sharesOutstanding"), last(pick(bal, SHARES)))
    f.avg_volume = nz(info.get("averageVolume") or info.get("averageDailyVolume10Day"))
    f.target_mean = nz(info.get("targetMeanPrice"))
    f.target_high = nz(info.get("targetHighPrice"))
    f.target_low = nz(info.get("targetLowPrice"))
    f.n_analysts = int(nz(info.get("numberOfAnalystOpinions"), 0))
    f.recommendation = info.get("recommendationKey") or ""

    # Rendement : calculé (le champ Yahoo `dividendYield` a changé d'unité en 2025)
    rate = nz(info.get("dividendRate"), nz(info.get("trailingAnnualDividendRate"), 0.0))
    f.dividend_rate = rate
    f.dividend_yield = rate / f.price if f.price and f.price > 0 and rate > 0 else 0.0

    revenue_s = revenue if revenue is not None and not revenue.empty else pick(inc, REVENUE).dropna()
    f.revenue = revenue_s
    f.revenue_source = revenue_source or ("Yahoo Finance" if not revenue_s.empty else "indisponible")
    if len(revenue_s) >= 2:
        r = revenue_s.tail(6)  # 5 ans de croissance = 6 points
        years = (r.index[-1] - r.index[0]).days / 365.25
        f.revenue_cagr = cagr(r.iloc[0], r.iloc[-1], years)
        f.revenue_years = int(round(years))

    rev = pick(inc, REVENUE)
    opi = pick(inc, OP_INCOME)
    ni = pick(inc, NET_INCOME)
    if not rev.empty:
        r_last = last(rev)
        f.operating_margin = last(opi) / r_last if r_last else float("nan")
        f.net_margin = last(ni) / r_last if r_last else float("nan")
        margins = (opi / rev).dropna()
        f.op_margin_std = float(margins.std()) if len(margins) >= 3 else float("nan")
    f.gross_margin = nz(info.get("grossMargins"))
    if math.isnan(f.operating_margin):
        f.operating_margin = nz(info.get("operatingMargins"))
    if math.isnan(f.net_margin):
        f.net_margin = nz(info.get("profitMargins"))

    debt = last(pick(bal, TOTAL_DEBT))
    equity = last(pick(bal, EQUITY))
    cash = last(pick(bal, CASH))
    if not math.isnan(debt) and not math.isnan(equity) and equity > 0:
        f.debt_to_equity = debt / equity
    elif info.get("debtToEquity") is not None:
        f.debt_to_equity = nz(info.get("debtToEquity")) / 100  # Yahoo : en %
    if math.isnan(debt):
        debt = nz(info.get("totalDebt"), 0.0)
    if math.isnan(cash):
        cash = nz(info.get("totalCash"), 0.0)
    f.net_debt = debt - cash

    f.roe = nz(info.get("returnOnEquity"))
    if math.isnan(f.roe) and equity and equity > 0:
        f.roe = last(ni) / equity

    # ROIC = NOPAT / capital investi
    pretax, tax = last(pick(inc, PRETAX)), last(pick(inc, TAX))
    tax_rate = min(max(tax / pretax, 0.0), 0.35) if pretax and pretax > 0 and not math.isnan(tax) else 0.21
    invested = last(pick(bal, INVESTED_CAPITAL))
    if math.isnan(invested) and not math.isnan(equity):
        invested = equity + (debt or 0) - (cash or 0)
    op_last = last(opi)
    if invested and invested > 0 and not math.isnan(op_last):
        f.roic = op_last * (1 - tax_rate) / invested

    interest = abs(last(pick(inc, INTEREST)))
    if interest and interest > 0 and not math.isnan(op_last):
        f.interest_coverage = op_last / interest

    fcf_s = pick(cf, FCF)
    if fcf_s.empty:
        fcf_s = pick(cf, OCF) + pick(cf, CAPEX)  # capex négatif chez Yahoo
    f.fcf = last(fcf_s)
    if math.isnan(f.fcf):
        f.fcf = nz(info.get("freeCashflow"))

    f.payout_ratio = nz(info.get("payoutRatio"))
    div_paid = abs(last(pick(cf, DIVIDENDS_PAID)))
    if f.fcf and f.fcf > 0 and div_paid and not math.isnan(div_paid):
        f.fcf_payout = div_paid / f.fcf
    elif f.fcf is not None and not math.isnan(f.fcf) and f.fcf <= 0 and div_paid > 0:
        f.fcf_payout = float("inf")
    return f


def moat_score(f: Fundamentals) -> tuple[str, float, list[str]]:
    """Note d'avantage concurrentiel (faible / modéré / fort) — proxy quantitatif :
    rentabilité du capital, marges, stabilité des marges, taille, croissance."""
    pts, why = 0.0, []
    if not math.isnan(f.roic):
        if f.roic > 0.20:
            pts += 3; why.append(f"ROIC élevé ({f.roic:.0%})")
        elif f.roic > 0.12:
            pts += 2; why.append(f"ROIC solide ({f.roic:.0%})")
        elif f.roic > 0.08:
            pts += 1
    if not math.isnan(f.gross_margin):
        if f.gross_margin > 0.60:
            pts += 2; why.append(f"marge brute de pricing power ({f.gross_margin:.0%})")
        elif f.gross_margin > 0.40:
            pts += 1
    if not math.isnan(f.operating_margin) and f.operating_margin > 0.25:
        pts += 1; why.append(f"marge opérationnelle {f.operating_margin:.0%}")
    if not math.isnan(f.op_margin_std) and f.op_margin_std < 0.03:
        pts += 1; why.append("marges très stables")
    if not math.isnan(f.market_cap) and f.market_cap > 200e9:
        pts += 1; why.append("effet d'échelle (méga-capitalisation)")
    if not math.isnan(f.revenue_cagr) and f.revenue_cagr > 0.10:
        pts += 1; why.append(f"croissance du CA {f.revenue_cagr:.0%}/an")
    score = pts / 9 * 10
    label = "fort" if pts >= 6 else "modéré" if pts >= 3 else "faible"
    return label, round(score, 1), why


def dividend_safety(f: Fundamentals, years_increase: int = 0) -> tuple[float, list[str]]:
    """Score de sécurité du dividende sur 10 (taux de distribution BPA et FCF,
    dette, couverture des intérêts, historique de hausses)."""
    if f.dividend_yield <= 0:
        return float("nan"), ["pas de dividende"]
    s, why = 5.0, []
    p = f.payout_ratio
    if not math.isnan(p):
        if p < 0.40: s += 1.5; why.append(f"taux de distribution bas ({p:.0%})")
        elif p < 0.60: s += 0.75
        elif p > 1.0: s -= 2.5; why.append(f"distribue plus que ses bénéfices ({p:.0%})")
        elif p > 0.80: s -= 1.25; why.append(f"taux de distribution élevé ({p:.0%})")
    fp = f.fcf_payout
    if not math.isnan(fp):
        if fp == float("inf"): s -= 2.5; why.append("FCF négatif")
        elif fp < 0.50: s += 1.5; why.append(f"dividende couvert {1/fp:.1f}x par le FCF" if fp > 0 else "FCF large")
        elif fp < 0.75: s += 0.5
        elif fp > 1.0: s -= 2; why.append(f"dividende > FCF ({fp:.0%})")
    de = f.debt_to_equity
    if not math.isnan(de):
        if de > 2.5: s -= 1; why.append(f"endettement élevé (D/E {de:.1f})")
        elif de < 0.5: s += 0.5
    if not math.isnan(f.interest_coverage) and f.interest_coverage < 4:
        s -= 1; why.append(f"couverture des intérêts faible ({f.interest_coverage:.1f}x)")
    if years_increase >= 25: s += 1.5; why.append(f"{years_increase} ans de hausses consécutives")
    elif years_increase >= 10: s += 1; why.append(f"{years_increase} ans de hausses")
    elif years_increase >= 5: s += 0.5
    if f.dividend_yield > 0.08: s -= 1.5; why.append(f"rendement suspect ({f.dividend_yield:.1%}) : risque de coupe")
    return float(np.clip(s, 0, 10)), why
