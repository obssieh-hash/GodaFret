import plotly.graph_objects as go
import streamlit as st

from godafret import services, ui
from godafret.analytics import advisor

ui.setup("Mon conseiller", "Réponds à quelques questions : l'outil te dit quoi faire, dans quel ordre, combien et où.")

with st.form("situation"):
    st.subheader("1. Ta situation")
    c1, c2, c3, c4 = st.columns(4)
    age = c1.number_input("Ton âge", 18, 100, 30)
    income = c2.number_input("Revenus nets par mois (€)", 0.0, 1e7, 2_500.0, 100.0)
    expenses = c3.number_input("Dépenses par mois (€)", 0.0, 1e7, 1_800.0, 100.0)
    savings = c4.number_input("Épargne totale disponible (€)", 0.0, 1e10, 20_000.0, 1_000.0)
    c5, c6, c7, c8 = st.columns(4)
    debt = c5.number_input("Crédits conso / revolving restants (€)", 0.0, 1e8, 0.0, 500.0)
    project = c6.number_input("Argent nécessaire dans moins de 3 ans (€)", 0.0, 1e9, 0.0, 500.0)
    horizon = c7.slider("Dans combien d'années auras-tu besoin du reste ?", 1, 40, 15)
    tmi = c8.selectbox("Tranche d'imposition", ["0 %", "11 %", "30 %", "41 %", "45 %"], index=1)
    st.subheader("2. Ton comportement face au risque")
    reaction = st.radio("Ton placement perd 20 % en 3 mois. Que fais-tu vraiment ?", list(advisor.REACTION_SCORE), index=2)
    experience = st.radio("Ton expérience de l'investissement", list(advisor.EXPERIENCE_SCORE), index=1)
    c9, c10 = st.columns(2)
    pea_already = c9.number_input("Déjà versé sur un PEA (€)", 0.0, 150_000.0, 0.0, 1_000.0)
    goal = c10.text_input("Ton objectif", "Faire grossir mon patrimoine")
    ok = st.form_submit_button("Me dire quoi faire", type="primary")

if ok:
    s = advisor.Situation(age=age, monthly_income=income, monthly_expenses=expenses, savings=savings,
                          expensive_debt=debt, short_term_project=project, horizon=horizon, reaction=reaction,
                          experience=experience, tmi=float(tmi.split()[0]) / 100, pea_already=pea_already, goal=goal)
    with st.spinner("Analyse de ta situation et du marché…"):
        out = ui.run_safely(services.advisor_plan, s)
    if out:
        st.session_state["advice"] = (s, *out)

if "advice" not in st.session_state:
    ui.footer()
    st.stop()

s, plan, signal = st.session_state["advice"]
ui.verdict_badge(f"Ton profil : {plan.tolerance.upper()} — {ui.money(plan.investable)} à investir + "
                 f"{ui.money(plan.monthly_invest)} par mois", True)
st.caption(plan.tolerance_why + (f" Marché aujourd'hui : {signal}." if signal else ""))

st.header("Ton plan d'action, dans l'ordre")
for stp in plan.steps:
    with st.container(border=True):
        a, b = st.columns([3, 1])
        a.markdown(f"### {stp['Étape']}. {stp['Quoi']}")
        b.metric("Montant", ui.money(stp["Montant"]))
        st.markdown(f"**À faire :** {stp['Action']}")
        st.markdown(f"**Où :** {stp['Où']}")
        st.caption(f"Pourquoi : {stp['Pourquoi']}")

if plan.investable > 0:
    st.header("Où va chaque euro investi")
    pl = plan.placements
    c1, c2 = st.columns(2)
    c1.plotly_chart(ui.pie(pl.groupby("Enveloppe")["Montant"].sum(), "Par enveloppe"), width="stretch")
    c2.plotly_chart(ui.pie(pl.groupby("Poche")["Montant"].sum(), "Par type de placement"), width="stretch")
    ui.table(pl, pcts=["Poids"], money_cols=["Montant"], hide_index=True)
    e = plan.expected
    m1, m2, m3 = st.columns(3)
    m1.metric("Rendement moyen attendu", ui.pct(e["rendement attendu"]) + " /an")
    m2.metric("Mauvaise année (1 sur 20)", ui.pct(e["mauvaise année (1 sur 20)"]),
              ui.money(e["mauvaise année (1 sur 20)"] * plan.investable), delta_color="off")
    m3.metric(f"Valeur médiane dans {s.horizon} ans",
              ui.money(plan.investable * (1 + e["rendement attendu"]) ** s.horizon +
                       plan.monthly_invest * 12 * (((1 + e["rendement attendu"]) ** s.horizon - 1) / e["rendement attendu"])
                       if e["rendement attendu"] else 0))
    st.caption("La « mauvaise année » arrivera : c'est le prix du rendement. Si tu ne supportes pas de voir ce montant "
               "en moins, choisis une réponse plus prudente à la question du comportement.")

if not plan.monthly.empty:
    st.header("Ton investissement automatique chaque mois")
    ui.table(plan.monthly[["Enveloppe", "Ticker", "Support", "Par mois"]], money_cols=["Par mois"], hide_index=True)

st.header("Les règles du gestionnaire de risque")
for r in plan.rules:
    st.markdown(f"- {r}")

st.info("Pour aller plus loin : **05 · Construction de portefeuille** (détail et historique), **03 · Gestion du risque** "
        "(si tu as déjà des placements), **01 · Sélection d'actions** (pour la petite part « paris » ≤ 10 %).")

md = "# Mon plan d'investissement\n\n" + f"Profil : {plan.tolerance}\n\n" + "\n".join(
    f"{x['Étape']}. **{x['Quoi']}** — {x['Action']} ({x['Montant']:,.0f} €, {x['Où']})" for x in plan.steps)
if plan.investable > 0:
    md += "\n\n## Placements\n" + ui.df_to_md(plan.placements, pcts=["Poids"], nums=["Montant"], index=False)
md += "\n\n## Règles\n" + "\n".join(f"- {r}" for r in plan.rules)
ui.download_md("Télécharger mon plan (Markdown)", md, "mon_plan.md")
ui.footer()
