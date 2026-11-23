## test_by_path.R  --  R side of the by_path cross-language test
##
## Runs every case in ../cases.csv and ../validation_cases.csv and writes
##   results/r_results.csv      one row per (case, path, statistic), full precision
##   results/r_validation.csv   accepted / rejected for each invalid input
##   results/r_meta.txt         which DIDmultiplegtDYN was used
##
## Usage (from anywhere):
##   Rscript tests_by_path/r/test_by_path.R
##
## Environment variables (all optional):
##   DCDH_R_SOURCE    path to a package source folder (e.g. ../did_multiplegt_dyn/R)
##                    loaded with pkgload::load_all(); default: installed package
##   DCDH_R_LIB       extra library folder put first on .libPaths()
##   DCDH_ONLY_CASES  space-separated case_ids to run (default: all)

extra_lib <- Sys.getenv("DCDH_R_LIB")
if (nzchar(extra_lib)) .libPaths(c(extra_lib, .libPaths()))

suppressPackageStartupMessages({
  library(haven)
  library(polars)   # DIDmultiplegtDYN needs polars attached, not only installed
})

## -- Locate folders ----------------------------------------------------------
script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- regmatches(args, regexpr("(?<=--file=).*", args, perl = TRUE))
  if (length(m) > 0 && nzchar(m[1])) return(dirname(normalizePath(m[1], mustWork = FALSE)))
  for (i in seq_len(sys.nframe())) {
    fr <- sys.frame(i)
    if (!is.null(fr$ofile) && nzchar(fr$ofile)) return(dirname(normalizePath(fr$ofile, mustWork = FALSE)))
  }
  getwd()
}
TB_DIR      <- normalizePath(file.path(script_dir(), ".."), mustWork = TRUE)
PROJ_ROOT   <- normalizePath(file.path(TB_DIR, ".."), mustWork = TRUE)
RESULTS_DIR <- file.path(TB_DIR, "results")
dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

## -- Load the package under test ---------------------------------------------
src <- Sys.getenv("DCDH_R_SOURCE")
if (nzchar(src)) {
  pkgload::load_all(src, quiet = TRUE, export_all = FALSE)
  pkg_file <- normalizePath(src)
  pkg_version <- as.character(read.dcf(file.path(src, "DESCRIPTION"), fields = "Version"))
} else {
  suppressPackageStartupMessages(library(DIDmultiplegtDYN))
  pkg_file <- find.package("DIDmultiplegtDYN")
  pkg_version <- as.character(packageVersion("DIDmultiplegtDYN"))
}
writeLines(c(
  "language=r",
  paste0("r_version=", R.version.string),
  paste0("package_file=", pkg_file),
  paste0("package_version=", pkg_version),
  paste0("polars_version=", as.character(packageVersion("polars"))),
  paste0("run_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
), file.path(RESULTS_DIR, "r_meta.txt"))
cat(sprintf("Testing DIDmultiplegtDYN %s from %s\n", pkg_version, pkg_file))

## -- Helpers -----------------------------------------------------------------
num <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  if (length(x) == 0 || is.na(x)) "" else sprintf("%.17g", x)
}

load_data <- function(rel_path) {
  df <- as.data.frame(zap_labels(read_dta(file.path(PROJ_ROOT, rel_path))))
  df
}

build_args <- function(cs, df) {
  a <- list(df = df, outcome = cs$outcome, group = cs$group, time = cs$time,
            treatment = cs$treatment, effects = as.integer(cs$effects),
            placebo = as.integer(cs$placebo), graph_off = TRUE)
  a$by_path <- if (tolower(cs$by_path) == "all") "all" else as.numeric(cs$by_path)
  if (nzchar(cs$controls)) a$controls <- strsplit(cs$controls, " +")[[1]]
  if (nzchar(cs$weight))   a$weight   <- cs$weight
  if (nzchar(cs$cluster))  a$cluster  <- cs$cluster
  if (cs$normalized == "1") a$normalized <- TRUE
  if (nzchar(cs$switchers)) a$switchers <- cs$switchers
  if (cs$only_never_switchers == "1") a$only_never_switchers <- TRUE
  a
}

empty_row <- function(case_id, path = "", order = "", status = "ok", message = "") {
  data.frame(case_id = case_id, path = path, path_order = order, n_groups = "",
             row = "", estimate = "", se = "", lb_ci = "", ub_ci = "", n = "",
             switchers = "", source = "precise", status = status, message = message,
             stringsAsFactors = FALSE)
}

