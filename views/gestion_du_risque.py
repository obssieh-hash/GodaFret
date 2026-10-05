from dataclasses import replace

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from godafret import services, ui
from godafret.config import LIMITS
from godafret.universes import BENCHMARKS, SECTORS_FR

ui.setup("03 · Gestion du risque", "Méthode « analyste risque senior Bridgewater » — rapport de comité des risques")

st.subheader("Ton portefeuille actuel")
default = pd.DataFrame({"Ticker": ["AAPL", "MSFT", "NVDA", "MC.PA", "TTE.PA", "JPM", "IWDA.AS", "GLD"],
                        "Poids %": [15.0, 15.0, 10.0, 15.0, 10.0, 10.0, 20.0, 5.0]})
pos = st.data_editor(st.session_state.get("risk_pos", default), num_rows="dynamic", width="stretch",
                     column_config={"Poids %": st.column_config.NumberColumn(min_value=0.0, max_value=100.0, step=0.5)})
c1, c2, c3 = st.columns(3)
value = c1.number_input("Valeur totale du portefeuille", 1_000.0, 1e10, 1_000_000.0, 10_000.0)
base_ccy = c2.selectbox("Devise de référence", ["EUR", "USD", "CHF", "GBP"])
bench = BENCHMARKS[c3.selectbox("Indice de référence", list(BENCHMARKS))]
with st.expander("Limites de risque (comité)"):
    l1, l2, l3, l4 = st.columns(4)
    limits = replace(LIMITS,
                     max_single_position=l1.number_input("Max par ligne (%)", 1.0, 100.0, LIMITS.max_single_position * 100) / 100,
                     max_sector=l2.number_input("Max par secteur (%)", 5.0, 100.0, LIMITS.max_sector * 100) / 100,
                     max_var_99_1d=l3.number_input("VaR 99 % 1 j max (%)", 0.5, 20.0, LIMITS.max_var_99_1d * 100) / 100,
                     max_drawdown_stress=l4.number_input("Perte stress max (%)", 5.0, 90.0, LIMITS.max_drawdown_stress * 100) / 100)

if st.button("Lancer l'analyse de risque", type="primary"):
    p = pos.dropna()
    p = p[p["Poids %"] > 0]
    holdings = dict(zip(p["Ticker"].str.strip().str.upper(), p["Poids %"]))
    if len(holdings) < 2:
        st.warning("Il faut au moins 2 lignes.")
        st.stop()
    st.session_state["risk_pos"] = pos
    with st.spinner("Calcul des corrélations, stress tests et VaR…"):
        rep = ui.run_safely(services.risk_report, holdings, value, bench, base_ccy, limits)
    if rep:
        st.session_state["risk"] = (rep, value, base_ccy, limits)

if "risk" not in st.session_state:
    ui.footer()
    st.stop()

rep, value, base_ccy, limits = st.session_state["risk"]
w = rep["weights"]
cur = base_ccy
if rep.get("fx_failed"):
    st.warning("Taux de change indisponibles pour " + ", ".join(rep["fx_failed"]) + " : risque calculé en devise locale.")
else:
    st.caption(f"Tous les calculs sont faits en {cur} (cours convertis avec les taux BCE) : le risque de change est inclus.")

# ------------------------------------------------------------ synthèse comité
st.header("Synthèse du comité des risques")
breaches = [c for c in rep["checks"] if not c.ok]
ui.verdict_badge(f"{len(breaches)} limite(s) dépassée(s) sur {len(rep['checks'])}" if breaches else
                 "Toutes les limites sont respectées", not breaches)
var1 = rep["var"].set_index(["Horizon", "Confiance"])
k1, k2, k3, k4 = st.columns(4)
k1.metric("VaR 99 % 1 jour", ui.pct(var1.loc[("1 j", "99%"), "VaR historique"], 2),
          ui.money(var1.loc[("1 j", "99%"), "VaR historique"] * value, cur), delta_color="off")
