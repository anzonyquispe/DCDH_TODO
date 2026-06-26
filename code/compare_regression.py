"""
compare_regression.py
---------------------
Reads the CSV exported by tests_stata_reset.do and checks that every
numeric difference between the new (reset) version and the SSC version
is within tolerance.

Usage:
    python compare_regression.py [--csv PATH] [--tol TOLERANCE]

Defaults:
    --csv  ../logfiles/datasets/data_compare_<version>_<dataname>.csv
           (auto-detected: picks the most recently modified CSV in
            ../logfiles/datasets/ matching data_compare_*.csv)
    --tol  1e-8
"""

import argparse
import csv
import glob
import math
import os
import sys


def find_latest_csv(datasets_dir: str) -> str:
    pattern = os.path.join(datasets_dir, "data_compare_*.csv")
    matches = glob.glob(pattern)
    if not matches:
        raise FileNotFoundError(
            f"No data_compare_*.csv files found in {datasets_dir}\n"
            "Run tests_stata_reset.do first."
        )
    return max(matches, key=os.path.getmtime)


def read_comparison_csv(path: str):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows


def run_comparison(csv_path: str, tol: float) -> int:
    rows = read_comparison_csv(csv_path)
    if not rows:
        print("ERROR: CSV is empty.")
        return 1

    # Detect column names
    cols = list(rows[0].keys())
    effect_col = cols[0]
    diff_cols = [c for c in cols if "diff" in c.lower()]
    new_cols  = [c for c in cols if "diff" not in c.lower() and c != effect_col and "ssc" not in c.lower()]
    ssc_cols  = [c for c in cols if "ssc" in c.lower()]

    print(f"\nFile   : {csv_path}")
    print(f"Rows   : {len(rows)}")
    print(f"Tol    : {tol:.2e}\n")
    print(f"{'Row':<5}  {'Effect':<40}  {'New':>14}  {'SSC':>14}  {'Diff':>14}  Status")
    print("-" * 100)

    n_fail = 0
    max_abs_diff = 0.0
    fail_rows = []

    for i, row in enumerate(rows, 1):
        effect = row.get(effect_col, "")

        for dc in diff_cols:
            raw = row.get(dc, "").strip()
            if raw in ("", ".", "NA"):
                continue
            try:
                diff = float(raw)
            except ValueError:
                continue

            abs_diff = abs(diff)
            max_abs_diff = max(max_abs_diff, abs_diff)

            # find matching new / ssc values
            new_val = ssc_val = float("nan")
            for nc in new_cols:
                try:
                    new_val = float(row.get(nc, "nan"))
                except ValueError:
                    pass
            for sc in ssc_cols:
                try:
                    ssc_val = float(row.get(sc, "nan"))
                except ValueError:
                    pass

            if abs_diff > tol:
                status = "FAIL"
                n_fail += 1
                fail_rows.append((i, effect, new_val, ssc_val, diff))
                print(f"{i:<5}  {effect:<40}  {new_val:>14.7g}  {ssc_val:>14.7g}  {diff:>14.7g}  {status}")

    print("-" * 100)
    print(f"\nSummary")
    print(f"  Total rows checked : {len(rows)}")
    print(f"  Rows with |diff| > {tol:.2e} : {n_fail}")
    print(f"  Maximum |diff|     : {max_abs_diff:.6e}")

    if n_fail == 0:
        print("\n  RESULT: PASS — new and SSC versions are numerically identical.")
        return 0
    else:
        print(f"\n  RESULT: FAIL — {n_fail} row(s) differ beyond tolerance.")
        return 1


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    datasets_dir = os.path.normpath(os.path.join(here, "..", "logfiles", "datasets"))

    parser = argparse.ArgumentParser(description="Compare new vs SSC did_multiplegt_dyn results.")
    parser.add_argument("--csv", default=None,
                        help="Path to data_compare_*.csv (auto-detected if omitted)")
    parser.add_argument("--tol", type=float, default=1e-8,
                        help="Tolerance for flagging differences (default 1e-8)")
    args = parser.parse_args()

    csv_path = args.csv or find_latest_csv(datasets_dir)
    sys.exit(run_comparison(csv_path, args.tol))


if __name__ == "__main__":
    main()
