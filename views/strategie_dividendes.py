import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from godafret import services, ui
from godafret.analytics import dividends
from godafret.universes import DIVIDEND_EU, DIVIDEND_US, SECTORS_FR

ui.setup("07 · Stratégie dividendes", "Méthode « stratégiste en chef du fonds de dotation de Harvard » — revenu passif")

with st.form("div"):
    c1, c2, c3, c4 = st.columns(4)
    amount = c1.number_input("Montant total investi (€)", 1_000.0, 1e10, 200_000.0, 5_000.0)
    target = c2.number_input("Objectif de revenu mensuel (€)", 0.0, 1e7, 600.0, 50.0)
    account = c3.selectbox("Type de compte", ["CTO", "PEA", "Assurance-vie", "PER"])
    tmi = c4.selectbox("Tranche marginale d'imposition", ["0 %", "11 %", "30 %", "41 %", "45 %"], index=2)
    c5, c6, c7 = st.columns(3)
    n = c5.slider("Nombre de lignes", 15, 20, 18)
    min_safety = c6.slider("Sécurité minimale /10", 3.0, 9.0, 6.0, 0.5)
    price_g = c7.number_input("Croissance annuelle des cours supposée (%)", 0.0, 10.0, 4.0, 0.5) / 100
    univ = st.multiselect("Univers", ["Dividendes US", "Dividendes Europe"], default=["Dividendes US", "Dividendes Europe"])
    extra = st.text_input("Tickers supplémentaires", placeholder="ex. O, ENB, NG.L")
    ok = st.form_submit_button("Construire le portefeuille dividendes", type="primary")

if ok:
    tickers = (DIVIDEND_US if "Dividendes US" in univ else []) + (DIVIDEND_EU if "Dividendes Europe" in univ else []) + \
              [t.strip().upper() for t in extra.split(",") if t.strip()]
    bar = st.progress(0.0, "Analyse des dividendes…")
    df = ui.run_safely(services.dividend_universe, tickers, account, lambda p, t: bar.progress(p, f"Analyse de {t}…"))
    bar.empty()
    if df is not None:
        st.session_state["divs"] = (df, amount, target, account, tmi, n, min_safety, price_g)

if "divs" not in st.session_state:
    ui.footer()
    st.stop()

df, amount, target, account, tmi, n, min_safety, price_g = st.session_state["divs"]
port = dividends.build_portfolio(df, n=n, min_safety=min_safety)
if port.empty:
    st.error("Aucune valeur ne passe les filtres : baisse la sécurité minimale.")
    st.stop()
port["Montant"] = port["Poids"] * amount
port["Revenu annuel brut"] = port["Montant"] * port["Rendement"]
port["Revenu annuel net"] = port["Revenu annuel brut"] * (1 - port["Impôt effectif"].fillna(0))
gross_m = port["Revenu annuel brut"].sum() / 12
net_m = port["Revenu annuel net"].sum() / 12
y = (port["Poids"] * port["Rendement"]).sum()
g5 = (port["Poids"] * port["Croissance div. estimée 5 ans"].fillna(0)).sum()
tax_avg = 1 - port["Revenu annuel net"].sum() / port["Revenu annuel brut"].sum()

m1, m2, m3, m4 = st.columns(4)
m1.metric("Rendement moyen", ui.pct(y, 2))
m2.metric("Revenu mensuel brut", ui.money(gross_m))
m3.metric("Revenu mensuel net d'impôt", ui.money(net_m), ui.money(net_m - target) + " vs objectif",
          delta_color="normal")
m4.metric("Croissance du dividende estimée", ui.pct(g5) + " /an")
if target and net_m < target:
    need = target * 12 / (y * (1 - tax_avg)) if y > 0 else float("nan")
    st.warning(f"Objectif de {ui.money(target)}/mois non atteint aujourd'hui : il faudrait environ "
               f"{ui.money(need)} investis à ce rendement — ou laisser jouer la croissance des dividendes (voir projection). "
               "Ne pas chercher des rendements > 7 % : c'est souvent le signe d'un dividende menacé.")

st.header("1. Les valeurs sélectionnées")
cols = ["Nom", "Secteur", "Cours", "Rendement", "Sécurité /10", "Années de hausse", "Taux de distribution (BPA)",
        "Taux de distribution (FCF)", "Croissance div. 5 ans (hist.)", "Croissance div. estimée 5 ans", "Poids",
        "Montant", "Revenu annuel net"]
v = port[cols].copy()
v["Secteur"] = v["Secteur"].map(lambda s: SECTORS_FR.get(s, s))
ui.table(v, pcts=["Rendement", "Taux de distribution (BPA)", "Taux de distribution (FCF)", "Croissance div. 5 ans (hist.)",
                  "Croissance div. estimée 5 ans", "Poids"], nums=["Cours", "Sécurité /10"],
         money_cols=["Montant", "Revenu annuel net"])
