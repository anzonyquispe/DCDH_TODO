# R bootstrap tests

Bootstrap standard errors are random, so they cannot be compared across
languages the way the main suite compares analytic results. This folder tests
R's `bootstrap = c(reps, seed)` on its own terms **and** against Stata on the
*same* resamples.

```
R_bootstrap/
  run_bootstrap.sh        one command (asks for / reads DCDH_R_PKG and DCDH_STATA_ADO like run_tests.sh)
  bootstrap_specs.csv     39 specs: a base spec of ../specs/specs.csv + reps + seed (+ stata_manual flag)
  run_bootstrap.R         the R runs
  manual_bootstrap.do     Stata replay of R's resamples
  compare_bootstrap.py    verdicts -> results/bootstrap_report.txt, bootstrap_details.csv
```

```bash
bash R_bootstrap/run_bootstrap.sh --r-pkg installed --stata-ado installed
bash R_bootstrap/run_bootstrap.sh --only "RB01 RB03" --reps 10
bash R_bootstrap/run_bootstrap.sh --skip stata        # R-only checks
```

## Specs (`bootstrap_specs.csv`, seed 1234; reps 20, wagepan specs RB01–RB05: 5% of the groups and 4 reps)

`subsample = groups_5pct` keeps every 20th group (sorted ids, identical in R and Stata),
which makes the wagepan specs fast.

| bids | base specs | source |
|---|---|---|
| RB01 | A02 wagepan `effects(5) placebo(2)` | the `bootstrap(20,1234)` spec of **tests_stata.do** |
| RB02–RB05 | A08 weight, A09 cluster, B03 by_path(4), G04 reset(4) + avg_time_periods | new combinations |
| RB06–RB24 | C01–C19 (the tests_stata.do options on deryugina) | R_didgt_polars `bootstrap_equivalence/specs.R` |
| RB25–RB33 | D01–D09 (book chapters 1–4) | `specs.R` |
| RB34–RB39 | E01–E06 | `specs.R` |

## Runs and checks

R runs every spec six times: without bootstrap (**analytic**), with
`bootstrap(reps, seed)` saving its resamples (**A**,
`options(DID_BOOTSTRAP_SAMPLE_DIR=…)`), the same seed again (**B**), the
saved resamples loaded back (**C**, `DID_BOOTSTRAP_LOAD_SAMPLES=TRUE`), another
seed (**D**), and the saved resamples with the row-replication method (**E**,
`DID_BOOTSTRAP_METHOD="row_replication"`).

| check | passes when |
|---|---|
| point | bootstrap point estimates = analytic point estimates |
| counts | N and switchers unchanged by bootstrap |
| reproducible | same seed ⇒ identical SEs (A = B) |
| replay | saved resamples ⇒ identical SEs (A = C) |
| method | both resampling methods ⇒ same SEs (A = E) |
| active | another seed ⇒ other SEs (A ≠ D); SEs finite and > 0 |
| stata_point | R analytic estimates = Stata analytic estimates |
| **stata_se** | R's bootstrap SE = Stata's SE on the **same** resamples: `manual_bootstrap.do` rebuilds each resampled data set from R's `rep_*.csv` (each drawn cluster duplicated `count` times, every copy its own group/cluster), runs the analytic estimator, and takes the standard deviation across replications |
| stata_boot | R SE / Stata `bootstrap(reps, seed)` SE within [0.5, 2] — different random draws, so a warning only |

`stata_se` runs for the specs with `stata_manual = 1` (non-by specs; by_path
draws resamples per path). Python has no bootstrap, so it is not tested here.
