"""
compare_wagepan_specs.py
========================
Read results/wagepan_specs.csv and verify that for every option combination
on wagepan, N_switchers_effect_k (N_std) equals N_switch_avg_k (N_avg).

Mirrors: code/compare_wagepan_specs.py  (Stata version)

Usage (from tests_R/):
    python compare/compare_wagepan_specs.py
"""

import csv
import sys
from collections import defaultdict
from pathlib import Path

CSV_PATH = Path(__file__).parent.parent / "results" / "wagepan_specs.csv"


def main():
    print("=" * 76)
    print("compare_wagepan_specs.py [R]  —  N_switchers_effect_k vs N_switch_avg_k")
    print("=" * 76)

    try:
        with open(CSV_PATH) as fh:
            rows = list(csv.DictReader(fh))
    except FileNotFoundError:
        print(f"ERROR: {CSV_PATH} not found — run test_wagepan_specs.R first.")
        sys.exit(1)

    if not rows:
        print(f"ERROR: {CSV_PATH} is empty.")
        sys.exit(1)

    print(f"Loaded {len(rows)} rows from {CSV_PATH}\n")

    by_spec = defaultdict(list)
    for r in rows:
        by_spec[r["spec"]].append(r)

    print(f"{'Spec':<26} {'effects':>8}  {'PASS':>6}  {'FAIL':>6}  {'MISS':>6}  {'ERR':>4}")
    print("-" * 76)

    gp = gf = gm = ge = 0
    for spec in sorted(by_spec):
        grp    = by_spec[spec]
        n_pass = sum(1 for r in grp if r["pass"] == "PASS")
        n_fail = sum(1 for r in grp if r["pass"] == "FAIL")
        n_miss = sum(1 for r in grp if r["pass"] == "MISS")
        n_err  = sum(1 for r in grp if r["pass"].startswith("ERROR"))
        gp += n_pass; gf += n_fail; gm += n_miss; ge += n_err
        flag  = "  <-- !" if (n_fail or n_err) else ""
        n_eff = sum(1 for r in grp if int(r["effect_num"]) >= 0)
        print(f"{spec:<26} {n_eff:>8}  {n_pass:>6}  {n_fail:>6}  "
              f"{n_miss:>6}  {n_err:>4}{flag}")

    print("-" * 76)
    print(f"{'TOTAL':<26} {len(rows):>8}  {gp:>6}  {gf:>6}  {gm:>6}  {ge:>4}")
    print("=" * 76)

    err_rows  = [r for r in rows if r["pass"].startswith("ERROR")]
    miss_rows = [r for r in rows if r["pass"] == "MISS"]
    fail_rows = [r for r in rows if r["pass"] == "FAIL"]

    if err_rows:
        print("\nERROR rows:")
        for r in err_rows:
            print(f"  spec={r['spec']:<26}  {r['pass']}")

    if miss_rows:
        print(f"\nMISS rows:")
        for r in miss_rows:
            print(f"  {r['spec']:<26} eff={r['effect_num']:>2}  "
                  f"N_std={r['N_std']}  N_avg={r['N_avg']}")

    if fail_rows:
        print(f"\nFAIL rows (N_std != N_avg):")
        print(f"{'spec':<26} {'eff':>4} {'N_std':>10} {'N_avg':>10} {'diff':>10}")
        print("-" * 64)
        for r in fail_rows:
            print(f"{r['spec']:<26} {r['effect_num']:>4} "
                  f"{r['N_std']:>10} {r['N_avg']:>10} {r['diff']:>10}")
        sys.exit(1)

    if gf == 0 and ge == 0 and not miss_rows:
        print("\nRESULT: PASS — avg_time_periods switcher counts match the "
              "standard pipeline across every option combination on wagepan.")
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
