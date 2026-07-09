## helpers.R — shared utilities for the R test suite
## Mirrors the Stata helper programs (_swrow, _diagrow, reset_groups).

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(polars)
})

# Robust script directory resolution that works under both source() and Rscript.
script_dir <- function() {
  # Rscript: --file=<path> is on the command line
  args <- commandArgs(trailingOnly = FALSE)
  m <- regmatches(args, regexpr("(?<=--file=).*", args, perl = TRUE))
  if (length(m) > 0 && nzchar(m[1])) {
    return(dirname(normalizePath(m[1], mustWork = FALSE)))
  }
  # source(): sys.frame(1)$ofile is set
  for (i in seq_len(sys.nframe())) {
    fr <- sys.frame(i)
    if (!is.null(fr$ofile) && nzchar(fr$ofile)) {
      return(dirname(normalizePath(fr$ofile, mustWork = FALSE)))
    }
  }
  getwd()
}

# ── Paths ─────────────────────────────────────────────────────────────────────
.HELPER_DIR <- script_dir()
PROJ_ROOT   <- normalizePath(file.path(.HELPER_DIR, "../.."), mustWork = FALSE)
DATA_DIR    <- file.path(PROJ_ROOT, "_data")
RESULTS_DIR <- file.path(PROJ_ROOT, "tests_R", "results")
dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

# ── CSV helpers ───────────────────────────────────────────────────────────────

#' Initialise a switcher CSV (b1–b6 format)
init_switcher_csv <- function(path) {
  writeLines("dataset,spec,reset,effect_num,N_did,N_avg,diff,pass", path)
}

#' Initialise the wagepan-specs CSV
init_wagepan_csv <- function(path) {
  writeLines("spec,effect_num,N_std,N_avg,diff,pass", path)
}

#' Write one row to a switcher CSV and print to console
write_swrow <- function(path, dataset, spec, reset, effnum, n_did, n_avg) {
  if (is.na(n_did) || is.na(n_avg)) {
    diff <- NA; pass <- "MISS"
  } else {
    diff <- n_did - n_avg
    pass <- if (diff == 0) "PASS" else "FAIL"
  }
  row <- sprintf("%s,%s,%d,%d,%s,%s,%s,%s",
                 dataset, spec, reset, effnum,
                 ifelse(is.na(n_did), ".", n_did),
                 ifelse(is.na(n_avg), ".", n_avg),
                 ifelse(is.na(diff),  ".", diff),
                 pass)
  cat(row, "\n", file = path, append = TRUE)
  tag <- sprintf("  %s  %s/%s  reset=%d  eff=%d  did=%s  avg=%s",
                 pass, dataset, spec, reset, effnum,
                 ifelse(is.na(n_did), ".", n_did),
                 ifelse(is.na(n_avg), ".", n_avg))
  if (pass == "PASS") message(tag) else warning(tag, call. = FALSE)
}

#' Write an ERROR sentinel row to a switcher CSV
write_diagrow <- function(path, dataset, spec, reset, msg) {
  row <- sprintf("%s,%s,%d,-1,.,.,.,ERROR:%s", dataset, spec, reset, msg)
  cat(row, "\n", file = path, append = TRUE)
  warning(sprintf("  ERROR  %s/%s  reset=%d  %s", dataset, spec, reset, msg),
          call. = FALSE)
}

#' Write one row to the wagepan-specs CSV
write_wrow <- function(path, spec, effnum, n_std, n_avg) {
  if (is.na(n_std) || is.na(n_avg)) {
    diff <- NA; pass <- "MISS"
  } else {
    diff <- n_std - n_avg
    pass <- if (diff == 0) "PASS" else "FAIL"
  }
  row <- sprintf("%s,%d,%s,%s,%s,%s",
                 spec, effnum,
                 ifelse(is.na(n_std), ".", n_std),
                 ifelse(is.na(n_avg), ".", n_avg),
                 ifelse(is.na(diff),  ".", diff),
                 pass)
  cat(row, "\n", file = path, append = TRUE)
  tag <- sprintf("  %s  %s  eff=%d  std=%s  avg=%s",
                 pass, spec, effnum,
                 ifelse(is.na(n_std), ".", n_std),
                 ifelse(is.na(n_avg), ".", n_avg))
  if (pass == "PASS") message(tag) else warning(tag, call. = FALSE)
}

# ── reset_groups_R ────────────────────────────────────────────────────────────
# R port of reset_groups_function.do.
# Modifies df in place (returns a new data.frame).
# When reset == 0, returns df unchanged.
# With replace_group = TRUE, overwrites the group column with the new pseudo-id.

