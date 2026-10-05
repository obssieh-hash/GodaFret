import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from plotly.subplots import make_subplots

from godafret import services, ui
from godafret.analytics import technical

ui.setup("06 · Analyse technique", "Méthode « trader quantitatif senior Citadel » — bulletin technique et plan de trade")

c1, c2, c3 = st.columns([2, 1, 1])
ticker = c1.text_input("Ticker (format Yahoo)", "AAPL").strip().upper()
cost = c2.number_input("Ton prix de revient (0 = pas de position)", 0.0, 1e7, 0.0)
if c3.button("Analyser", type="primary"):
    with st.spinner("Calcul des indicateurs…"):
        out = ui.run_safely(services.technical_report, ticker, cost or None)
    if out:
        st.session_state["tech"] = (ticker, out[0], out[1], cost)

if "tech" not in st.session_state:
    ui.footer()
    st.stop()

ticker, rep, src, cost = st.session_state["tech"]
plan = rep.plan
good = True if "ACHAT" in rep.rating else False if "VENTE" in rep.rating else None
ui.verdict_badge(f"{ticker} : {rep.rating} (score {rep.score:+.2f} sur une échelle de −1 à +1)", good)

m1, m2, m3, m4, m5 = st.columns(5)
m1.metric("Cours", ui.num(rep.price))
m2.metric("Entrée idéale", ui.num(plan["entrée"]), plan["zone d'entrée"], delta_color="off")
m3.metric("Stop-loss", ui.num(plan["stop-loss"]), ui.pct(-plan["risque %"]), delta_color="off")
m4.metric("Objectif", ui.num(plan["objectif"]), ui.pct(plan["gain potentiel %"]), delta_color="off")
m5.metric("Rendement / risque", f"{ui.num(plan['ratio rendement/risque'])} : 1")
st.markdown(f"**Configuration : {plan['type de configuration']}**")
if plan.get("alerte"):
    st.warning(plan["alerte"])

# ------------------------------------------------------------ graphique
f = rep.frame.tail(400)
fig = make_subplots(rows=3, cols=1, shared_xaxes=True, row_heights=[0.6, 0.2, 0.2], vertical_spacing=0.03)
fig.add_trace(go.Candlestick(x=f.index, open=f["Open"], high=f["High"], low=f["Low"], close=f["Close"], name="Cours"), 1, 1)
for n, col in ((50, "#0969da"), (100, "#8250df"), (200, "#bf3989")):
    fig.add_trace(go.Scatter(x=f.index, y=f[f"MM{n}"], name=f"MM{n}", line=dict(width=1.4, color=col)), 1, 1)
fig.add_trace(go.Scatter(x=f.index, y=f["upper"], name="Bollinger haut", line=dict(width=0.8, dash="dot", color="gray")), 1, 1)
fig.add_trace(go.Scatter(x=f.index, y=f["lower"], name="Bollinger bas", line=dict(width=0.8, dash="dot", color="gray")), 1, 1)
for s in rep.supports:
    fig.add_hline(y=s["niveau"], line_color=ui.COLORS["up"], line_dash="dash", annotation_text=f"S {s['niveau']}", row=1, col=1)
for r in rep.resistances:
    fig.add_hline(y=r["niveau"], line_color=ui.COLORS["down"], line_dash="dash", annotation_text=f"R {r['niveau']}", row=1, col=1)
fig.add_hline(y=plan["stop-loss"], line_color="black", annotation_text="stop", row=1, col=1)
fig.add_trace(go.Scatter(x=f.index, y=f["RSI"], name="RSI", line=dict(color="#953800")), 2, 1)
fig.add_hline(y=70, line_dash="dot", row=2, col=1)
fig.add_hline(y=30, line_dash="dot", row=2, col=1)
fig.add_trace(go.Bar(x=f.index, y=f["hist"], name="MACD histo"), 3, 1)
fig.add_trace(go.Scatter(x=f.index, y=f["macd"], name="MACD"), 3, 1)
fig.add_trace(go.Scatter(x=f.index, y=f["signal"], name="Signal"), 3, 1)
fig.update_layout(height=820, xaxis_rangeslider_visible=False, margin=dict(t=20, b=10), legend=dict(orientation="h"))
st.plotly_chart(fig, width="stretch")
st.caption(f"Source des cours : {src}")

st.header("1. Tendance par horizon")
ui.table(pd.DataFrame({"Tendance": rep.trends}))

