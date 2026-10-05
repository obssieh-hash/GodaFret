import math

from godafret.analytics import dcf


def base_inputs(**kw):
    d = dict(base_revenue=100.0, growth_start=0.0, growth_end=0.0, margin_start=0.2, margin_end=0.2, tax_rate=0.25,
             da_pct=0.05, capex_pct=0.05, nwc_pct=0.0, risk_free=0.04, beta=1.0, equity_risk_premium=0.05,
             cost_of_debt=0.05, market_cap=1000.0, total_debt=0.0, net_debt=0.0, shares=10.0, price=10.0,
             terminal_growth=0.0, exit_multiple=8.0, mid_year=False)
    d.update(kw)
    return dcf.DCFInputs(**d)


def test_zero_growth_dcf_equals_perpetuity():
    inp = base_inputs()
    assert abs(inp.wacc - 0.09) < 1e-12
    res = dcf.run(inp)
    # FCFF = 100 × 20 % × (1 − 25 %) = 15 par an à perpétuité → VE = 15 / 9 %
    assert abs(res.ev_gordon - 15 / 0.09) < 1e-6
    assert abs(res.value_gordon - 15 / 0.09 / 10) < 1e-6


def test_exit_multiple_and_verdict():
    inp = base_inputs(price=100.0)
    res = dcf.run(inp)
    assert res.verdict == "SURÉVALUÉE"
    ebitda = 100 * 0.25
    pv = sum(15 / 1.09 ** t for t in range(1, 6))
    assert abs(res.ev_exit - (pv + ebitda * 8 / 1.09 ** 5)) < 1e-6


def test_sensitivity_monotonic_in_wacc():
    inp = base_inputs(terminal_growth=0.02, growth_start=0.05, growth_end=0.03)
    s = dcf.sensitivity(inp)
    col = s.iloc[:, 2].values
    assert all(col[i] > col[i + 1] for i in range(len(col) - 1))
    sc = dcf.scenarios(inp)
    assert sc.loc["Baissier", "Valeur retenue"] < sc.loc["Central", "Valeur retenue"] < sc.loc["Haussier", "Valeur retenue"]


def test_implied_growth_roundtrip():
    inp = base_inputs(terminal_growth=0.02)
    res = dcf.run(inp)
    # si le multiple de sortie = multiple implicite de Gordon, la croissance implicite = g
    res2 = dcf.run(inp, exit_multiple=res.implied_multiple_gordon)
    assert math.isclose(res2.implied_growth_exit, 0.02, abs_tol=1e-9)
