import math

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from godafret import services, ui

ui.setup("04 · Résultats trimestriels", "Méthode « analyste actions senior JPMorgan » — note pré-résultats")

KPIS = {
    "Technology": ["Croissance du cloud / des abonnements (ARR)", "Marge brute", "Guidance du trimestre suivant",
                   "Carnet de commandes (RPO)", "Dépenses d'investissement IA"],
    "Communication Services": ["Utilisateurs actifs (DAU/MAU)", "Revenu publicitaire par utilisateur", "Abonnés", "Capex"],
    "Consumer Cyclical": ["Ventes à périmètre constant", "Marge brute", "Niveau des stocks", "Panier moyen / trafic"],
    "Consumer Defensive": ["Croissance organique (volume vs prix)", "Marge brute", "Effet de change"],
    "Healthcare": ["Ventes des produits phares", "Pipeline (essais cliniques)", "Guidance BPA annuelle", "Brevets"],
    "Financial Services": ["Marge nette d'intérêt (NII)", "Provisions pour pertes", "Ratio CET1", "Coefficient d'exploitation"],
    "Energy": ["Production (barils/jour)", "Prix réalisés", "Rachats d'actions et dividende", "Marges de raffinage"],
    "Industrials": ["Prises de commandes / carnet", "Marge opérationnelle", "Free cash-flow", "Chaîne d'approvisionnement"],
    "Utilities": ["Base d'actifs régulés", "Croissance du BPA", "Plan d'investissement"],
    "Real Estate": ["FFO par action", "Taux d'occupation", "Coût de la dette"],
    "Basic Materials": ["Volumes", "Prix des matières", "Coûts de l'énergie"],
}

c1, c2 = st.columns([3, 1])
ticker = c1.text_input("Entreprise qui publie (ticker Yahoo)", "NVDA").strip().upper()
if c2.button("Analyser", type="primary"):
    with st.spinner("Historique des résultats, consensus et options…"):
        rep = ui.run_safely(services.earnings_report, ticker)
    if rep:
        st.session_state["earn"] = (ticker, rep)

if "earn" not in st.session_state:
    ui.footer()
    st.stop()

ticker, rep = st.session_state["earn"]
info = rep["info"]
st.subheader(f"{info.get('shortName', ticker)} ({ticker}) — cours {ui.num(rep['spot'])} {info.get('currency', '')}")

# ------------------------------------------------------------ décision en haut
reco = rep["recommendation"]
ui.verdict_badge(f"Décision : {reco}", True if reco.startswith("ACHETER") else False if reco.startswith("VENDRE") else None)
nd = rep["next_date"]
d1, d2, d3, d4 = st.columns(4)
d1.metric("Prochaine publication", nd.strftime("%d/%m/%Y") if nd is not None else "inconnue")
d2.metric("Taux de battement (8 trim.)", ui.pct(rep["stats"].get("beat_rate"), 0))
d3.metric("Mouvement implicite (options)", ui.pct(rep["implied"].get("move")),
          f"échéance {rep['implied'].get('expiry', '—')}", delta_color="off")
avg_abs = rep["reactions"]["Réaction J+1"].abs().mean() if not rep["reactions"].empty else float("nan")
d4.metric("Mouvement moyen historique", ui.pct(avg_abs))
for w in rep["why"]:
    st.markdown(f"- {w}")
st.caption(rep["revision"][1])

# ------------------------------------------------------------ historique des surprises
st.header("1. Résultats publiés vs attentes")
h = rep["history"].tail(8).copy()
if h.empty:
    st.info("Historique indisponible (ajoute une clé Finnhub ou Alpha Vantage pour une source de secours).")
else:
    h["Battu ?"] = (h["eps_actual"] > h["eps_estimate"]).map({True: "✅ battu", False: "❌ manqué"})
    h["date"] = pd.to_datetime(h["date"]).dt.strftime("%d/%m/%Y")
    h = h.rename(columns={"date": "Date", "eps_estimate": "BPA attendu", "eps_actual": "BPA publié",
                          "surprise_pct": "Surprise (%)"}).set_index("Date")
    ui.table(h, nums=["BPA attendu", "BPA publié", "Surprise (%)"])
    st.caption(f"Source : {rep['history_source']}")

# ------------------------------------------------------------ consensus
st.header("2. Consensus pour les trimestres à venir")
an = rep["analyst"]
lab = {"0q": "Trimestre en cours", "+1q": "Trimestre suivant", "0y": "Exercice en cours", "+1y": "Exercice suivant"}
cc1, cc2 = st.columns(2)
if "earnings_estimate" in an:
    ee = an["earnings_estimate"].rename(index=lab)
    cc1.markdown("**Bénéfice par action**")
    with cc1:
        ui.table(ee, nums=[c for c in ee.columns if c != "growth"], pcts=["growth"])
if "revenue_estimate" in an:
    re_ = an["revenue_estimate"].rename(index=lab)
    cc2.markdown("**Chiffre d'affaires**")
    with cc2:
        ui.table(re_, bigs=[c for c in ("avg", "low", "high", "yearAgoRevenue") if c in re_], pcts=["growth"],
                 nums=["numberOfAnalysts"])
