"""Moteur de risque de portefeuille (style desk risque / Bridgewater).

Corrélations, concentration (secteur, pays, devise), sensibilité aux taux,
stress tests historiques et hypothétiques, VaR / CVaR (historique, paramétrique,
Cornish-Fisher, Monte-Carlo Student-t), liquidité, contributions au risque,
scénarios extrêmes probabilisés, couvertures et rééquilibrage sous contraintes.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import pandas as pd
from scipy import optimize, stats

from ..config import LIMITS, RiskLimits
from . import indicators as ind

TD = 252

HISTORICAL_STRESS = {
    "Crise financière 2008 (09/10/2007 → 09/03/2009)": ("2007-10-09", "2009-03-09"),
    "Crise de la dette euro 2011 (29/04 → 03/10/2011)": ("2011-04-29", "2011-10-03"),
    "Choc Chine / pétrole 2015-16 (20/07/2015 → 11/02/2016)": ("2015-07-20", "2016-02-11"),
    "Krach Covid 2020 (19/02 → 23/03/2020)": ("2020-02-19", "2020-03-23"),
    "Choc de taux 2022 (03/01 → 12/10/2022)": ("2022-01-03", "2022-10-12"),
}

# Choc marché actions, choc de taux (pb), probabilité annuelle indicative (fréquence historique)
HYPOTHETICAL = {
    "Récession modérée": {"equity": -0.20, "rates_bp": -100, "proba": 0.15,
                          "desc": "Récession classique : actions −20 %, la banque centrale baisse les taux."},
    "Récession sévère / krach": {"equity": -0.35, "rates_bp": -150, "proba": 0.05,
                                 "desc": "Type 2008 : actions −35 %, fuite vers la qualité."},
    "Choc d'inflation / taux +200 pb": {"equity": -0.15, "rates_bp": 200, "proba": 0.07,
                                         "desc": "Type 2022 : taux longs +2 pts, actions et obligations baissent ensemble."},
    "Stagflation": {"equity": -0.25, "rates_bp": 150, "proba": 0.04,
                    "desc": "Croissance faible + inflation : pire cas pour un 60/40."},
    "Krach éclair (-10 % en 1 semaine)": {"equity": -0.10, "rates_bp": -30, "proba": 0.10,
                                           "desc": "Choc de liquidité court (2010, 2015, 2018, 2024)."},
}


# ------------------------------------------------------------------ bases
def clean_prices(prices: pd.DataFrame, min_obs: int = 120) -> pd.DataFrame:
    p = prices.ffill(limit=5)
    keep = [c for c in p.columns if p[c].notna().sum() >= min_obs]
    return p[keep]


def returns(prices: pd.DataFrame) -> pd.DataFrame:
    return prices.pct_change(fill_method=None).iloc[1:]


def normalize_weights(w: dict[str, float]) -> pd.Series:
    s = pd.Series(w, dtype=float).clip(lower=0)
    return s / s.sum() if s.sum() > 0 else s


def portfolio_series(rets: pd.DataFrame, w: pd.Series) -> pd.Series:
    """Rendement quotidien du portefeuille (rééquilibré chaque jour) sur la période commune."""
    r = rets[w.index].dropna()
    return r @ w


def ledoit_wolf(rets: pd.DataFrame) -> pd.DataFrame:
    """Covariance rétrécie vers une cible identité mise à l'échelle (Ledoit & Wolf 2004)."""
    x = rets.dropna().values
    n, p = x.shape
    x = x - x.mean(axis=0)
    s = x.T @ x / n
    mu = np.trace(s) / p
    target = mu * np.eye(p)
    d2 = np.sum((s - target) ** 2)
    b2 = sum(np.sum((np.outer(r, r) - s) ** 2) for r in x) / n ** 2
    shrink = min(b2, d2) / d2 if d2 > 0 else 1.0
    cov = shrink * target + (1 - shrink) * s
    return pd.DataFrame(cov, index=rets.columns, columns=rets.columns)


# ------------------------------------------------------------------ corrélation & concentration
def correlation_report(rets: pd.DataFrame, w: pd.Series) -> dict:
    corr = rets[w.index].dropna().corr()
    pairs = []
    cols = list(corr.columns)
    for i in range(len(cols)):
        for j in range(i + 1, len(cols)):
            pairs.append((cols[i], cols[j], corr.iloc[i, j]))
    num = sum(w[a] * w[b] * c for a, b, c in pairs)
    den = sum(w[a] * w[b] for a, b, _ in pairs)
    avg = num / den if den > 0 else float("nan")
    high = sorted([p for p in pairs if p[2] > 0.75], key=lambda x: -x[2])
    return {"matrix": corr, "weighted_avg": avg, "high_pairs": high}


