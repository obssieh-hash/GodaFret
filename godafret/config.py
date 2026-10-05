"""Configuration : clés API (toutes optionnelles), hypothèses de marché et limites de risque.

Les clés sont lues dans les variables d'environnement, puis dans `st.secrets`
si l'application tourne sous Streamlit. Aucune clé n'est obligatoire : sans clé,
l'outil utilise Yahoo Finance, SEC EDGAR, FRED (CSV) et la BCE (Frankfurter).
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field


def _secret(name: str) -> str | None:
    value = os.environ.get(name)
    if value:
        return value.strip()
    try:  # Streamlit est optionnel (utilisation en ligne de commande / tests)
        import streamlit as st

        if name in st.secrets:
            return str(st.secrets[name]).strip()
    except Exception:
        pass
    return None


def api_key(name: str) -> str | None:
    """FMP_API_KEY, FINNHUB_API_KEY, ALPHAVANTAGE_API_KEY, FRED_API_KEY."""
    return _secret(name)


def sec_user_agent() -> str:
    # La SEC exige un User-Agent identifiant l'appelant (nom + e-mail).
    return _secret("SEC_USER_AGENT") or "GodaFret research contact@godafret.app"


@dataclass(frozen=True)
class MarketAssumptions:
    """Hypothèses par défaut, toutes modifiables dans l'interface."""

    equity_risk_premium: float = 0.050   # prime de risque actions (Damodaran ~4.5-5.5 %)
    fallback_risk_free: float = 0.042    # si FRED est indisponible (10 ans US)
    terminal_growth: float = 0.025       # croissance perpétuelle
    default_tax_rate: float = 0.21       # IS fédéral US
    trading_days: int = 252


@dataclass(frozen=True)
class RiskLimits:
    """Limites façon comité des risques d'une banque d'investissement."""

    max_single_position: float = 0.10    # 10 % max par ligne
    max_sector: float = 0.30             # 30 % max par secteur
    max_country: float = 0.60            # 60 % max par pays (hors US toléré via override)
    max_var_99_1d: float = 0.03          # VaR 99 % 1 jour < 3 % du portefeuille
    max_drawdown_stress: float = 0.35    # perte max en scénario de stress
    max_avg_correlation: float = 0.60    # corrélation moyenne entre lignes
    max_days_to_liquidate: float = 5.0   # à 20 % du volume quotidien moyen
    participation_rate: float = 0.20


@dataclass(frozen=True)
class FrenchTax:
    """Fiscalité française 2026 (à vérifier chaque année — paramètres modifiables).

    LFSS 2026 : prélèvements sociaux portés à 18,6 % sur la plupart des revenus du
    capital (PFU = 12,8 % + 18,6 % = 31,4 %) ; l'assurance-vie reste à 17,2 %.
    """

    ir_flat: float = 0.128
    social: float = 0.186
    social_life_insurance: float = 0.172
    pea_min_years: int = 5
    av_allowance_single: float = 4600.0
    av_allowance_couple: float = 9200.0
    us_withholding_treaty: float = 0.15  # retenue à la source US (convention FR-US, W-8BEN)

    @property
    def pfu(self) -> float:
        return self.ir_flat + self.social


MARKET = MarketAssumptions()
LIMITS = RiskLimits()
TAX_FR = FrenchTax()


@dataclass
class InvestorProfile:
    risk_tolerance: str = "modérée"      # prudente | modérée | dynamique | agressive
    amount: float = 100_000.0
    horizon_years: int = 10
    sectors: list[str] = field(default_factory=list)
    account: str = "CTO"                 # PEA | Assurance-vie | CTO | PER
