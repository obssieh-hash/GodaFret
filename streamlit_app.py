"""GodaFret — desk d'investissement.  Lancer : streamlit run streamlit_app.py"""
import streamlit as st

st.set_page_config(page_title="GodaFret", page_icon="📈", layout="wide")

PAGES = [
    st.Page("views/accueil.py", title="Accueil", icon="🏦", default=True),
    st.Page("views/selection_actions.py", title="01 · Sélection d'actions", icon="🎯"),
    st.Page("views/valorisation_dcf.py", title="02 · Valorisation DCF", icon="🧮"),
    st.Page("views/gestion_du_risque.py", title="03 · Gestion du risque", icon="🛡️"),
    st.Page("views/resultats_trimestriels.py", title="04 · Résultats trimestriels", icon="📊"),
    st.Page("views/construction_portefeuille.py", title="05 · Construction de portefeuille", icon="🧱"),
    st.Page("views/analyse_technique.py", title="06 · Analyse technique", icon="📈"),
    st.Page("views/strategie_dividendes.py", title="07 · Stratégie dividendes", icon="💶"),
]
st.navigation(PAGES).run()
