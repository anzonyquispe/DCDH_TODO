"""
avg_time_periods — Python port of Mata _compute_Tg + _avg_cumul
Mirrors did_multiplegt_dyn_reset.do lines 57–307 and the Stata block 3272–3326.
"""

from __future__ import annotations
import numpy as np
import pandas as pd


# ──────────────────────────────────────────────────────────────────────────────
def _compute_Tg_per_group(
    df_g: pd.DataFrame,
    all_df: pd.DataFrame,
    refp: float,
    Tgc: float,
    cls_val,
    group: str,
    time: str,
    outcome: str,
    F_g_col: str,
    d_sq_int: str,
) -> float:
    """
    For switcher group g, find T_g^{(h)}: the last period P in [F_g, Tgc]
    such that:
      (i)  g itself has outcome observed at refp and at P
      (ii) ∃ control g' (same class, F_{g'} > P) with outcome at refp and P

    Returns last_P = F_g - 1 (default) if no valid period found.
    """
    g_id   = df_g[group].iloc[0]
    Fg_val = df_g[F_g_col].iloc[0]
    last_P = Fg_val - 1

    # g must have observed outcome at refp
    own_ref_rows = df_g[df_g[time] == refp]
    if own_ref_rows.empty or own_ref_rows[outcome].isna().all():
        return last_P

    P = int(Fg_val)
    while P <= int(Tgc):
        # g has outcome at P?
        own_P_rows = df_g[df_g[time] == P]
        if own_P_rows.empty or own_P_rows[outcome].isna().all():
            P += 1
            continue

        # find a control g' in same class with F_{g'} > P and outcomes at refp & P
        others = all_df[
            (all_df[group] != g_id) &
            (all_df[d_sq_int] == cls_val) &
            (all_df[F_g_col] > P)
        ]
        if not others.empty:
            grp_others = others.groupby(group)
            has_ctrl = False
            for _, grp in grp_others:
                ref_rows = grp[grp[time] == refp]
                P_rows   = grp[grp[time] == P]
                if (not ref_rows.empty and not ref_rows[outcome].isna().all() and
                        not P_rows.empty   and not P_rows[outcome].isna().all()):
                    has_ctrl = True
                    break
            if has_ctrl:
                last_P = P
        P += 1

    return float(last_P)


def compute_avg_time_periods(
    df: pd.DataFrame,
    col: dict,
    scalars: dict,
    ell_max: int,
    *,
    switchers_dir: str = "",    # "" = both, "in" = only S_g=1, "out" = only S_g=0
    same_switchers: bool = False,
    continuous: int = 0,
) -> dict:
    """
    Compute:
      - avg_cumul: weighted average M_g across all switchers and horizons
      - nswitch[k]: number of switchers contributing to effect k (k=1..ell_max)

    Returns dict with keys: avg_cumul, nswitch (list, 1-indexed), num, den.
    """
    group    = col["group"]
    time     = col["time"]
    outcome  = col["outcome"]
    treatment= col["treatment"]
    F_g_col  = col["F_g"]
    T_g_col  = col["T_g"]
    S_g_col  = col["S_g"]
    d_sq_int = col["d_sq_int"]
    d_sq_orig= col.get("d_sq_orig", col["d_sq"])
    N_gt_w   = col["N_gt_w"]

    T_max   = scalars["T_max"]

    # ── cell-validity indicator: outcome observed (NOT treatment) ─────────────
    # This is the critical fix: ngt_bin = (outcome != .) only,
    # so that never-switchers (treatment=NaN after continuous binarization)
    # still qualify as controls.
    df = df.copy()
    df["_ngt_bin"] = df[outcome].notna().astype(float)

    # ── restrict to eligible switchers ────────────────────────────────────────
    sw_mask = df["_ever_sw"] == 1
    if switchers_dir == "in":
        sw_mask &= df[S_g_col] == 1
    elif switchers_dir == "out":
        sw_mask &= df[S_g_col] == 0

    switcher_groups = df[sw_mask][group].unique()

    num      = 0.0
    den      = 0.0
    nswitch  = [0.0] * (ell_max + 1)  # 1-indexed; index 0 unused

    for g_id in switcher_groups:
        df_g  = df[df[group] == g_id]
        Fg_   = float(df_g[F_g_col].iloc[0])
        Tg_cls= float(df_g[T_g_col].iloc[0])
        ever  = float(df_g["_ever_sw"].iloc[0])
        cls_v = df_g[d_sq_int].iloc[0]

        if ever != 1 or np.isnan(Fg_) or Fg_ >= T_max + 1:
            continue

        # reference period (fixed)
        refp = Fg_ - 1

        # per-horizon T_g
        Tg_ph = _compute_Tg_per_group(
            df_g   = df_g,
            all_df = df,
            refp   = refp,
            Tgc    = Tg_cls,
            cls_val= cls_v,
            group  = group,
            time   = time,
            outcome= outcome,
            F_g_col= F_g_col,
            d_sq_int= d_sq_int,
        )

        Mg_ = min(ell_max, max(0, int(Tg_ph - Fg_ + 1)))

        if same_switchers and Mg_ < ell_max:
            continue

        if Fg_ > Tg_ph:
            continue

        # reference outcome & treatment observed?
        ref_rows = df_g[df_g[time] == refp]
        if ref_rows.empty or ref_rows[outcome].isna().all():
            continue

        y_ref_ok = True
        d1_val   = df_g[d_sq_orig].iloc[0]  # baseline treatment

        for k in range(Mg_):
            period = int(Fg_ + k)

            # horizon outcome and treatment
            hor_rows = df_g[df_g[time] == period]
            if hor_rows.empty:
                continue
            dval = hor_rows[treatment].iloc[0]
            yhor = hor_rows[outcome].iloc[0]

            if pd.isna(dval) or pd.isna(yhor) or not y_ref_ok:
                continue

            # check control exists at (refp, period)
            others = df[
                (df[group] != g_id) &
                (df[d_sq_int] == cls_v) &
                (df[F_g_col] > period)
            ]
            has_ctrl = False
            for _, grp in others.groupby(group):
                r = grp[grp[time] == refp]
                p = grp[grp[time] == period]
                if (not r.empty and r[outcome].notna().any() and
                        not p.empty and p[outcome].notna().any()):
                    has_ctrl = True
                    break

            if has_ctrl:
                incr   = abs(dval - d1_val)
                weight = Mg_ - k
                num   += incr * weight
                den   += incr
                # weighted switcher count (using N_gt weight at the horizon)
                w_val = df_g[df_g[time] == period][N_gt_w].sum()
                nswitch[k + 1] += float(w_val) if not np.isnan(w_val) else 1.0

    avg_cumul = (num / den) if den != 0 else np.nan

    return {
        "avg_cumul": avg_cumul,
        "nswitch":   nswitch,   # list length ell_max+1; index 0 unused
        "num":       num,
        "den":       den,
    }
