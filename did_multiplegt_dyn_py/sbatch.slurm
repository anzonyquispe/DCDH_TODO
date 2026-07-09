#!/bin/bash
#SBATCH --job-name=did_py_tests
#SBATCH --output=did_multiplegt_dyn_py/tests/results/slurm_%j.log
#SBATCH --error=did_multiplegt_dyn_py/tests/results/slurm_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=7
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --partition=standard          # ← adjust to your cluster partition

cd "$(dirname "$0")/.." || exit 1

PY=$(command -v python3 || command -v python)
[[ -z "$PY" ]] && { echo "ERROR: python not found"; exit 1; }

# install package in editable mode if not already installed
pip install -q -e did_multiplegt_dyn_py/

mkdir -p did_multiplegt_dyn_py/tests/results

echo "=== Python DID test suite started: $(date) ==="

"$PY" did_multiplegt_dyn_py/tests/test_b1_gentzkow_noreset.py &  PID1=$!
"$PY" did_multiplegt_dyn_py/tests/test_b2_gentzkow_reset4.py  &  PID2=$!
"$PY" did_multiplegt_dyn_py/tests/test_b3_wagepan_noreset.py  &  PID3=$!
"$PY" did_multiplegt_dyn_py/tests/test_b4_wagepan_reset4.py   &  PID4=$!
"$PY" did_multiplegt_dyn_py/tests/test_b5_favara_noreset.py   &  PID5=$!
"$PY" did_multiplegt_dyn_py/tests/test_b6_favara_reset4.py    &  PID6=$!
"$PY" did_multiplegt_dyn_py/tests/test_wagepan_specs.py        &  PID7=$!

FAIL=0
for pid in $PID1 $PID2 $PID3 $PID4 $PID5 $PID6 $PID7; do
  wait "$pid" || FAIL=$((FAIL + 1))
done

echo "=== Scripts finished: $(date) ==="

echo ""; echo "--- compare_switchers.py ---"
"$PY" did_multiplegt_dyn_py/tests/compare_switchers.py;  CMP1=$?

echo ""; echo "--- compare_wagepan_specs.py ---"
"$PY" did_multiplegt_dyn_py/tests/compare_wagepan_specs.py; CMP2=$?

if [[ $FAIL -eq 0 && $CMP1 -eq 0 && $CMP2 -eq 0 ]]; then
  echo "=== RESULT: ALL TESTS PASSED ==="; exit 0
else
  echo "=== RESULT: SOME TESTS FAILED ==="; exit 1
fi
