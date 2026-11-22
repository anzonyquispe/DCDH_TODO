#!/usr/bin/env bash
# check_env.sh -- check that Stata, R and Python can run the suite.
# Called by run_tests.sh; can also be run alone:  bash check_env.sh
# Uses STATA_BIN, RSCRIPT, PYTHON and DCDH_R_PKG / DCDH_PY_PKG if set.
# First argument: the --skip list of run_tests.sh (e.g. ",stata,").

SKIP="${1:-}"
skipped() { [[ "$SKIP" == *",$1,"* ]]; }
OK=1
say() { printf '  %-8s %s\n' "$1" "$2"; }

if ! skipped stata; then
  if [[ -n "${STATA_BIN:-}" && -x "$STATA_BIN" ]] || command -v "${STATA_BIN:-stata-mp}" >/dev/null 2>&1; then
    say stata "ok ($STATA_BIN)"
  else
    say stata "NOT FOUND - set STATA_BIN"; OK=0
  fi
fi

if ! skipped r; then
  RS="${RSCRIPT:-Rscript}"
  if ! command -v "$RS" >/dev/null 2>&1; then
    say r "Rscript NOT FOUND - set RSCRIPT"; OK=0
  else
    need="haven polars"
    [[ -f "${DCDH_R_PKG:-}/DESCRIPTION" ]] && need="$need pkgload"
    [[ "${DCDH_R_PKG:-}" == "installed" ]] && need="$need DIDmultiplegtDYN"
    miss=$("$RS" -e "for (p in strsplit('$need',' ')[[1]]) if (!requireNamespace(p, quietly=TRUE)) cat(p, '')" 2>/dev/null)
    if [[ -n "$miss" ]]; then
      say r "missing R packages: $miss"
      [[ "$miss" == *polars* ]] && say "" 'install with: install.packages("polars", repos = "https://rpolars.r-universe.dev")'
      OK=0
    else
      say r "ok ($("$RS" -e 'cat(R.version.string)' 2>/dev/null))"
    fi
  fi
fi

if ! skipped python; then
  PY="${PYTHON:-python}"
  msg=$("$PY" - <<'EOF' 2>&1
import importlib, sys
bad = [m for m in ("numpy", "pandas", "polars") if importlib.util.find_spec(m) is None]
if bad:
    print("missing Python packages: " + " ".join(bad)); sys.exit(1)
import polars
major = int(polars.__version__.split(".")[0])
print(f"ok (Python {sys.version.split()[0]}, polars {polars.__version__})"
      + ("  WARNING: did_multiplegt_dyn currently breaks with polars>=2 (pl.count removed); use polars<2" if major >= 2 else ""))
EOF
)
  rc=$?
  say python "$msg"
  [[ $rc -ne 0 ]] && OK=0
fi

[[ $OK -eq 1 ]] && exit 0
echo "Environment check failed; fix the items above."
exit 1
