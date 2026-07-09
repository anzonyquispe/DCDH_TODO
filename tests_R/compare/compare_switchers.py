"""
compare_switchers.py
====================
Read all results/switchers_b*.csv files and verify that
N_switchers_effect_k (N_did) == N_switch_avg_k (N_avg)
for every effect in every specification.

Mirrors: code/compare_switchers.py  (Stata version)

Usage (from tests_R/):
    python compare/compare_switchers.py
"""

import csv
import glob
import sys
from collections import defaultdict
from pathlib import Path

RESULTS_DIR = Path(__file__).parent.parent / "results"
PATTERN     = str(RESULTS_DIR / "switchers_b*.csv")


def load_all(pattern):
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"ERROR: no files matched {pattern}")
        sys.exit(1)
    rows = []
    for f in files:
        with open(f) as fh:
            n = 0
            for row in csv.DictReader(fh):
                row["_source"] = f
                rows.append(row)
                n += 1
        print(f"  Loaded {f}  ({n} rows)")
    return rows


def main():
    print("=" * 76)
    print("compare_switchers.py [R]  —  N_switchers_effect_k vs N_switch_avg_k")
    print("=" * 76)

    rows = load_all(PATTERN)
    print(f"\nTotal rows: {len(rows)}\n")

    groups = defaultdict(list)
    for r in rows:
        groups[(r["dataset"], r["spec"], r["reset"])].append(r)

    print(f"{'Dataset':<15} {'Spec':<10} {'Reset':>5}  "
          f"{'Effects':>7}  {'PASS':>6}  {'FAIL':>6}  {'MISS':>6}  {'ERR':>4}")
    print("-" * 76)

    gp = gf = gm = ge = 0
    for key in sorted(groups):
        ds, spec, rst = key
        grp   = groups[key]
        n_pass = sum(1 for r in grp if r["pass"] == "PASS")
        n_fail = sum(1 for r in grp if r["pass"] == "FAIL")
        n_miss = sum(1 for r in grp if r["pass"] == "MISS")
        n_err  = sum(1 for r in grp if r["pass"].startswith("ERROR"))
        gp += n_pass; gf += n_fail; gm += n_miss; ge += n_err
        flag = "  <-- !" if (n_fail or n_err) else ""
        n_eff = sum(1 for r in grp if int(r["effect_num"]) >= 0)
        print(f"{ds:<15} {spec:<10} {rst:>5}  "
              f"{n_eff:>7}  {n_pass:>6}  {n_fail:>6}  {n_miss:>6}  {n_err:>4}{flag}")

    print("-" * 76)
    print(f"{'TOTAL':<33}  {len(rows):>7}  {gp:>6}  {gf:>6}  {gm:>6}  {ge:>4}")
    print("=" * 76)

    # detail
    err_rows  = [r for r in rows if r["pass"].startswith("ERROR")]
    miss_rows = [r for r in rows if r["pass"] == "MISS"]
    fail_rows = [r for r in rows if r["pass"] == "FAIL"]

    if err_rows:
        print("\nERROR rows:")
        for r in err_rows:
            print(f"  {r['dataset']:<15} {r['spec']:<10}  reset={r['reset']}  {r['pass']}")

    if miss_rows:
        print(f"\nMISS rows ({len(miss_rows)}):")
        for r in miss_rows:
            print(f"  {r['dataset']:<15} {r['spec']:<10}  "
                  f"reset={r['reset']}  eff={r['effect_num']:>3}  "
                  f"N_did={r['N_did']}  N_avg={r['N_avg']}")

    if fail_rows:
        print(f"\nFAIL rows ({len(fail_rows)}) — the signal:")
        print(f"{'dataset':<15} {'spec':<10} {'reset':>5} {'eff':>4} "
              f"{'N_did':>10} {'N_avg':>10} {'diff':>10}")
        print("-" * 70)
        for r in fail_rows:
            print(f"{r['dataset']:<15} {r['spec']:<10} {r['reset']:>5} "
                  f"{r['effect_num']:>4} {r['N_did']:>10} {r['N_avg']:>10} "
                  f"{r['diff']:>10}")
        sys.exit(1)

    if gf == 0 and ge == 0 and not miss_rows:
        print("\nRESULT: PASS — switcher counts match across all batches.")
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
