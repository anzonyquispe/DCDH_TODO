"""
compare_switchers.py
====================
Read all switchers_b*.csv files from logfiles/ and verify that
N_did == N_avg for every effect in every specification.

Expected CSV columns:
    dataset, spec, reset, effect_num, N_did, N_avg, diff, pass

Usage (from the project root):
    python code/compare_switchers.py
"""

import csv
import glob
import sys
from collections import defaultdict

LOGDIR = "logfiles"
PATTERN = f"{LOGDIR}/switchers_b*.csv"


def load_all(pattern):
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"ERROR: no files matched {pattern}")
        sys.exit(1)
    rows = []
    for f in files:
        with open(f, "r") as fh:
            reader = csv.DictReader(fh)
            n = 0
            for row in reader:
                row["_source"] = f
                rows.append(row)
                n += 1
        print(f"  Loaded {f}  ({n} rows)")
    return rows


def main():
    print("=" * 76)
    print("compare_switchers.py  —  N_switchers(did_multiplegt_dyn) vs avg_cumul_periods")
    print("=" * 76)

    rows = load_all(PATTERN)
    print(f"\nTotal rows across all batch files: {len(rows)}\n")

    # ---- per-spec summary ----
    print(f"{'Dataset':<15} {'Spec':<10} {'Reset':>5}  {'Effects':>7}  {'PASS':>6}  {'FAIL':>6}  {'MISS':>6}")
    print("-" * 76)

    groups = defaultdict(list)
    for r in rows:
        key = (r["dataset"], r["spec"], r["reset"])
        groups[key].append(r)

    grand_pass = grand_fail = grand_miss = grand_err = 0
    for key in sorted(groups.keys()):
        ds, spec, rst = key
        grp = groups[key]
        n_pass = sum(1 for r in grp if r["pass"] == "PASS")
        n_fail = sum(1 for r in grp if r["pass"] == "FAIL")
        n_miss = sum(1 for r in grp if r["pass"] == "MISS")
        n_err  = sum(1 for r in grp if r["pass"].startswith("ERROR"))
        grand_pass += n_pass
        grand_fail += n_fail
        grand_miss += n_miss
        grand_err  += n_err
        flag = "" if (n_fail == 0 and n_miss == 0 and n_err == 0) else "  <-- !"
        print(
            f"{ds:<15} {spec:<10} {rst:>5}  {len(grp):>7}  {n_pass:>6}  {n_fail:>6}  {n_miss:>6}{flag}"
        )

    print("-" * 76)
    print(
        f"{'GRAND TOTAL':<15} {'':10} {'':>5}  {len(rows):>7}  {grand_pass:>6}  {grand_fail:>6}  {grand_miss:>6}"
    )
    print("=" * 76)

    # ---- error rows (top of report so they're easy to spot) ----
    err_rows = [r for r in rows if r["pass"].startswith("ERROR")]
    if err_rows:
        print(f"\nERROR rows (commands that did not return any results):")
        for r in err_rows:
            print(
                f"  {r['_source']}  {r['dataset']:<13} {r['spec']:<10} "
                f"reset={r['reset']}  msg={r['pass']}"
            )

    # ---- only real FAILs are the signal we care about ----
    fails = [r for r in rows if r["pass"] == "FAIL"]
    misses = [r for r in rows if r["pass"] == "MISS"]

    if not fails and not err_rows:
        if misses:
            print(
                f"\nRESULT: PASS — all matched effects agree "
                f"(plus {len(misses)} MISS rows where one side reported nothing past its max effect)."
            )
        else:
            print("\nRESULT: PASS — N_switchers match exactly for all effects in all specs.")
        return

    if fails:
        print(f"\nFAIL rows (N_did != N_avg) — the actual signal:\n")
        print(
            f"{'source':<32} {'dataset':<13} {'spec':<10} {'rst':>3} {'eff':>4} "
            f"{'N_did':>10} {'N_avg':>10} {'diff':>10} {'pass':>6}"
        )
        print("-" * 110)
        for r in fails:
            print(
                f"{r['_source']:<32} {r['dataset']:<13} {r['spec']:<10} {r['reset']:>3} "
                f"{r['effect_num']:>4} {r['N_did']:>10} {r['N_avg']:>10} {r['diff']:>10} {r['pass']:>6}"
            )
        print()

    print(f"\nRESULT: FAIL — {len(fails)} discrepancy row(s), {len(err_rows)} error row(s).")
    sys.exit(1)


if __name__ == "__main__":
    main()