st.header("2. Supports et résistances")
a, b = st.columns(2)
with a:
    st.markdown("**Supports**")
    ui.table(pd.DataFrame(rep.supports), pcts=["distance"], nums=["niveau", "force"], hide_index=True)
with b:
    st.markdown("**Résistances**")
    ui.table(pd.DataFrame(rep.resistances), pcts=["distance"], nums=["niveau", "force"], hide_index=True)

st.header("3. Moyennes mobiles et croisements")
ui.table(pd.DataFrame(rep.moving_averages).T, pcts=["écart"], nums=["valeur"])
if rep.crosses:
    ui.table(pd.DataFrame(rep.crosses), hide_index=True)

st.header("4. RSI, MACD, Bollinger — expliqués simplement")
for k, v in rep.oscillators.items():
    st.markdown(f"- **{k}** : {v}")

st.header("5. Volumes : qui domine ?")
for k, v in rep.volume.items():
    st.markdown(f"- **{k}** : {v}")

st.header("6. Figures chartistes")
if rep.patterns:
    ui.table(pd.DataFrame(rep.patterns), nums=["ligne de cou", "objectif"], hide_index=True)
else:
    st.markdown("Aucune figure classique (double sommet/creux, épaule-tête-épaule, tasse avec anse) détectée sur 1 an.")
st.caption("Détection algorithmique à partir des points hauts/bas (fenêtre ±5 séances) ; une figure n'est "
           "valide qu'après cassure de la ligne de cou.")

st.header("7. Fibonacci")
fib = rep.fibonacci
st.markdown(f"Mouvement de référence ({fib['sens']}) : plus bas {fib['plus bas']} le {fib['date plus bas']} → plus haut "
            f"{fib['plus haut']} le {fib['date plus haut']}.")
ui.table(pd.DataFrame({"Retracements": fib["niveaux"]}), nums=["Retracements"])
st.markdown("Extensions : " + ", ".join(f"{k} = {v}" for k, v in fib["extensions"].items()) +
            ". Les zones 38,2 %-61,8 % sont les zones de rebond les plus fréquentes.")

st.header("8-9. Plan de trade")
ui.table(pd.DataFrame({"Plan": {k: ui.pct(v) if ("%" in k or "plus/moins" in k) else str(v) for k, v in plan.items()}}))
with st.expander("Calculateur de taille de position"):
    k1, k2, k3 = st.columns(3)
    capital = k1.number_input("Capital total", 1_000.0, 1e10, 100_000.0, 1_000.0)
    rpt = k2.number_input("Risque max par trade (% du capital)", 0.1, 5.0, 1.0, 0.1) / 100
    mw = k3.number_input("Poids max de la ligne (%)", 1.0, 100.0, 10.0) / 100
    ps = technical.position_size(capital, rpt, plan["entrée"], plan["stop-loss"], mw)
    if ps:
        st.markdown(f"Acheter **{ps['quantité']} actions** (≈ {ui.num(ps['montant'], 0)}, {ui.pct(ps['poids'])} du capital) ; "
                    f"perte si le stop est touché : **{ui.num(ps['perte max si stop'], 0)}** "
                    f"({ui.pct(ps['perte max si stop'] / capital, 2)} du capital).")

st.header("10. Note de confiance — détail des signaux")
sig = pd.DataFrame([{"Signal": s.name, "Poids": s.weight, "Lecture": s.value, "Détail": s.comment} for s in rep.signals])
ui.table(sig, nums=["Poids", "Lecture"], hide_index=True)

md = f"""# Bulletin technique — {ticker}

**{rep.rating}** (score {rep.score:+.2f})

| Plan | |
|---|---|
| Cours | {plan['cours']} |
| Zone d'entrée | {plan["zone d'entrée"]} |
| Stop-loss | {plan['stop-loss']} ({plan['justification stop']}) |
| Objectif | {plan['objectif']} ({plan['justification objectif']}) |
| Rendement/risque | {plan['ratio rendement/risque']} : 1 |

## Tendances
""" + "\n".join(f"- {k} : {v}" for k, v in rep.trends.items()) + "\n\n## Indicateurs\n" + "\n".join(
    f"- {k} : {v}" for k, v in {**rep.oscillators, **rep.volume}.items())
ui.download_md("Télécharger le bulletin (Markdown)", md, f"technique_{ticker}.md")
ui.footer()
