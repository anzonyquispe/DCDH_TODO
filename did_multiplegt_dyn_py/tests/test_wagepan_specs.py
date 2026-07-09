"""
19 option combinations on wagepan.
Cross-check: N_switchers_effect_k == N_switch_avg_k for every effect.
Mirrors: code/test_wagepan_specs.do  +  tests_R/R/test_wagepan_specs.R
"""

import sys
from datetime import datetime
from pathlib import Path
import pyreadstat

sys.path.insert(0, str(Path(__file__).parent.parent))
from did_multiplegt_dyn import did_multiplegt_dyn
from tests.helpers import (DATA_DIR, RESULTS_DIR, init_wagepan_csv,
                            write_wrow, extract_N_switchers, extract_N_switch_avg)

DATA   = DATA_DIR / "wagepan.dta"
Y, G, TM, D = "lwage", "nr", "year", "union"
CONT, NONPAR, WGHT, CLUST = "hours", "black", "educ", "hisp"
N_EFF, N_PL = 5, 2

CSV = RESULTS_DIR / "wagepan_specs.csv"
LOG = RESULTS_DIR / "test_wagepan_specs.log"


def run_spec(df_base, label: str, **kwargs):
    print(f"\n{'─'*70}\nSPEC: {label}\n{'─'*70}")
    result = None
    try:
        result = did_multiplegt_dyn(
            df_base, outcome=Y, group=G, time=TM, treatment=D,
            avg_time_periods=True, graph_off=True,
            **kwargs,
        )
    except Exception as e:
        row = f"{label},-1,.,.,.,ERROR:{e}\n"
        with open(CSV, "a") as fh:
            fh.write(row)
        print(f"  ERROR  {label}  {e}", file=sys.stderr)
        return

    N_std = extract_N_switchers(result, N_EFF)
    N_avg = extract_N_switch_avg(result, N_EFF)
    n_max = max(len(N_std), len(N_avg))
    if n_max == 0:
        row = f"{label},-1,.,.,.,ERROR:no_effects_found\n"
        with open(CSV, "a") as fh:
            fh.write(row)
        return
    for k in range(1, n_max + 1):
        write_wrow(CSV, label, k, N_std.get(k), N_avg.get(k))


def _run():
    print(f"=== test_wagepan_specs  started: {datetime.now()} ===")
    init_wagepan_csv(CSV)
    df_base, _ = pyreadstat.read_dta(str(DATA))
    print(f"Loaded {DATA}  ({len(df_base)} rows)")

    run_spec(df_base, "Baseline",               effects=N_EFF)
    run_spec(df_base, "Placebos",               effects=N_EFF, placebo=N_PL)
    run_spec(df_base, "Normalized",             effects=N_EFF, placebo=N_PL, normalized=True)
    run_spec(df_base, "Controls",               effects=N_EFF, placebo=N_PL, controls=CONT)
    run_spec(df_base, "Trends_Nonparam",        effects=N_EFF, placebo=N_PL, trends_nonparam=NONPAR)
    # trends_lin excluded: avg_time_periods undefined under trends_lin
    run_spec(df_base, "Weight",                 effects=N_EFF, placebo=N_PL, weight=WGHT)
    run_spec(df_base, "Cluster",                effects=N_EFF, placebo=N_PL, cluster=CLUST)
    run_spec(df_base, "Same_Switchers",         effects=N_EFF, placebo=N_PL, same_switchers=True)
    run_spec(df_base, "Same_Switchers_Pl",      effects=N_EFF, placebo=N_PL,
             same_switchers=True, same_switchers_pl=True)
    run_spec(df_base, "Switchers_In",           effects=N_EFF, placebo=N_PL, switchers="in")
    run_spec(df_base, "Switchers_Out",          effects=N_EFF, placebo=N_PL, switchers="out")
    run_spec(df_base, "Only_Never_Switchers",   effects=N_EFF, placebo=N_PL,
             only_never_switchers=True)
    run_spec(df_base, "CI_Level_90",            effects=N_EFF, placebo=N_PL, ci_level=90)
    run_spec(df_base, "CI_Level_99",            effects=N_EFF, placebo=N_PL, ci_level=99)
    run_spec(df_base, "Less_Conservative_SE",   effects=N_EFF, placebo=N_PL,
             less_conservative_se=True)
    run_spec(df_base, "Dont_Drop_Larger_Lower", effects=N_EFF, placebo=N_PL,
             dont_drop_larger_lower=True)
    run_spec(df_base, "Effects_Equal",          effects=N_EFF, placebo=N_PL,
             effects_equal="all")
    # Continuous specs: no placebo (matches Stata)
    run_spec(df_base, "Continuous_1",           effects=N_EFF, continuous=1)
    run_spec(df_base, "Continuous_4",           effects=N_EFF, continuous=4)

    print(f"\nCSV written to: {CSV}")
    print(f"=== test_wagepan_specs  finished: {datetime.now()} ===")


if __name__ == "__main__":
    _run()