k2.metric("Bêta du portefeuille", ui.num(rep["beta_port"]))
worst = rep["hyp_stress"]["Impact portefeuille"].min()
k3.metric("Pire scénario de stress", ui.pct(worst), ui.money(worst * value, cur), delta_color="off")
k4.metric("Nombre effectif de lignes", ui.num(1 / (w ** 2).sum(), 1), f"sur {len(w)}", delta_color="off")
ui.table(pd.DataFrame([{"Règle": c.rule, "Valeur": c.value, "Limite": c.limit, "Statut": "✅ OK" if c.ok else "🚨 DÉPASSEMENT"}
                       for c in rep["checks"]]), hide_index=True)

st.subheader("Carte de chaleur des risques par ligne (1 = faible, 10 = élevé)")
st.plotly_chart(ui.heatmap(rep["heat"], "", 1, 10, "RdYlGn_r", ".1f"), width="stretch")

# ------------------------------------------------------------ 1. corrélations
st.header("1. Corrélation entre les positions")
corr = rep["corr"]
st.plotly_chart(ui.heatmap(corr["matrix"], "Corrélation des rendements quotidiens (5 ans)", -1, 1, "RdBu_r", ".2f"),
                width="stretch")
st.markdown(f"Corrélation moyenne pondérée : **{corr['weighted_avg']:.2f}**. " + (
    "Paires très corrélées (> 0,75) : " + ", ".join(f"{a}/{b} ({c:.2f})" for a, b, c in corr["high_pairs"][:6])
    if corr["high_pairs"] else "Aucune paire au-dessus de 0,75 : bonne diversification."))

# ------------------------------------------------------------ 2-3. concentration
st.header("2. Concentration sectorielle · 3. Exposition géographique et devises")
a, b, c = st.columns(3)
a.plotly_chart(ui.pie(rep["sectors"].rename(index=lambda s: SECTORS_FR.get(s, s)), "Secteurs"), width="stretch")
b.plotly_chart(ui.pie(rep["countries"], "Pays du siège"), width="stretch")
c.plotly_chart(ui.pie(rep["currencies"], "Devises de cotation"), width="stretch")
st.markdown(f"**{ui.pct(rep['foreign_share'], 0)}** du portefeuille est exposé à une autre devise que l'{cur}. "
            "Une baisse de 10 % de ces devises contre l'euro coûterait environ "
            f"**{ui.money(rep['foreign_share'] * 0.10 * value, cur)}**.")

# ------------------------------------------------------------ 4. taux
st.header("4. Sensibilité aux taux d'intérêt")
rb = rep["rate_beta"]
if rb.empty:
    st.info("Série de taux FRED indisponible.")
else:
    st.plotly_chart(ui.bar(rb.sort_values(), "Variation de prix estimée pour +1 point sur le 10 ans US", True),
                    width="stretch")
    st.markdown(f"Portefeuille : **{ui.pct(rep['rate_port'])}** pour +100 pb "
                f"(≈ {ui.money(rep['rate_port'] * value, cur)}). Régression hebdomadaire sur 5 ans.")

# ------------------------------------------------------------ 5. stress tests
st.header("5. Stress tests — récession et crises historiques")
ui.table(rep["hyp_stress"].set_index("Scénario"), pcts=["Probabilité annuelle (indicative)", "Impact portefeuille"],
         money_cols=["Perte estimée"])
if not rep["hist_stress"].empty:
    ui.table(rep["hist_stress"].set_index("Scénario"), pcts=["Indice de référence", "Portefeuille"])
    st.caption("Performance réelle de tes lignes pendant chaque crise ; une ligne sans historique est approximée par "
               "bêta × indice.")

# ------------------------------------------------------------ VaR et extrêmes
st.header("Valeur à risque et scénarios extrêmes")
ui.table(rep["var"].set_index(["Horizon", "Confiance"]),
         pcts=["VaR historique", "CVaR historique", "VaR normale", "VaR Cornish-Fisher", "VaR Monte-Carlo (t)",
               "CVaR Monte-Carlo (t)"], money_cols=["VaR max (€/$)"])
st.caption("VaR 99 % 1 jour = perte qui ne devrait être dépassée qu'un jour sur 100. CVaR = perte moyenne au-delà. "
           "Cornish-Fisher et Student-t tiennent compte des queues épaisses.")
if not rep["tails"].empty:
    ui.table(rep["tails"].set_index("Événement sur 12 mois"), pcts=["Probabilité"])
    st.caption("Probabilités estimées par bootstrap par blocs de 20 jours (20 000 trajectoires d'un an) à partir de "
               "l'historique réel du portefeuille.")

