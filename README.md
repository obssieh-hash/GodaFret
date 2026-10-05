# GodaFret

Ce dépôt contient deux projets :

| Dossier | Contenu |
|---|---|
| [`mobile/`](mobile/README.md) | **GodaFret Banque** : application mobile Flutter (connexion + PIN, MFA/OTP, solde, dépôt, retrait, transfert interne, prêt, échéancier, remboursement, historique, notifications, tableau de bord) sur Apache Fineract |
| [`infra/`](infra/README.md) | Serveur Ubuntu : Fineract + Mifos X + PostgreSQL + Keycloak (MFA) + Caddy, en Docker Compose |
| racine | Desk d'investissement GodaFret (Streamlit), décrit ci-dessous |

# GodaFret — Desk d'investissement

Outil d'analyse d'investissement qui calcule avec **de vraies données de marché** les 7 méthodes
« banque d'investissement » suivantes :

| # | Module | Inspiré de | Ce qu'il calcule |
|---|---|---|---|
| 00 | **Mon conseiller** (page d'accueil) | Conseiller patrimonial + risk manager | Répond à quelques questions sur ta situation et ton comportement face au risque, puis te dit quoi faire dans l'ordre : rembourser les crédits chers, épargne de précaution, puis montant exact par ETF et par enveloppe (PEA, assurance-vie, CTO, PER), rythme d'investissement selon le marché, virement mensuel et règles de risque |
| 01 | Sélection d'actions | Goldman Sachs | Top 10 selon ton profil, PER vs médiane du secteur, CA sur 5 ans, dette/capitaux propres, rendement et sécurité du dividende, avantage concurrentiel (faible/modéré/fort), objectifs à 12 mois haussier/baissier, note de risque /10 justifiée, zone d'entrée et stop-loss, répartition du capital |
| 02 | Valorisation DCF | Morgan Stanley | Projection du CA sur 5 ans, marges, FCFF année par année, CMPC (CAPM + bêta de Blume), valeur terminale par Gordon **et** par multiple de sortie, contrôles de cohérence croisés, sensibilité CMPC × g et CMPC × multiple, scénarios, verdict, hypothèses fragiles |
| 03 | Gestion du risque | Bridgewater | Corrélations, concentration secteur/pays/devise, cours convertis en EUR (risque de change inclus), sensibilité aux taux (régression sur le 10 ans US), 5 crises historiques rejouées et 5 scénarios hypothétiques, VaR/CVaR (historique, normale, Cornish-Fisher, Monte-Carlo Student-t), probabilités de pertes extrêmes (bootstrap), liquidité, contributions au risque, contrôle des limites, couvertures chiffrées, rééquilibrage (parité de risque, variance minimale, Sharpe max) |
| 04 | Résultats trimestriels | JPMorgan | 8 derniers trimestres publiés vs attendus, consensus BPA/CA, révisions des analystes, mouvement implicite des options (straddle), réaction du cours après chaque publication, scénarios, décision acheter avant / vendre avant / attendre |
| 05 | Construction de portefeuille | BlackRock | Allocation actions/obligations/alternatifs, ETF par enveloppe (PEA, assurance-vie, CTO, PER), cœur/satellites, rendement attendu, mauvaise année, backtest, rééquilibrage, fiscalité, plan d'investissement mensuel (Monte-Carlo), indice de référence, politique d'investissement d'une page |
| 06 | Analyse technique | Citadel | Tendances jour/semaine/mois, supports/résistances, MM 50/100/200 et croisements, RSI, MACD, Bollinger, volumes et OBV, figures chartistes, Fibonacci, plan de trade (repli ou cassure), ratio rendement/risque, taille de position, note achat fort → vente forte |
| 07 | Stratégie dividendes | Fonds de Harvard | 15-20 valeurs, sécurité /10, années consécutives de hausse, taux de distribution BPA et FCF, revenu mensuel net, plafond sectoriel, croissance des dividendes, intérêts composés sur 10 ans, fiscalité française par enveloppe, classement du plus sûr au plus agressif |

Chaque page génère un rapport téléchargeable (Markdown).

## API intégrées

| API | Coût | Utilisation |
|---|---|---|
| Yahoo Finance (yfinance) | gratuit, sans clé | cours, ratios, états financiers, dividendes, résultats, consensus, options |
| SEC EDGAR XBRL | gratuit, sans clé | comptes officiels 10-K des sociétés US sur 10+ ans |
| FRED (Fed de St. Louis) | gratuit, sans clé | taux sans risque, courbe des taux, macro |
| BCE via Frankfurter | gratuit, sans clé | taux de change officiels (actuels et historiques) |
| Stooq | gratuit, sans clé | cours de secours |
| Finnhub | clé gratuite | surprises de BPA, calendrier, actualités |
| Alpha Vantage | clé gratuite (25 req/jour) | historique des résultats |
| Financial Modeling Prep | clé gratuite limitée / payant | CA par segment, objectifs de cours |

Si une source ne répond pas, l'outil bascule automatiquement sur la suivante.

### L'API payante la plus intéressante

**Financial Modeling Prep (offre Premium/Ultimate)** : états financiers mondiaux sur 30+ ans,
estimations d'analystes, CA par segment et transcriptions des conférences de résultats (la guidance
de la direction). Elle est déjà branchée : il suffit d'ajouter `FMP_API_KEY`. Alternatives :
EODHD (Europe), Polygon/Massive (options US). Niveau institutionnel : Bloomberg Terminal.

## Lancer l'outil

```bash
pip install -r requirements.txt
streamlit run streamlit_app.py
```

### En ligne, gratuitement (accessible depuis le téléphone)

1. Va sur https://share.streamlit.io et connecte ton compte GitHub.
2. *Create app* → dépôt `GodaFret`, fichier principal `streamlit_app.py`.
3. Optionnel : *Settings → Secrets* et colle le contenu de `.streamlit/secrets.toml.example` avec tes clés.

## Tests

```bash
pip install -r requirements-dev.txt
pytest
```

Les tests utilisent des données de marché synthétiques : ils vérifient les calculs (DCF contre la formule exacte,
VaR, optimiseur, dividendes…) et exécutent chaque page sans accès réseau.

## Limites de risque par défaut

10 % max par ligne, 30 % par secteur, 60 % par pays, VaR 99 % à 1 jour < 3 %, perte en stress < 35 %,
corrélation moyenne < 0,60, liquidation en moins de 5 jours. Modifiables dans `godafret/config.py`
et sur la page Gestion du risque.

## Avertissement

Outil d'aide à la décision, pas un conseil en investissement personnalisé. Les données gratuites peuvent
comporter des erreurs ou des retards ; vérifie toujours les chiffres clés avant d'investir. La fiscalité
(`godafret/config.py`, `FrenchTax`) est paramétrée pour 2026 et doit être revue chaque année.
