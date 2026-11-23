#!/usr/bin/env bash
# run_all.sh -- run the by_path tests in Stata, R and Python, then compare.
#
# Usage (from anywhere; works in Git Bash on Windows, macOS and Linux):
#   bash tests_by_path/run_all.sh                  # all steps
#   bash tests_by_path/run_all.sh r python compare # only some steps
#
# Optional environment variables
#   STATA_BIN           Stata executable (auto-detected otherwise)
#   RSCRIPT, PYTHON     interpreters (default: Rscript, python3/python)
#   DCDH_STATA_ADO_DIR  folder with did_multiplegt_dyn.ado ("installed" = use Stata's)
#   DCDH_R_SOURCE       R package source folder for pkgload::load_all()
#   DCDH_R_LIB          extra R library folder
#   DCDH_PY_SRC         folder containing the did_multiplegt_dyn Python package
#   DCDH_ONLY_CASES     space-separated case_ids to run

set -u
cd "$(dirname "$0")" || exit 1
TB="$(pwd)"
RES="$TB/results"
STEPS="${*:-stata r python compare}"
mkdir -p "$RES/logs_stata"

IS_WIN=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; esac

find_stata() {
  [[ -n "${STATA_BIN:-}" ]] && { echo "$STATA_BIN"; return; }
  for c in stata-mp stata-se stata StataMP-64 StataSE-64; do
    command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return; }
  done
  for c in "/c/Program Files/Stata"*/Stata*-64.exe \
           "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp" \
           "/Applications/Stata/StataSE.app/Contents/MacOS/stata-se" \
           "/usr/local/stata"*/stata-mp; do
    [[ -x "$c" ]] && { echo "$c"; return; }
  done
}

PY="${PYTHON:-$(command -v python3 || command -v python)}"
RS="${RSCRIPT:-Rscript}"
STATUS=0
PIDS=()

if [[ " $STEPS " == *" stata "* ]]; then
  SB="$(find_stata)"
  if [[ -z "$SB" ]]; then
    echo "ERROR: Stata not found; set STATA_BIN."; STATUS=1
  else
    rm -f "$RES/stata_results.csv" "$RES/stata_validation.csv" "$RES/stata_meta.txt"
    echo ">> Stata: $SB"
    (
      cd "$RES/logs_stata" || exit 1
      if [[ $IS_WIN -eq 1 ]]; then
        # MSYS_NO_PATHCONV stops Git Bash from turning /e into a path.
        MSYS_NO_PATHCONV=1 "$SB" /e do "$(cygpath -w "$TB/stata/test_by_path.do")" "$(cygpath -w "$TB")"
      else
        "$SB" -b do "$TB/stata/test_by_path.do" "$TB"
      fi
      grep -q "^finished_at=" "$RES/stata_meta.txt" 2>/dev/null
    ) &
    PIDS+=("$!:stata")
  fi
fi

if [[ " $STEPS " == *" r "* ]]; then
  rm -f "$RES/r_results.csv" "$RES/r_validation.csv" "$RES/r_meta.txt"
  echo ">> R: $RS"
  "$RS" "$TB/r/test_by_path.R" > "$RES/r_console.log" 2>&1 &
  PIDS+=("$!:r")
fi

if [[ " $STEPS " == *" python "* ]]; then
  rm -f "$RES/python_results.csv" "$RES/python_validation.csv" "$RES/python_meta.txt"
  echo ">> Python: $PY"
  "$PY" "$TB/python/test_by_path.py" > "$RES/python_console.log" 2>&1 &
  PIDS+=("$!:python")
fi

for entry in "${PIDS[@]}"; do
  pid="${entry%%:*}"; name="${entry##*:}"
  if wait "$pid"; then
    echo "   $name finished"
  else
    echo "   $name FAILED (see $RES)"; STATUS=1
  fi
done

if [[ " $STEPS " == *" compare "* ]]; then
  echo ""
  "$PY" "$TB/compare/compare_by_path.py" || STATUS=1
fi
exit $STATUS