reset_groups_R <- function(df, gvar, tvar, dvar, reset,
                            replace_group = TRUE,
                            newgroup_col  = "new_group",
                            oldgroup_col  = "old_group") {

  if (reset == 0L) {
    message("reset(0): no splitting performed; data unchanged.")
    return(df)
  }

  # ── balance: keep only units observed in every period ─────────────────────
  n_before <- nrow(df)
  max_obs  <- df %>%
    filter(!is.na(.data[[dvar]])) %>%
    group_by(.data[[gvar]]) %>%
    summarise(.n = n(), .groups = "drop") %>%
    pull(.n) %>% max()

  df <- df %>%
    group_by(.data[[gvar]]) %>%
    filter(sum(!is.na(.data[[dvar]])) == max_obs) %>%
    ungroup()

  n_dropped <- n_before - nrow(df)

  # ── sort for correct lag computation ──────────────────────────────────────
  df <- df %>% arrange(.data[[gvar]], .data[[tvar]])

  # ── periods-since-last-change (psc) ───────────────────────────────────────
  df <- df %>%
    group_by(.data[[gvar]]) %>%
    mutate(
      .changed = c(0L, as.integer(.data[[dvar]][-1] != .data[[dvar]][-n()])),
      .spell   = cumsum(.changed),
      .psc     = ave(seq_along(.spell), .data[[gvar]], .spell,
                     FUN = function(x) seq_along(x) - 1L),
      .psc     = ifelse(.spell == 0L, 0L, .psc)
    ) %>%
    ungroup()

  # ── split points: psc == reset ────────────────────────────────────────────
  df <- df %>%
    group_by(.data[[gvar]]) %>%
    mutate(.reset_count = cumsum(.psc == reset)) %>%
    ungroup()

  # ── new pseudo-group id ───────────────────────────────────────────────────
  df[[oldgroup_col]] <- df[[gvar]]

  df <- df %>%
    mutate(.grp_key = paste(.data[[gvar]], .reset_count, sep = "_"))
  df[[newgroup_col]] <- as.integer(factor(df$.grp_key))

  n_newgrp <- length(unique(df[[newgroup_col]]))

  if (replace_group) df[[gvar]] <- df[[newgroup_col]]

  # clean temporaries
  df <- df %>% select(-any_of(c(".changed", ".spell", ".psc",
                                ".reset_count", ".grp_key")))

  message(sprintf("reset_groups_R: reset=%d | dropped=%d | pseudo-groups=%d",
                  reset, n_dropped, n_newgrp))
  df
}

# ── dump_result ──────────────────────────────────────────────────────────────
# Print the full regression summary and the avg_time_periods details for one
# run, plus an inline PASS/FAIL line per effect comparing
# N_switchers_effect_k against N_switch_avg_k. The log files written via
# sink() will then contain everything we need to eyeball each spec.

dump_result <- function(res, label, n_eff) {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("RESULT DUMP: ", label, "\n", sep = "")
  cat(strrep("=", 70), "\n", sep = "")

  if (is.null(res)) {
    cat("  res is NULL — did_multiplegt_dyn() returned no result.\n")
    return(invisible(NULL))
  }

  cat("\n-- summary(res) --\n")
  tryCatch(print(summary(res)), error = function(e) {
    cat("  (summary() failed: ", conditionMessage(e), ")\n", sep = "")
    tryCatch(print(res), error = function(e2) {
      cat("  (print() also failed: ", conditionMessage(e2), ")\n", sep = "")
    })
  })

  cat("\n-- avg_time_periods --\n")
  if (is.null(res$avg_cumul)) {
    cat("  avg_cumul not set (was avg_time_periods = TRUE?)\n")
  } else {
    cat(sprintf("  avg_cumul = %s\n", format(res$avg_cumul, nsmall = 4)))
  }

  cat("\n-- per-effect comparison (N_switchers_effect_k vs N_switch_avg_k) --\n")
  cat(sprintf("  %-8s  %-22s  %-18s  %-6s  %s\n",
              "effect", "N_switchers_effect_k", "N_switch_avg_k", "diff", "status"))
  cat("  ", strrep("-", 66), "\n", sep = "")
  for (k in seq_len(n_eff)) {
    n_std <- tryCatch(res[[paste0("N_switchers_effect_", k)]], error = function(e) NULL)
    n_avg <- tryCatch(res[[paste0("N_switch_avg_", k)]], error = function(e) NULL)
    n_std_s <- if (is.null(n_std)) "." else format(n_std)
    n_avg_s <- if (is.null(n_avg)) "." else format(n_avg)
    if (is.null(n_std) || is.null(n_avg)) {
      diff_s <- "."
      status <- "MISS"
    } else {
      d <- n_std - n_avg
      diff_s <- format(d)
      status <- if (d == 0) "PASS" else "FAIL"
    }
    cat(sprintf("  %-8d  %-22s  %-18s  %-6s  %s\n",
                k, n_std_s, n_avg_s, diff_s, status))
  }
  cat(strrep("=", 70), "\n", sep = "")
  invisible(NULL)
}

# ── Switcher-count extractor ──────────────────────────────────────────────────
# Pull N_switchers_effect_k from a did_multiplegt_dyn result object.
# Returns a named numeric vector; NA for missing entries.

extract_N_switchers <- function(res, max_k = 600L) {
  out <- setNames(rep(NA_real_, max_k), paste0("k", seq_len(max_k)))
  if (is.null(res)) return(out)
  for (k in seq_len(max_k)) {
    nm <- paste0("N_switchers_effect_", k)
    v  <- tryCatch(res[[nm]], error = function(e) NULL)
    if (is.null(v) || length(v) == 0 || is.na(v) || v == 0) break
    out[[k]] <- v
  }
  out
}

# ── avg_time_periods extractor ────────────────────────────────────────────────
# Pull N_switch_avg_k from a result object that was run with avg_time_periods.

extract_N_switch_avg <- function(res, max_k = 600L) {
  out <- setNames(rep(NA_real_, max_k), paste0("k", seq_len(max_k)))
  if (is.null(res)) return(out)
  for (k in seq_len(max_k)) {
    nm <- paste0("N_switch_avg_", k)
    v  <- tryCatch(res[[nm]], error = function(e) NULL)
    if (is.null(v) || length(v) == 0 || is.na(v) || v == 0) break
    out[[k]] <- v
  }
  out
}
