"""
DIDResult — result container mirroring Stata e() scalars and matrices.
"""

from __future__ import annotations
import numpy as np
import pandas as pd


class DIDResult:
    """
    Container for did_multiplegt_dyn estimates.

    Attributes (all also accessible as dict via .scalars / .matrices)
    -------------------------------------------------------------------
    Effect_k           : float — dynamic effect estimate at horizon k
    se_effect_k        : float — standard error
    lb_effect_k        : float — lower CI bound
    ub_effect_k        : float — upper CI bound
    N_switchers_effect_k : float — number of switcher groups at k
    N_effect_k         : float — total weighted observations at k
    Placebo_k          : float — placebo estimate at lag k
    se_placebo_k       : float — SE of placebo
    Av_tot_effect      : float — average cumulative effect
    se_avg_total_effect: float — SE of average effect
    avg_cumul          : float — avg periods (avg_time_periods option)
    N_switch_avg_k     : float — switcher count per k (avg_time_periods)
    p_jointeffects     : float — p-value joint nullity of effects
    p_jointplacebo     : float — p-value joint nullity of placebos
    """

    def __init__(self):
        self._d: dict = {}

    # ── generic attribute access ──────────────────────────────────────────────
    def __setattr__(self, name, value):
        if name.startswith("_"):
            super().__setattr__(name, value)
        else:
            self._d[name] = value

    def __getattr__(self, name):
        try:
            return self._d[name]
        except KeyError:
            raise AttributeError(name)

    def __getitem__(self, name):
        return self._d[name]

    def __contains__(self, name):
        return name in self._d

    def keys(self):
        return self._d.keys()

    # ── pretty print ─────────────────────────────────────────────────────────
    def __repr__(self) -> str:
        lines = ["DIDResult"]
        l = self._d.get("l_XX", 0)
        lp = self._d.get("l_placebo_XX", 0)

        lines.append(f"{'':>4}{'Effect':>8}  {'SE':>8}  {'[CI lower':>10}  {'CI upper]':>10}  {'N_switchers':>12}")
        lines.append("  " + "-" * 60)
        for k in range(1, int(l) + 1):
            eff = self._d.get(f"Effect_{k}", np.nan)
            se  = self._d.get(f"se_effect_{k}", np.nan)
            lb  = self._d.get(f"lb_effect_{k}", np.nan)
            ub  = self._d.get(f"ub_effect_{k}", np.nan)
            ns  = self._d.get(f"N_switchers_effect_{k}", np.nan)
            lines.append(
                f"  Effect_{k:<3} {eff:>8.4f}  {se:>8.4f}  "
                f"{lb:>10.4f}  {ub:>10.4f}  {ns:>12.0f}"
            )
        if lp > 0:
            lines.append("")
            for k in range(1, int(lp) + 1):
                pl = self._d.get(f"Placebo_{k}", np.nan)
                se = self._d.get(f"se_placebo_{k}", np.nan)
                lb = self._d.get(f"lb_placebo_{k}", np.nan)
                ub = self._d.get(f"ub_placebo_{k}", np.nan)
                lines.append(
                    f"  Placebo_{k:<2} {pl:>8.4f}  {se:>8.4f}  "
                    f"{lb:>10.4f}  {ub:>10.4f}"
                )
        avg = self._d.get("Av_tot_effect")
        if avg is not None and not np.isnan(avg):
            se = self._d.get("se_avg_total_effect", np.nan)
            lines.append(f"\n  Av_tot_effect {avg:>8.4f}  SE={se:>8.4f}")

        avg_c = self._d.get("avg_cumul")
        if avg_c is not None and not np.isnan(avg_c):
            lines.append(f"\n  avg_cumul (avg_time_periods) = {avg_c:.4f}")

        pj = self._d.get("p_jointeffects")
        if pj is not None:
            lines.append(f"\n  p-value (joint nullity effects): {pj:.4f}")
        pp = self._d.get("p_jointplacebo")
        if pp is not None:
            lines.append(f"  p-value (joint nullity placebos): {pp:.4f}")

        return "\n".join(lines)

    def summary(self) -> "DIDResult":
        print(self)
        return self

    def to_dataframe(self) -> pd.DataFrame:
        """Return estimates as a tidy DataFrame."""
        l  = int(self._d.get("l_XX", 0))
        lp = int(self._d.get("l_placebo_XX", 0))
        rows = []
        for k in range(1, l + 1):
            rows.append({
                "type": "effect", "k": k,
                "estimate": self._d.get(f"Effect_{k}"),
                "se":       self._d.get(f"se_effect_{k}"),
                "lb":       self._d.get(f"lb_effect_{k}"),
                "ub":       self._d.get(f"ub_effect_{k}"),
                "N_switchers": self._d.get(f"N_switchers_effect_{k}"),
                "N_switch_avg": self._d.get(f"N_switch_avg_{k}"),
            })
        for k in range(1, lp + 1):
            rows.append({
                "type": "placebo", "k": -k,
                "estimate": self._d.get(f"Placebo_{k}"),
                "se":       self._d.get(f"se_placebo_{k}"),
                "lb":       self._d.get(f"lb_placebo_{k}"),
                "ub":       self._d.get(f"ub_placebo_{k}"),
                "N_switchers": self._d.get(f"N_switchers_placebo_{k}"),
            })
        return pd.DataFrame(rows)
