"""
did_multiplegt_dyn — main entry point
Python port of did_multiplegt_dyn_final.do (de Chaisemartin & D'Haultfoeuille 2024).
"""

from __future__ import annotations
import warnings
import numpy as np
import pandas as pd

from .data_prep  import prepare
from .controls   import residualize_controls
from .core       import compute_effect
from .avg_time   import compute_avg_time_periods
from .results    import DIDResult
from .utils      import _chi2_pval, _normal_quantile


# ──────────────────────────────────────────────────────────────────────────────
def did_multiplegt_dyn(
    df: pd.DataFrame,
    outcome: str,
    group: str,
    time: str,
    treatment: str,
    *,
    # ── core ──────────────────────────────────────────────────────────────────
    effects: int = 1,
    placebo: int = 0,
    # ── sample / design restrictions ──────────────────────────────────────────
    switchers: str = "",                  # "" | "in" | "out"
    only_never_switchers: bool = False,
    dont_drop_larger_lower: bool = False,
    # ── conditioning ──────────────────────────────────────────────────────────
    controls: str | list[str] | None = None,
    trends_nonparam: str | None = None,
    weight: str | None = None,
    cluster: str | None = None,
    # ── estimation variants ───────────────────────────────────────────────────
    normalized: bool = False,
    same_switchers: bool = False,
    same_switchers_pl: bool = False,
    continuous: int = 0,
    trends_lin: bool = False,
    less_conservative_se: bool = False,
    # ── inference ─────────────────────────────────────────────────────────────
    ci_level: int = 95,
    effects_equal: str = "",
    # ── avg_time_periods ──────────────────────────────────────────────────────
    avg_time_periods: bool = False,
    # ── output ────────────────────────────────────────────────────────────────
    graph_off: bool = False,
    save_results: str | None = None,
    # ── stubs (advanced options, not yet implemented) ─────────────────────────
    bootstrap: tuple | None = None,
    predict_het: list | None = None,
    by: str | None = None,
    by_path: str | int | None = None,
    design: str | None = None,
    save_sample: bool = False,
    drop_if_d_miss_before_first_switch: bool = False,
) -> DIDResult:
    """
    Estimate dynamic DiD effects following de Chaisemartin & D'Haultfoeuille (2024).

    Parameters
    ----------
    df         : pandas DataFrame
    outcome    : outcome variable name
    group      : group (unit) variable name
    time       : time variable name
    treatment  : treatment variable name
    effects    : number of dynamic effects to estimate
    placebo    : number of placebo (pre-trend) estimates
    switchers  : restrict to switchers-in ("in"), switchers-out ("out"), or both ("")
    ... (see docstring of each option in the Stata help file)

    Returns
    -------
    DIDResult object with Effect_k, se_effect_k, lb/ub, N_switchers_effect_k, etc.
    """
    if isinstance(controls, str):
        controls = [controls]
    controls = list(controls or [])

    # ── stub warnings ─────────────────────────────────────────────────────────
    for opt, name in [
        (bootstrap,   "bootstrap"),
        (predict_het, "predict_het"),
        (by,          "by"),
        (by_path,     "by_path"),
        (design,      "design"),
    ]:
        if opt is not None:
            warnings.warn(
                f"Option '{name}' is not yet implemented in the Python version.",
                stacklevel=2,
            )

    if trends_lin:
        warnings.warn(
            "trends_lin is not yet implemented in the Python version.",
            stacklevel=2,
        )

    # ── Phase 1: data preparation ─────────────────────────────────────────────
    prep = prepare(
        df, outcome, group, time, treatment,
        weight=weight, controls=controls,
        trends_nonparam=trends_nonparam,
        cluster=cluster,
        continuous=continuous,
        dont_drop_larger_lower=dont_drop_larger_lower,
        only_never_switchers=only_never_switchers,
        drop_if_d_miss_before_first_switch=drop_if_d_miss_before_first_switch,
    )

    wdf     = prep["df"]
    scalars = prep["scalars"]
    col     = prep["col"]
    G       = scalars["G"]
    T_max   = scalars["T_max"]
    l_u     = scalars["l_u"]
    l_a     = scalars["l_a"]

    # clamp requested effects to feasible
    l_max = max(l_u, l_a)
    if effects > l_max:
        warnings.warn(
            f"effects={effects} exceeds maximum feasible ({l_max}). Clamping.",
            stacklevel=2,
        )
    l_XX = min(effects, l_max)

    # clamp placebos
    l_pl_max = max(0, min(l_u, l_a))  # conservative: must have both directions
    l_placebo_XX = min(placebo, l_pl_max) if placebo > 0 else 0

    # ── Phase 2: controls residualization ─────────────────────────────────────
    coefs = residualize_controls(wdf, col, controls, lag=1)

    # ── Phase 3–4: per-effect estimation ──────────────────────────────────────
    z = _normal_quantile(ci_level)
    res = DIDResult()

    # store dimension scalars
    res.l_XX         = l_XX
    res.l_placebo_XX = l_placebo_XX

    # aggregation accumulators for Av_tot_effect
    num_avg = 0.0
    den_avg = 0.0

    # covariance matrix data for joint tests
    U_g_all   : list[pd.Series] = []   # one per effect
    U_g_pl_all: list[pd.Series] = []   # one per placebo

    for ell in range(1, l_XX + 1):
        in_res  = (compute_effect(wdf, col, scalars, ell, 1,
                                  controls=controls, coefs=coefs,
                                  same_switchers=same_switchers,
                                  l_total=l_XX,
                                  only_never_switchers=only_never_switchers,
                                  trends_nonparam=trends_nonparam,
                                  normalized=normalized,
                                  continuous=continuous)
                   if switchers in ("", "in") else None)

        out_res = (compute_effect(wdf, col, scalars, ell, 0,
                                  controls=controls, coefs=coefs,
                                  same_switchers=same_switchers,
                                  l_total=l_XX,
                                  only_never_switchers=only_never_switchers,
                                  trends_nonparam=trends_nonparam,
                                  normalized=normalized,
                                  continuous=continuous)
                   if switchers in ("", "out") else None)

        if in_res is None and out_res is None:
            break

        # ── aggregate ──────────────────────────────────────────────────────
        N_in  = in_res["N_obs"]   if in_res  else 0
        N_out = out_res["N_obs"]  if out_res else 0
        N_tot = N_in + N_out

        if N_tot == 0:
            break

        w_in  = N_in  / N_tot
        w_out = N_out / N_tot

        eff_in  = in_res["effect"]    if in_res  else 0.0
        eff_out = out_res["effect"]   if out_res else 0.0
        effect  = w_in * eff_in + w_out * eff_out

        var_in  = in_res["se_sq"]   if in_res  else 0.0
        var_out = out_res["se_sq"]  if out_res else 0.0
        var_tot = w_in**2 * var_in + w_out**2 * var_out
        se      = np.sqrt(var_tot)

        # ── normalization ──────────────────────────────────────────────────
        if normalized:
            delta = (w_in  * (in_res["delta_avg"]  if in_res  else 1.0) +
                     w_out * (out_res["delta_avg"] if out_res else 1.0))
            if delta > 0:
                effect /= delta
                se     /= delta

        # ── store effect ───────────────────────────────────────────────────
        setattr(res, f"Effect_{ell}",             effect)
        setattr(res, f"se_effect_{ell}",           se)
        setattr(res, f"lb_effect_{ell}",           effect - z * se)
        setattr(res, f"ub_effect_{ell}",           effect + z * se)
        setattr(res, f"N_effect_{ell}",            N_tot)
        setattr(res, f"N_switchers_effect_{ell}",
                (in_res["N_switchers"] if in_res else 0) +
                (out_res["N_switchers"] if out_res else 0))

        # accumulate for average effect
        num_avg += effect
        den_avg += 1

        # covariance data (one series per effect, aligned on group index)
        U_g_ell = pd.concat(
            [x["U_g"] for x in [in_res, out_res] if x is not None]
        ).groupby(level=0).sum()
        U_g_all.append(U_g_ell / G)

    # ── average cumulative effect ─────────────────────────────────────────────
    if den_avg > 0 and not trends_lin:
        Av = num_avg / den_avg
        # SE of average = sqrt(mean of variances / l²)  (rough; no cross-terms)
        var_sum = sum(
            getattr(res, f"se_effect_{k}", 0.0) ** 2
            for k in range(1, l_XX + 1)
            if hasattr(res, f"se_effect_{k}")
        )
        se_av = np.sqrt(var_sum) / den_avg
        res.Av_tot_effect       = float(Av)
        res.se_avg_total_effect = float(se_av)
        res.lb_avg_total_effect = float(Av - z * se_av)
        res.ub_avg_total_effect = float(Av + z * se_av)

    # ── placebos ──────────────────────────────────────────────────────────────
    for ell_pl in range(1, l_placebo_XX + 1):
        # Placebos use negative lag: ΔY_{g, F_g-1 - (ell_pl-1), ell_pl}
        in_pl  = (compute_effect(wdf, col, scalars, ell_pl, 1,
                                 controls=controls, coefs=coefs,
                                 same_switchers=same_switchers or same_switchers_pl,
                                 l_total=l_XX,
                                 only_never_switchers=only_never_switchers,
                                 trends_nonparam=trends_nonparam)
                  if switchers in ("", "in") else None)
        out_pl = (compute_effect(wdf, col, scalars, ell_pl, 0,
                                 controls=controls, coefs=coefs,
                                 same_switchers=same_switchers or same_switchers_pl,
                                 l_total=l_XX,
                                 only_never_switchers=only_never_switchers,
                                 trends_nonparam=trends_nonparam)
                  if switchers in ("", "out") else None)

        if in_pl is None and out_pl is None:
            break

        N_in  = in_pl["N_obs"]  if in_pl  else 0
        N_out = out_pl["N_obs"] if out_pl else 0
        N_tot = N_in + N_out
        if N_tot == 0:
            break

        w_in  = N_in / N_tot
        w_out = N_out / N_tot
        eff   = (w_in  * (in_pl["effect"]  if in_pl  else 0.0) +
                 w_out * (out_pl["effect"] if out_pl else 0.0))
        var   = (w_in**2 * (in_pl["se_sq"]  if in_pl  else 0.0) +
                 w_out**2 * (out_pl["se_sq"] if out_pl else 0.0))
        se    = np.sqrt(var)

        setattr(res, f"Placebo_{ell_pl}",            eff)
        setattr(res, f"se_placebo_{ell_pl}",          se)
        setattr(res, f"lb_placebo_{ell_pl}",          eff - z * se)
        setattr(res, f"ub_placebo_{ell_pl}",          eff + z * se)
        setattr(res, f"N_switchers_placebo_{ell_pl}",
                (in_pl["N_switchers"]  if in_pl  else 0) +
                (out_pl["N_switchers"] if out_pl else 0))

        U_g_ell = pd.concat(
            [x["U_g"] for x in [in_pl, out_pl] if x is not None]
        ).groupby(level=0).sum()
        U_g_pl_all.append(U_g_ell / G)

    # ── joint hypothesis tests ────────────────────────────────────────────────
    if len(U_g_all) >= 2:
        Sigma, theta = _build_vcov(U_g_all, G)
        res.p_jointeffects = _joint_null_pval(theta, Sigma)

    if len(U_g_pl_all) >= 2:
        Sigma_pl, theta_pl = _build_vcov(U_g_pl_all, G)
        res.p_jointplacebo = _joint_null_pval(theta_pl, Sigma_pl)

    # ── effects_equal ─────────────────────────────────────────────────────────
    if effects_equal and len(U_g_all) >= 2:
        if effects_equal == "all":
            lb_eq, ub_eq = 1, l_XX
        else:
            parts = effects_equal.split(",")
            lb_eq, ub_eq = int(parts[0]), int(parts[1])
        idx = [k - 1 for k in range(lb_eq, ub_eq + 1) if k - 1 < len(U_g_all)]
        if len(idx) >= 2:
            U_sub = [U_g_all[i] for i in idx]
            Sigma_eq, theta_eq = _build_vcov(U_sub, G)
            res.p_equality_effects = _equality_pval(theta_eq, Sigma_eq)

    # ── avg_time_periods ──────────────────────────────────────────────────────
    if avg_time_periods:
        atp = compute_avg_time_periods(
            wdf, col, scalars, l_XX,
            switchers_dir=switchers,
            same_switchers=same_switchers,
            continuous=continuous,
        )
        res.avg_cumul = atp["avg_cumul"]
        for k in range(1, l_XX + 1):
            setattr(res, f"N_switch_avg_{k}", atp["nswitch"][k])

        print(f"Average number of time periods over which a treatment's "
              f"effect is accumulated = {atp['avg_cumul']:.4f}")
        print("Number of switchers per effect (avg_time_periods):")
        for k in range(1, l_XX + 1):
            print(f"   Effect_{k} : {atp['nswitch'][k]:.0f}")

    return res


