#!/usr/bin/env bash
# run_bootstrap.sh -- R bootstrap tests: R runs, Stata replay of R's resamples, verdicts.
#
#   bash R_bootstrap/run_bootstrap.sh                          # asks which versions to test
#   bash R_bootstrap/run_bootstrap.sh --r-pkg installed --stata-ado installed
#   bash R_bootstrap/run_bootstrap.sh --only "RB01 RB03" --reps 10
#   bash R_bootstrap/run_bootstrap.sh --skip stata            # R-only checks
#
# Options: --r-pkg, --stata-ado (same values as run_tests.sh; read from ../config.env
# too), --only "BIDS", --reps N (override the reps in bootstrap_specs.csv),
# --skip stata, --results DIR (default R_bootstrap/results), --yes (never ask).

set -u
cd "$(dirname "$0")/.." || exit 1
SUITE="$(pwd)"
RES="$SUITE/R_bootstrap/results"
CONFIG="$SUITE/config.env"
ONLY="" REPS="" SKIP="" YES=0 A_R="" A_STATA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --r-pkg) A_R="$2"; shift 2 ;;
    --stata-ado) A_STATA="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --reps) REPS="$2"; shift 2 ;;
    --skip) SKIP=",$2,"; shift 2 ;;
    --results) RES="$2"; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
if [[ -f "$CONFIG" ]]; then
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" == \#* ]] && continue
    v="${v%$'\r'}"; v="${v%\"}"; v="${v#\"}"; export "$k=$v"
  done < "$CONFIG"
fi
[[ -n "$A_R" ]] && export DCDH_R_PKG="$A_R"
[[ -n "$A_STATA" ]] && export DCDH_STATA_ADO="$A_STATA"
ask() {
  local var="$1" q="$2" val
  [[ -n "${!var:-}" ]] && return
  if [[ $YES -eq 1 || ! -t 0 ]]; then echo "ERROR: $var is not set ($q)"; exit 2; fi
  read -r -p "$q > " val
  [[ -z "$val" ]] && { echo "ERROR: an answer is required (nothing is assumed)."; exit 2; }
  export "$var=$val"
}
ask DCDH_R_PKG "Which DIDmultiplegtDYN should R test? (installed | source folder | .tar.gz)"
[[ "$SKIP" == *",stata,"* ]] || ask DCDH_STATA_ADO "Which did_multiplegt_dyn.ado should Stata use? (installed | file | folder)"

find_python() {
  [[ -n "${PYTHON:-}" ]] && { echo "$PYTHON"; return; }
  for c in python3 python py; do
    command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1 && { command -v "$c"; return; }
  done
}
PY="$(find_python)"; RS="${RSCRIPT:-Rscript}"
export DCDH_ONLY="$ONLY" DCDH_BOOT_REPS="$REPS"
mkdir -p "$RES"
echo ">> R bootstrap runs ($DCDH_R_PKG) -> $RES"
"$RS" "$SUITE/R_bootstrap/run_bootstrap.R" "$SUITE" "$RES" > "$RES/r_console.log" 2>&1 || echo "   R exited with an error (see $RES/r_console.log)"

if [[ "$SKIP" != *",stata,"* ]]; then
  SB="${STATA_BIN:-}"
  if [[ -z "$SB" ]]; then
    for c in stata-mp stata-se stata StataMP-64 StataSE-64; do command -v "$c" >/dev/null 2>&1 && { SB="$(command -v "$c")"; break; }; done
    for c in "/c/Program Files/Stata"*/Stata*-64.exe "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp" "/usr/local/stata"*/stata-mp; do
      [[ -z "$SB" && -x "$c" ]] && SB="$c"
    done
  fi
  echo ">> Stata replay of R's resamples ($DCDH_STATA_ADO)"
  (
    cd "$RES" || exit 1
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) MSYS_NO_PATHCONV=1 "$SB" /e do "$(cygpath -w "$SUITE/R_bootstrap/manual_bootstrap.do")" "$(cygpath -w "$SUITE")" "$(cygpath -w "$RES")" ;;
      *) "$SB" -b do "$SUITE/R_bootstrap/manual_bootstrap.do" "$SUITE" "$RES" ;;
    esac
  ) > "$RES/stata_console.log" 2>&1
fi
echo ""
"$PY" "$SUITE/R_bootstrap/compare_bootstrap.py" "$RES"
