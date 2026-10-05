from dataclasses import replace

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from godafret import services, ui
from godafret.analytics import dcf
from godafret.config import MARKET

ui.setup("02 · Valorisation DCF", "Méthode « VP banque d'affaires Morgan Stanley » — mémo de valorisation")

c1, c2, c3, c4 = st.columns([2, 1, 1, 1])
ticker = c1.text_input("Ticker (format Yahoo)", "MSFT").strip().upper()
erp = c2.number_input("Prime de risque actions (%)", 3.0, 9.0, MARKET.equity_risk_premium * 100, 0.25) / 100
g = c3.number_input("Croissance perpétuelle (%)", 0.0, 4.0, MARKET.terminal_growth * 100, 0.25) / 100
if c4.button("Construire le modèle", type="primary") or st.session_state.get("dcf_ticker") not in (None, ticker):
    res = ui.run_safely(services.dcf_inputs, ticker, erp, g)
    if res:
        st.session_state["dcf"] = res
        st.session_state["dcf_ticker"] = ticker

if "dcf" not in st.session_state:
    st.info("Entre un ticker puis clique sur « Construire le modèle ».")
    ui.footer()
    st.stop()

base, f, info, st_, rf_src = st.session_state["dcf"]
ccy = f.currency

st.subheader(f"{f.name} ({f.ticker}) — {f.sector} · cours {ui.num(f.price)} {ccy}")
if "Financial" in (f.sector or ""):
    st.warning("Banque/assurance : le DCF par les flux de trésorerie disponibles est peu fiable pour ce secteur.")

with st.expander("Hypothèses (modifiables)", expanded=True):
    a1, a2, a3, a4 = st.columns(4)
    gs = a1.number_input("Croissance CA an 1 (%)", -20.0, 60.0, base.growth_start * 100, 0.5) / 100
    ge = a1.number_input("Croissance CA an 5 (%)", -10.0, 40.0, base.growth_end * 100, 0.5) / 100
    ms = a2.number_input("Marge EBIT an 1 (%)", -50.0, 80.0, base.margin_start * 100, 0.5) / 100
    me = a2.number_input("Marge EBIT an 5 (%)", -50.0, 80.0, base.margin_end * 100, 0.5) / 100
    tax = a3.number_input("Taux d'impôt (%)", 0.0, 40.0, base.tax_rate * 100, 0.5) / 100
    capex = a3.number_input("Capex (% CA)", 0.0, 50.0, base.capex_pct * 100, 0.25) / 100
    da = a3.number_input("D&A (% CA)", 0.0, 40.0, base.da_pct * 100, 0.25) / 100
    nwc = a4.number_input("Δ BFR (% de la hausse du CA)", -50.0, 50.0, base.nwc_pct * 100, 1.0) / 100
    beta = a4.number_input("Bêta (ajusté)", 0.2, 3.0, float(base.beta), 0.05)
    mult = a4.number_input("Multiple de sortie VE/EBITDA", 2.0, 40.0, float(base.exit_multiple), 0.5)
    rf = a1.number_input("Taux sans risque (%)", 0.0, 10.0, base.risk_free * 100, 0.05) / 100
    kd = a2.number_input("Coût de la dette avant impôt (%)", 0.0, 15.0, base.cost_of_debt * 100, 0.1) / 100
    st.caption(f"Taux sans risque : {rf_src}. " + " ".join(base.notes))

inp = replace(base, growth_start=gs, growth_end=ge, margin_start=ms, margin_end=me, tax_rate=tax, capex_pct=capex,
              da_pct=da, nwc_pct=nwc, beta=beta, exit_multiple=mult, risk_free=rf, cost_of_debt=kd,
              equity_risk_premium=erp, terminal_growth=g)
r = dcf.run(inp)

good = None if r.verdict == "CORRECTEMENT VALORISÉE" else r.verdict == "SOUS-ÉVALUÉE"
ui.verdict_badge(f"{r.verdict} — juste valeur {ui.num(r.value_blended)} {ccy} vs cours {ui.num(f.price)} "
                 f"({ui.pct(r.upside)})", good)
if abs(r.upside) > 1:
    st.warning("Écart de plus de 100 % avec le cours : vérifie les hypothèses et les données (devise des comptes, "
               "nombre d'actions, éléments exceptionnels). Un tel écart vient plus souvent d'une donnée erronée que "
               "d'une vraie opportunité.")
m1, m2, m3, m4 = st.columns(4)
m1.metric("Valeur (croissance perpétuelle)", f"{ui.num(r.value_gordon)} {ccy}", ui.pct(r.value_gordon / f.price - 1))
m2.metric("Valeur (multiple de sortie)", f"{ui.num(r.value_exit)} {ccy}", ui.pct(r.value_exit / f.price - 1))
m3.metric("CMPC (WACC)", ui.pct(r.wacc, 2))
m4.metric("Part de la valeur terminale", ui.pct(r.tv_share_gordon, 0))

st.header("1. Projection sur 5 ans et flux de trésorerie disponibles")
proj = r.projection.copy()
scale = 1e6
money_cols = ["Chiffre d'affaires", "EBIT", "Impôts", "NOPAT", "D&A", "Capex", "Δ BFR", "FCFF", "EBITDA", "FCFF actualisé"]
show = proj.copy()
for c in money_cols:
    show[c] = show[c] / scale
unit = f"millions {info.get('financialCurrency') or ccy}"
disp = pd.DataFrame(index=show.columns, columns=show.index, dtype=object)
for c in show.columns:
    for y in show.index:
        v = show.loc[y, c]
        disp.loc[c, y] = ui.pct(v) if c in ("Croissance", "Marge EBIT") else ui.num(v, 3) if c == "Facteur d'actualisation" else ui.num(v, 0)
