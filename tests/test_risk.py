import numpy as np
import pandas as pd

from godafret.analytics import risk
from tests.conftest import make_ohlcv


def _prices():
    return pd.DataFrame({f"A{i}": make_ohlcv(seed=i, n=800)["Close"] for i in range(5)})


def test_var_table_ordering():
    rets = risk.returns(_prices())
    w = risk.normalize_weights({c: 1 for c in rets.columns})
    port = risk.portfolio_series(rets, w)
    v = risk.var_table(port, 1_000_000, sims=5000)
    one = v[v["Horizon"] == "1 j"].set_index("Confiance")
    assert (one.loc["99%", "VaR historique"] > one.loc["95%", "VaR historique"])
    assert (v["CVaR historique"] >= v["VaR historique"] - 1e-12).all()
    ten = v[v["Horizon"] == "10 j"].set_index("Confiance")
    assert ten.loc["99%", "VaR normale"] > one.loc["99%", "VaR normale"]


def test_risk_contributions_sum_to_one_and_optimizer_limits():
    rets = risk.returns(_prices())
    cov = risk.ledoit_wolf(rets)
    assert np.all(np.linalg.eigvalsh(cov.values) > 0)
    w = risk.normalize_weights({"A0": 0.4, "A1": 0.3, "A2": 0.1, "A3": 0.1, "A4": 0.1})
    rc = risk.risk_contributions(cov, w)
    assert abs(rc["Contribution au risque"].sum() - 1) < 1e-9
    for m in ("risk_parity", "min_variance", "max_sharpe"):
        x = risk.optimize_weights(cov, m, 0.30, risk.shrunk_expected_returns(rets))
        assert abs(x.sum() - 1) < 1e-6 and x.max() <= 0.30 + 1e-6 and x.min() >= -1e-9
    rp = risk.optimize_weights(cov, "risk_parity", 1.0)
    rc_rp = risk.risk_contributions(cov, rp)["Contribution au risque"]
    assert rc_rp.max() - rc_rp.min() < 0.02


def test_stress_hypothetical_linear():
    w = pd.Series({"X": 0.5, "Y": 0.5})
    out = risk.stress_hypothetical(w, pd.Series({"X": 1.0, "Y": 2.0}), pd.Series({"X": 0.0, "Y": -0.05}), 100)
    row = out.set_index("Scénario").loc["Récession sévère / krach"]
    # X : −35 % ; Y : 2 × −35 % + (−5 %) × (−1,5) = −62,5 %
    assert abs(row["Impact portefeuille"] - (0.5 * -0.35 + 0.5 * -0.625)) < 1e-12


def test_liquidity_and_limits():
    w = pd.Series({"X": 0.6, "Y": 0.4})
    liq = risk.liquidity(w, 1e6, {"X": 1e9, "Y": 1e5}, 0.2)
    assert liq.loc["X", "Note liquidité /10"] == 10 and liq.loc["Y", "Jours pour liquider"] == 20
    checks = risk.check_limits(w, pd.Series({"Tech": 1.0}), pd.Series({"US": 1.0}), 0.02, -0.2, 0.5, 20)
    assert not checks[0].ok and checks[3].ok and not checks[-1].ok


def test_tail_probabilities_monotonic():
    rets = risk.returns(_prices())
    port = risk.portfolio_series(rets, risk.normalize_weights({c: 1 for c in rets.columns}))
    t = risk.tail_probabilities(port, n_paths=3000).set_index("Événement sur 12 mois")["Probabilité"]
    assert t.iloc[0] >= t.iloc[1] >= t.iloc[2] >= t.iloc[3]
