#!/usr/bin/env bash
# run_all.sh — run the full R test suite locally (no SLURM needed)
# Usage (from project root):  bash tests_R/run_all.sh
# Usage (from tests_R/):      bash run_all.sh

cd "$(dirname "$0")/.." || exit 1

RSCRIPT=$(command -v Rscript)
if [[ -z "$RSCRIPT" ]]; then
  echo "ERROR: Rscript not found."
  exit 1
fi

mkdir -p tests_R/results

echo "=== R test suite started: $(date) ==="

"$RSCRIPT" tests_R/R/test_b1_gentzkow_noreset.R &  PID1=$!
"$RSCRIPT" tests_R/R/test_b2_gentzkow_reset4.R  &  PID2=$!
"$RSCRIPT" tests_R/R/test_b3_wagepan_noreset.R  &  PID3=$!
"$RSCRIPT" tests_R/R/test_b4_wagepan_reset4.R   &  PID4=$!
"$RSCRIPT" tests_R/R/test_b5_favara_noreset.R   &  PID5=$!
"$RSCRIPT" tests_R/R/test_b6_favara_reset4.R    &  PID6=$!
"$RSCRIPT" tests_R/R/test_wagepan_specs.R        &  PID7=$!

FAIL=0
for pid in $PID1 $PID2 $PID3 $PID4 $PID5 $PID6 $PID7; do
  wait "$pid" || FAIL=$((FAIL + 1))
done

echo ""
echo "=== R scripts finished: $(date) ==="

echo ""
echo "--- compare_switchers.py ---"
python3 tests_R/compare/compare_switchers.py
CMP1=$?

echo ""
echo "--- compare_wagepan_specs.py ---"
python3 tests_R/compare/compare_wagepan_specs.py
CMP2=$?

echo ""
if [[ $FAIL -eq 0 && $CMP1 -eq 0 && $CMP2 -eq 0 ]]; then
  echo "=== RESULT: ALL TESTS PASSED ==="
  exit 0
else
  echo "=== RESULT: SOME TESTS FAILED  (R_fails=$FAIL  cmp1=$CMP1  cmp2=$CMP2) ==="
  exit 1
fi