with st.expander("Pourquoi ces notes de sécurité ?"):
    for t, r in port.iterrows():
        st.markdown(f"- **{t}** ({r['Sécurité /10']:.1f}/10) : {r['Pourquoi'] or '—'}")

st.header("2. Taux de distribution : repérer les dividendes non soutenables")
risky = df[(df["Taux de distribution (BPA)"] > 0.8) | (df["Taux de distribution (FCF)"] > 0.9)]
if risky.empty:
    st.markdown("Aucune valeur de l'univers ne distribue plus de 80 % de ses bénéfices ou 90 % de son FCF.")
else:
    st.markdown("Valeurs **à éviter ou surveiller** (distribuent presque tout, voire plus, de ce qu'elles gagnent) :")
    ui.table(risky[["Nom", "Rendement", "Taux de distribution (BPA)", "Taux de distribution (FCF)", "Sécurité /10"]],
             pcts=["Rendement", "Taux de distribution (BPA)", "Taux de distribution (FCF)"], nums=["Sécurité /10"])

st.header("3. Répartition sectorielle")
a, b = st.columns(2)
a.plotly_chart(ui.pie(port.groupby("Secteur")["Poids"].sum().rename(index=lambda s: SECTORS_FR.get(s, s)), "Par secteur"),
               width="stretch")
b.plotly_chart(ui.pie(port.groupby("Pays")["Poids"].sum(), "Par pays"), width="stretch")
st.caption("Plafond de 25 % par secteur pour éviter qu'une crise sectorielle (ex. banques 2008, énergie 2020) ne "
           "coupe une grande partie du revenu.")

st.header("4. Projection de revenus mensuels et réinvestissement (10 ans)")
proj = dividends.drip_projection(amount, y, g5, price_g, tax_avg, years=10)
fig = go.Figure()
fig.add_trace(go.Scatter(x=proj.index, y=proj["Valeur avec DRIP"], name="Capital avec réinvestissement", line=dict(width=3)))
fig.add_trace(go.Scatter(x=proj.index, y=proj["Valeur sans DRIP"] + proj["Dividendes cumulés encaissés (sans DRIP)"],
                         name="Sans réinvestissement (capital + dividendes encaissés)", line=dict(dash="dash")))
fig.update_layout(height=360, xaxis_title="Années", margin=dict(t=20, b=10))
st.plotly_chart(fig, width="stretch")
ui.table(proj, money_cols=list(proj.columns))
st.markdown(f"Dans 10 ans, avec réinvestissement : revenu mensuel net ≈ **{ui.money(proj['Revenu mensuel net (DRIP)'].iloc[-1])}** "
            f"(contre {ui.money(net_m)} aujourd'hui). Hypothèses : rendement {ui.pct(y, 2)}, croissance du dividende "
            f"{ui.pct(g5)}/an, cours +{ui.pct(price_g)}/an, impôt {ui.pct(tax_avg, 0)}.")

st.header(f"5. Fiscalité des dividendes — {account}")
for region, label in (("FR", "Actions françaises"), ("EU", "Actions européennes"), ("US", "Actions américaines")):
    rate, txt = dividends.tax_rate(account, region)
    st.markdown(f"- **{label}** : {txt}")
if account == "CTO" and tmi in ("0 %", "11 %"):
    st.info(f"Avec une TMI de {tmi}, l'option pour le barème progressif (abattement de 40 % sur les dividendes) est "
            "généralement plus avantageuse que la flat tax : à cocher sur la déclaration (case 2OP), elle s'applique "
            "à tous les revenus du capital de l'année.")

st.header("6. Classement : du plus sûr au plus agressif")
rk = dividends.ranking(df)
ui.table(rk[["Nom", "Profil", "Sécurité /10", "Rendement", "Années de hausse", "Taux de distribution (BPA)"]],
         pcts=["Rendement", "Taux de distribution (BPA)"], nums=["Sécurité /10"])

md = (f"# Plan de portefeuille dividendes\n\nMontant {amount:,.0f} € · compte {account} · rendement {ui.pct(y, 2)} · "
      f"revenu net {ui.money(net_m)}/mois\n\n" +
      ui.df_to_md(v[["Nom", "Rendement", "Sécurité /10", "Années de hausse", "Poids", "Revenu annuel net"]],
                  pcts=["Rendement", "Poids"], nums=["Sécurité /10", "Revenu annuel net"]) +
      "\n\n## Projection 10 ans\n" + ui.df_to_md(proj[["Valeur avec DRIP", "Revenu mensuel net (DRIP)"]],
                                                nums=["Valeur avec DRIP", "Revenu mensuel net (DRIP)"]))
ui.download_md("Télécharger le plan (Markdown)", md, "plan_dividendes.md")
ui.footer()
