"""
reset_groups — Python port of reset_groups_function.do

Split each unit into pseudo-units: a new pseudo-unit starts every time
the treatment has been STABLE for `reset` periods following a change.
"""

from __future__ import annotations
import numpy as np
import pandas as pd


def reset_groups(
    df: pd.DataFrame,
    gvar: str,
    tvar: str,
    dvar: str,
    reset: int,
    replace_group: bool = True,
    newgroup_col: str = "new_group",
    oldgroup_col: str = "old_group",
) -> pd.DataFrame:
    """
    Apply the de Chaisemartin & D'Haultfoeuille reset option.

    Parameters
    ----------
    df            : input DataFrame
    gvar          : group column name
    tvar          : time column name
    dvar          : treatment column name
    reset         : number of stable post-change periods that triggers a split
    replace_group : if True, overwrite gvar with the new pseudo-group IDs
    newgroup_col  : name for the new pseudo-group column
    oldgroup_col  : name for the preserved original-group column

    Returns
    -------
    DataFrame with pseudo-group IDs added (and gvar replaced if replace_group=True).
    """
    if reset == 0:
        print("reset(0): no splitting performed; data unchanged.")
        return df.copy()

    df = df.copy().sort_values([gvar, tvar]).reset_index(drop=True)

    # ── balance: keep units observed in the maximum number of non-missing D periods
    n_before = len(df)
    counts = df.groupby(gvar)[dvar].transform(lambda s: s.notna().sum())
    max_obs = counts.max()
    df = df[counts == max_obs].reset_index(drop=True)
    n_dropped = n_before - len(df)

    # ── periods since last treatment change (psc)
    df = df.sort_values([gvar, tvar]).reset_index(drop=True)

    def _psc(grp: pd.DataFrame) -> pd.Series:
        d = grp[dvar].values
        changed = np.zeros(len(d), dtype=int)
        changed[1:] = (d[1:] != d[:-1]).astype(int)
        spell = np.cumsum(changed)
        psc = np.zeros(len(d), dtype=int)
        for i in range(1, len(d)):
            if spell[i] == spell[i - 1]:  # same spell → increment
                psc[i] = psc[i - 1] + 1
            else:  # new spell → reset
                psc[i] = 0
        # first obs of a new spell that started at change: psc = 0; after reset
        # periods it equals `reset`
        return pd.Series(psc, index=grp.index)

    df["_psc"] = df.groupby(gvar, group_keys=False).apply(_psc)

    # ── cumulative reset count per unit
    df["_reset_hit"] = (df["_psc"] == reset).astype(int)
    df["_reset_count"] = df.groupby(gvar)["_reset_hit"].cumsum()

    # ── new pseudo-group ID
    df[oldgroup_col] = df[gvar]
    key = df[gvar].astype(str) + "_" + df["_reset_count"].astype(str)
    df[newgroup_col] = pd.factorize(key, sort=False)[0] + 1
    n_newgrp = df[newgroup_col].nunique()

    if replace_group:
        df[gvar] = df[newgroup_col]

    df = df.drop(columns=["_psc", "_reset_hit", "_reset_count"])

    print(
        f"reset_groups: reset={reset} | dropped={n_dropped} | "
        f"pseudo-groups={n_newgrp}"
    )
    return df
