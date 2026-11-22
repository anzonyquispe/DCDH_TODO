## run_bootstrap.R -- R-specific bootstrap tests (see README.md)
##
## For every row of bootstrap_specs.csv (a base spec from ../specs/specs.csv plus
## bootstrap(reps, seed)) runs DIDmultiplegtDYN six times:
##   analytic   no bootstrap                                  -> point estimates, N, analytic SE
##   A          bootstrap(reps, seed), resamples SAVED        -> se_A
##   B          bootstrap(reps, seed) again                   -> se_B   (same seed => identical)
##   C          resamples of A LOADED back                    -> se_C   (replay => identical to A)
##   D          bootstrap(reps, seed + 1)                     -> se_D   (must differ: bootstrap is active)
##   E          resamples of A loaded, method row_replication -> se_E   (second method => identical to A)
## and writes <results>/r_bootstrap.csv (one row per estimate) and
## <results>/samples/<bid>/rep_*.csv (the resamples, read by Stata/manual_bootstrap.do).
##
## Usage:  Rscript R_bootstrap/run_bootstrap.R <suite folder> <results folder>
## Env:    DCDH_R_PKG (REQUIRED, as in R/run_specs.R), DCDH_ONLY (bids), DCDH_BOOT_REPS (override reps)

args <- commandArgs(trailingOnly = TRUE)
SUITE <- normalizePath(if (length(args) >= 1) args[1] else file.path(getwd(), ".."), mustWork = TRUE)
RES <- if (length(args) >= 2) args[2] else file.path(SUITE, "R_bootstrap", "results")
dir.create(RES, recursive = TRUE, showWarnings = FALSE)
source(file.path(SUITE, "R", "common.R"))

