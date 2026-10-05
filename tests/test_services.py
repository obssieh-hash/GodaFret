"""Pipeline complet de chaque module avec des données synthétiques (aucun appel réseau)."""
import pandas as pd

from godafret import services
from godafret.analytics import allocation, dcf


def test_screen(fake_market):
    df = services.screen(["AAA", "BBB", "CCC", "DDD", "EEE", "FFF"], "modérée")
    assert len(df) == 6
    assert {"PER vs secteur", "Note de risque /10", "Zone d'entrée", "Objectif 12 m haussier"} <= set(df.columns)
    assert (df["Objectif 12 m baissier"] < df["Objectif 12 m haussier"]).all()
    assert df["Source CA"].iloc[0] == "SEC EDGAR (10-K)" and df["Années de CA"].iloc[0] == 5


def test_dcf_service(fake_market):
    inp, f, info, st, src = services.dcf_inputs("AAA", 0.05, 0.025)
    res = dcf.run(inp)
    assert res.value_blended > 0 and res.verdict
    assert dcf.key_risks(inp, res, f)


def test_risk_service(fake_market):
    rep = services.risk_report({"AAA": 0.3, "BBB": 0.3, "CCC": 0.2, "DDD": 0.2}, 2_000_000)
    assert abs(rep["weights"].sum() - 1) < 1e-9
    assert not rep["var"].empty and not rep["hyp_stress"].empty and not rep["hist_stress"].empty
    assert len(rep["top3"]) == 3 and rep["hedges"]
    assert set(rep["compare"].index) == {"Actuel", "risk_parity", "min_variance", "max_sharpe"}
    assert rep["checks"][0].ok is False  # 30 % > limite de 10 %
    assert rep["fx_failed"] == []  # actifs en USD convertis en EUR


def test_earnings_service(fake_market):
    rep = services.earnings_report("AAA")
    assert rep["stats"]["quarters"] == 8 and rep["stats"]["beat_rate"] == 1.0
    assert rep["implied"]["move"] > 0
    assert rep["recommendation"] in ("ACHETER AVANT", "VENDRE / ALLÉGER AVANT", "ATTENDRE LA PUBLICATION")


def test_allocation_service(fake_market):
    p = allocation.Profile(40, 60_000, 50_000, 800, 20, "dynamique", "CTO", "retraite")
    rep = services.allocation_report(p)
    assert rep["hist"]["rendement annualisé"] == rep["hist"]["rendement annualisé"]
    assert "Politique d'investissement" in rep["ips"]


def test_technical_and_dividends_service(fake_market):
    rep, src = services.technical_report("AAA", 100.0)
    assert rep.rating
    df = services.dividend_universe(["AAA", "BBB", "TTE.PA", "NESN.SW"], "PEA")
    assert list(df.index) == ["TTE.PA"]
    df2 = services.dividend_universe(["AAA", "BBB", "TTE.PA", "NESN.SW"], "CTO")
    assert len(df2) == 4 and (df2["Années de hausse"] >= 10).all()
