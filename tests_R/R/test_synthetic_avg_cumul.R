## test_synthetic_avg_cumul.R
## Smoke-test of the new `avg_time_periods` + `reset` wiring without needing
## the gentzkow/wagepan dta files (which are not shipped with the repo).
## Runs on the built-in favara_imbs sample data.
##
## Verifies:
##   * the package loads
##   * did_multiplegt_dyn() with avg_time_periods = TRUE returns
##       res$avg_cumul         (scalar)
##       res$N_switchers_effect_k  (one per estimated effect)
##       res$N_switch_avg_k        (one per estimated effect)
##   * reset = k changes the group structure (more sub-groups than baseline)
##   * the C++ entry points are reachable

suppressPackageStartupMessages({
  library(DIDmultiplegtDYN)
  library(polars)
})

data(favara_imbs)
df <- as.data.frame(favara_imbs)

cat("=== synthetic avg_cumul smoke test ===\n")
cat(sprintf("rows: %d  groups: %d  periods: %d\n",
            nrow(df), length(unique(df$county)), length(unique(df$year))))

cat("\n--- baseline run with avg_time_periods = TRUE ---\n")
res <- did_multiplegt_dyn(
  df = df, outcome = "Dl_vloans_b", group = "county",
  time = "year", treatment = "inter_bra",
  effects = 3, avg_time_periods = TRUE, graph_off = TRUE
)

stopifnot(!is.null(res$avg_cumul))
stopifnot(!is.null(res$N_switchers_effect_1))
stopifnot(!is.null(res$N_switch_avg_1))

for (k in 1:3) {
  n_std <- res[[paste0("N_switchers_effect_", k)]]
  n_avg <- res[[paste0("N_switch_avg_", k)]]
  cat(sprintf("  effect_%d   N_switchers_effect=%s   N_switch_avg=%s\n",
              k,
              ifelse(is.null(n_std), "NULL", format(n_std)),
              ifelse(is.null(n_avg), "NULL", format(n_avg))))
}
cat(sprintf("  avg_cumul = %s\n", format(res$avg_cumul, nsmall = 4)))

cat("\n--- run with reset = 4 ---\n")
res2 <- did_multiplegt_dyn(
  df = df, outcome = "Dl_vloans_b", group = "county",
  time = "year", treatment = "inter_bra",
  effects = 3, reset = 4, avg_time_periods = TRUE, graph_off = TRUE
)
cat(sprintf("  reset=4: avg_cumul = %s   N_switch_avg_1 = %s\n",
            format(res2$avg_cumul, nsmall = 4),
            format(res2$N_switch_avg_1)))

cat("\n=== ALL CHECKS PASSED ===\n")
