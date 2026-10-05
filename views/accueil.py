"""Page d'accueil : modules, API intégrées et état des connexions."""
import pandas as pd
import streamlit as st

from godafret import ui
from godafret.config import LIMITS

ui.setup("GodaFret — Desk d'investissement",
         "7 analyses de niveau banque d'investissement, alimentées par des API financières gratuites.")

st.markdown("""
Cet outil reprend les 7 méthodes de tes captures (Goldman Sachs, Morgan Stanley, Bridgewater, JPMorgan,
BlackRock, Citadel, Harvard) et les **calcule avec de vraies données de marché**, au lieu de demander à une IA
d'inventer les chiffres. Chaque nombre affiché vient d'une API et chaque méthode de calcul est expliquée.
""")

MODULES = [
    ("views/selection_actions.py", "01 · Sélection d'actions", "Goldman Sachs",
     "Top 10 selon ton profil : PER vs secteur, CA sur 5 ans, dette, dividende, avantage concurrentiel, "
     "objectifs à 12 mois, note de risque /10, zones d'entrée et stop-loss."),
    ("views/valorisation_dcf.py", "02 · Valorisation DCF", "Morgan Stanley",
     "Projection 5 ans, FCF, CMPC, valeur terminale (Gordon + multiple), tableaux de sensibilité, verdict."),
    ("views/gestion_du_risque.py", "03 · Gestion du risque", "Bridgewater",
     "Corrélations, concentration, change, taux, stress tests, VaR, liquidité, couvertures, rééquilibrage."),
    ("views/resultats_trimestriels.py", "04 · Résultats trimestriels", "JPMorgan",
     "Historique des surprises, consensus, mouvement implicite des options, réactions passées, décision."),
    ("views/construction_portefeuille.py", "05 · Construction de portefeuille", "BlackRock",
     "Allocation actions/obligations/alternatifs, ETF par enveloppe (PEA, AV, CTO, PER), IPS d'une page."),
    ("views/analyse_technique.py", "06 · Analyse technique", "Citadel",
     "Tendances, supports/résistances, MM 50/100/200, RSI, MACD, Bollinger, figures, Fibonacci, plan de trade."),
    ("views/strategie_dividendes.py", "07 · Stratégie dividendes", "Harvard",
     "15-20 valeurs, sécurité /10, années de hausse, revenu mensuel, intérêts composés sur 10 ans, fiscalité."),
]
cols = st.columns(2)
for i, (path, title, house, desc) in enumerate(MODULES):
    with cols[i % 2].container(border=True):
        st.page_link(path, label=f"**{title}** — style {house}", icon="➡️")
        st.caption(desc)

st.header("Les API intégrées")
apis = pd.DataFrame([
    ["Yahoo Finance (yfinance)", "Gratuit, sans clé", "Cours, volumes, ratios, états financiers (4 ans), dividendes, "
     "résultats et surprises, consensus, objectifs d'analystes, options", "Non officiel ; limites de débit"],
    ["SEC EDGAR XBRL", "Gratuit, sans clé", "Comptes officiels 10-K des sociétés US sur 10+ ans (CA, résultat, dette, FCF)",
     "10 requêtes/s, sociétés US uniquement"],
    ["FRED (Fed de St. Louis)", "Gratuit, sans clé (clé gratuite optionnelle)", "Taux sans risque 10 ans, courbe des taux, "
     "spreads de crédit, VIX, inflation, chômage, taux BCE", "—"],
    ["BCE via Frankfurter", "Gratuit, sans clé", "Taux de change officiels BCE (conversion des devises)", "Quotidien"],
    ["Stooq", "Gratuit, sans clé", "Cours historiques de secours si Yahoo ne répond pas", "Secours"],
    ["Finnhub", "Clé gratuite", "Surprises de BPA, calendrier des résultats, recommandations, actualités",
     "60 requêtes/min"],
    ["Alpha Vantage", "Clé gratuite", "Historique des résultats (BPA publié vs attendu, heure de publication)",
     "25 requêtes/jour"],
    ["Financial Modeling Prep", "Clé gratuite (limitée) / payant", "CA par segment, objectifs de cours consensuels, "
     "estimations, transcriptions (offres payantes)", "250 requêtes/jour en gratuit"],
], columns=["API", "Coût", "Ce qu'elle apporte à l'outil", "Limites"])
ui.table(apis, hide_index=True)

st.header("💎 L'API payante la plus intéressante")
st.markdown("""
**Financial Modeling Prep (offre Premium/Ultimate)** — meilleur rapport qualité/prix pour cet outil :
- 30+ ans d'états financiers **mondiaux** (Europe incluse, là où la SEC ne couvre que les US) ;
- **estimations d'analystes** (CA, BPA) et objectifs de cours, **CA par segment**, **transcriptions des conférences
  de résultats** (la guidance de la direction, impossible à obtenir gratuitement de façon fiable) ;
- API officielle et stable (contrairement à Yahoo), déjà branchée dans l'outil : il suffit d'ajouter la clé `FMP_API_KEY`.

Ordre de prix indicatif : de ~20 à ~150 $/mois selon l'offre (vérifie les tarifs actuels sur leur site).
Alternatives : **EODHD All-in-One** (très bonne couverture Europe), **Polygon/Massive** (données d'options US
temps réel). Niveau institutionnel : **Bloomberg Terminal** (~30 000 $/an), LSEG Workspace ou FactSet.
""")

st.header("État des connexions")
if st.button("Tester toutes les API"):
    from godafret.data.provider import status

    with st.spinner("Test des sources…"):
        ui.table(pd.DataFrame(status()), hide_index=True)

with st.expander("Ajouter des clés API (optionnel)"):
    st.markdown("""
Crée le fichier `.streamlit/secrets.toml` (ou les variables d'environnement du même nom) :
```toml
FINNHUB_API_KEY = "ta_clé"        # https://finnhub.io  (gratuit)
ALPHAVANTAGE_API_KEY = "ta_clé"   # https://www.alphavantage.co  (gratuit)
FMP_API_KEY = "ta_clé"            # https://financialmodelingprep.com
FRED_API_KEY = "ta_clé"           # https://fred.stlouisfed.org  (gratuit, optionnel)
SEC_USER_AGENT = "Ton Nom ton@email.com"
```
Sur Streamlit Community Cloud : *Settings → Secrets* et colle le même contenu.
""")

with st.expander("Limites de risque appliquées (comité des risques)"):
    st.markdown(f"""
- Poids max par ligne : **{LIMITS.max_single_position:.0%}** · par secteur : **{LIMITS.max_sector:.0%}** ·
  par pays : **{LIMITS.max_country:.0%}**
- VaR 99 % à 1 jour : **< {LIMITS.max_var_99_1d:.0%}** du portefeuille
- Perte maximale en scénario de stress : **< {LIMITS.max_drawdown_stress:.0%}**
- Corrélation moyenne : **< {LIMITS.max_avg_correlation:.2f}** · liquidation en **< {LIMITS.max_days_to_liquidate:.0f} jours**
  à {LIMITS.participation_rate:.0%} du volume quotidien
""")
ui.footer()
