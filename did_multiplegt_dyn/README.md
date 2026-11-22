# did_multiplegt_dyn — cross-language test suite (Stata · R · Python)

Checks that **R** (`DIDmultiplegtDYN`) and **Python** (`py_did_multiplegt_dyn`)
reproduce **Stata** (`did_multiplegt_dyn.ado`, the reference) on every
specification we have ever tested, element by element: every `e()` scalar,
`e()` macro, `e()` matrix cell and the matrices the command leaves behind.

```
did_multiplegt_dyn/
  run_tests.sh / run_tests.ps1   one command: runs Stata, R, Python, then the comparison
  check_env.sh                   checks interpreters and required packages
  config.example.env             copy to config.env to remember which versions to test
  data/                          every dataset (SOURCES.md: origin + checksums)
    reference_stata/             saved Stata results used as fixed benchmarks
  specs/
    specs.csv                    the 121 specifications, written in Stata syntax
    validation.csv               14 inputs that must be accepted / rejected
    option_map.csv               Stata option -> R / Python argument
    not_supported.csv            options a language does not have (reported, not failed)
    stata_only.csv               elements only Stata stores by design (not compared)
    golden.csv                   specs also compared with saved Stata results
  Stata/run_specs.do             reference run
  R/run_specs.R, R/common.R      R run
  Python/run_specs.py            Python run
  compare/compare.py             verdicts -> results/report.txt, summary.csv, details.csv
  compare/selftest.py            proves compare.py catches planted errors
  R_bootstrap/                   R-specific bootstrap tests (own README)
  results/                       generated, git-ignored
```

## Running it

**New user? Start with [`TESTING.html`](TESTING.html)** (one page: install, pick versions, run, read the report).
`run_jobs.py` runs every spec as its own job (Stata in parallel, R and Python one by one), then merges and compares.

```bash
bash run_tests.sh                     # asks which Stata ado, R package and Python package to test
```

**The versions under test are always the developer's choice — nothing is
assumed.** Give them as options, in `config.env`, or answer the prompts (the
script offers to save the answers):

| option | meaning | examples |
|---|---|---|
| `--stata-ado` | the `did_multiplegt_dyn.ado` Stata uses as reference | `installed` · `C:/…/did_multiplegt_dyn/Stata` · `…/did_multiplegt_dyn.ado` |
| `--r-pkg` | the `DIDmultiplegtDYN` R tests | `installed` · a source folder (has `DESCRIPTION`, loaded with `pkgload`) · a `.tar.gz` · a library folder |
| `--py-pkg` | the `did_multiplegt_dyn` Python tests | `installed` · the folder containing the package, e.g. `…/py_did_multiplegt_dyn/src` |

Typical use after changing a package locally:

```bash
bash run_tests.sh --stata-ado installed \
                  --r-pkg ../../did_multiplegt_dyn/R \
                  --py-pkg ../../py_did_multiplegt_dyn/src
bash run_tests.sh --skip stata               # reuse Stata's last results (Stata is the slow part)
bash run_tests.sh --only "A02 F14"           # a few specs
bash run_tests.sh --blocks "F G"             # whole blocks
bash run_tests.sh --selftest                 # also check the comparison script itself
```

From PowerShell: `.\run_tests.ps1 <same options>` (uses Git Bash).
Exit code 0 = no FAIL / MISSING / ERROR.

The three languages run **one after the other** by default: the largest spec
(D10, Moser–Voena, 290k rows, 21 effects) alone needs ~6 GB in Stata and
~5 GB in Python, and three at once exhausted a 32 GB machine. `--parallel`
runs them together. A full run takes roughly 1–2 hours, mostly Stata.

**Requirements.** Stata with `gtools`; R with `haven` and `polars`
(`install.packages("polars", repos = "https://rpolars.r-universe.dev")` — it
must be attached before `DIDmultiplegtDYN`; `pkgload` for source folders);
Python with `numpy`, `pandas`, `polars<2` (the package breaks with Polars 2:
`pl.count()` was removed). `check_env.sh` checks all of this.

## The specifications (121 + 14 input checks)

Every spec is one row of `specs/specs.csv`: dataset, `y g t d`, a data
preparation id and the options **in Stata syntax**; R and Python translate it
through `option_map.csv`, so a spec is written once.