def breakdown(w: pd.Series, attr: dict[str, str]) -> pd.Series:
    s = pd.Series({t: attr.get(t) or "Inconnu" for t in w.index})
    return w.groupby(s).sum().sort_values(ascending=False)


def hhi(w: pd.Series) -> float:
    return float((w ** 2).sum())


# ------------------------------------------------------------------ sensibilité aux taux
def rate_sensitivity(prices: pd.DataFrame, yield10: pd.Series, years: int = 5) -> pd.Series:
    """Variation de prix (en %) pour +100 pb sur le 10 ans US, par régression hebdomadaire."""
    if yield10 is None or yield10.empty:
        return pd.Series(dtype=float)
    p = prices.resample("W-FRI").last()
    y = yield10.resample("W-FRI").last()
    start = p.index[-1] - pd.DateOffset(years=years)
    r = p.pct_change(fill_method=None)
    dy = y.diff()  # en points de %
    df = r.join(dy.rename("_dy"), how="inner")
    df = df[df.index >= start]
    out = {}
    for c in prices.columns:
        sub = df[[c, "_dy"]].dropna()
        if len(sub) < 52 or sub["_dy"].var() == 0:
            continue
        out[c] = np.cov(sub[c], sub["_dy"])[0, 1] / sub["_dy"].var()  # Δprix pour +1 pt
    return pd.Series(out)


# ------------------------------------------------------------------ VaR / CVaR
def var_table(port: pd.Series, value: float, conf=(0.95, 0.99), horizons=(1, 10), sims: int = 50_000,
              seed: int = 7) -> pd.DataFrame:
    r = port.dropna()
    mu, sd = r.mean(), r.std()
    sk, ku = stats.skew(r), stats.kurtosis(r)  # excès de kurtosis
    df_t, loc_t, sc_t = stats.t.fit(r)
    df_t = max(df_t, 2.5)
    rng = np.random.default_rng(seed)
    rows = []
    for h in horizons:
        # Monte-Carlo : somme de h tirages Student-t (queues épaisses)
        sim = stats.t.rvs(df_t, loc=loc_t, scale=sc_t, size=(sims, h), random_state=rng).sum(axis=1)
        hist_h = r.rolling(h).sum().dropna() if h > 1 else r
        for c in conf:
            q = 1 - c
            z = stats.norm.ppf(q)
            z_cf = z + (z ** 2 - 1) * sk / 6 + (z ** 3 - 3 * z) * ku / 24 - (2 * z ** 3 - 5 * z) * sk ** 2 / 36
            hist_var = -np.quantile(hist_h, q)
            hist_cvar = -hist_h[hist_h <= -hist_var].mean()
            param = -(mu * h + z * sd * math.sqrt(h))
            cf = -(mu * h + z_cf * sd * math.sqrt(h))
            mc_var = -np.quantile(sim, q)
            mc_cvar = -sim[sim <= -mc_var].mean()
            rows.append({"Horizon": f"{h} j", "Confiance": f"{c:.0%}", "VaR historique": hist_var,
                         "CVaR historique": hist_cvar, "VaR normale": param, "VaR Cornish-Fisher": cf,
                         "VaR Monte-Carlo (t)": mc_var, "CVaR Monte-Carlo (t)": mc_cvar,
                         "VaR max (€/$)": max(hist_var, cf, mc_var) * value})
    return pd.DataFrame(rows)


# ------------------------------------------------------------------ stress tests
def stress_historical(prices_long: pd.DataFrame, w: pd.Series, bench: str) -> pd.DataFrame:
    """Performance réelle du portefeuille actuel sur chaque crise. Si un titre
    n'existait pas, on l'approxime par bêta × indice de référence (signalé)."""
    rets = returns(prices_long)
    rows = []
    for name, (a, b) in HISTORICAL_STRESS.items():
        win = prices_long.loc[a:b]
        if win.empty or bench not in win or win[bench].dropna().empty:
            continue
        bench_ret = win[bench].dropna().iloc[-1] / win[bench].dropna().iloc[0] - 1
        total, proxied = 0.0, []
        for t, wt in w.items():
            s = win[t].dropna() if t in win else pd.Series(dtype=float)
            if len(s) >= 0.9 * len(win[bench].dropna()):
                r = s.iloc[-1] / s.iloc[0] - 1
            else:
                b_ = ind.beta(rets[t], rets[bench]) if t in rets else float("nan")
                b_ = 1.0 if math.isnan(b_) else b_
                r = max(-0.95, b_ * bench_ret)
                proxied.append(t)
            total += wt * r
        rows.append({"Scénario": name, "Indice de référence": bench_ret, "Portefeuille": total,
                     "Lignes approximées (bêta)": ", ".join(proxied) or "—"})
    return pd.DataFrame(rows)


