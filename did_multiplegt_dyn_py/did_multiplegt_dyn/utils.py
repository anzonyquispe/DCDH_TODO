"""Shared utility helpers."""

from __future__ import annotations
import numpy as np
import pandas as pd


def _to_int_groups(series: pd.Series) -> pd.Series:
    """Map arbitrary group values to consecutive integers starting at 1."""
    codes, _ = pd.factorize(series, sort=True)
    return pd.Series(codes + 1, index=series.index, dtype=np.int64)


def _rectangularize(df: pd.DataFrame, gvar: str, tvar: str) -> pd.DataFrame:
    """Return a complete (g, t) grid; new rows get NaN for all other columns."""
    idx = pd.MultiIndex.from_product(
        [df[gvar].unique(), df[tvar].unique()], names=[gvar, tvar]
    )
    return df.set_index([gvar, tvar]).reindex(idx).reset_index()


def _lag(series: pd.Series, n: int, group_index: pd.Series) -> pd.Series:
    """Lag `series` by `n` periods within groups defined by `group_index`."""
    df_tmp = pd.DataFrame({"g": group_index, "v": series})
    return df_tmp.groupby("g")["v"].shift(n)


def _long_diff(series: pd.Series, n: int, group_index: pd.Series) -> pd.Series:
    """Y_{g,t} - Y_{g,t-n}."""
    return series - _lag(series, n, group_index)


def _safe_inv(mat: np.ndarray) -> np.ndarray | None:
    """Return matrix inverse; None if singular (det <= 1e-16)."""
    if abs(np.linalg.det(mat)) <= 1e-16:
        return None
    return np.linalg.inv(mat)


def _chi2_pval(stat: float, df: int) -> float:
    from scipy.stats import chi2
    if not np.isfinite(stat) or df <= 0:
        return np.nan
    return float(1.0 - chi2.cdf(stat, df))


def _normal_quantile(ci_level: int) -> float:
    from scipy.stats import norm
    alpha = 1.0 - ci_level / 100.0
    return float(norm.ppf(1.0 - alpha / 2.0))
