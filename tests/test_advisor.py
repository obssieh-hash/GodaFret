from godafret.analytics import advisor


def _s(**kw):
    d = dict(age=30, monthly_income=3000, monthly_expenses=2000, savings=50_000)
    d.update(kw)
    return advisor.Situation(**d)


def test_order_debt_then_reserve_then_invest():
    p = advisor.build_plan(_s(expensive_debt=5_000), above_ma200=True, vix=15)
    titles = [x["Quoi"] for x in p.steps]
    assert titles[0] == "Rembourser les crédits chers" and titles[1] == "Épargne de précaution"
    assert abs(p.investable - (50_000 - 5_000 - 12_000)) < 1e-6
    assert abs(p.placements["Montant"].sum() - p.investable) < 1e-6
    assert abs(p.placements["Poids"].sum() - 1) < 1e-9


def test_pea_cap_overflow_goes_to_cto():
    p = advisor.build_plan(_s(savings=1_000_000, pea_already=140_000), True, 15)
    assert p.placements.loc[p.placements["Enveloppe"] == "PEA", "Montant"].sum() <= 10_000 + 1e-6
    assert (p.placements["Enveloppe"] == "CTO").any()


def test_small_savings_builds_reserve_first():
    p = advisor.build_plan(_s(savings=3_000), None, None)
    assert p.investable == 0 and p.placements["Montant"].sum() == 0
    assert not p.monthly.empty  # les versements mensuels gardent la répartition cible
    assert any(x["Quoi"] == "Compléter la précaution" for x in p.steps)


def test_panic_seller_is_capped():
    tol, _ = advisor.risk_profile(_s(reaction="Je vends tout pour arrêter les pertes",
                                     experience="Expérimenté (plusieurs krachs vécus)", horizon=30))
    assert tol in ("prudente", "modérée")
    tol2, _ = advisor.risk_profile(_s(reaction="J'en profite pour acheter plus",
                                      experience="Expérimenté (plusieurs krachs vécus)", horizon=30))
    assert tol2 == "agressive"


def test_timing_more_gradual_in_stress():
    assert advisor.market_timing(False, 35)[0] < advisor.market_timing(True, 14)[0]


def test_small_amounts_are_consolidated():
    small = advisor.build_plan(_s(savings=15_000, monthly_income=2000, monthly_expenses=1800), True, 15)
    big = advisor.build_plan(_s(savings=500_000), True, 15)
    assert len(small.placements) < len(big.placements)
    assert abs(small.placements["Poids"].sum() - 1) < 1e-9
