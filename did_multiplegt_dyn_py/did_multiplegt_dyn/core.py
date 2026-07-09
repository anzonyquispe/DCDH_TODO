"""
Phase 3 & 4 — Core estimation
Compute U_{g,ℓ} (per-group DID contribution) and its variance component
for one horizon ℓ and one switcher direction (in or out).

Mirrors Stata did_multiplegt_dyn_core_new  (lines ~4595-5600).
"""

from __future__ import annotations
import numpy as np
import pandas as pd


def _control_mask(
    df: pd.DataFrame,
    col: dict,
    ell: int,
    *,
    only_never_switchers: bool,
    trends_nonparam: str | None,
) -> pd.Series:
    """
    True for (g,t) cells that qualify as controls for effect ℓ:
      - F_g > t  (has not switched by t)
      - ΔY_{g,ℓ} observed  (outcome non-missing at t and t-ℓ)
    """
    time    = col["time"]
    F_g     = col["F_g"]
    outcome = col["outcome"]
    group   = col["group"]

    dy = df.groupby(group)[outcome].diff(ell)
    ctrl = (df[F_g] > df[time]) & dy.notna()

    if only_never_switchers:
        T_max = df[col["time"]].max()
        ctrl &= (df[F_g] >= T_max + 1)

    return ctrl