def stress_hypothetical(w: pd.Series, betas: pd.Series, rate_beta: pd.Series, value: float) -> pd.DataFrame:
    rows = []
    for name, sc in HYPOTHETICAL.items():
        per = {}
        for t in w.index:
            b = betas.get(t, 1.0)
            b = 1.0 if b is None or math.isnan(b) else b
            rb = rate_beta.get(t, 0.0)
            rb = 0.0 if rb is None or math.isnan(rb) else rb
            per[t] = max(-0.95, b * sc["equity"] + rb * sc["rates_bp"] / 100)
        loss = float(sum(w[t] * per[t] for t in w.index))
        worst = min(per, key=per.get)
        rows.append({"Scénario": name, "Description": sc["desc"], "Probabilité annuelle (indicative)": sc["proba"],
                     "Impact portefeuille": loss, "Perte estimée": loss * value,
                     "Pire ligne": f"{worst} ({per[worst]:.0%})"})
    return pd.DataFrame(rows)


def tail_probabilities(port: pd.Series, n_paths: int = 20_000, horizon: int = TD, block: int = 20,
                       seed: int = 11) -> pd.DataFrame:
    """Probabilités sur 1 an par bootstrap par blocs (préserve la persistance de la volatilité)."""
    r = port.dropna().values
    if len(r) < 2 * block:
        return pd.DataFrame()
    rng = np.random.default_rng(seed)
    n_blocks = math.ceil(horizon / block)
    starts = rng.integers(0, len(r) - block, size=(n_paths, n_blocks))
    idx = (starts[:, :, None] + np.arange(block)).reshape(n_paths, -1)[:, :horizon]
    paths = np.cumprod(1 + r[idx], axis=1)
    final = paths[:, -1] - 1
    dd = (paths / np.maximum.accumulate(paths, axis=1) - 1).min(axis=1)
    rows = []
    for x in (0.10, 0.20, 0.30, 0.40):
        rows.append({"Événement sur 12 mois": f"Perte annuelle > {x:.0%}", "Probabilité": float((final < -x).mean())})
    for x in (0.15, 0.25, 0.35):
        rows.append({"Événement sur 12 mois": f"Baisse maximale en cours d'année > {x:.0%}",
                     "Probabilité": float((dd < -x).mean())})
    rows.append({"Événement sur 12 mois": "Rendement médian simulé", "Probabilité": float(np.median(final))})
    return pd.DataFrame(rows)


# ------------------------------------------------------------------ liquidité
def liquidity(w: pd.Series, value: float, adv_value: dict[str, float], participation: float) -> pd.DataFrame:
    rows = []
    for t, wt in w.items():
        pos = wt * value
        adv = adv_value.get(t)
        if not adv or math.isnan(adv) or adv <= 0:
            rows.append({"Ligne": t, "Montant": pos, "Volume moyen/jour": np.nan, "Jours pour liquider": np.nan,
                         "Note liquidité /10": 5.0})
            continue
        days = pos / (adv * participation)
        score = (10 if days < 0.05 else 9 if days < 0.25 else 8 if days < 1 else 6 if days < 3 else
                 4 if days < 10 else 2 if days < 30 else 1)
        rows.append({"Ligne": t, "Montant": pos, "Volume moyen/jour": adv, "Jours pour liquider": days,
                     "Note liquidité /10": float(score)})
    return pd.DataFrame(rows).set_index("Ligne")


# ------------------------------------------------------------------ contributions au risque
def risk_contributions(cov: pd.DataFrame, w: pd.Series) -> pd.DataFrame:
    c = cov.loc[w.index, w.index].values * TD
    wv = w.values
    sig = math.sqrt(wv @ c @ wv)
    mrc = c @ wv / sig
    rc = wv * mrc
    vol = np.sqrt(np.diag(c))
    return pd.DataFrame({"Poids": wv, "Volatilité annuelle": vol, "Contribution au risque": rc / sig,
                         "Ratio risque/poids": (rc / sig) / np.where(wv > 0, wv, np.nan)}, index=w.index)