# ──────────────────────────────────────────────────────────────────────────────
def _build_vcov(
    U_g_list: list[pd.Series], G: int
) -> tuple[np.ndarray, np.ndarray]:
    """
    Build variance-covariance matrix and effect vector from per-group U_{g,ℓ}.
    Σ_ℓℓ' = (1/G²) Σ_g U_{g,ℓ} U_{g,ℓ'}
    """
    l = len(U_g_list)
    all_groups = sorted(set().union(*[s.index for s in U_g_list]))
    U_mat = np.zeros((len(all_groups), l))
    idx_map = {g: i for i, g in enumerate(all_groups)}
    for col_i, ser in enumerate(U_g_list):
        for g, v in ser.items():
            U_mat[idx_map[g], col_i] = v

    Sigma = (U_mat.T @ U_mat) / (G ** 2)
    theta = U_mat.mean(axis=0)
    return Sigma, theta


def _joint_null_pval(theta: np.ndarray, Sigma: np.ndarray) -> float:
    """χ² test: H₀: θ = 0."""
    try:
        inv = np.linalg.inv(Sigma)
        stat = float(theta @ inv @ theta) * len(theta)
    except np.linalg.LinAlgError:
        return np.nan
    return _chi2_pval(stat, len(theta))


def _equality_pval(theta: np.ndarray, Sigma: np.ndarray) -> float:
    """χ² test: H₀: all elements of θ equal (demeaned version)."""
    l = len(theta)
    D = np.eye(l) - np.ones((l, l)) / l
    theta_d = D @ theta
    Sigma_d = D @ Sigma @ D.T
    try:
        inv = np.linalg.pinv(Sigma_d)
        stat = float(theta_d @ inv @ theta_d)
    except Exception:
        return np.nan
    return _chi2_pval(stat, l - 1)