# ------------------------------------------------------------ 6. liquidité
st.header("6. Risque de liquidité")
ui.table(rep["liquidity"], money_cols=["Montant", "Volume moyen/jour"], nums=["Jours pour liquider", "Note liquidité /10"])
st.caption(f"Jours nécessaires pour vendre en ne dépassant pas {limits.participation_rate:.0%} du volume quotidien.")

# ------------------------------------------------------------ 7. positions individuelles
st.header("7. Risque par position et dimensionnement")
rc = rep["contrib"]
fig = go.Figure([go.Bar(name="Poids", x=rc.index, y=rc["Poids"]),
                 go.Bar(name="Contribution au risque", x=rc.index, y=rc["Contribution au risque"])])
fig.update_layout(barmode="group", height=360, yaxis_tickformat=".0%", margin=dict(t=20, b=10))
st.plotly_chart(fig, width="stretch")
ui.table(rc, pcts=["Poids", "Volatilité annuelle", "Contribution au risque"], nums=["Ratio risque/poids"])
over = rc[rc["Ratio risque/poids"] > 1.3]
for t, r in over.iterrows():
    st.markdown(f"- **{t}** apporte {ui.pct(r['Contribution au risque'])} du risque pour {ui.pct(r['Poids'])} du capital "
                f"→ réduire vers {ui.pct(r['Poids'] / r['Ratio risque/poids'])} pour un risque proportionnel.")

# ------------------------------------------------------------ 9. couvertures
st.header("8. Les 3 principaux risques et leurs couvertures")
for i, (key, _, label) in enumerate(rep["top3"], 1):
    st.markdown(f"**{i}. {label}**")
ui.table(pd.DataFrame(rep["hedges"]).set_index("Risque"), money_cols=["Montant notionnel à couvrir"])

# ------------------------------------------------------------ 10. rééquilibrage
st.header("9. Rééquilibrage proposé")
names = {"risk_parity": "Parité de risque", "min_variance": "Variance minimale", "max_sharpe": "Sharpe maximal"}
ui.table(rep["compare"].rename(index=names), pcts=["Volatilité", "Rendement historique", "Baisse max"], nums=["Sharpe"])
choice = st.radio("Méthode", list(names), format_func=names.get, horizontal=True)
target = rep["optimal"][choice]
reb = pd.DataFrame({"Poids actuel": w, "Poids cible": target})
reb["Écart"] = reb["Poids cible"] - reb["Poids actuel"]
reb["Ordre"] = reb["Écart"] * value
reb["Action"] = reb["Écart"].map(lambda x: "ACHETER" if x > 0.005 else "VENDRE" if x < -0.005 else "conserver")
ui.table(reb, pcts=["Poids actuel", "Poids cible", "Écart"], money_cols=["Ordre"])
st.caption(f"Contraintes : poids entre 0 et {limits.max_single_position:.0%} par ligne. Covariance Ledoit-Wolf ; "
           "rendements attendus rétrécis à 50 % vers la moyenne (pour éviter de sur-optimiser le passé). "
           "La parité de risque est la méthode « All Weather » de Bridgewater.")

md = "# Rapport de gestion des risques\n\n## Limites\n" + "\n".join(
    f"- {'OK' if c.ok else 'DÉPASSEMENT'} — {c.rule} : {c.value} (limite {c.limit})" for c in rep["checks"]) + \
    "\n\n## Stress tests\n" + ui.df_to_md(rep["hyp_stress"].set_index("Scénario")[["Probabilité annuelle (indicative)", "Impact portefeuille"]],
                                         pcts=["Probabilité annuelle (indicative)", "Impact portefeuille"]) + \
    "\n\n## Principaux risques\n" + "\n".join(f"- {x[2]}" for x in rep["top3"]) + \
    "\n\n## Rééquilibrage (" + names[choice] + ")\n" + ui.df_to_md(reb[["Poids actuel", "Poids cible", "Action"]],
                                                                  pcts=["Poids actuel", "Poids cible"])
ui.download_md("Télécharger le rapport de risque (Markdown)", md, "rapport_risque.md")
ui.footer()
