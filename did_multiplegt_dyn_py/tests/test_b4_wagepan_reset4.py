"""Batch 4 — wagepan, reset(4), effects(600)."""
import sys
from datetime import datetime
from pathlib import Path
import pyreadstat

sys.path.insert(0, str(Path(__file__).parent.parent))
from did_multiplegt_dyn import did_multiplegt_dyn, reset_groups
from tests.helpers import (DATA_DIR, RESULTS_DIR, init_switcher_csv,
                            write_swrow, write_diagrow,
                            extract_N_switchers, extract_N_switch_avg)

DS, SPEC, RST, NEFF = "wagepan", "reset4", 4, 600
DATA = DATA_DIR / "wagepan.dta"
Y, G, TM, D = "lwage", "nr", "year", "union"
CSV = RESULTS_DIR / "switchers_b4.csv"

def _run():
    print(f"=== test_b4_wagepan_reset4  started: {datetime.now()} ===")
    init_switcher_csv(CSV)
    df_raw, _ = pyreadstat.read_dta(str(DATA))

    try:
        df = reset_groups(df_raw, gvar=G, tvar=TM, dvar=D,
                          reset=RST, replace_group=True)
    except Exception as e:
        write_diagrow(CSV, DS, SPEC, RST, f"reset_groups_failed:{e}")
        return

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
    for k in range(1, n_max + 1):
        write_swrow(CSV, DS, SPEC, RST, k, N_did.get(k), N_avg.get(k))
    print(f"=== test_b4_wagepan_reset4  finished: {datetime.now()} ===")

if __name__ == "__main__":
    _run()
