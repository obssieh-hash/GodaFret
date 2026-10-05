import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from godafret import services, ui
from godafret.universes import SECTORS_FR, UNIVERSES

ui.setup("01 · Sélection d'actions", "Méthode « analyste actions senior Goldman Sachs » — screening multi-facteurs")

with st.form("profil"):
    st.subheader("Ton profil d'investisseur")
    c1, c2, c3 = st.columns(3)
    tol = c1.selectbox("Tolérance au risque", ["prudente", "modérée", "dynamique", "agressive"], index=1)
    amount = c2.number_input("Montant investi", min_value=1_000.0, value=100_000.0, step=1_000.0)
    horizon = c3.slider("Horizon (années)", 1, 30, 10)
    c4, c5 = st.columns(2)
    uni = c4.multiselect("Univers à analyser", list(UNIVERSES), default=["Grandes capitalisations US (~100)"])
    custom = c5.text_input("Tickers en plus (séparés par des virgules)", placeholder="ex. MC.PA, ASML.AS, TSM")
    sectors = st.multiselect("Secteurs préférés (vide = tous)", [k for k in SECTORS_FR if k not in ("ETF", "Inconnu")],
                             format_func=lambda s: SECTORS_FR[s])
    go_btn = st.form_submit_button("Lancer le screening", type="primary")

if go_btn:
    tickers = [t for u in uni for t in UNIVERSES[u]] + [t.strip().upper() for t in custom.split(",") if t.strip()]
    if not tickers:
        st.warning("Choisis au moins un univers ou un ticker.")
        st.stop()
    bar = st.progress(0.0, "Récupération des données…")
    df = ui.run_safely(services.screen, tickers, tol, sectors or None,
                       lambda p, t: bar.progress(p, f"Analyse de {t}…"))
    bar.empty()
    if df is not None:
        st.session_state["screen"] = (df, tol, amount, horizon)

if "screen" in st.session_state:
    df, tol, amount, horizon = st.session_state["screen"]
    elig = df[df["Éligible"]]
    top = elig.head(10)
    if horizon < 3:
        st.warning("Horizon < 3 ans : les actions sont risquées sur une période aussi courte. Garde la majorité en "
                   "placements sans risque et n'investis ici qu'une petite partie.")
    st.success(f"{len(df)} actions analysées · {len(elig)} compatibles avec un profil {tol} · top 10 ci-dessous")

    st.header("Tableau de synthèse")
    cols = ["Nom", "Secteur", "Cours", "PER", "PER médian secteur", "PER vs secteur", "CA CAGR", "Dette/Capitaux propres",
            "Rendement", "Sécurité dividende /10", "Avantage concurrentiel", "Objectif 12 m baissier",
            "Objectif 12 m haussier", "Note de risque /10", "Zone d'entrée", "Stop-loss", "Score global"]
    view = top[cols].copy()
    view["Secteur"] = view["Secteur"].map(lambda s: SECTORS_FR.get(s, s))
    ui.table(view, pcts=["PER vs secteur", "CA CAGR", "Rendement"],
             nums=["Cours", "PER", "PER médian secteur", "Dette/Capitaux propres", "Sécurité dividende /10",
                   "Objectif 12 m baissier", "Objectif 12 m haussier", "Note de risque /10", "Stop-loss", "Score global"])
    st.caption("PER médian secteur = médiane des sociétés du même secteur dans l'univers analysé. CA CAGR = croissance "
               "annuelle moyenne du chiffre d'affaires sur 5 ans (SEC EDGAR pour les US, sinon 4 ans Yahoo). "
               "Objectifs 12 mois = 20e / 80e centile autour de l'objectif moyen des analystes, avec la volatilité "
               "réelle du titre. Stop-loss = sous le support le plus proche (ou 2 ATR).")

    st.header("Répartition proposée du capital")
    from godafret.analytics.screener import allocate

    alloc = allocate(top, amount)
    ui.table(alloc[["Nom", "Cours", "Volatilité", "Poids", "Montant", "Nb d'actions", "Stop-loss"]],
             pcts=["Volatilité", "Poids"], nums=["Cours", "Stop-loss"], money_cols=["Montant", "Nb d'actions"])
    st.caption("Pondération inverse à la volatilité (chaque ligne apporte un risque comparable), plafonnée à 15 %.")

    st.header("Fiches détaillées")
    for t, r in top.iterrows():
        with st.expander(f"{t} — {r['Nom']} · risque {r['Note de risque /10']}/10 · moat {r['Avantage concurrentiel']}"):
            c1, c2, c3, c4 = st.columns(4)
            c1.metric("Cours", ui.num(r["Cours"]))
            c2.metric("PER / médiane secteur", f"{ui.num(r['PER'], 1)} / {ui.num(r['PER médian secteur'], 1)}",
                      ui.pct(r["PER vs secteur"]), delta_color="inverse")
            c3.metric("Rendement du dividende", ui.pct(r["Rendement"]),
                      f"sécurité {ui.num(r['Sécurité dividende /10'], 1)}/10")
            c4.metric("Objectifs 12 mois", f"{ui.num(r['Objectif 12 m baissier'])} → {ui.num(r['Objectif 12 m haussier'])}")
            hist = r["CA historique"] if isinstance(r["CA historique"], dict) else {}
            if hist:
                fig = go.Figure(go.Bar(x=[str(k) for k in hist], y=list(hist.values()), marker_color=ui.COLORS["accent"]))
                fig.update_layout(title=f"Chiffre d'affaires ({r['Source CA']})", height=280, margin=dict(t=40, b=10))
                st.plotly_chart(fig, width="stretch", key=f"rev_{t}")
            st.markdown(f"**Note de risque {r['Note de risque /10']}/10** — {r['Justification risque']}")
            st.markdown(f"**Avantage concurrentiel : {r['Avantage concurrentiel']}** ({r['Note moat /10']}/10) — "
                        f"{r['Pourquoi (moat)'] or 'pas de signal quantitatif fort'}")
            zone = r["Zone d'entrée"]
            st.markdown(f"**Plan d'entrée** : zone {zone}, stop-loss {ui.num(r['Stop-loss'])}, objectif "
                        f"technique {ui.num(r['Objectif technique'])} (rendement/risque {ui.num(r['R/R'])}). "
                        f"Analystes : {r['Analystes (bas/haut)']} ({r['Nb analystes']} avis).")

    with st.expander("Toutes les actions analysées (y compris non éligibles)"):
        ui.table(df[["Nom", "Secteur", "Score global", "Note de risque /10", "Éligible", "PER", "CA CAGR", "Rendement"]],
                 pcts=["CA CAGR", "Rendement"], nums=["Score global", "Note de risque /10", "PER"])

    md = "# Rapport de sélection d'actions\n\n" + f"Profil : {tol}, {amount:,.0f}, horizon {horizon} ans\n\n" + ui.df_to_md(
        view, pcts=["PER vs secteur", "CA CAGR", "Rendement"],
        nums=["Cours", "PER", "PER médian secteur", "Dette/Capitaux propres", "Objectif 12 m baissier",
              "Objectif 12 m haussier", "Stop-loss", "Score global"])
    ui.download_md("Télécharger le rapport (Markdown)", md, "selection_actions.md")
ui.footer()