P <- load_package(RES)
writeLines(c("language=r", paste0("language_version=", R.version.string),
             paste0("package_source=", P$source), paste0("package_version=", P$version),
             paste0("started_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))), file.path(RES, "r_meta.txt"))
cat(sprintf("Testing DIDmultiplegtDYN %s from %s\n", P$version, P$source))

SPECS <- read_spec_file(SUITE, "specs.csv")
OPTMAP <- read_spec_file(SUITE, "option_map.csv")
NOTSUP <- read_spec_file(SUITE, "not_supported.csv"); NOTSUP <- NOTSUP[NOTSUP$lang == "r", , drop = FALSE]
BOOT <- read.csv(file.path(SUITE, "R_bootstrap", "bootstrap_specs.csv"), colClasses = "character", strip.white = TRUE)
only <- strsplit(Sys.getenv("DCDH_ONLY"), " +")[[1]]
reps_override <- Sys.getenv("DCDH_BOOT_REPS")

## one run -> list of units, each a data.frame(row, est, se, n, sw)
tables <- function(res) {
  one <- function(u) {
    R <- u$results; out <- NULL
    for (nm in c("Effects", "ATE", "Placebos")) {
      m <- R[[nm]]; if (is.null(m)) next; m <- as.matrix(m); if (!nrow(m)) next
      rn <- trimws(rownames(m)); if (nm == "ATE") rn <- "Av_tot_eff"
      out <- rbind(out, data.frame(row = rn, est = m[, 1], se = m[, 2], n = m[, 5], sw = m[, 6], stringsAsFactors = FALSE))
    }
    out
  }
  if (!is.null(res$by_levels)) {
    labs <- gsub(" ", "", as.character(res$by_levels))
    setNames(lapply(seq_along(labs), function(k) one(res[[paste0("by_level_", k)]])), paste0("path=", labs))
  } else list(one(res))
}

run <- function(df, s, args, opts = list()) {
  old <- options(opts); on.exit(options(old))
  a <- c(list(df = df, outcome = s$outcome, group = s$group, time = s$time, treatment = s$treatment, graph_off = TRUE), args)
  t0 <- Sys.time()
  r <- tryCatch(suppressMessages(suppressWarnings(do.call(did_multiplegt_dyn, a))), error = function(e) e)
  list(res = r, secs = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2))
}

OUT <- list(); STATUS <- list()
fmt <- function(d) { for (c in names(d)) if (is.numeric(d[[c]])) d[[c]] <- ifelse(is.na(d[[c]]), "", sprintf("%.17g", d[[c]])); d }
OUT_FILE <- file.path(RES, "r_bootstrap.csv"); ST_FILE <- file.path(RES, "r_status.csv")
unlink(c(OUT_FILE, ST_FILE))
flush_boot <- function() {
  # append after every spec, so a crash keeps the specs already done
  if (length(OUT)) {
    d <- fmt(do.call(rbind, OUT))
    write.table(d, OUT_FILE, sep = ",", row.names = FALSE, qmethod = "double",
                append = file.exists(OUT_FILE), col.names = !file.exists(OUT_FILE))
    OUT <<- list()
  }
  if (length(STATUS)) {
    st <- as.data.frame(do.call(rbind, STATUS), stringsAsFactors = FALSE); names(st) <- c("bid", "status", "message")
    write.table(st, ST_FILE, sep = ",", row.names = FALSE, qmethod = "double",
                append = file.exists(ST_FILE), col.names = !file.exists(ST_FILE))
    STATUS <<- list()
  }
}
for (i in seq_len(nrow(BOOT))) {
  flush_boot()
  b <- BOOT[i, ]
  if (length(only) && !(b$bid %in% only)) next
  s <- SPECS[SPECS$spec_id == b$base_spec, ]
  if (!nrow(s)) { STATUS[[length(STATUS) + 1]] <- c(b$bid, "error", "base spec not in specs.csv"); next }
  reps <- as.numeric(if (nzchar(reps_override)) reps_override else b$reps); seed <- as.numeric(b$seed)
  cat(sprintf("\n=== %s (%s): %s  bootstrap(%d,%d)\n", b$bid, b$base_spec, s$options, reps, seed))
  ba <- build_args(s$options, OPTMAP, NOTSUP, P$formals)
  if (!is.null(ba$not_supported)) { STATUS[[length(STATUS) + 1]] <- c(b$bid, "not_supported", ba$not_supported); next }
  df <- prep_data(load_data(file.path(SUITE, "data"), s$dataset), s$prep)
  if (!is.null(b$subsample) && b$subsample == "groups_5pct") {
    # every 20th group in sorted-id order (deterministic; Stata does the same)
    ids <- sort(unique(df[[s$group]]))
    df <- df[df[[s$group]] %in% ids[(seq_along(ids) - 1) %% 20 == 0], , drop = FALSE]
    cat(sprintf("  subsample groups_5pct: %d of %d groups
", length(unique(df[[s$group]])), length(ids)))
  }
  sdir <- normalizePath(file.path(RES, "samples", b$bid), mustWork = FALSE)
  unlink(sdir, recursive = TRUE); dir.create(sdir, recursive = TRUE, showWarnings = FALSE)
  runs <- list(
    analytic = run(df, s, ba$args),
    A = run(df, s, c(ba$args, list(bootstrap = c(reps, seed))), list(DID_BOOTSTRAP_SAMPLE_DIR = sdir)),
    B = run(df, s, c(ba$args, list(bootstrap = c(reps, seed)))),
    C = run(df, s, c(ba$args, list(bootstrap = c(reps, seed))), list(DID_BOOTSTRAP_SAMPLE_DIR = sdir, DID_BOOTSTRAP_LOAD_SAMPLES = TRUE)),
    D = run(df, s, c(ba$args, list(bootstrap = c(reps, seed + 1)))),
    E = run(df, s, c(ba$args, list(bootstrap = c(reps, seed))),
            list(DID_BOOTSTRAP_SAMPLE_DIR = sdir, DID_BOOTSTRAP_LOAD_SAMPLES = TRUE, DID_BOOTSTRAP_METHOD = "row_replication")))
  errs <- vapply(runs, function(r) if (inherits(r$res, "error")) conditionMessage(r$res) else "", "")
  for (k in names(errs)[nzchar(errs)]) cat("  run", k, "ERROR:", errs[[k]], "\n")
  if (nzchar(errs[["analytic"]]) || nzchar(errs[["A"]])) {
    STATUS[[length(STATUS) + 1]] <- c(b$bid, "error", paste(names(errs)[nzchar(errs)], errs[nzchar(errs)], sep = ": ", collapse = " | "))
    next
  }
  tabs <- lapply(runs, function(r) if (inherits(r$res, "error")) NULL else tables(r$res))
  units <- names(tabs$A); if (is.null(units)) units <- ""
  for (u in seq_along(tabs$A)) {
    ta <- tabs$A[[u]]; if (is.null(ta)) next
    get <- function(run, col) { t <- tabs[[run]][[u]]; if (is.null(t)) return(rep(NA, nrow(ta))); t[[col]][match(ta$row, t$row)] }
    OUT[[length(OUT) + 1]] <- data.frame(
      bid = b$bid, base_spec = b$base_spec, unit = if (is.null(names(tabs$A))) "" else names(tabs$A)[u], row = ta$row,
      est_analytic = get("analytic", "est"), est_boot = ta$est, n_analytic = get("analytic", "n"), n_boot = ta$n,
      sw_analytic = get("analytic", "sw"), sw_boot = ta$sw, se_analytic = get("analytic", "se"),
      se_A = ta$se, se_B = get("B", "se"), se_C = get("C", "se"), se_D = get("D", "se"), se_E = get("E", "se"),
      reps = reps, seed = seed, stringsAsFactors = FALSE)
  }
  msg <- paste(sprintf("%s=%ss", names(runs), vapply(runs, function(r) as.character(r$secs), "")), collapse = " ")
  if (any(nzchar(errs))) msg <- paste(msg, "| errors:", paste(names(errs)[nzchar(errs)], errs[nzchar(errs)], sep = ": ", collapse = " | "))
  STATUS[[length(STATUS) + 1]] <- c(b$bid, "ok", msg)
  cat("  ", msg, "\n")
}
flush_boot()
cat(paste0("finished_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n"), file = file.path(RES, "r_meta.txt"), append = TRUE)
cat("\nR bootstrap tests finished. Results in", RES, "\n")
