"""
compare_avg_time.py
-------------------
Reads the CSV exported by test_avg_time_integration.do and checks that
avg_cumul_XX from the integrated did_multiplegt_dyn option matches the
standalone avg_cumul_periods function within tolerance.

Usage:
    python compare_avg_time.py [--csv PATH] [--tol TOLERANCE]

Defaults:
    --csv  ../logfiles/avg_time_integration_results.csv
    --tol  1e-6
"""

import argparse
import csv
import math
import os
import sys


DEFAULT_CSV = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "..", "logfiles", "avg_time_integration_results.csv")
)


def read_csv(path: str):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows


def run_comparison(csv_path: str, tol: float) -> int:
    if not os.path.exists(csv_path):
        print(f"ERROR: CSV not found at {csv_path}")
        print("Run test_avg_time_integration.do first.")
        return 1

    rows = read_csv(csv_path)
    if not rows:
        print("ERROR: CSV is empty.")
        return 1

    print(f"\nFile   : {csv_path}")
    print(f"Rows   : {len(rows)}")
    print(f"Tol    : {tol:.2e}\n")

    header = f"{'Scenario':<40}  {'Integrated':>12}  {'Standalone':>12}  {'Diff':>12}  Status"
    print(header)
    print("-" * len(header))

    n_fail = 0
    max_abs_diff = 0.0

    for row in rows:
        scenario   = row.get("scenario", "?")
        pass_flag  = row.get("pass", "?").strip()

        try:
            integrated = float(row["integrated"])
            standalone = float(row["standalone"])
            diff       = float(row["diff"])
        except (KeyError, ValueError):
            print(f"  WARNING: cannot parse row for scenario '{scenario}', skipping.")
            continue

        abs_diff = abs(diff)
        max_abs_diff = max(max_abs_diff, abs_diff)

        # Re-evaluate against requested tol (Stata used 1e-6 in the CSV)
        status = "PASS" if abs_diff <= tol else "FAIL"
        if status == "FAIL":
            n_fail += 1

        int_str = f"{integrated:.7g}" if not math.isnan(integrated) else "."
        sta_str = f"{standalone:.7g}" if not math.isnan(standalone) else "."
        dif_str = f"{diff:.3e}"      if not math.isnan(diff)       else "."

        print(f"{scenario:<40}  {int_str:>12}  {sta_str:>12}  {dif_str:>12}  {status}")

    print("-" * len(header))
    print(f"\nSummary")
    print(f"  Scenarios checked          : {len(rows)}")
    print(f"  Scenarios with |diff| > {tol:.0e} : {n_fail}")
    print(f"  Maximum |diff|             : {max_abs_diff:.6e}")

    if n_fail == 0:
        print("\n  RESULT: PASS — integrated option matches standalone function.")
        return 0
    else:
        print(f"\n  RESULT: FAIL — {n_fail} scenario(s) differ beyond tolerance.")
        return 1


def main():
    parser = argparse.ArgumentParser(
        description="Check that avg_time_periods integrated option matches standalone avg_cumul_periods."
    )
    parser.add_argument("--csv", default=DEFAULT_CSV,
                        help=f"Path to CSV (default: {DEFAULT_CSV})")
    parser.add_argument("--tol", type=float, default=1e-6,
                        help="Tolerance for flagging differences (default 1e-6)")
    args = parser.parse_args()

    sys.exit(run_comparison(args.csv, args.tol))


if __name__ == "__main__":
    main()
