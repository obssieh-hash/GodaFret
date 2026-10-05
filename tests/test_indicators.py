import numpy as np
import pandas as pd

from godafret.analytics import indicators as ind


def test_rsi_extremes():
    up = pd.Series(np.arange(1, 60, dtype=float))
    assert ind.rsi(up).iloc[-1] == 100
    down = pd.Series(np.arange(60, 1, -1, dtype=float))
    assert ind.rsi(down).iloc[-1] < 1


def test_max_drawdown_and_cagr():
    s = pd.Series([100, 120, 60, 90], index=pd.date_range("2020-01-01", periods=4))
    assert abs(ind.max_drawdown(s) + 0.5) < 1e-12
    assert abs(ind.cagr(100, 121, 2) - 0.10) < 1e-12


def test_macd_bollinger_shapes():
    s = pd.Series(np.linspace(1, 2, 200))
    m = ind.macd(s)
    b = ind.bollinger(s)
    assert {"macd", "signal", "hist"} <= set(m.columns)
    assert (b["upper"].dropna() >= b["lower"].dropna()).all()


def test_beta_of_scaled_series_is_scale():
    rng = np.random.default_rng(0)
    m = pd.Series(rng.normal(0, 0.01, 500))
    assert abs(ind.beta(1.5 * m, m) - 1.5) < 1e-9
