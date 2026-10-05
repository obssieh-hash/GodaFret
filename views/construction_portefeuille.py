import plotly.graph_objects as go
import streamlit as st

from godafret import services, ui
from godafret.analytics import allocation

ui.setup("05 · Construction de portefeuille", "Méthode « stratégiste portefeuille BlackRock » — politique d'investissement")

with st.form("situation"):
    c1, c2, c3, c4 = st.columns(4)
    age = c1.number_input("Âge", 18, 100, 35)
    income = c2.number_input("Revenus annuels nets (€)", 0.0, 1e8, 45_000.0, 1_000.0)
    savings = c3.number_input("Épargne à investir (€)", 0.0, 1e10, 30_000.0, 1_000.0)
    monthly = c4.number_input("Versement mensuel (€)", 0.0, 1e7, 500.0, 50.0)
    c5, c6, c7, c8 = st.columns(4)
    horizon = c5.slider("Horizon (années)", 1, 40, 15)
    tol = c6.selectbox("Tolérance au risque", list(allocation.TOLERANCE_EQUITY), index=1)
    account = c7.selectbox("Type de compte", ["PEA", "Assurance-vie", "CTO", "PER"])
    expenses = c8.number_input("Dépenses mensuelles (€)", 0.0, 1e6, 2_000.0, 100.0)
    goal = st.text_input("Objectif", "Préparer la retraite et faire croître mon patrimoine")
    ok = st.form_submit_button("Construire mon portefeuille", type="primary")

if ok:
    p = allocation.Profile(age=age, income=income, savings=savings, monthly=monthly, horizon=horizon, tolerance=tol,
                           account=account, goal=goal, monthly_expenses=expenses)
    with st.spinner("Allocation, historique et projections…"):
        rep = ui.run_safely(services.allocation_report, p)
    if rep:
        st.session_state["alloc"] = (p, rep)

if "alloc" not in st.session_state:
    ui.footer()
    st.stop()

p, rep = st.session_state["alloc"]
t = rep["table"]
fwd, hist = rep["forward"], rep["hist"]

st.header("1. Allocation d'actifs")
a, b = st.columns([1, 1])
by_class = t.groupby("Classe")["Poids"].sum().sort_values(ascending=False)
a.plotly_chart(ui.pie(by_class, "Par classe d'actifs"), width="stretch")
b.plotly_chart(ui.pie(t.set_index("Poche")["Poids"], "Par poche"), width="stretch")
for w in rep["why"]:
    st.markdown(f"- {w}")
st.markdown("*Graphique d'allocation : anneau extérieur = poches cœur (stables, peu chères, détenues en permanence) et "
            "satellites (convictions, plafonnées) ; la part actions détermine 90 % du risque.*")

st.header("2-3. ETF recommandés — cœur et satellites")
view = t.drop(columns=["key"]).copy()
view["Montant initial"] = view["Poids"] * p.savings
view["Versement mensuel"] = view["Poids"] * p.monthly
ui.table(view.set_index("Poche"), pcts=["Poids", "Frais"], money_cols=["Montant initial", "Versement mensuel"])
st.caption("Vérifie la disponibilité de chaque ETF chez ton courtier / assureur ; un équivalent (même indice, frais "
           "proches) convient parfaitement.")
if p.savings < 6 * p.monthly_expenses:
    st.warning(f"Ton épargne ({ui.money(p.savings)}) est inférieure à 6 mois de dépenses "
               f"({ui.money(6 * p.monthly_expenses)}) : constitue d'abord ton épargne de précaution (Livret A, LDDS).")

st.header("4-5. Rendement attendu et perte maximale")
m1, m2, m3, m4 = st.columns(4)
m1.metric("Rendement annuel attendu", ui.pct(fwd["rendement attendu"]))
m2.metric("Fourchette 80 % (1 an)", f"{ui.pct(fwd['fourchette 80 % basse'], 0)} / {ui.pct(fwd['fourchette 80 % haute'], 0)}")
m3.metric("Mauvaise année (1 sur 20)", ui.pct(fwd["mauvaise année (1 sur 20)"]),
          ui.money(fwd["mauvaise année (1 sur 20)"] * p.savings), delta_color="off")
m4.metric("Volatilité", ui.pct(fwd["volatilité"]))
if hist:
    h1, h2, h3, h4 = st.columns(4)
    h1.metric(f"Historique {hist['période']}", ui.pct(hist["rendement annualisé"]) + " /an")
    h2.metric("Pire année civile", ui.pct(hist["pire année civile"]), str(hist["année de la pire perte"]), delta_color="off")
    h3.metric("Pire période de 12 mois", ui.pct(hist["pire période de 12 mois"]))
    h4.metric("Baisse maximale", ui.pct(hist["baisse maximale"]))
    fig = go.Figure(go.Scatter(x=hist["série"].index, y=hist["série"].values * 100, fill="tozeroy"))
    fig.update_layout(height=320, title="Backtest (base 100, proxys en USD, rééquilibrage mensuel)", margin=dict(t=40, b=10))
    st.plotly_chart(fig, width="stretch")
st.caption("Rendement attendu : hypothèses prospectives prudentes à 10 ans par classe d'actifs (dans l'esprit des "
           "Capital Market Assumptions publiées par BlackRock, Vanguard, JPMorgan), nettes de ~0,25 % de frais. "
           "Historique : ETF américains à long historique servant de proxys.")

st.header("6. Rééquilibrage")
for r in rep["rebalancing"]:
    st.markdown(f"- {r}")

st.header(f"7. Optimisation fiscale — {p.account}")
for r in rep["tax"]:
    st.markdown(f"- {r}")

st.header("8. Plan d'investissement mensuel")
dca = rep["dca"]
fig = go.Figure()
fig.add_trace(go.Scatter(x=dca.index, y=dca["Optimiste (90 %)"], name="Optimiste (90 %)", line=dict(width=0)))
fig.add_trace(go.Scatter(x=dca.index, y=dca["Pessimiste (10 %)"], name="Pessimiste (10 %)", fill="tonexty", line=dict(width=0)))
fig.add_trace(go.Scatter(x=dca.index, y=dca["Médian"], name="Médian", line=dict(width=3)))
fig.add_trace(go.Scatter(x=dca.index, y=dca["Versé"], name="Total versé", line=dict(dash="dash")))
fig.update_layout(height=380, xaxis_title="Années", margin=dict(t=20, b=10))
st.plotly_chart(fig, width="stretch")
ui.table(dca, money_cols=list(dca.columns))

st.header("9. Indice de référence")
st.markdown(rep["benchmark"])

st.header("10. Ta politique d'investissement (1 page)")
st.markdown(rep["ips"])
ui.download_md("Télécharger la politique d'investissement (Markdown)", rep["ips"], "politique_investissement.md")
ui.footer()
