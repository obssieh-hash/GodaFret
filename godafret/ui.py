"""Composants d'interface Streamlit partagés."""
from __future__ import annotations

import math

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

DISCLAIMER = ("Outil d'aide à la décision : les données gratuites peuvent comporter des erreurs ou des retards "
              "et les projections ne garantissent rien. Ceci n'est pas un conseil en investissement personnalisé "
              "au sens réglementaire ; vérifie toujours les chiffres clés avant d'engager de l'argent.")

COLORS = {"up": "#1a7f37", "down": "#cf222e", "neutral": "#6e7781", "accent": "#0969da"}


def setup(title: str, subtitle: str = "") -> None:
    st.set_page_config(page_title=f"{title} · GodaFret", page_icon="📈", layout="wide")
    st.title(title)
    if subtitle:
        st.caption(subtitle)


def footer() -> None:
    st.divider()
    st.caption("⚠️ " + DISCLAIMER)


def pct(x, d: int = 1) -> str:
    try:
        if x is None or math.isnan(float(x)):
            return "—"
        if math.isinf(float(x)):
            return "∞"
        return f"{float(x) * 100:.{d}f} %"
    except (TypeError, ValueError):
        return "—"


def num(x, d: int = 2) -> str:
    try:
        if x is None or math.isnan(float(x)):
            return "—"
        return f"{float(x):,.{d}f}".replace(",", " ")
    except (TypeError, ValueError):
        return "—"


def money(x, ccy: str = "€", d: int = 0) -> str:
    s = num(x, d)
    return s if s == "—" else f"{s} {ccy}"


def big(x, ccy: str = "") -> str:
    try:
        x = float(x)
    except (TypeError, ValueError):
        return "—"
    if math.isnan(x):
        return "—"
    for div, suf in ((1e12, " T"), (1e9, " Md"), (1e6, " M"), (1e3, " k")):
        if abs(x) >= div:
            return f"{x / div:,.2f}{suf} {ccy}".strip()
    return f"{x:,.0f} {ccy}".strip()


def table(df: pd.DataFrame, pcts=(), nums=(), money_cols=(), bigs=(), height: int | None = None, **kw) -> None:
    fmt = {}
    for c in pcts:
        if c in df:
            fmt[c] = pct
    for c in nums:
        if c in df:
            fmt[c] = num
    for c in money_cols:
        if c in df:
            fmt[c] = lambda v: num(v, 0)
    for c in bigs:
        if c in df:
            fmt[c] = big
    sty = df.style.format(fmt, na_rep="—")
    if height is not None:
        kw["height"] = height
    st.dataframe(sty, width="stretch", **kw)


def heatmap(df: pd.DataFrame, title: str = "", zmin=None, zmax=None, colorscale="RdYlGn_r", fmt=".2f",
            height: int | None = None) -> go.Figure:
    fig = go.Figure(go.Heatmap(z=df.values, x=list(df.columns), y=list(df.index), colorscale=colorscale,
                               zmin=zmin, zmax=zmax, text=df.values, texttemplate="%{text:" + fmt + "}",
                               hovertemplate="%{y} / %{x} : %{z:" + fmt + "}<extra></extra>"))
    fig.update_layout(title=title, height=height or max(320, 38 * len(df) + 120), margin=dict(l=10, r=10, t=40, b=10))
    return fig


def bar(series: pd.Series, title: str = "", as_pct: bool = True, color: str | None = None) -> go.Figure:
    fig = go.Figure(go.Bar(x=list(series.index), y=series.values,
                           marker_color=color or COLORS["accent"],
                           text=[pct(v) if as_pct else num(v) for v in series.values], textposition="outside"))
    fig.update_layout(title=title, height=360, margin=dict(l=10, r=10, t=40, b=10),
                      yaxis_tickformat=".0%" if as_pct else None)
    return fig


def pie(series: pd.Series, title: str = "") -> go.Figure:
    fig = go.Figure(go.Pie(labels=list(series.index), values=series.values, hole=0.45, textinfo="label+percent"))
    fig.update_layout(title=title, height=380, margin=dict(l=10, r=10, t=40, b=10), showlegend=False)
    return fig


def verdict_badge(text: str, good: bool | None) -> None:
    color = COLORS["up"] if good else COLORS["down"] if good is False else COLORS["neutral"]
    st.markdown(f"<div style='padding:14px 18px;border-radius:10px;background:{color};color:white;"
                f"font-size:1.4rem;font-weight:700;text-align:center'>{text}</div>", unsafe_allow_html=True)


def download_md(label: str, content: str, filename: str) -> None:
    st.download_button(label, content.encode("utf-8"), file_name=filename, mime="text/markdown")


def df_to_md(df: pd.DataFrame, pcts=(), nums=(), index: bool = True) -> str:
    d = df.copy()
    for c in pcts:
        if c in d:
            d[c] = d[c].map(pct)
    for c in nums:
        if c in d:
            d[c] = d[c].map(num)
    return d.to_markdown(index=index)


def run_safely(fn, *args, **kwargs):
    """Affiche une erreur lisible au lieu d'une trace Python."""
    try:
        return fn(*args, **kwargs)
    except Exception as exc:
        st.error(f"Impossible de terminer l'analyse : {exc}")
        st.info("Vérifie le ticker (format Yahoo : AAPL, MC.PA, SAP.DE, NESN.SW…) et ta connexion. "
                "Les API gratuites limitent parfois le nombre de requêtes : réessaie dans une minute.")
        return None
