"""Univers d'investissement prédéfinis (tickers au format Yahoo Finance)."""

SECTORS_FR = {
    "Technology": "Technologie", "Healthcare": "Santé", "Financial Services": "Finance",
    "Consumer Cyclical": "Conso. cyclique", "Consumer Defensive": "Conso. de base", "Industrials": "Industrie",
    "Energy": "Énergie", "Utilities": "Services publics", "Real Estate": "Immobilier",
    "Basic Materials": "Matériaux", "Communication Services": "Communication", "ETF": "ETF", "Inconnu": "Inconnu",
}

US_LARGE = [
    "AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "META", "AVGO", "TSLA", "BRK-B", "JPM", "V", "MA", "LLY", "UNH",
    "JNJ", "XOM", "CVX", "PG", "HD", "COST", "WMT", "KO", "PEP", "MRK", "ABBV", "ORCL", "CRM", "ADBE", "AMD",
    "NFLX", "TMO", "ABT", "MCD", "CSCO", "ACN", "LIN", "DHR", "TXN", "QCOM", "INTU", "NOW", "AMAT", "ISRG",
    "CAT", "GE", "HON", "UNP", "RTX", "LMT", "BKNG", "SPGI", "BLK", "GS", "MS", "AXP", "SCHW", "PGR", "CB",
    "NEE", "DUK", "SO", "PLD", "AMT", "T", "VZ", "DIS", "NKE", "SBUX", "LOW", "MDT", "BMY", "PFE", "AMGN",
    "GILD", "VRTX", "REGN", "ADP", "MMC", "ZTS", "SHW", "ECL", "APD", "DE", "ETN", "PH", "ITW", "KLAC", "LRCX",
    "PANW", "SNPS", "CDNS", "MCO", "ICE", "CME", "TJX", "ELV", "CI", "SYK", "BSX",
]

CAC40 = [
    "AI.PA", "AIR.PA", "ALO.PA", "MT.AS", "CS.PA", "BNP.PA", "EN.PA", "CAP.PA", "CA.PA", "ACA.PA", "BN.PA",
    "DSY.PA", "EDEN.PA", "ENGI.PA", "EL.PA", "ERF.PA", "RMS.PA", "KER.PA", "OR.PA", "LR.PA", "MC.PA", "ML.PA",
    "ORA.PA", "RI.PA", "PUB.PA", "RNO.PA", "SAF.PA", "SGO.PA", "SAN.PA", "SU.PA", "GLE.PA", "STLAP.PA",
    "STMPA.PA", "TEP.PA", "HO.PA", "TTE.PA", "URW.PA", "VIE.PA", "DG.PA",
]

EUROPE_LEADERS = [
    "ASML.AS", "SAP.DE", "SIE.DE", "ALV.DE", "DTE.DE", "MUV2.DE", "NESN.SW", "NOVN.SW", "ROG.SW", "UBSG.SW",
    "NOVO-B.CO", "AZN.L", "SHEL.L", "HSBA.L", "ULVR.L", "REL.L", "RIO.L", "GSK.L", "IBE.MC", "SAN.MC",
    "ITX.MC", "ISP.MI", "ENEL.MI", "RACE.MI", "ADYEN.AS", "INGA.AS", "ABI.BR", "MC.PA", "OR.PA", "AI.PA",
    "SU.PA", "TTE.PA", "SAN.PA", "AIR.PA", "SAF.PA", "RMS.PA",
]

# Dividendes : "aristocrates" US (≥ 25 ans de hausses) + grandes valeurs européennes
DIVIDEND_US = [
    "JNJ", "PG", "KO", "PEP", "ABBV", "ABT", "ADP", "AFL", "APD", "CAT", "CB", "CL", "CVX", "XOM", "ED", "EMR",
    "GPC", "HRL", "ITW", "KMB", "LOW", "MCD", "MDT", "NUE", "O", "SHW", "SPGI", "SYY", "TGT", "WMT", "LIN",
    "ESS", "FRT", "BDX", "ADM", "CINF", "DOV", "ATO", "BEN", "CLX", "ECL", "EXPD", "GD", "KVUE", "MKC",
    "NDSN", "PNR", "PPG", "ROP", "SJM", "SWK", "TROW", "WST", "BRO", "CHD", "CTAS", "FAST", "IBM", "TXN",
    "VZ", "MO", "PM", "UPS", "HD", "MSFT", "AVGO", "JPM", "NEE",
]
DIVIDEND_EU = [
    "TTE.PA", "SAN.PA", "OR.PA", "AI.PA", "BN.PA", "ORA.PA", "ENGI.PA", "VIE.PA", "SU.PA", "CS.PA", "BNP.PA",
    "ALV.DE", "MUV2.DE", "DTE.DE", "NESN.SW", "NOVN.SW", "ROG.SW", "ZURN.SW", "ULVR.L", "BATS.L", "SHEL.L",
    "GSK.L", "NG.L", "LGEN.L", "IBE.MC", "ENEL.MI", "ISP.MI", "NN.AS", "UNA.AS",
]

UNIVERSES = {
    "Grandes capitalisations US (~100)": US_LARGE,
    "CAC 40": CAC40,
    "Leaders européens": EUROPE_LEADERS,
    "Dividendes US (aristocrates & co)": DIVIDEND_US,
    "Dividendes Europe": DIVIDEND_EU,
}

BENCHMARKS = {"S&P 500 (SPY)": "SPY", "MSCI World (URTH)": "URTH", "MSCI ACWI (ACWI)": "ACWI",
              "CAC 40 (^FCHI)": "^FCHI", "Euro Stoxx 50 (^STOXX50E)": "^STOXX50E"}
