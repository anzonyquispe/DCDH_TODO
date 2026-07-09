"""
Phase 2 — Controls residualization
Mirrors Stata lines ~1219-1423 of did_multiplegt_dyn_final.do.

For each baseline-treatment level d:
  - keep pre-switch (g,t) cells
  - regress long-diff outcome on long-diff controls + time FEs
  - return predicted residuals and coefficient vectors
"""

from __future__ import annotations
import numpy as np
import pandas as pd
from .utils import _safe_inv


def residualize_controls(
    df: pd.DataFrame,
    col: dict,
    controls: list[str],
    lag: int = 1,
) -> dict[int, np.ndarray]:
    """
    Compute per-baseline-level OLS coefficients (θ_d) for control residualization.

    Parameters
    ----------
    df       : working DataFrame (already rectangularized, with _d_sq_int)
    col      : column name map from data_prep
    controls : list of control variable names
    lag      : long-difference lag (=1 for first differences; usually 1)

    Returns
    -------
    dict mapping d_sq_int value → coefficient array (len = len(controls));
    or empty dict if no controls.
    """
    if not controls:
        return {}

    outcome    = col["outcome"]
    group      = col["group"]
    time       = col["time"]
    d_sq_int   = col["d_sq_int"]
    F_g        = col["F_g"]
    N_gt       = col["N_gt_w"]

    coefs: dict[int, np.ndarray] = {}

    for d_level in df[d_sq_int].dropna().unique():
        mask = (df[d_sq_int] == d_level) & (df[time] < df[F_g])

        sub = df[mask].copy().sort_values([group, time])

        # long-diff outcome and controls
        sub["_dy"] = sub.groupby(group)[outcome].diff(lag)
        for c in controls:
            sub[f"_dx_{c}"] = sub.groupby(group)[c].diff(lag)

        sub = sub.dropna(subset=["_dy"] + [f"_dx_{c}" for c in controls])
        if len(sub) == 0:
            continue

        # time fixed-effects as dummies
        time_dummies = pd.get_dummies(sub[time], drop_first=True, dtype=float)
        X_ctrl = sub[[f"_dx_{c}" for c in controls]].values
        X = np.hstack([X_ctrl, time_dummies.values])
        y = sub["_dy"].values
        w = sub[N_gt].values.astype(float)

        # weighted OLS: (X'WX)^{-1} X'Wy
        W = np.diag(w)
        XtW  = X.T @ W
        XtWX = XtW @ X
        inv  = _safe_inv(XtWX)
        if inv is None:
            continue  # singular — skip this baseline level

        theta = inv @ XtW @ y
        # extract only the control part (not time FE coefficients)
        coefs[d_level] = theta[:len(controls)]

    return coefs


def adjust_outcome(
    df: pd.DataFrame,
    col: dict,
    controls: list[str],
    coefs: dict[int, np.ndarray],
    ell: int,
    adj_col: str = "_adj_dy",
) -> pd.DataFrame:
    """
    Subtract the control prediction from the long-diff outcome for effect ℓ.

    Δ̃Y_{g,t} = ΔY_{g,t} - θ_d · ΔX_{g,t}
    """
    if not controls or not coefs:
        df[adj_col] = np.nan
        return df

    outcome  = col["outcome"]
    group    = col["group"]
    time     = col["time"]
    d_sq_int = col["d_sq_int"]

    df = df.copy()
    dy = df.groupby(group)[outcome].diff(ell)
    prediction = pd.Series(0.0, index=df.index)

    for d_level, theta in coefs.items():
        mask = df[d_sq_int] == d_level
        for j, c in enumerate(controls):
            dx = df.groupby(group)[c].diff(ell)
            prediction[mask] += theta[j] * dx[mask]

    df[adj_col] = dy - prediction
    return df
