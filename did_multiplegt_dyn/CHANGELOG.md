# Changelog: package fixes found with this suite

One entry per issue: what differed from Stata, the cause, the fix and the evidence.
Newest first.

## 2026-11-22: Python weighted total-effect count truncated / overflowed (package fix)

- **Package:** `py_did_multiplegt_dyn` 0.1.9 (`src/did_multiplegt_dyn/did_multiplegt_main.py`)
- **Symptom:** with `weight()`, the weighted count of the total effect (`N.w` of the `ATE` row, i.e. Stata's `e(N_avg_total_effect)`) was wrong. C08: 13708.967 → 13708; E02: 6204.884 → 6204; D11: 3,739,858,180 → −555,109,109.
- **Cause:** two separate problems.
  1. The value was stored with `int(N_effect_XX)` (line 2989), which cut off the decimals of a sum of weights.
  2. The weight column was copied with its own type (line 793). D11's weight `stpop` is `Int32`, so the weighted counts were `Int32`, and their sum overflowed (Polars wraps `Int32` sums).
- **Fix:** `weight_XX` is now cast to `Float64` when it is created, as Stata computes in doubles. The `ATE` row's `N.w` is stored as `float(N_effect_XX)`. The unweighted count on the next line (a true count) still uses `int`.
- **Evidence:** all 9 specs with `weight()` were re-run, plus 4 unweighted controls.
  - C08, D11 and E02 now PASS in Python. All 8 weighted specs with a Stata reference now PASS; G16 has none, since the installed ado lacks `reset`.
  - The unweighted controls (A01, C01, D18, F01) give byte-for-byte identical output.
  - In A08 and C08, 85 values changed at rounding level (relative ≤ 7e-5, from computing in `Float64`), all still within tolerance of Stata.
  - Results from before this fix: `results/jobs_python_before_weightfix/`, `results/summary_before_weightfix.csv`.
- **Status:** changed in the working copy of `py_did_multiplegt_dyn` (not committed).

## 2026-11-22: counts under `weight()` were compared under the wrong name (suite fix)

- **Symptom:** the 8 weighted specs (A08, C08, D03, D04, D11, E02, F06, F23) failed on every count (`N_effect_#`, `N_switchers_*`, `N_placebo_#`, `N_avg_total_effect`), while all estimates, SEs and p-values passed. For example, in A08 `N_effect_1` was 32838 in Stata and 2767 in R and Python.
- **Cause:** a naming difference, not a regression problem. With weights, Stata stores the **weighted** count in `e(N_effect_#)` (ado line 1692: total of the weighted cell counts). It writes the unweighted count to `e(N_effect_#_w)` and to its table (lines 1703–1707: "Display correct N with weights"). The `_w` scalars are then cleared when `e()` is re-posted (around line 3499). R and Python use the opposite labels: `N` / `Switchers` = unweighted, `N.w` / `Switchers.w` = weighted.
- **Fix (`compare/compare.py`):** for specs with `weight()`, Stata's `e(N_*)` count scalars are compared with R/Python `N_*_w`, with a relative tolerance because weighted counts are not whole numbers. Stata's table is still compared with the unweighted `N` / `Switchers`. Recorded in `specs/element_map.csv`.
- **Evidence:** Stata `e(N_*)` = R/Python `N_*_w` in 428 of 436 cases. Python now passes A08, D03, D04, F06 and F23.
- **Real bugs this exposed** (not fixed):
  - **Python:** the weighted total-effect count is cut to a whole number, and overflows in D11. C08: 13708.967 → 13708; E02: 6204.884 → 6204; D11: 3,739,858,180 → −555,109,109. The cause is `did_multiplegt_main.py` lines 2971–2989: `pl.max_horizontal([pl.lit(0)] + …)` and `int(N_effect_XX)`.
  - **R:** the weighted placebo counts are wrong (A08 `N_placebo_1` 22043 vs 26425; 0 in F06 and F23). Probably the same R `N_placebo_#` problem seen without weights.

## 2026-11-22: Python `by_path` dropped groups with a gap before their first switch

- **Package:** `py_did_multiplegt_dyn` 0.1.9 (`src/did_multiplegt_dyn/did_multiplegt_main.py`, `by_path` preparation)
- **Symptom:** D18 (`effects(2) by_path(3)`, Gentzkow et al. data): Python's N was lower than Stata's (4477 vs 4529 for `Effect_1`, path 0,1,1), and its effects differed by up to 7%.
- **Cause:** before splitting the sample into paths, Python recomputed the baseline treatment `d_sq_XX` as the treatment at `F_g − 1`. Stata uses the treatment at the group's **first non-missing period** (ado lines 542–543). For the 12 counties with no observation just before their first switch, Python's `d_sq_XX` was missing, so they failed the control filter `d_sq_XX == path_d_sq` (`_by_path.py`) and their 148 pre-switch control cells were dropped from every path.
- **Fix:** in the `by_path` preparation, `d_sq_XX` is now the treatment at the first period where the treatment is not missing, as in Stata.
- **Evidence:** with the fix, Python reproduces Stata on all three D18 paths (path 0,1,1: `Effect_1` 0.0131318, se 0.0071358, N 4529; `Effect_2` 0.0093570, se 0.0090553, N 3713). This was first confirmed in memory, then by re-running the suite.
- **Not changed:** Python's `by_path` preparation still differs from Stata in two other ways that this case did not need. It does not drop cells where the treatment is both above and below its baseline, and it does not set `F_g = T+1` when the treatment is missing just before the switch (Stata ado lines 553–565 and 671–676).
- **Status:** changed in the working copy of `py_did_multiplegt_dyn` (not committed). The R package (2.4.0) shows a similar gap on D18 (N 4479), which has not been checked yet.
- **Suite re-run:** the 95 Python specs with problems, plus the input checks, were re-run with the fixed source. D18, F01 and F11 (by_path on the Gentzkow data) now match Stata with no problems. The results from before the fix are kept in `results/*_before_fix*`.

## 2026-11-22: test-suite changes

- The `Av_tot_eff` row/column of Stata's `e(V)` is now compared correctly (`compare/compare.py`). Stata fills its diagonal with `se_avg_total_effect`² and its covariances with 0, which are placeholders, not estimates. R and Python keep the total effect in a separate table (`results$ATE` / `result["did_multiplegt_dyn"]["ATE"]`), so the diagonal is compared with that table's SE squared, and the 0 placeholders are not compared.

- `e(b)` is no longer compared (`specs/stata_only.csv`). The same numbers are compared one by one as `Effect_#`, `Placebo_#` and `Av_tot_effect`, with their `se_*`.
- R and Python element names were checked against the returned objects and recorded in `specs/element_map.csv`. The harness now also reads `avg_cumul` and `N_switch_avg_#` (R and Python), Python's `predict_het`, and R's `switch_dates_Dsq_#`. A crash in R's output writer on D12 is fixed.
- `run_jobs.py` runs one job per spec (Stata in parallel, R and Python one by one), and `--merge-only` re-merges existing jobs.
