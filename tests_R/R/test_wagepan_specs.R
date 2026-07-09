## test_wagepan_specs.R
## Cross-check: e(N_switchers_effect_k) == e(N_switch_avg_k)
## across every option combination on the wagepan dataset.
## Mirrors: code/test_wagepan_specs.do

.this_dir <- (function() { a <- commandArgs(trailingOnly = FALSE); m <- regmatches(a, regexpr("(?<=--file=).*", a, perl = TRUE)); if (length(m)) return(dirname(normalizePath(m[1], mustWork = FALSE))); for (i in seq_len(sys.nframe())) { fr <- sys.frame(i); if (!is.null(fr$ofile)) return(dirname(normalizePath(fr$ofile, mustWork = FALSE))) }; getwd() })(); source(file.path(.this_dir, "helpers.R"))
library(DIDmultiplegtDYN)

DATA   <- file.path(DATA_DIR, "wagepan.dta")
Y      <- "lwage"
G      <- "nr"
TM     <- "year"
D      <- "union"
CONT   <- "hours"
NONPAR <- "black"
WGHT   <- "educ"
CLUST  <- "hisp"
N_EFF  <- 5L
N_PL   <- 2L

CSV <- file.path(RESULTS_DIR, "wagepan_specs.csv")
LOG <- file.path(RESULTS_DIR, "test_wagepan_specs.log")
con <- file(LOG, open = "wt")
sink(con, type = "message"); sink(con, type = "output")
on.exit({ sink(type = "output"); sink(type = "message"); close(con) })

cat(sprintf("=== test_wagepan_specs  started: %s ===\n", Sys.time()))
init_wagepan_csv(CSV)

df_base <- as.data.frame(read_dta(DATA))
cat(sprintf("Loaded %s  (%d rows)\n", DATA, nrow(df_base)))

# ── helper: run one spec and write rows ───────────────────────────────────────
run_spec <- function(label, extra_args) {
  cat(sprintf("\n%s\nSPEC: %s\n%s\n", strrep("-", 70), label, strrep("-", 70)))
  df <- df_base

  args <- c(
    list(df = df, outcome = Y, group = G, time = TM, treatment = D,
         avg_time_periods = TRUE, graph_off = TRUE),
    extra_args
  )

  res <- tryCatch(do.call(did_multiplegt_dyn, args),
                  error = function(e) {
                    warning(sprintf("SPEC %s failed: %s", label, e$message))
                    NULL
                  })

  dump_result(res, sprintf("wagepan/%s effects=%d", label, N_EFF), N_EFF)

  N_std <- extract_N_switchers(res, N_EFF)
  N_avg <- extract_N_switch_avg(res, N_EFF)

  n_std_found <- sum(!is.na(N_std))
  n_avg_found <- sum(!is.na(N_avg))

  if (n_std_found == 0 && n_avg_found == 0) {
    row <- sprintf("%s,-1,.,.,.,ERROR:no_effects_found", label)
    cat(row, "\n", file = CSV, append = TRUE)
    warning(sprintf("  ERROR  %s  no effects found", label), call. = FALSE)
    return(invisible(NULL))
  }

  n_max <- max(n_std_found, n_avg_found)
  for (k in seq_len(n_max)) {
    write_wrow(CSV, label, k, N_std[[k]], N_avg[[k]])
  }
}

# ── Spec list — mirrors test_wagepan_specs.do Bookmark #1 ─────────────────────

run_spec("Baseline",
  list(effects = N_EFF))

run_spec("Placebos",
  list(effects = N_EFF, placebo = N_PL))

run_spec("Normalized",
  list(effects = N_EFF, placebo = N_PL, normalized = TRUE))

run_spec("Controls",
  list(effects = N_EFF, placebo = N_PL, controls = CONT))

run_spec("Trends_Nonparam",
  list(effects = N_EFF, placebo = N_PL, trends_nonparam = NONPAR))

# trends_lin excluded: avg_time_periods undefined under trends_lin

run_spec("Weight",
  list(effects = N_EFF, placebo = N_PL, weight = WGHT))

run_spec("Cluster",
  list(effects = N_EFF, placebo = N_PL, cluster = CLUST))

run_spec("Same_Switchers",
  list(effects = N_EFF, placebo = N_PL, same_switchers = TRUE))

run_spec("Same_Switchers_Pl",
  list(effects = N_EFF, placebo = N_PL,
       same_switchers = TRUE, same_switchers_pl = TRUE))

run_spec("Switchers_In",
  list(effects = N_EFF, placebo = N_PL, switchers = "in"))

run_spec("Switchers_Out",
  list(effects = N_EFF, placebo = N_PL, switchers = "out"))

run_spec("Only_Never_Switchers",
  list(effects = N_EFF, placebo = N_PL, only_never_switchers = TRUE))

run_spec("CI_Level_90",
  list(effects = N_EFF, placebo = N_PL, ci_level = 90))

run_spec("CI_Level_99",
  list(effects = N_EFF, placebo = N_PL, ci_level = 99))

run_spec("Less_Conservative_SE",
  list(effects = N_EFF, placebo = N_PL, less_conservative_se = TRUE))

run_spec("Dont_Drop_Larger_Lower",
  list(effects = N_EFF, placebo = N_PL, dont_drop_larger_lower = TRUE))

run_spec("Effects_Equal",
  list(effects = N_EFF, placebo = N_PL, effects_equal = "all"))

# Continuous specs: no placebo (matches Stata)
# Continuous_8 omitted: hits variable limit on wagepan (same as Stata)
run_spec("Continuous_1",
  list(effects = N_EFF, continuous = 1))

run_spec("Continuous_4",
  list(effects = N_EFF, continuous = 4))

cat(sprintf("\nCSV written to: %s\n", CSV))
cat(sprintf("=== test_wagepan_specs  finished: %s ===\n", Sys.time()))
