#!/bin/bash
#SBATCH --job-name=did_R_tests
#SBATCH --output=tests_R/results/slurm_%j.log
#SBATCH --error=tests_R/results/slurm_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=7
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --partition=standard          # ← adjust to your cluster partition

# ── run from the project root ─────────────────────────────────────────────────
cd "$(dirname "$0")/.." || exit 1

echo "=== R test suite started: $(date) ==="
echo "Working directory: $(pwd)"

RSCRIPT=$(command -v Rscript)
if [[ -z "$RSCRIPT" ]]; then
  echo "ERROR: Rscript not found. Load the R module first."
  exit 1
fi

mkdir -p tests_R/results

# ── Run all 7 R scripts in parallel ──────────────────────────────────────────
"$RSCRIPT" tests_R/R/test_b1_gentzkow_noreset.R &  PID1=$!
"$RSCRIPT" tests_R/R/test_b2_gentzkow_reset4.R  &  PID2=$!
"$RSCRIPT" tests_R/R/test_b3_wagepan_noreset.R  &  PID3=$!
"$RSCRIPT" tests_R/R/test_b4_wagepan_reset4.R   &  PID4=$!
"$RSCRIPT" tests_R/R/test_b5_favara_noreset.R   &  PID5=$!
"$RSCRIPT" tests_R/R/test_b6_favara_reset4.R    &  PID6=$!
"$RSCRIPT" tests_R/R/test_wagepan_specs.R        &  PID7=$!

# wait for all and collect exit codes
FAIL=0
for pid in $PID1 $PID2 $PID3 $PID4 $PID5 $PID6 $PID7; do
  wait "$pid" || FAIL=$((FAIL + 1))
done

echo ""
echo "=== All R scripts finished: $(date) ==="

if [[ $FAIL -gt 0 ]]; then
  echo "WARNING: $FAIL R script(s) exited with non-zero status."
fi

# ── Python comparators ────────────────────────────────────────────────────────
echo ""
echo "--- compare_switchers.py ---"
python3 tests_R/compare/compare_switchers.py
CMP1=$?

echo ""
echo "--- compare_wagepan_specs.py ---"
python3 tests_R/compare/compare_wagepan_specs.py
CMP2=$?

# ── Final verdict ─────────────────────────────────────────────────────────────
echo ""
if [[ $FAIL -eq 0 && $CMP1 -eq 0 && $CMP2 -eq 0 ]]; then
  echo "=== RESULT: ALL TESTS PASSED ==="
  exit 0
else
  echo "=== RESULT: SOME TESTS FAILED  (R_fails=$FAIL  cmp1=$CMP1  cmp2=$CMP2) ==="
  exit 1
fi