## Rows of one results table (Effects / ATE / Placebos), columns 1..6 are
## Estimate, SE, LB CI, UB CI, N, Switchers in every DIDmultiplegtDYN version.
table_rows <- function(mat, case_id, path, order) {
  if (is.null(mat)) return(NULL)
  mat <- as.matrix(mat)
  if (nrow(mat) == 0) return(NULL)
  out <- vector("list", nrow(mat))
  for (r in seq_len(nrow(mat))) {
    out[[r]] <- data.frame(
      case_id = case_id, path = path, path_order = order, n_groups = "",
      row = trimws(rownames(mat)[r]),
      estimate = num(mat[r, 1]), se = num(mat[r, 2]), lb_ci = num(mat[r, 3]),
      ub_ci = num(mat[r, 4]), n = num(mat[r, 5]), switchers = num(mat[r, 6]),
      source = "precise", status = "ok", message = "", stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

p_row <- function(case_id, path, order, name, value) {
  r <- empty_row(case_id, path, order)
  r$row <- name
  r$estimate <- num(value)
  r
}

## -- Estimation cases ----------------------------------------------------------
cases <- read.csv(file.path(TB_DIR, "cases.csv"), colClasses = "character",
                  na.strings = character(0), strip.white = TRUE)
only <- strsplit(Sys.getenv("DCDH_ONLY_CASES"), " +")[[1]]
if (length(only) > 0) cases <- cases[cases$case_id %in% only, , drop = FALSE]

all_rows <- list()
for (i in seq_len(nrow(cases))) {
  cs <- cases[i, ]
  cat(sprintf("\n=== CASE %s (by_path = %s) ===\n", cs$case_id, cs$by_path))
  df <- load_data(cs$dataset)
  t0 <- Sys.time()
  res <- tryCatch(
    suppressMessages(suppressWarnings(do.call(did_multiplegt_dyn, build_args(cs, df)))),
    error = function(e) e)
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (inherits(res, "error")) {
    msg <- gsub("[\r\n\"]", " ", conditionMessage(res))
    cat("  ERROR:", msg, "\n")
    all_rows[[length(all_rows) + 1]] <- empty_row(cs$case_id, status = "case_error", message = msg)
    next
  }

  labels <- as.character(res$by_levels)
  for (k in seq_along(labels)) {
    branch <- res[[paste0("by_level_", k)]]
    if (is.null(branch) || is.null(branch$results)) {
      all_rows[[length(all_rows) + 1]] <- empty_row(cs$case_id, labels[k], k, "path_error", "no results for this path")
      next
    }
    R <- branch$results
    all_rows[[length(all_rows) + 1]] <- table_rows(R$Effects,  cs$case_id, labels[k], k)
    all_rows[[length(all_rows) + 1]] <- table_rows(R$ATE,      cs$case_id, labels[k], k)
    all_rows[[length(all_rows) + 1]] <- table_rows(R$Placebos, cs$case_id, labels[k], k)
    if (!is.null(R$p_jointeffects))
      all_rows[[length(all_rows) + 1]] <- p_row(cs$case_id, labels[k], k, "p_joint_effects", R$p_jointeffects)
    if (!is.null(R$p_jointplacebo))
      all_rows[[length(all_rows) + 1]] <- p_row(cs$case_id, labels[k], k, "p_joint_placebos", R$p_jointplacebo)
  }
  cat(sprintf("  %d paths in %.1fs\n", length(labels), secs))
}
out <- do.call(rbind, all_rows[!vapply(all_rows, is.null, logical(1))])
write.csv(out, file.path(RESULTS_DIR, "r_results.csv"), row.names = FALSE, na = "")

## -- Input validation cases --------------------------------------------------
vcases <- read.csv(file.path(TB_DIR, "validation_cases.csv"), colClasses = "character",
                   na.strings = character(0), strip.white = TRUE)
wagepan <- load_data("_data/wagepan.dta")
vout <- data.frame(vcase_id = character(0), outcome = character(0), message = character(0),
                   stringsAsFactors = FALSE)
for (i in seq_len(nrow(vcases))) {
  v <- vcases[i, ]
  bp <- if (v$by_path_type == "num") as.numeric(v$by_path) else v$by_path
  a <- list(df = wagepan, outcome = "lwage", group = "nr", time = "year", treatment = "union",
            effects = 2L, placebo = 0L, graph_off = TRUE, by_path = bp)
  if (v$with_by == "1") a$by <- "black"
  res <- tryCatch(suppressMessages(suppressWarnings(do.call(did_multiplegt_dyn, a))),
                  error = function(e) e)
  if (inherits(res, "error")) {
    outcome <- "rejected"
    msg <- gsub("[\r\n,\"]", " ", conditionMessage(res))
  } else {
    outcome <- if (!is.null(res$by_level_1$results)) "accepted" else "rejected"
    msg <- ""
  }
  cat(sprintf("VALIDATION %s by_path=%s -> %s\n", v$vcase_id, v$by_path, outcome))
  vout[nrow(vout) + 1, ] <- list(v$vcase_id, outcome, substr(msg, 1, 200))
}
write.csv(vout, file.path(RESULTS_DIR, "r_validation.csv"), row.names = FALSE, na = "")
cat("\nR by_path tests finished. Results in", RESULTS_DIR, "\n")
