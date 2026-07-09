"""
Batch 1 — gentzkowetal_balanced, no reset, effects(600)
Cross-check: N_switchers_effect_k == N_switch_avg_k
Mirrors: code/test_switchers_b1.do  +  tests_R/R/test_b1_gentzkow_noreset.R
"""

import sys
from datetime import datetime
from pathlib import Path

import pyreadstat

sys.path.insert(0, str(Path(__file__).parent.parent))
from did_multiplegt_dyn import did_multiplegt_dyn
from tests.helpers import (
    DATA_DIR, RESULTS_DIR,
    init_switcher_csv, write_swrow, write_diagrow,
    extract_N_switchers, extract_N_switch_avg,
)

DS   = "gentzkow"
SPEC = "noreset"
RST  = 0
NEFF = 600
DATA = DATA_DIR / "gentzkowetal_didtextbook_balanced.dta"
Y, G, TM, D = "prestout", "cnty90", "year", "numdailies"

CSV = RESULTS_DIR / "switchers_b1.csv"
LOG = RESULTS_DIR / "test_b1_gentzkow_noreset.log"

def main():
    with open(LOG, "w") as log:
        sys.stdout = log; sys.stderr = log
        try:
            _run()
        finally:
            sys.stdout = sys.__stdout__
            sys.stderr = sys.__stderr__

def _run():
    print(f"=== test_b1_gentzkow_noreset  started: {datetime.now()} ===")
    init_switcher_csv(CSV)

    df, _ = pyreadstat.read_dta(str(DATA))
    print(f"Loaded {DATA}  ({len(df)} rows)")
    print(f"\n{'─'*60}\n{DS}  effects({NEFF})  no_reset\n{'─'*60}")

    result = None
    try:
        result = did_multiplegt_dyn(
            df, outcome=Y, group=G, time=TM, treatment=D,
            effects=NEFF, avg_time_periods=True, graph_off=True,
        )
    except Exception as e:
        write_diagrow(CSV, DS, SPEC, RST, f"did_multiplegt_dyn_failed:{e}")

    N_did = extract_N_switchers(result, NEFF)
    N_avg = extract_N_switch_avg(result, NEFF)
    n_max = max(len(N_did), len(N_avg))
    print(f"  -> N_did effects found: {len(N_did)}")
    print(f"  -> N_avg effects found: {len(N_avg)}")

    if n_max == 0:
        write_diagrow(CSV, DS, SPEC, RST, "no_effects_found")
    else:
        for k in range(1, n_max + 1):
            write_swrow(CSV, DS, SPEC, RST, k, N_did.get(k), N_avg.get(k))

    print(f"\nCSV written to: {CSV}")
    print(f"=== test_b1_gentzkow_noreset  finished: {datetime.now()} ===")

if __name__ == "__main__":
    _run()