def optimize_weights(cov: pd.DataFrame, method: str, max_w: float, mu: pd.Series | None = None,
                     rf: float = 0.0) -> pd.Series:
    """Parité de risque, variance minimale ou Sharpe maximal, poids ∈ [0, max_w]."""
    c = cov.values * TD
    n = len(c)
    max_w = max(max_w, 1.0 / n + 1e-6)
    bounds = [(0.0, max_w)] * n
    cons = [{"type": "eq", "fun": lambda x: x.sum() - 1}]
    x0 = np.full(n, 1 / n)
    if method == "risk_parity":
        def obj(x):
            port = math.sqrt(x @ c @ x)
            rc = x * (c @ x) / port
            return float(((rc - port / n) ** 2).sum()) * 1e4
    elif method == "min_variance":
        def obj(x):
            return float(x @ c @ x)
    else:
        m = mu.values if mu is not None else np.zeros(n)

        def obj(x):
            v = math.sqrt(x @ c @ x)
            return -(x @ m - rf) / v if v > 0 else 0.0
    res = optimize.minimize(obj, x0, method="SLSQP", bounds=bounds, constraints=cons,
                            options={"maxiter": 500, "ftol": 1e-12})
    x = np.clip(res.x if res.success else x0, 0, None)
    return pd.Series(x / x.sum(), index=cov.index)


def shrunk_expected_returns(rets: pd.DataFrame, intensity: float = 0.5) -> pd.Series:
    """Rendements attendus annualisés rétrécis vers la moyenne commune (réduit l'erreur d'estimation)."""
    m = rets.mean() * TD
    return intensity * m.mean() + (1 - intensity) * m


# ------------------------------------------------------------------ carte de chaleur des risques
def heatmap_scores(w: pd.Series, vol: pd.Series, mdd: pd.Series, corr_to_port: pd.Series,
                   liq: pd.Series, rate_b: pd.Series, limits: RiskLimits = LIMITS) -> pd.DataFrame:
    """Note 1 (faible) à 10 (élevé) par ligne et par dimension de risque."""
    def scale(x, lo, hi):
        if x is None or (isinstance(x, float) and math.isnan(x)):
            return np.nan
        return float(np.clip(1 + 9 * (x - lo) / (hi - lo), 1, 10))

    rows = {}
    for t in w.index:
        rows[t] = {
            "Concentration": scale(w[t], 0.02, limits.max_single_position * 2),
            "Volatilité": scale(vol.get(t, np.nan), 0.12, 0.60),
            "Drawdown": scale(-mdd.get(t, np.nan), 0.15, 0.70),
            "Corrélation au portefeuille": scale(corr_to_port.get(t, np.nan), 0.2, 0.95),
            "Liquidité": scale(11 - liq.get(t, 5.0), 1, 10),
            "Taux d'intérêt": scale(abs(rate_b.get(t, np.nan)), 0.0, 0.15),
        }
    df = pd.DataFrame(rows).T
    df["Score global"] = df.mean(axis=1, skipna=True)
    return df.sort_values("Score global", ascending=False)


@dataclass
class LimitCheck:
    rule: str
    value: str
    limit: str
    ok: bool

    def __post_init__(self):
        self.ok = bool(self.ok)


def check_limits(w: pd.Series, sectors: pd.Series, countries: pd.Series, var99: float, worst_stress: float,
                 avg_corr: float, max_days: float, limits: RiskLimits = LIMITS) -> list[LimitCheck]:
    out = [
        LimitCheck("Poids max par ligne", f"{w.max():.1%} ({w.idxmax()})", f"{limits.max_single_position:.0%}",
                   w.max() <= limits.max_single_position + 1e-9),
        LimitCheck("Poids max par secteur", f"{sectors.max():.1%} ({sectors.idxmax()})", f"{limits.max_sector:.0%}",
                   sectors.max() <= limits.max_sector + 1e-9),
        LimitCheck("Poids max par pays", f"{countries.max():.1%} ({countries.idxmax()})", f"{limits.max_country:.0%}",
                   countries.max() <= limits.max_country + 1e-9),
        LimitCheck("VaR 99 % à 1 jour", f"{var99:.2%}", f"{limits.max_var_99_1d:.0%}", var99 <= limits.max_var_99_1d),
        LimitCheck("Perte en stress (pire scénario)", f"{worst_stress:.1%}", f"-{limits.max_drawdown_stress:.0%}",
                   worst_stress >= -limits.max_drawdown_stress),
        LimitCheck("Corrélation moyenne", f"{avg_corr:.2f}", f"{limits.max_avg_correlation:.2f}",
                   not (avg_corr > limits.max_avg_correlation)),
        LimitCheck("Jours pour liquider (pire ligne)", f"{max_days:.1f}", f"{limits.max_days_to_liquidate:.0f}",
                   not (max_days > limits.max_days_to_liquidate)),
    ]
    return out