| block | what | # | source |
|---|---|---:|---|
| A | wagepan `effects(5) placebo(2)` + each option of `tests_stata.do`: baseline, placebos, normalized, controls, trends_nonparam, trends_lin, continuous(1), weight, cluster, same_switchers, same_switchers_pl, switchers(in/out), only_never_switchers, ci_level(90/99), less_conservative_se, dont_drop_larger_lower, effects_equal(all); + continuous(4) | 20 | **tests_stata.do** main block (19), DCDH_TODO `test_wagepan_specs` (1) |
| B | wagepan: design(,console), by(black), by_path(4), predict_het(black,all), date_first_switch(by_baseline_treat,console) | 5 | **tests_stata.do** additional-outputs block |
| C | the block-A options on deryugina (absorbing binary treatment) | 19 | R_didgt_polars `specs.R` |
| D | did_book: ch01 T2/T3, ch02 T5/T6 (continuous + weight), ch03 T8/T10/T11, ch04 T13/T14, ch04 Moser–Voena, ch06 Wolfers, ch08 design(0.8) ×3, effects_equal + cluster, normalized_weights, same_switchers with `if`, by_path(3) | 18 | **did_book** chapters + `specs.R` |
| E | favara basic/weight, predict_het, by(coastal), normalized_weights, drop_if_d_miss_before_first_switch | 6 | `specs.R` |
| F | by_path: the former `tests_by_path` cases, help-file example, pytest cases, notebook by_path(6), `.Rhistory` favara by_path(all), and by_path(4) × every block-A option | 35 | `tests_by_path`, pytest, notebooks, **new** combinations |
| G | reset / avg_time_periods: b1–b6, gentzkow reset(0/1/4/1+normalized) (also vs saved Stata results), reset × by_path, reset × options | 18 | DCDH_TODO `tests_R`, `code/*.do`, **new** combinations |
| H | input checks: by_path 2 / all / ALL / 0 / −1 / −3 / 2.5 / abc / "−1", by + by_path, by_path + graphoptions, reset 1 / −1 / 2.5 | 14 | the ado's input checks, pytest |

`tests_stata.do` contributes 24 of the 121 specs (~20%) — all of its
specifications; its 25th, `bootstrap(20,1234)`, is `RB01` in `R_bootstrap/`.
The book and the `specs.R` lists give ~35%, by_path and reset combinations ~45%.

Data preparation ids (`prep` column), implemented identically in the three
runners: `deryugina_year_controls`, `gentzkow_t11` (`year<=first_change |
same_treat_after_first_change==1`), `gentzkow_ch08` (same with `<`),
`hollingsworth_t13`, `hollingsworth_t14`. Missing values follow Stata's rule
(missing is larger than any number).

**Adding a spec:** add a row to `specs/specs.csv` (options in Stata syntax).
A new option also needs a row in `option_map.csv`.

## What is compared

For every spec and every estimation unit (each by_path path and each by()
level is its own unit), with Stata as the reference:

* **units** — the same paths/levels are estimated; an extra or missing one fails.
* **e() scalars** — `Effect_k`, `se_effect_k`, `N_effect_k`, `N_switchers_effect_k`,
  the `Placebo_k` and `Av_tot_effect` equivalents, `*_w`, `p_jointeffects`,
  `p_jointplacebo`, `p_equality_effects`, `switch_dates*`.
* **e() macros** — `cmd`, `effects`, `placebo`.
* **matrices** — `e(b)`, `e(V)`, `mat_res_XX` (all 7 columns), `desmat` (design),
  `dfs#` (date_first_switch), `e(effect_het_*)` (predict_het), `mat_res_XX_by_<level>`.
* **by_path in Stata** — Stata keeps only the last path in `e()`, so the
  runner re-runs `by_path(k)` for k = 1…# (the k-th run ends with the k-th
  most common path) to get every path at full precision, and also parses every
  path from the log at display precision.
* **golden** — G07–G10 are also compared with saved Stata results
  (`data/reference_stata/`), which still works when the Stata under test
  cannot run `reset`.
* **validation** — each input is accepted/rejected as in Stata (Stata's input
  checks print an error and exit with rc 0, so "rejected" there means no `e()`).

Tolerance `|x − stata| ≤ 1e-7 + 1e-6·|stata|` (Stata stores intermediates as
float); counts (N, switchers, #groups) exact; half a displayed digit is added
when only Stata's displayed value exists.

| status | meaning | counted as failure |
|---|---|---|
| PASS | equal within tolerance | |
| FAIL | value differs / extra path | ✔ |
| MISSING | Stata stores it, the language does not return it | ✔ |
| ERROR | the language crashed or did not run the spec | ✔ |
| EXTRA | the language returns something Stata does not store | warning |
| ROUNDED | the language returns a rounded number that agrees to its last digit | warning |
| NOT_SUPPORTED | option listed in `not_supported.csv`, or the package lacks the argument | no |
| STATA_NOT_SUPPORTED / STATA_ERROR | the Stata under test cannot run the spec: no reference | no (listed) |

`not_supported.csv` currently flags the `design()` and `predict_het()` outputs
in R and Python (updated in the latest Stata, not yet ported — their estimates
are still compared), Python's `date_first_switch` output and `bootstrap`, and
`graphoptions()`. Delete a line when the language catches up.

`report.txt` gives the verdict per spec and language, the problems grouped by
kind (with a note when R and Python agree and only Stata differs), and the
NOT SUPPORTED list; `details.csv` has every single check.

## Notes

* Stata batch on Windows from Git Bash needs `MSYS_NO_PATHCONV=1` (otherwise
  `/e` becomes a path and Stata opens its GUI); `run_tests.sh` handles it.
* Stata's `macro drop path_*_XX` is invalid syntax (wildcards only at the
  end), so leftover by_path globals are cleared one by one — they used to leak
  from one spec into the next in the old `tests_by_path` harness.
* R and Python write their results after every spec, so a crash keeps what
  was done; specs never reached are reported as ERROR.
