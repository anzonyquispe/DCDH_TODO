## test_b2_gentzkow_reset4.R
## Batch 2: gentzkowetal_balanced — reset(4) applied to data, then effects(600)
## Cross-check: N_switchers_effect_k  ==  N_switch_avg_k
## Mirrors: code/test_switchers_b2.do

.this_dir <- (function() { a <- commandArgs(trailingOnly = FALSE); m <- regmatches(a, regexpr("(?<=--file=).*", a, perl = TRUE)); if (length(m)) return(dirname(normalizePath(m[1], mustWork = FALSE))); for (i in seq_len(sys.nframe())) { fr <- sys.frame(i); if (!is.null(fr$ofile)) return(dirname(normalizePath(fr$ofile, mustWork = FALSE))) }; getwd() })(); source(file.path(.this_dir, "helpers.R"))
library(DIDmultiplegtDYN)

DS    <- "gentzkow"
SPEC  <- "reset4"
RST   <- 4L
NEFF  <- 4L
DATA  <- file.path(DATA_DIR, "gentzkowetal_didtextbook_balanced.dta")
Y     <- "prestout"
G     <- "cnty90"
TM    <- "year"
D     <- "numdailies"

CSV <- file.path(RESULTS_DIR, "switchers_b2.csv")
LOG <- file.path(RESULTS_DIR, "test_b2_gentzkow_reset4.log")
con <- file(LOG, open = "wt")
sink(con, type = "message"); sink(con, type = "output")
on.exit({ sink(type = "output"); sink(type = "message"); close(con) })

cat(sprintf("=== test_b2_gentzkow_reset4  started: %s ===\n", Sys.time()))
init_switcher_csv(CSV)

df_raw <- as.data.frame(read_dta(DATA))
cat(sprintf("Loaded %s  (%d rows)\n", DATA, nrow(df_raw)))

cat(sprintf("\n%s\n%s  effects(%d)  reset(%d) applied to data\n%s\n",
            strrep("-", 60), DS, NEFF, RST, strrep("-", 60)))

# apply reset to data first, then run with no reset option
df <- tryCatch(
  reset_groups_R(df_raw, gvar = G, tvar = TM, dvar = D,
                 reset = RST, replace_group = TRUE),
  error = function(e) {
    write_diagrow(CSV, DS, SPEC, RST, paste0("reset_groups_failed:", e$message))
    NULL
  }
)

if (!is.null(df)) {
  res_did <- tryCatch(
    did_multiplegt_dyn(df = df, outcome = Y, group = G, time = TM,
                       treatment = D, effects = NEFF,
                       avg_time_periods = TRUE, graph_off = TRUE),
    error = function(e) {
      warning("did_multiplegt_dyn failed: ", e$message); NULL
    }
  )

  dump_result(res_did, sprintf("%s/%s reset=%d effects=%d", DS, SPEC, RST, NEFF), NEFF)

  N_did <- extract_N_switchers(res_did, NEFF)
  N_avg <- extract_N_switch_avg(res_did, NEFF)

  n_did_found <- sum(!is.na(N_did))
  n_avg_found <- sum(!is.na(N_avg))
  cat(sprintf("  -> N_did effects found: %d\n", n_did_found))
  cat(sprintf("  -> N_avg effects found: %d\n", n_avg_found))

  if (n_did_found == 0 && n_avg_found == 0) {
    write_diagrow(CSV, DS, SPEC, RST, "no_effects_found")
  } else {
    n_max <- max(n_did_found, n_avg_found)
    for (k in seq_len(n_max)) {
      write_swrow(CSV, DS, SPEC, RST, k, N_did[[k]], N_avg[[k]])
    }
  }
}

cat(sprintf("\nCSV written to: %s\n", CSV))
cat(sprintf("=== test_b2_gentzkow_reset4  finished: %s ===\n", Sys.time()))