disp.index.name = unit
st.dataframe(disp, width="stretch")
st.caption("FCFF = EBIT × (1 − impôt) + D&A − Capex − Δ BFR. Actualisation en milieu d'année.")

st.header("2. Coût moyen pondéré du capital")
e, d = max(inp.market_cap, 0), max(inp.total_debt, 0)
wacc_tbl = pd.DataFrame({"Valeur": [ui.pct(inp.risk_free, 2), ui.num(inp.beta), ui.pct(inp.equity_risk_premium, 2),
                                    ui.pct(inp.cost_of_equity, 2), ui.pct(inp.cost_of_debt, 2),
                                    ui.pct(inp.cost_of_debt * (1 - inp.tax_rate), 2), ui.pct(e / (e + d) if e + d else 1),
                                    ui.pct(d / (e + d) if e + d else 0), ui.pct(r.wacc, 2)]},
                        index=["Taux sans risque", "Bêta", "Prime de risque", "Coût des fonds propres (CAPM)",
                               "Coût de la dette", "Coût de la dette après impôt", "Poids fonds propres",
                               "Poids dette", "CMPC"])
st.dataframe(wacc_tbl, width="stretch")

st.header("3. Valeur terminale — deux méthodes")
fin_ccy = info.get("financialCurrency") or ccy
tv = pd.DataFrame({
    "Croissance perpétuelle": [ui.big(r.tv_gordon, fin_ccy), ui.big(r.ev_gordon, fin_ccy), ui.num(r.value_gordon),
                               f"multiple implicite {ui.num(r.implied_multiple_gordon, 1)}x EBITDA"],
    "Multiple de sortie": [ui.big(r.tv_exit, fin_ccy), ui.big(r.ev_exit, fin_ccy), ui.num(r.value_exit),
                           f"croissance implicite {ui.pct(r.implied_growth_exit)}"]},
    index=["Valeur terminale (an 5)", "Valeur d'entreprise", f"Valeur par action ({ccy})", "Contrôle de cohérence"])
st.dataframe(tv, width="stretch")
st.caption(f"Valeur des fonds propres = VE − dette nette ({ui.big(inp.net_debt, fin_ccy)}) ; "
           f"{ui.big(inp.shares)} actions.")

st.header("4. Tableaux de sensibilité (juste valeur par action)")
s1, s2 = st.columns(2)
sg = dcf.sensitivity(inp, method="gordon")
sx = dcf.sensitivity(inp, method="exit")
rel = lambda t: (t / f.price - 1)
s1.plotly_chart(ui.heatmap(rel(sg), "CMPC × croissance perpétuelle (% vs cours)", -0.5, 0.5, "RdYlGn", ".0%"),
                width="stretch")
s2.plotly_chart(ui.heatmap(rel(sx), "CMPC × multiple de sortie (% vs cours)", -0.5, 0.5, "RdYlGn", ".0%"),
                width="stretch")
with st.expander("Valeurs absolues"):
    ui.table(sg, nums=list(sg.columns))
    ui.table(sx, nums=list(sx.columns))

st.header("5. Scénarios et comparaison avec le cours")
sc = dcf.scenarios(inp)
ui.table(sc, pcts=["CMPC", "Potentiel"], nums=["Valeur (Gordon)", "Valeur (multiple)", "Valeur retenue"])
fig = go.Figure()
for name, row in sc.iterrows():
    fig.add_trace(go.Bar(x=[name], y=[row["Valeur retenue"]], name=name, text=ui.num(row["Valeur retenue"]),
                         textposition="outside"))
fig.add_hline(y=f.price, line_dash="dash", annotation_text=f"cours {ui.num(f.price)}")
fig.update_layout(height=360, showlegend=False, margin=dict(t=30, b=10))
st.plotly_chart(fig, width="stretch")

st.header("6. Hypothèses qui pourraient faire s'effondrer le modèle")
risks = dcf.key_risks(inp, r, f)
for x in risks:
    st.markdown(f"- {x}")

memo = f"""# Mémo de valorisation — {f.name} ({f.ticker})

**Verdict : {r.verdict}** — juste valeur {ui.num(r.value_blended)} {ccy} vs cours {ui.num(f.price)} ({ui.pct(r.upside)})

| | Croissance perpétuelle | Multiple de sortie |
|---|---|---|
| Valeur par action | {ui.num(r.value_gordon)} | {ui.num(r.value_exit)} |
| Hypothèse terminale | g = {ui.pct(inp.terminal_growth)} | {ui.num(inp.exit_multiple, 1)}x EBITDA |

CMPC {ui.pct(r.wacc, 2)} (Ke {ui.pct(inp.cost_of_equity, 2)}, bêta {ui.num(inp.beta)}, Rf {ui.pct(inp.risk_free, 2)}, ERP {ui.pct(inp.equity_risk_premium)})

## Projection (millions)
{ui.df_to_md(show[["Croissance", "Chiffre d'affaires", "Marge EBIT", "EBIT", "NOPAT", "FCFF"]], pcts=["Croissance", "Marge EBIT"], nums=["Chiffre d'affaires", "EBIT", "NOPAT", "FCFF"])}

## Sensibilité (CMPC × g)
{ui.df_to_md(sg, nums=list(sg.columns))}

## Scénarios
{ui.df_to_md(sc, pcts=["CMPC", "Potentiel"], nums=["Valeur (Gordon)", "Valeur (multiple)", "Valeur retenue"])}

## Risques du modèle
""" + "\n".join(f"- {x}" for x in risks)
ui.download_md("Télécharger le mémo (Markdown)", memo, f"dcf_{f.ticker}.md")
ui.footer()
