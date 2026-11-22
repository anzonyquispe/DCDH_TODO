#!/usr/bin/env bash
# run_tests.sh -- run the did_multiplegt_dyn suite in Stata, R and Python, then compare.
#
#   bash run_tests.sh                       # asks which package versions to test
#   bash run_tests.sh --stata-ado installed --r-pkg ../did_multiplegt_dyn/R --py-pkg ../py_did_multiplegt_dyn/src
#   bash run_tests.sh --only "A02 F14" --skip stata      # reuse Stata's last results
#   bash run_tests.sh --blocks "F G"
#
# Which versions are tested is ALWAYS the user's choice; nothing is defaulted.
# The three answers can be given as options, in config.env (see config.example.env)
# or interactively. Values:
#   --stata-ado  a did_multiplegt_dyn.ado file, the folder that contains it, or "installed"
#   --r-pkg      "installed", a package source folder, a .tar.gz, or a library folder
#   --py-pkg     "installed", or the folder that contains the did_multiplegt_dyn package (…/src)
#
# Other options:
#   --only "IDS"     spec ids to run          --blocks "A B"  blocks to run
#   --skip LIST      comma list of stata,r,python,compare to skip
#   --results DIR    where results go (default: ./results)
#   --config FILE    config file (default: ./config.env)
#   --yes            do not ask anything (fail if a version is missing)
#   --selftest       also run compare/selftest.py
#   --parallel       run Stata, R and Python at the same time (faster; needs a lot of
#                    memory: the largest spec alone uses ~6 GB per language)

set -u
cd "$(dirname "$0")" || exit 1
SUITE="$(pwd)"
CONFIG="$SUITE/config.env"
RES="$SUITE/results"
ONLY="" BLOCKS="" SKIP="" YES=0 SELFTEST=0 PARALLEL=0
A_STATA="" A_R="" A_PY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stata-ado) A_STATA="$2"; shift 2 ;;
    --r-pkg)     A_R="$2"; shift 2 ;;
    --py-pkg)    A_PY="$2"; shift 2 ;;
    --only)      ONLY="$2"; shift 2 ;;
    --blocks)    BLOCKS="$2"; shift 2 ;;
    --skip)      SKIP=",$2,"; shift 2 ;;
    --results)   RES="$2"; shift 2 ;;
    --config)    CONFIG="$2"; shift 2 ;;
    --yes|-y)    YES=1; shift ;;
    --selftest)  SELFTEST=1; shift ;;
    --parallel)  PARALLEL=1; shift ;;
    -h|--help)   sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown option $1 (see --help)"; exit 2 ;;
  esac
done
skipped() { [[ "$SKIP" == *",$1,"* ]]; }

# config.env: KEY=VALUE lines (command-line options win)
if [[ -f "$CONFIG" ]]; then
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" == \#* ]] && continue
    v="${v%$'\r'}"; v="${v%\"}"; v="${v#\"}"
    export "$k=$v"
  done < "$CONFIG"
fi
[[ -n "$A_STATA" ]] && export DCDH_STATA_ADO="$A_STATA"
[[ -n "$A_R" ]]     && export DCDH_R_PKG="$A_R"
[[ -n "$A_PY" ]]    && export DCDH_PY_PKG="$A_PY"

IS_WIN=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; esac

ask() {  # ask VAR "question" "examples"
  local var="$1" q="$2" ex="$3" val
  if [[ -n "${!var:-}" ]]; then return; fi
  if [[ $YES -eq 1 || ! -t 0 ]]; then
    echo "ERROR: $var is not set ($q). Pass it as an option or put it in $CONFIG."; exit 2
  fi
  echo ""
  echo "$q"
  echo "  e.g. $ex"
  read -r -p "> " val
  [[ -z "$val" ]] && { echo "ERROR: an answer is required (nothing is assumed)."; exit 2; }
  export "$var=$val"
  NEW_ANSWERS=1
}
NEW_ANSWERS=0
skipped stata  || ask DCDH_STATA_ADO "Which did_multiplegt_dyn.ado should Stata test (the reference)?" \
  "installed | C:/.../did_multiplegt_dyn/Stata | C:/.../did_multiplegt_dyn.ado"
skipped r      || ask DCDH_R_PKG "Which DIDmultiplegtDYN should R test?" \
  "installed | C:/.../did_multiplegt_dyn/R (source folder) | DIDmultiplegtDYN_2.4.0.tar.gz"
skipped python || ask DCDH_PY_PKG "Which did_multiplegt_dyn should Python test?" \
  "installed | C:/.../py_did_multiplegt_dyn/src"
