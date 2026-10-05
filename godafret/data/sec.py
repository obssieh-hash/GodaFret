"""SEC EDGAR XBRL — gratuit, sans clé (User-Agent obligatoire).

Source officielle des comptes 10-K des sociétés américaines : sert à obtenir
5 à 15 ans d'historique (Yahoo n'en fournit que 4).
"""
from __future__ import annotations

import pandas as pd

from ..config import sec_user_agent
from .cache import DAY, cached
from .http import get_json

# Plusieurs balises US-GAAP possibles pour un même poste : on prend la première
# disponible pour chaque exercice.
TAGS = {
    "revenue": ["RevenueFromContractWithCustomerExcludingAssessedTax", "Revenues",
                "SalesRevenueNet", "RevenueFromContractWithCustomerIncludingAssessedTax"],
    "operating_income": ["OperatingIncomeLoss"],
    "net_income": ["NetIncomeLoss"],
    "operating_cash_flow": ["NetCashProvidedByUsedInOperatingActivities"],
    "capex": ["PaymentsToAcquirePropertyPlantAndEquipment"],
    "equity": ["StockholdersEquity"],
    "long_term_debt": ["LongTermDebt", "LongTermDebtNoncurrent"],
    "dividends_paid": ["PaymentsOfDividendsCommonStock", "PaymentsOfDividends"],
    "eps_diluted": ["EarningsPerShareDiluted"],
}


def _headers() -> dict:
    return {"User-Agent": sec_user_agent(), "Accept-Encoding": "gzip, deflate"}


@cached(ttl=7 * DAY)
def ticker_to_cik() -> dict[str, int]:
    data = get_json("https://www.sec.gov/files/company_tickers.json", headers=_headers())
    return {row["ticker"].upper(): int(row["cik_str"]) for row in data.values()}


@cached(ttl=DAY)
def company_facts(ticker: str) -> dict:
    cik = ticker_to_cik().get(ticker.upper().replace(".", "-"))
    if cik is None:
        return {}
    return get_json(f"https://data.sec.gov/api/xbrl/companyfacts/CIK{cik:010d}.json", headers=_headers())


def _annual_from_tag(facts: dict, tag: str) -> pd.Series:
    node = facts.get("facts", {}).get("us-gaap", {}).get(tag)
    if not node:
        return pd.Series(dtype=float)
    units = node.get("units", {})
    rows = units.get("USD") or units.get("USD/shares") or next(iter(units.values()), [])
    recs = []
    for r in rows:
        # 10-K, exercice complet (≈ 1 an pour les flux, valeur de clôture pour les stocks)
        if r.get("form") not in ("10-K", "10-K/A") or r.get("fp") != "FY":
            continue
        end = pd.Timestamp(r["end"])
        if "start" in r:
            days = (end - pd.Timestamp(r["start"])).days
            if not 350 <= days <= 380:
                continue
        recs.append((end, r["val"], r.get("filed", "")))
    if not recs:
        return pd.Series(dtype=float)
    df = pd.DataFrame(recs, columns=["end", "val", "filed"]).sort_values("filed")
    # La dernière publication fait foi (retraitements)
    s = df.groupby("end")["val"].last().sort_index().astype(float)
    return s


def annual_fundamentals(ticker: str, years: int = 10) -> pd.DataFrame:
    """Lignes = date de clôture d'exercice, colonnes = postes (USD)."""
    try:
        facts = company_facts(ticker)
    except Exception:
        return pd.DataFrame()
    if not facts:
        return pd.DataFrame()
    cols = {}
    for key, tags in TAGS.items():
        merged = pd.Series(dtype=float)
        for tag in tags:
            s = _annual_from_tag(facts, tag)
            merged = s if merged.empty else merged.combine_first(s)
        if not merged.empty:
            cols[key] = merged
    if not cols:
        return pd.DataFrame()
    df = pd.DataFrame(cols).sort_index()
    if "revenue" in df:
        df = df[df["revenue"].notna()]
    return df.tail(years)
