# by_path cross-language tests (Stata / R / Python)

Checks that the `by_path` option of `did_multiplegt_dyn` gives the same answer
in Stata, R (`DIDmultiplegtDYN`) and Python (`py_did_multiplegt_dyn`).
Stata is the reference.

```
tests_by_path/
  cases.csv                 estimation cases, shared by all three languages
  validation_cases.csv      invalid / edge inputs (0, -1, "ALL", 2.5, by + by_path, ...)
  stata/test_by_path.do     -> results/stata_results.csv, stata_validation.csv, stata_meta.txt
  r/test_by_path.R          -> results/r_results.csv,     r_validation.csv,     r_meta.txt
  python/test_by_path.py    -> results/python_results.csv, python_validation.csv, python_meta.txt
  compare/compare_by_path.py-> results/comparison_summary.txt, comparison_details.csv
  run_all.sh                runs the three languages in parallel, then the comparison
```

## Running

```bash
bash tests_by_path/run_all.sh                    # everything
bash tests_by_path/run_all.sh r python compare   # skip Stata (reuse its last results)
DCDH_ONLY_CASES="gentzkow_e2_bp3" bash tests_by_path/run_all.sh
```

Each script can also be run on its own:

```bash
Rscript tests_by_path/r/test_by_path.R
python  tests_by_path/python/test_by_path.py
python  tests_by_path/compare/compare_by_path.py      # stdlib only
# Stata, Windows:  StataMP-64.exe /e do tests_by_path\stata\test_by_path.do <full path of tests_by_path>
# Stata, Mac/Linux: stata-mp -b do tests_by_path/stata/test_by_path.do <full path of tests_by_path>
```

Choosing which version of each package is tested (all optional):

| Variable | Default | Example |
|---|---|---|
| `DCDH_STATA_ADO_DIR` | `../did_multiplegt_dyn/Stata` (repo next to this one) | `installed` to use the ado installed in Stata |
| `DCDH_R_SOURCE` | installed `DIDmultiplegtDYN` | `../did_multiplegt_dyn/R` (loaded with `pkgload::load_all`) |
| `DCDH_R_LIB` | – | extra library folder, put first on `.libPaths()` |
| `DCDH_PY_SRC` | installed `did_multiplegt_dyn` | `../py_did_multiplegt_dyn/src` (e.g. with the `bypath` branch checked out) |
| `STATA_BIN`, `RSCRIPT`, `PYTHON` | auto-detected | |

Requirements: Stata with `gtools`; R with `haven` and `polars`
(`install.packages("polars", repos = "https://rpolars.r-universe.dev")`,
it must be attached before `DIDmultiplegtDYN`); Python with the package's
dependencies. **Note:** the Python package currently fails with Polars 2.x
(`pl.count()` was removed), so use `polars<2` until that is fixed.

## Cases

`cases.csv` (one row per specification, same columns in every language):

| case_id | what it covers |
|---|---|
| `wagepan_e5p2_bp4` | `code/test_new_opts.do`, Stata log `logfiles/stat_2026-02-27.log`, Python notebook |
| `gentzkow_e2_bp3`, `gentzkow_e2p1_bp3` | did_book ch. 8, CQ#45b (without / with a placebo) |
| `wagepan_e3p1_bp3`, `wagepan_e3p1_all` | the Python pytest cases |
| `wagepan_e2p1_bp99` | `#` larger than the number of paths |
| `wagepan_e3p1_bp3_{controls,weight,normalized,swin,swout,onlynever}` | by_path combined with other options |
| `gentzkow_e2p1_bp3_cluster` | by_path + cluster (counties clustered by state) |
| `favara_e8p3_bp2_cluster` | example in the Stata help file (treatment 0–4) |
| `gentzkow_e1_all` | all paths, including baselines ≥ 10 (multi-digit treatment values) |

To add a case, add a row to `cases.csv`; no script needs to change.
`stata_precise = 1` asks Stata for full-precision numbers (see below); use it
when `by_path` is a small integer.

## How the numbers are collected

* **R / Python** return per-path results, exported at full precision.
* **Stata** does not store per-path results: each path is a nested call that
  only prints its table. The Stata script therefore exports two sources:
  * `display` – the log of the real `by_path(#)` call, parsed; every path, at
    the displayed precision (~7 significant digits);
  * `precise` – `by_path(k)` for k = 1..#. After each call `mat_res_XX` and
    `e()` hold the results of the last path estimated, i.e. the k-th most
    common path, at full precision.

  A `by_path(k)` run is only used when path k is the last path it printed
  (otherwise `mat_res_XX` still holds the previous path).
  * `enum` – every path the command enumerated, including paths for which it
    prints nothing (e.g. switch-out paths under `switchers(in)`).

  The comparison uses `precise` where available, otherwise `display`, and also
  checks that the two agree (`stata_int`). A path Stata enumerates but skips
  is fine if the other language also returns nothing (or an error) for it.

## What "match" means

`compare_by_path.py` checks, per case and language, against Stata:

* the case runs; the same set of paths is estimated (`paths`), in the same
  order (`order`, warning only), with the same number of groups per path
  (`n_groups`, Python only);
* the same statistics exist for every path (`rows`): `Effect_k`, `Av_tot_eff`,
  `Placebo_k`, `p_joint_effects`, `p_joint_placebos`. Extra p-values that Stata
  does not report are warnings, any other extra or missing row fails;
* values (`values`): N and switchers exactly; estimate, SE and CI bounds within
  `|x - stata| <= 1e-7 + 1e-6*|stata|` (change with `--atol/--rtol`), plus half
  a displayed digit when only Stata's displayed value exists. Stata keeps
  intermediate variables in float, so results agree to ~7 significant digits,
  not bit-for-bit;
* `validation`: every input in `validation_cases.csv` is accepted / rejected
  as in Stata. Stata's input checks print an error and `exit` with return code
  0, so "rejected" in Stata means that no results matrix was produced.

The script exits with 1 if any check fails, and prints a table plus the
failures grouped by kind. Every individual check is in
`results/comparison_details.csv`.