if [[ $NEW_ANSWERS -eq 1 && -t 0 ]]; then
  read -r -p "Save these answers to $CONFIG for next time? [y/N] " yn
  if [[ "$yn" == [yY]* ]]; then
    { echo "# written by run_tests.sh on $(date)"
      echo "DCDH_STATA_ADO=${DCDH_STATA_ADO:-}"; echo "DCDH_R_PKG=${DCDH_R_PKG:-}"; echo "DCDH_PY_PKG=${DCDH_PY_PKG:-}"
      [[ -n "${STATA_BIN:-}" ]] && echo "STATA_BIN=$STATA_BIN"
      [[ -n "${RSCRIPT:-}" ]] && echo "RSCRIPT=$RSCRIPT"
      [[ -n "${PYTHON:-}" ]] && echo "PYTHON=$PYTHON"; } > "$CONFIG"
    echo "saved $CONFIG"
  fi
fi

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
find_python() {  # first interpreter that really runs (python3 can be a Windows Store stub)
  [[ -n "${PYTHON:-}" ]] && { echo "$PYTHON"; return; }
  for c in python3 python py; do
    command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1 && { command -v "$c"; return; }
  done
}
PY="$(find_python)"
RS="${RSCRIPT:-Rscript}"
SB=""; skipped stata || SB="$(find_stata)"

export DCDH_ONLY="$ONLY" DCDH_BLOCKS="$BLOCKS"
mkdir -p "$RES"
echo ""
echo "================ did_multiplegt_dyn suite ================"
skipped stata  || echo "  Stata  : ${SB:-NOT FOUND}   ado: $DCDH_STATA_ADO"
skipped r      || echo "  R      : $RS   package: $DCDH_R_PKG"
skipped python || echo "  Python : $PY   package: $DCDH_PY_PKG"
[[ -n "$ONLY$BLOCKS" ]] && echo "  subset : only='$ONLY' blocks='$BLOCKS'"
echo "  results: $RES"
echo ""

PYTHON="$PY" RSCRIPT="$RS" STATA_BIN="$SB" bash "$SUITE/check_env.sh" "$SKIP" || exit 2

STATUS=0
PIDS=()
if ! skipped stata; then
  rm -rf "$RES/stata"
  (
    cd "$RES" || exit 1
    if [[ $IS_WIN -eq 1 ]]; then
      # MSYS_NO_PATHCONV stops Git Bash from turning /e into a path
      MSYS_NO_PATHCONV=1 "$SB" /e do "$(cygpath -w "$SUITE/Stata/run_specs.do")" "$(cygpath -w "$SUITE")" "$(cygpath -w "$RES")"
    else
      "$SB" -b do "$SUITE/Stata/run_specs.do" "$SUITE" "$RES"
    fi
    grep -q "^finished_at=" "$RES/stata/meta.txt" 2>/dev/null   # batch Stata always exits 0
  ) > "$RES/stata_console.log" 2>&1 &
  PIDS+=("$!:stata")
  [[ $PARALLEL -eq 1 ]] || { echo "  stata running..."; wait "$!"; echo "  stata exit $?"; }
fi
if ! skipped r; then
  rm -rf "$RES/r"
  "$RS" "$SUITE/R/run_specs.R" "$SUITE" "$RES" > "$RES/r_console.log" 2>&1 &
  PIDS+=("$!:r")
  [[ $PARALLEL -eq 1 ]] || { echo "  r running..."; wait "$!"; echo "  r exit $?"; }
fi
if ! skipped python; then
  rm -rf "$RES/python"
  "$PY" "$SUITE/Python/run_specs.py" "$SUITE" "$RES" > "$RES/python_console.log" 2>&1 &
  PIDS+=("$!:python")
  [[ $PARALLEL -eq 1 ]] || { echo "  python running..."; wait "$!"; echo "  python exit $?"; }
fi
echo "running... (logs: $RES/*_console.log)"
[[ $PARALLEL -eq 1 ]] && for entry in "${PIDS[@]}"; do wait "${entry%%:*}"; done
for entry in "${PIDS[@]}"; do
  name="${entry##*:}"
  if grep -q "^finished_at=" "$RES/$name/meta.txt" 2>/dev/null; then echo "  $name finished"
  else echo "  $name DID NOT FINISH (see $RES/${name}_console.log); specs it did not reach are reported as ERROR"; STATUS=1; fi
done

if ! skipped compare; then
  echo ""
  "$PY" "$SUITE/compare/compare.py" "$RES" || STATUS=1
fi
if [[ $SELFTEST -eq 1 ]]; then
  "$PY" "$SUITE/compare/selftest.py" "$RES" || STATUS=1
fi
exit $STATUS
