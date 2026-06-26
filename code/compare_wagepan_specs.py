"""
compare_wagepan_specs.py
========================
Read logfiles/wagepan_specs.csv and verify that for every option combination
on wagepan, the standard switcher count e(N_switchers_effect_k) equals the
avg_time_periods switcher count e(N_switch_avg_k), for every effect.

Expected CSV columns:
    spec, effect_num, N_std, N_avg, diff, pass
"""

import csv
import sys
from collections import defaultdict

CSV_PATH = "logfiles/wagepan_specs.csv"


def main():
    print("=" * 76)
    print("compare_wagepan_specs.py  —  N_switchers_effect_k vs N_switch_avg_k")
    print("=" * 76)

    rows = []
    try:
        with open(CSV_PATH, "r") as fh:
            for row in csv.DictReader(fh):
                rows.append(row)
    except FileNotFoundError:
        print(f"ERROR: {CSV_PATH} not found — run test_wagepan_specs.do first.")
        sys.exit(1)

    if not rows:
        print(f"ERROR: {CSV_PATH} is empty.")
        sys.exit(1)

    print(f"Loaded {len(rows)} rows from {CSV_PATH}\n")

    by_spec = defaultdict(list)
    for r in rows:
        by_spec[r["spec"]].append(r)

    print(f"{'Spec':<24} {'effects':>8}  {'PASS':>6}  {'FAIL':>6}  {'MISS':>6}  {'ERR':>4}")
    print("-" * 76)

    gp = gf = gm = ge = 0
    for spec in sorted(by_spec.keys()):
        grp = by_spec[spec]
        n_pass = sum(1 for r in grp if r["pass"] == "PASS")
        n_fail = sum(1 for r in grp if r["pass"] == "FAIL")
        n_miss = sum(1 for r in grp if r["pass"] == "MISS")
        n_err  = sum(1 for r in grp if r["pass"].startswith("ERROR"))
        gp += n_pass; gf += n_fail; gm += n_miss; ge += n_err
        flag = "" if (n_fail == 0 and n_err == 0) else "  <-- !"
        eff_count = sum(1 for r in grp if int(r["effect_num"]) >= 0)
        print(f"{spec:<24} {eff_count:>8}  {n_pass:>6}  {n_fail:>6}  {n_miss:>6}  {n_err:>4}{flag}")

    print("-" * 76)
    print(f"{'TOTAL':<24} {len(rows):>8}  {gp:>6}  {gf:>6}  {gm:>6}  {ge:>4}")
    print("=" * 76)

    err = [r for r in rows if r["pass"].startswith("ERROR")]
    if err:
        print("\nERROR rows:")
        for r in err:
            print(f"  spec={r['spec']:<24}  msg={r['pass']}")

    miss_rows = [r for r in rows if r["pass"] == "MISS"]
    if miss_rows:
        print(f"\nMISS rows (one side reported nothing):")
        for r in miss_rows:
            print(f"  {r['spec']:<24} eff={r['effect_num']:>2}  N_std={r['N_std']}  N_avg={r['N_avg']}")

    fails = [r for r in rows if r["pass"] == "FAIL"]
    if fails:
        print(f"\nFAIL rows (N_std != N_avg) — the signal:")
        print(f"{'spec':<24} {'eff':>4} {'N_std':>10} {'N_avg':>10} {'diff':>10}")
        print("-" * 64)
        for r in fails:
            print(f"{r['spec']:<24} {r['effect_num']:>4} {r['N_std']:>10} {r['N_avg']:>10} {r['diff']:>10}")
        print()
        sys.exit(1)

    if gf == 0 and ge == 0 and not miss_rows:
        print("\nRESULT: PASS — avg_time_periods switcher counts match the standard pipeline "
              "across every option combination on wagepan.")
    elif gf > 0 or ge > 0 or miss_rows:
        sys.exit(1)


if __name__ == "__main__":
    main()
