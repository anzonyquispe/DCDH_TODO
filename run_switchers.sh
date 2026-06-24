#!/bin/bash
# run_switchers.sh
# Runs all 6 switcher test dofiles in parallel on macOS.
# Usage: bash run_switchers.sh

# ─── USER SETTINGS ────────────────────────────────────────────────────────────
PROJECT_DIR="/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"

# Auto-detect Stata binary: tries stata-mp first, then stata-se, then stata.
# If none are found on PATH, falls back to searching /Applications.
if command -v stata-mp &>/dev/null; then
    STATA_BIN="stata-mp"
elif command -v stata-se &>/dev/null; then
    STATA_BIN="stata-se"
elif command -v stata &>/dev/null; then
    STATA_BIN="stata"
else
    STATA_BIN=$(find /Applications -name 'stata-mp' 2>/dev/null | head -1)
    if [[ -z "${STATA_BIN}" ]]; then
        STATA_BIN=$(find /Applications -name 'stata-se' 2>/dev/null | head -1)
    fi
    if [[ -z "${STATA_BIN}" ]]; then
        echo "ERROR: Stata executable not found. Set STATA_BIN manually in this script."
        exit 1
    fi
fi
# ──────────────────────────────────────────────────────────────────────────────

cd "${PROJECT_DIR}" || { echo "ERROR: cannot cd to ${PROJECT_DIR}"; exit 1; }
mkdir -p logfiles

echo "============================================================"
echo "run_switchers.sh  started: $(date)"
echo "Project : ${PROJECT_DIR}"
echo "Stata   : ${STATA_BIN}"
echo "============================================================"

PIDS=()
BATCHES=(1 2 3 4 5 6)

for b in "${BATCHES[@]}"; do
    DOFILE="code/test_switchers_b${b}.do"
    SLURM_LOG="logfiles/shell_b${b}.log"

    echo "  Launching batch ${b}: ${DOFILE}"

    "${STATA_BIN}" -b do "${DOFILE}" \
        > "${SLURM_LOG}" 2>&1 &

    PIDS+=($!)
done

echo ""
echo "All 6 batches launched. Waiting for completion..."
echo "(check logfiles/shell_b{1..6}.log and logfiles/test_switchers_b{1..6}.log)"
echo ""

# Wait for each PID and collect exit codes
FAILED=()
for i in "${!PIDS[@]}"; do
    b="${BATCHES[$i]}"
    pid="${PIDS[$i]}"
    wait "${pid}"
    rc=$?
    if [[ ${rc} -ne 0 ]]; then
        echo "  [WARN] batch ${b} exited with code ${rc}"
        FAILED+=("${b}")
    else
        echo "  [OK]   batch ${b} finished"
    fi
done

echo ""
echo "============================================================"
echo "run_switchers.sh  finished: $(date)"
if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo "All batches completed successfully."
    echo "Run:  python code/compare_switchers.py"
else
    echo "Batches with non-zero exit: ${FAILED[*]}"
    echo "Inspect logs in logfiles/shell_b{N}.log and logfiles/test_switchers_b{N}.log"
fi
echo "============================================================"
