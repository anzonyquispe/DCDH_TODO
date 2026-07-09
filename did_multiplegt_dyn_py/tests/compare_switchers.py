"""Compare results/switchers_b*.csv — mirrors code/compare_switchers.py."""
import csv, glob, sys
from collections import defaultdict
from pathlib import Path

RESULTS_DIR = Path(__file__).parent / "results"
PATTERN     = str(RESULTS_DIR / "switchers_b*.csv")

def main():
    print("=" * 76)
    print("compare_switchers.py [Python]  —  N_switchers_effect_k vs N_switch_avg_k")
    print("=" * 76)

    files = sorted(glob.glob(PATTERN))
    if not files:
        print(f"ERROR: no files matched {PATTERN}")
        sys.exit(1)

    rows = []
    for f in files:
        with open(f) as fh:
            for row in csv.DictReader(fh):
                row["_source"] = f; rows.append(row)
        print(f"  Loaded {f}  ({sum(1 for _ in open(f)) - 1} rows)")

    groups = defaultdict(list)
    for r in rows:
        groups[(r["dataset"], r["spec"], r["reset"])].append(r)

    print(f"\n{'Dataset':<15} {'Spec':<10} {'Reset':>5}  "
          f"{'Effects':>7}  {'PASS':>6}  {'FAIL':>6}  {'MISS':>6}")
    print("-" * 76)

    gp = gf = gm = ge = 0
    for key in sorted(groups):
        ds, spec, rst = key
        grp = groups[key]
        n_pass = sum(1 for r in grp if r["pass"] == "PASS")
        n_fail = sum(1 for r in grp if r["pass"] == "FAIL")
        n_miss = sum(1 for r in grp if r["pass"] == "MISS")
        n_err  = sum(1 for r in grp if r["pass"].startswith("ERROR"))
        gp += n_pass; gf += n_fail; gm += n_miss; ge += n_err
        flag = "  <-- !" if (n_fail or n_err) else ""
        n_eff = sum(1 for r in grp if int(r["effect_num"]) >= 0)
        print(f"{ds:<15} {spec:<10} {rst:>5}  "
              f"{n_eff:>7}  {n_pass:>6}  {n_fail:>6}  {n_miss:>6}  {flag}")

    print("-" * 76)
    print(f"{'TOTAL':<33}  {len(rows):>7}  {gp:>6}  {gf:>6}  {gm:>6}")
    print("=" * 76)

    fails = [r for r in rows if r["pass"] == "FAIL"]
    if fails:
        print(f"\nFAIL rows ({len(fails)}):")
        for r in fails:
            print(f"  {r['dataset']:<15} {r['spec']:<10} reset={r['reset']} "
                  f"eff={r['effect_num']:>3}  N_did={r['N_did']}  N_avg={r['N_avg']}")
        sys.exit(1)

    if gf == 0 and ge == 0 and gm == 0:
        print("\nRESULT: PASS — all switcher counts match.")
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