if "eps_trend" in an:
    st.markdown("**Évolution du consensus BPA (révisions)**")
    ui.table(an["eps_trend"].rename(index=lab), nums=list(an["eps_trend"].columns))

# ------------------------------------------------------------ KPI & segments
st.header("3. Indicateurs que Wall Street surveille · 4. Segments")
for k in KPIS.get(info.get("sector"), ["Croissance du CA", "Marges", "Guidance", "Free cash-flow"]):
    st.markdown(f"- {k}")
segs = rep["segments"]
if segs is not None and not segs.empty:
    seg = segs.tail(4)
    fig = go.Figure([go.Bar(name=c, x=[d.year for d in seg.index], y=seg[c]) for c in seg.columns])
    fig.update_layout(barmode="stack", height=360, title="CA par segment (FMP)", margin=dict(t=40, b=10))
    st.plotly_chart(fig, width="stretch")
    share = seg.iloc[-1] / seg.iloc[-1].sum()
    growth = seg.iloc[-1] / seg.iloc[-2] - 1 if len(seg) > 1 else share * float("nan")
    ui.table(pd.DataFrame({"Part du CA": share, "Croissance sur 1 an": growth}), pcts=["Part du CA", "Croissance sur 1 an"])
else:
    st.info("Le CA par segment et le résumé de la conférence (guidance de la direction) ne sont pas disponibles "
            "gratuitement de façon fiable : ajoute une clé FMP (offre payante) — voir la page d'accueil. "
            "En attendant, lis le communiqué de presse sur le site investisseurs de la société.")

# ------------------------------------------------------------ options
st.header("5. Mouvement anticipé par le marché des options")
imp = rep["implied"]
if imp:
    st.markdown(f"Straddle à la monnaie (prix d'exercice {ui.num(imp['strike'])}, échéance {imp['expiry']}) : "
                f"call {ui.num(imp['call'])} + put {ui.num(imp['put'])} = **{ui.num(imp['straddle'])}**, soit "
                f"**±{ui.pct(imp['move'])}** (volatilité implicite ATM {ui.pct(imp['iv_atm'], 0)}).")
    st.caption("Le prix du straddle est la meilleure estimation, par le marché, de l'amplitude du mouvement jusqu'à "
               "l'échéance (publication incluse).")
else:
    st.info("Pas de chaîne d'options disponible (fréquent hors des États-Unis).")

# ------------------------------------------------------------ réactions
st.header("6. Réaction du cours après les dernières publications")
react = rep["reactions"]
if not react.empty:
    fig = go.Figure(go.Bar(x=[str(d) for d in react["Date"]], y=react["Réaction J+1"],
                           marker_color=[ui.COLORS["up"] if v > 0 else ui.COLORS["down"] for v in react["Réaction J+1"]],
                           text=[ui.pct(v) for v in react["Réaction J+1"]], textposition="outside"))
    if imp:
        for s in (1, -1):
            fig.add_hline(y=s * imp["move"], line_dash="dot", annotation_text="implicite actuel")
    fig.update_layout(height=360, yaxis_tickformat=".0%", margin=dict(t=20, b=10))
    st.plotly_chart(fig, width="stretch")
    ui.table(react.set_index("Date"), pcts=[c for c in react.columns if c != "Date"])

# ------------------------------------------------------------ scénarios
st.header("7-8. Scénarios haussier et baissier")
sc = rep["scenarios"]
s1, s2 = st.columns(2)
with s1.container(border=True):
    st.markdown(f"### 🟢 Haussier : {ui.pct(sc['haussier']['variation'])} → {ui.num(sc['haussier']['cours'])}")
    st.markdown("Battement du BPA **et** du CA, guidance relevée, indicateurs clés au-dessus du consensus.")
with s2.container(border=True):
    st.markdown(f"### 🔴 Baissier : {ui.pct(sc['baissier']['variation'])} → {ui.num(sc['baissier']['cours'])}")
    st.markdown("BPA en ligne mais guidance prudente, marge sous pression ou indicateur clé en déception.")
st.caption("Amplitudes = maximum entre le mouvement implicite des options et la réaction moyenne historique "
           "dans le même sens.")

if rep["news"]:
    st.header("Actualités récentes (Finnhub)")
    for n in rep["news"]:
        st.markdown(f"- [{n.get('headline')}]({n.get('url')}) — {n.get('source')}")

md = f"""# Note pré-résultats — {info.get('shortName', ticker)} ({ticker})

**Décision : {reco}** · publication : {nd.strftime('%d/%m/%Y') if nd is not None else 'inconnue'}

- Taux de battement : {ui.pct(rep['stats'].get('beat_rate'), 0)} ; surprise moyenne {ui.num(rep['stats'].get('avg_surprise_pct'))} %
- Mouvement implicite : {ui.pct(imp.get('move'))} ; mouvement moyen historique : {ui.pct(avg_abs)}
- {rep['revision'][1]}
- Haussier : {ui.pct(sc['haussier']['variation'])} → {ui.num(sc['haussier']['cours'])} ; baissier : {ui.pct(sc['baissier']['variation'])} → {ui.num(sc['baissier']['cours'])}

## Justification
""" + "\n".join(f"- {w}" for w in rep["why"])
ui.download_md("Télécharger la note (Markdown)", md, f"resultats_{ticker}.md")
ui.footer()
