"""
Phase 1 — Data preparation
Mirrors Stata lines ~470–1206 of did_multiplegt_dyn_final.do
"""

from __future__ import annotations
import warnings
import numpy as np
import pandas as pd
from .utils import _rectangularize, _to_int_groups


# ──────────────────────────────────────────────────────────────────────────────
def prepare(
    df: pd.DataFrame,
    outcome: str,
    group: str,
    time: str,
    treatment: str,
    *,
    weight: str | None = None,
    controls: list[str] | None = None,
    trends_nonparam: str | None = None,
    cluster: str | None = None,
    continuous: int = 0,
    dont_drop_larger_lower: bool = False,
    only_never_switchers: bool = False,
    drop_if_d_miss_before_first_switch: bool = False,
    trends_lin: bool = False,
) -> dict:
    """
    Clean and rectangularize the dataset; compute all group-level variables
    (F_g, T_g, d_sq, S_g, L_g, N_gt, …).

    Returns a dict with keys:
        df        : cleaned working DataFrame
        scalars   : dict of t_min, T_max, G, l_u, l_a (max available effects)
        col       : dict mapping logical names → actual column names
    """

    controls    = controls or []
    keep_cols   = ([outcome, group, time, treatment]
                   + controls
                   + ([trends_nonparam] if trends_nonparam else [])
                   + ([weight]          if weight          else [])
                   + ([cluster]         if cluster         else []))

    df = df[keep_cols].copy()
    df = df.dropna(subset=[group, time])

    # ── 1. Collapse to (g, t) level ──────────────────────────────────────────
    # If multiple obs per (g,t), take weighted mean (weight = count or sum).
    agg_cols = [c for c in [outcome, treatment] + controls
                + ([trends_nonparam] if trends_nonparam else [])
                + ([cluster]         if cluster         else [])
                if c != weight]

    if weight:
        df["_w"] = df[weight].fillna(0)
        g = df.groupby([group, time])
        wt = g["_w"].transform("sum")
        for c in agg_cols:
            df[c] = df[c] * df["_w"] / wt.replace(0, np.nan)
        df = g[agg_cols + ["_w"]].sum().reset_index()
        df.rename(columns={"_w": "_weight_XX"}, inplace=True)
    else:
        df = df.groupby([group, time])[agg_cols].mean().reset_index()
        df["_weight_XX"] = 1.0

    df = df.sort_values([group, time]).reset_index(drop=True)

    # ── 2. Baseline treatment d_sq = D_{g,1} (first non-missing D) ───────────
    first_d = (df.dropna(subset=[treatment])
               .groupby(group)[treatment].first()
               .rename("_d_sq"))
    df = df.merge(first_d, on=group, how="left")

    # ── 3. Design Restriction 2: drop mixed-direction groups ─────────────────
    if not dont_drop_larger_lower:
        df["_diff_from_sq"] = df[treatment] - df["_d_sq"]
        ever_up   = df.groupby(group)["_diff_from_sq"].transform(
                        lambda s: (s > 0).any())
        ever_down = df.groupby(group)["_diff_from_sq"].transform(
                        lambda s: (s < 0).any())
        df = df[~(ever_up & ever_down)].reset_index(drop=True)
        df.drop(columns=["_diff_from_sq"], inplace=True)

    # ── 4. ever_change_d, F_g ─────────────────────────────────────────────────
    df["_ever_change"] = df.groupby(group)[treatment].transform(
        lambda s: (s != s.iloc[0]).any()
    )
    # F_g: first time D != d_sq
    def _fg(grp):
        d_sq_val = grp["_d_sq"].iloc[0]
        changed = grp[treatment] != d_sq_val
        if changed.any():
            return grp[time][changed].min()
        return np.nan
    fg = df.groupby(group).apply(_fg).rename("_F_g")
    df = df.merge(fg, on=group, how="left")

    # ── 5. Drop time periods with no control group for any baseline level ─────
    strat = ([treatment, "_d_sq"]
             + ([trends_nonparam] if trends_nonparam else []))
    never_sw = ~df["_ever_change"]
    df["_has_ctrl_at_t"] = df.groupby([time] + [s for s in strat if s != time])[
        "_ever_change"
    ].transform(lambda s: (~s).any())
    df = df[df["_has_ctrl_at_t"]].reset_index(drop=True)

    # ── 6. t_min, T_max, sentinel F_g for never-switchers ────────────────────
    t_min  = int(df[time].min())
    T_max  = int(df[time].max())
    df["_F_g"] = df["_F_g"].fillna(T_max + 1).astype(float)

    # ── 7. Rectangularize ────────────────────────────────────────────────────
    df = _rectangularize(df, group, time)
    df = df.sort_values([group, time]).reset_index(drop=True)

    # propagate group-level constants after rectangularize
    for col in ["_d_sq", "_F_g", "_weight_XX",
                *([trends_nonparam] if trends_nonparam else []),
                *([cluster]         if cluster         else [])]:
        if col in df.columns:
            df[col] = df.groupby(group)[col].transform("first")

    # ── 8. N_gt = 1 iff outcome and treatment both observed ──────────────────
    df["_N_gt"] = (df[outcome].notna() & df[treatment].notna()).astype(float)
    df["_N_gt_w"] = df["_N_gt"] * df["_weight_XX"]

    # ── 9. T_g: last period where a control exists for g's stratum ───────────
    #   T_g = max(F_g_trunc) - 1 per (d_sq, [trends_nonparam]) stratum
    #   F_g_trunc = F_g  (no trunc_control implemented here yet)
    strat_tg = (["_d_sq"]
                + ([trends_nonparam] if trends_nonparam else []))
    df["_T_g"] = (df.groupby(strat_tg)["_F_g"]
                  .transform("max") - 1)

    # ── 10. S_g: switcher direction ───────────────────────────────────────────
    mask_sw = df["_F_g"] < T_max + 1
    post_sw = (df[time] >= df["_F_g"]) & (df[time] <= df["_T_g"])
    df["_post_treat"] = np.where(post_sw, df[treatment], np.nan)
    avg_post = (df.groupby(group)["_post_treat"]
                .transform("mean"))
    df["_S_g"] = np.where(
        mask_sw,
        (avg_post > df["_d_sq"]).astype(float),
        np.nan
    )
    # Drop groups whose avg post-switch = d_sq (no first stage)
    no_fs = (df["_F_g"] < T_max + 1) & (avg_post == df["_d_sq"])
    df = df[~no_fs].reset_index(drop=True)

    # ── 11. Continuous option: binarize treatment ─────────────────────────────
    if continuous > 0:
        df["_d_sq_orig"] = df["_d_sq"]
        # S_g_het: +1 for switcher-in, -1 for switcher-out, NaN for never
        df["_S_g_het"] = np.where(df["_S_g"] == 1, 1.0,
                         np.where(df["_S_g"] == 0, -1.0, np.nan))
        # binarize: D_gt = 1(t>=F_g)*S_g_het  for switchers; NaN for never
        df[treatment] = np.where(
            df["_S_g_het"].notna(),
            (df[time] >= df["_F_g"]).astype(float) * df["_S_g_het"],
            np.nan
        )
        df["_d_sq"] = 0.0  # baseline forced to 0

    # ── 12. L_g = T_g - F_g + 1 ──────────────────────────────────────────────
    df["_L_g"] = (df["_T_g"] - df["_F_g"] + 1).clip(lower=0)

    # ── 13. Group count G ─────────────────────────────────────────────────────
    G = df[group].nunique()

    # ── 14. d_sq_int: integer code for baseline treatment level ───────────────
    df["_d_sq_int"] = _to_int_groups(df["_d_sq"].fillna(-999))

    # ever-switcher indicator
    df["_ever_sw"] = (df["_F_g"] < T_max + 1).astype(float)

    # max available effects per direction
    sw_in  = df[df["_S_g"] == 1]
    sw_out = df[df["_S_g"] == 0]
    l_u = int(sw_in.groupby(group)["_L_g"].first().max()) if len(sw_in) else 0
    l_a = int(sw_out.groupby(group)["_L_g"].first().max()) if len(sw_out) else 0

    scalars = dict(t_min=t_min, T_max=T_max, G=G, l_u=l_u, l_a=l_a)
    col = dict(
        outcome=outcome, group=group, time=time, treatment=treatment,
        weight="_weight_XX", N_gt="_N_gt", N_gt_w="_N_gt_w",
        F_g="_F_g", T_g="_T_g", L_g="_L_g", S_g="_S_g",
        d_sq="_d_sq", d_sq_int="_d_sq_int", ever_sw="_ever_sw",
        d_sq_orig="_d_sq_orig" if continuous > 0 else "_d_sq",
        trends_nonparam=trends_nonparam, cluster=cluster,
    )

    return {"df": df, "scalars": scalars, "col": col}