def compute_effect(
    df: pd.DataFrame,
    col: dict,
    scalars: dict,
    ell: int,
    s_dir: int,                  # 1 = switcher-in, 0 = switcher-out
    *,
    controls: list[str] | None = None,
    coefs: dict | None = None,
    same_switchers: bool = False,
    same_switchers_pl: bool = False,
    l_total: int = 1,
    only_never_switchers: bool = False,
    trends_nonparam: str | None = None,
    normalized: bool = False,
    continuous: int = 0,
) -> dict | None:
    """
    Compute the ℓ-th dynamic effect contribution for switcher direction s_dir.

    Returns a dict with:
        effect     : DID estimate
        se_sq      : variance estimate (before dividing by G²)
        N_obs      : # (g,t) observations in distance_to_switch
        N_switchers: # switcher groups
        U_g        : per-group U_{g,ℓ} Series
        U_g_var    : per-group variance component Series
        delta_avg  : mean treatment change (for normalization)
    """
    controls = controls or []
    coefs    = coefs or {}

    group    = col["group"]
    time     = col["time"]
    outcome  = col["outcome"]
    treatment= col["treatment"]
    F_g      = col["F_g"]
    T_g      = col["T_g"]
    L_g      = col["L_g"]
    S_g      = col["S_g"]
    d_sq     = col["d_sq"]
    d_sq_int = col["d_sq_int"]
    N_gt_w   = col["N_gt_w"]
    T_max    = scalars["T_max"]
    G        = scalars["G"]

    # ── long-diff outcome (ΔY_{g,t,ℓ}) ────────────────────────────────────────
    dy = df.groupby(group)[outcome].diff(ell).rename("_dy")
    df = df.copy()
    df["_dy"] = dy

    # ── control indicator ──────────────────────────────────────────────────────
    ctrl = _control_mask(df, col, ell,
                         only_never_switchers=only_never_switchers,
                         trends_nonparam=trends_nonparam)
    df["_ctrl"] = ctrl.astype(float)

    # ── count controls per (time, d_sq, [trends_nonparam]) ────────────────────
    strat = [time, d_sq_int]
    if trends_nonparam:
        strat.append(trends_nonparam)
    df["_N_ctrl"] = (df.groupby(strat)["_N_gt_w"]
                     .transform(lambda s: (s * df.loc[s.index, "_ctrl"]).sum())
                     if "_N_gt_w" in df.columns
                     else df.groupby(strat)["_ctrl"].transform("sum"))
    # also count within (time, d_sq, group) for demeaning
    df["_N_ctrl_g"] = df.groupby(strat + [group])["_ctrl"].transform("sum")

    # ── distance-to-switch indicator ───────────────────────────────────────────
    at_horizon = df[time] == (df[F_g] - 1 + ell)
    within_Lg  = ell <= df[L_g]
    right_dir  = df[S_g] == s_dir
    has_ctrl   = df["_N_ctrl"] > 0

    dy_ok = df["_dy"].notna()

    if same_switchers:
        # group must survive ALL l_total effects
        def _can_all(grp):
            fg  = grp[F_g].iloc[0]
            tg  = grp[T_g].iloc[0]
            return pd.Series(fg - 1 + l_total <= tg, index=grp.index)
        df["_still_sw"] = df.groupby(group, group_keys=False).apply(_can_all)
        dist = at_horizon & within_Lg & right_dir & has_ctrl & dy_ok & df["_still_sw"]
    else:
        dist = at_horizon & within_Lg & right_dir & has_ctrl & dy_ok

    df["_dist"] = dist.astype(float)

    switcher_obs = df[df["_dist"] == 1]
    N_obs      = int(switcher_obs["_N_gt_w"].sum())
    N_switchers= switcher_obs[group].nunique()

    if N_switchers == 0:
        return None

    # ── control mean Δy per (time, d_sq, [trends_nonparam]) ──────────────────
    df["_ctrl_dy"] = df["_dy"] * df["_ctrl"]
    ctrl_sum_dy = df.groupby(strat)["_ctrl_dy"].transform("sum")
    ctrl_sum_N  = df.groupby(strat)["_ctrl"].transform("sum").replace(0, np.nan)
    df["_ctrl_mean_dy"] = ctrl_sum_dy / ctrl_sum_N

    # per-group share of control at time t
    df["_ctrl_g_share"] = (
        df.groupby(strat)["_N_ctrl_g"].transform("sum")
        / df["_N_ctrl"].replace(0, np.nan)
    )

    # ── residualize controls if needed ─────────────────────────────────────────
    if controls and coefs:
        for d_level, theta in coefs.items():
            mask = df[d_sq_int] == d_level
            adj = pd.Series(0.0, index=df.index)
            for j, c in enumerate(controls):
                dx = df.groupby(group)[c].diff(ell)
                adj[mask] += theta[j] * dx[mask]
            df.loc[mask, "_dy"] -= adj[mask]

    # ── U_{g,t,ℓ} = (ΔY_gt - ctrl_mean) * dist ───────────────────────────────
    #   summed over t within g gives U_{g,ℓ}
    df["_U_gt"] = (df["_dy"] - df["_ctrl_mean_dy"]) * df["_dist"]

    # per-group weight factor (1/N_switchers_in_stratum · N_gt)
    df["_N_s_t"] = df.groupby(strat)["_dist"].transform("sum").replace(0, np.nan)
    df["_ctrl_contribution"] = (df["_dist"] / df["_N_s_t"]) * df["_ctrl_mean_dy"]

    U_g = df.groupby(group)["_U_gt"].sum()
    U_g = U_g[U_g.index.isin(switcher_obs[group].unique())]

    # ── variance component U_{g,ℓ}^{var} ──────────────────────────────────────
    df["_U_gt_var"] = df["_U_gt"] ** 2  # simple squared contribution
    U_g_var = df.groupby(group)["_U_gt_var"].sum()
    U_g_var = U_g_var[U_g_var.index.isin(U_g.index)]

    # ── effect = (1/G) * sum U_g ──────────────────────────────────────────────
    effect = U_g.sum() / G
    se_sq  = U_g_var.sum() / (G ** 2)

    # ── delta_avg: mean treatment change (for normalization) ──────────────────
    d_sq_orig = col.get("d_sq_orig", d_sq)
    df["_delta"] = np.where(
        df["_dist"] == 1,
        (df[treatment] - df[d_sq_orig]).abs(),
        np.nan
    )
    delta_avg = df["_delta"].mean()

    return dict(
        effect      = float(effect),
        se_sq       = float(se_sq),
        N_obs       = N_obs,
        N_switchers = N_switchers,
        U_g         = U_g,
        U_g_var     = U_g_var,
        delta_avg   = float(delta_avg) if pd.notna(delta_avg) else 1.0,
    )