def hedging_ideas(top_risks: list[tuple[str, float, str]], value: float, beta_port: float,
                  usd_share: float, rate_beta_port: float, biggest: tuple[str, float]) -> list[dict]:
    """Stratégies de couverture chiffrées pour les principaux risques identifiés."""
    ideas = []
    for key, _, label in top_risks:
        if key == "marché":
            notional = beta_port * value
            ideas.append({"Risque": label, "Couverture": "Achat de puts sur indice (S&P 500 / Euro Stoxx 50), "
                          "échéance 3-6 mois, prix d'exercice ~10 % sous le cours ; ou collar (put acheté + call vendu) "
                          "pour un coût proche de zéro ; ou vente de futures (ex. Micro E-mini) pour réduire le bêta.",
                          "Montant notionnel à couvrir": notional,
                          "Coût indicatif": "puts 10 % OTM 6 mois ≈ 1,5-3 % du notionnel ; collar ≈ 0-0,5 %"})
        elif key == "concentration":
            t, wt = biggest
            excess = max(0.0, wt - LIMITS.max_single_position)
            ideas.append({"Risque": label, "Couverture": f"Alléger {t} de {excess:.1%} du portefeuille pour revenir "
                          f"sous la limite de {LIMITS.max_single_position:.0%} ; si la vente est fiscalement coûteuse, "
                          f"collar sur {t} (put 10 % OTM financé par un call 15 % OTM).",
                          "Montant notionnel à couvrir": wt * value, "Coût indicatif": "collar ≈ coût nul ; vente = fiscalité"})
        elif key == "taux":
            ideas.append({"Risque": label, "Couverture": "Réduire la duration : remplacer les obligations longues par "
                          "des échéances courtes (0-3 ans) ou du monétaire ; diversifier avec des obligations indexées "
                          "sur l'inflation ; réduire les valeurs de croissance longue duration.",
                          "Montant notionnel à couvrir": abs(rate_beta_port) * value,
                          "Coût indicatif": "perte de portage limitée (courbe peu pentue)"})
        elif key == "change":
            ideas.append({"Risque": label, "Couverture": "Utiliser des classes d'ETF couvertes en EUR (EUR Hedged) pour "
                          "50-100 % de l'exposition USD, ou un contrat de change à terme EUR/USD.",
                          "Montant notionnel à couvrir": usd_share * value,
                          "Coût indicatif": "≈ différentiel de taux USD-EUR (~1,5-2 %/an) ; frais ETF hedged +0,05-0,15 %"})
        elif key == "corrélation":
            ideas.append({"Risque": label, "Couverture": "Ajouter des actifs décorrélés : or (5-10 %), obligations d'État "
                          "courtes, stratégies trend-following ; remplacer les paires > 0,8 de corrélation par une seule ligne.",
                          "Montant notionnel à couvrir": 0.10 * value, "Coût indicatif": "coût d'opportunité en marché haussier"})
        elif key == "secteur":
            ideas.append({"Risque": label, "Couverture": "Plafonner le secteur dominant à 30 % ; réallouer vers les "
                          "secteurs sous-pondérés ou couvrir via un put sur l'ETF sectoriel (ex. XLK, XLF).",
                          "Montant notionnel à couvrir": 0.0, "Coût indicatif": "variable"})
        elif key == "liquidité":
            ideas.append({"Risque": label, "Couverture": "Fractionner les ordres (≤ 20 % du volume quotidien), utiliser des "
                          "ordres limites, et garder 5 % de liquidités pour ne pas vendre en catastrophe.",
                          "Montant notionnel à couvrir": 0.0, "Coût indicatif": "faible"})
    return ideas
