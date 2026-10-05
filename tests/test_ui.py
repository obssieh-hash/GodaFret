"""Exécute chaque page Streamlit de bout en bout (données synthétiques)."""
from pathlib import Path

import pytest
from streamlit.testing.v1 import AppTest

ROOT = Path(__file__).resolve().parent.parent

PAGES = {
    "views/accueil.py": None,
    "views/selection_actions.py": "custom",
    "views/valorisation_dcf.py": "button",
    "views/gestion_du_risque.py": "button",
    "views/resultats_trimestriels.py": "button",
    "views/construction_portefeuille.py": "button",
    "views/analyse_technique.py": "button",
    "views/strategie_dividendes.py": "button",
}


@pytest.mark.parametrize("page", list(PAGES))
def test_page_runs(page, fake_market):
    at = AppTest.from_file(str(ROOT / "streamlit_app.py"), default_timeout=120)
    at.run()
    assert not at.exception, at.exception
    at.switch_page(page)
    at.run()
    assert not at.exception, at.exception
    action = PAGES[page]
    if action == "custom":
        at.multiselect[0].set_value([])
        at.text_input[0].set_value("AAA, BBB, CCC, DDD, EEE, FFF, GGG, HHH, III, JJJ, KKK, LLL")
        at.button[0].click()
    elif action == "button":
        at.button[0].click()
    if action:
        at.run()
        assert not at.exception, at.exception
        assert not at.error, [e.value for e in at.error]
