## run_specs.R  --  R side of the did_multiplegt_dyn suite
##
## Runs every spec in ../specs/specs.csv and every input check in
## ../specs/validation.csv and writes, in <results>/r/:
##   outputs.csv     every result element under the name Stata uses for it
##                   (e_scalar Effect_1, se_effect_1, ...; e_matrix b / V;
##                   matrix mat_res_XX, desmat, dfs#; e_matrix effect_het_*)
##   status.csv      one row per spec (and per by / by_path unit)
##   validation.csv  accepted / rejected for each input check
##   meta.txt        which DIDmultiplegtDYN was tested
##
## Usage (normally called by ../run_tests.sh):
##   Rscript R/run_specs.R <suite folder> <results folder>
##
## Environment variables:
##   DCDH_R_PKG   REQUIRED. Which DIDmultiplegtDYN to test:
##                  installed          the version installed in R
##                  <folder>           a package source folder (has DESCRIPTION), loaded with pkgload
##                  <file.tar.gz>      a source tarball, installed into <results>/r/_lib
##                  <library folder>   a library folder that contains DIDmultiplegtDYN/
##   DCDH_ONLY    space-separated spec ids (default: all)
##   DCDH_BLOCKS  space-separated blocks (default: all)

args <- commandArgs(trailingOnly = TRUE)
SUITE <- normalizePath(if (length(args) >= 1) args[1] else file.path(getwd(), ".."), mustWork = TRUE)
RES <- if (length(args) >= 2) args[2] else file.path(SUITE, "results")
OUT <- file.path(RES, "r")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
DATA <- file.path(SUITE, "data")

source(file.path(SUITE, "R", "common.R"))
P <- load_package(OUT)
pkg_source <- P$source; pkg_version <- P$version; FORMALS <- P$formals

meta <- c("language=r", paste0("language_version=", R.version.string),
          paste0("package_source=", pkg_source), paste0("package_version=", pkg_version),
          paste0("polars_version=", as.character(packageVersion("polars"))),
          paste0("started_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
writeLines(meta, file.path(OUT, "meta.txt"))
cat(sprintf("Testing DIDmultiplegtDYN %s from %s
", pkg_version, pkg_source))

SPECS <- read_spec_file(SUITE, "specs.csv")
OPTMAP <- read_spec_file(SUITE, "option_map.csv")
NOTSUP <- read_spec_file(SUITE, "not_supported.csv")
NOTSUP <- NOTSUP[NOTSUP$lang == "r", , drop = FALSE]
VAL <- read_spec_file(SUITE, "validation.csv")
build <- function(opts) build_args(opts, OPTMAP, NOTSUP, FORMALS)
load_ds <- function(ds) load_data(DATA, ds)

## -- Result extraction under Stata's names -----------------------------------
num <- function(x) { x <- suppressWarnings(as.numeric(x)); ifelse(is.na(x), "", sprintf("%.17g", x)) }
ROWS <- list()
lab1 <- function(x) if (length(x) == 0 || is.na(x[1])) "" else as.character(x[1])  # NULL / character(0) / NA -> ""
emit <- function(spec, unit, kind, name, value, row = "", col = "", rowname = "", colname = "") {
  ROWS[[length(ROWS) + 1]] <<- c(spec, unit, kind, name, lab1(row), lab1(col),
                                   lab1(rowname), lab1(colname), lab1(value), "full")
}
OUT_COLS <- c("spec_id", "unit", "kind", "name", "row", "col", "rowname", "colname", "value", "precision")
MAT_COLS <- c("Estimate", "SE", "LB CI", "UB CI", "N", "Switchers")

emit_table <- function(spec, unit, tab, kind) {
  if (is.null(tab)) return(invisible())
  tab <- as.matrix(tab); if (nrow(tab) == 0) return(invisible())
  for (r in seq_len(nrow(tab))) {
    rn <- trimws(rownames(tab)[r])
    k <- as.integer(sub("^\\D+_", "", rn))
    get <- function(j) if (ncol(tab) >= j) tab[r, j] else NA
    est <- get(1); se <- get(2); n <- get(5); sw <- get(6); nw <- get(7); sww <- get(8)
    if (kind == "effect") {
      emit(spec, unit, "e_scalar", paste0("Effect_", k), num(est))
      emit(spec, unit, "e_scalar", paste0("se_effect_", k), num(se))
      emit(spec, unit, "e_scalar", paste0("N_effect_", k), num(n))
      emit(spec, unit, "e_scalar", paste0("N_switchers_effect_", k), num(sw))
      emit(spec, unit, "e_scalar", paste0("N_effect_", k, "_w"), num(nw))
      emit(spec, unit, "e_scalar", paste0("N_switchers_effect_", k, "_w"), num(sww))
      ttt <- k
    } else if (kind == "placebo") {
      emit(spec, unit, "e_scalar", paste0("Placebo_", k), num(est))
      emit(spec, unit, "e_scalar", paste0("se_placebo_", k), num(se))
      emit(spec, unit, "e_scalar", paste0("N_placebo_", k), num(n))
      emit(spec, unit, "e_scalar", paste0("N_switchers_placebo_", k), num(sw))
      emit(spec, unit, "e_scalar", paste0("N_placebo_", k, "_w"), num(nw))
      emit(spec, unit, "e_scalar", paste0("N_switchers_placebo_", k, "_w"), num(sww))
      ttt <- -k
    } else {
      rn <- "Av_tot_eff"
      emit(spec, unit, "e_scalar", "Av_tot_effect", num(est))
      emit(spec, unit, "e_scalar", "se_avg_total_effect", num(se))
      emit(spec, unit, "e_scalar", "N_avg_total_effect", num(n))
      emit(spec, unit, "e_scalar", "N_switchers_effect_average", num(sw))
      emit(spec, unit, "e_scalar", "N_avg_total_effect_w", num(nw))
      emit(spec, unit, "e_scalar", "N_switchers_effect_average_w", num(sww))
      ttt <- 0
    }
    for (j in 1:6) emit(spec, unit, "matrix", "mat_res_XX", num(get(j)), col = j, rowname = rn, colname = MAT_COLS[j])
    emit(spec, unit, "matrix", "mat_res_XX", num(ttt), col = 7, rowname = rn, colname = "time_to_treat")
  }
}

emit_unit <- function(spec, unit, u, top = u) {
  R <- u$results
  if (is.null(R)) return(FALSE)
  emit_table(spec, unit, R$Effects, "effect")
  emit_table(spec, unit, R$ATE, "ate")
  emit_table(spec, unit, R$Placebos, "placebo")
  for (p in c("p_jointeffects", "p_jointplacebo", "p_equality_effects"))
    if (!is.null(R[[p]])) emit(spec, unit, "e_scalar", p, num(R[[p]]))
  emit(spec, unit, "e_macro", "cmd", "did_multiplegt_dyn")
  if (!is.null(R$Effects)) emit(spec, unit, "e_macro", "effects", paste(trimws(rownames(as.matrix(R$Effects))), collapse = " "))
  if (!is.null(R$Placebos)) emit(spec, unit, "e_macro", "placebo", paste(trimws(rownames(as.matrix(R$Placebos))), collapse = " "))
  cf <- u$coef  # e(b) is not compared (see specs/stata_only.csv)
  if (!is.null(cf$vcov)) {
    V <- as.matrix(cf$vcov)
    for (i in seq_len(nrow(V))) for (j in seq_len(ncol(V)))
      emit(spec, unit, "e_matrix", "V", num(V[i, j]), row = i, col = j,
           rowname = trimws(rownames(V)[i]), colname = trimws(colnames(V)[j]))
  }
  # design(): matrix "desmat" in Stata
  d <- top$design
  if (!is.null(d) && !is.null(d$design_mat)) {
    M <- unclass(d$design_mat)
    for (i in seq_len(nrow(M))) for (j in seq_len(ncol(M)))
      emit(spec, unit, "matrix", "desmat", num(M[i, j]), row = i, col = j,
           rowname = rownames(M)[i], colname = colnames(M)[j])
  }
  # date_first_switch(): matrices "dfs#" in Stata
  f <- top$date_first_switch
  if (!is.null(f)) {
    for (nm in grep("^dfs_mat[0-9]*$", names(f), value = TRUE)) {
      M <- unclass(f[[nm]]); k <- sub("^dfs_mat", "", nm); if (!nzchar(k)) k <- "1"
      for (i in seq_len(nrow(M))) for (j in seq_len(ncol(M)))
        emit(spec, unit, "matrix", paste0("dfs", k), num(M[i, j]), row = i, col = j,
             rowname = rownames(M)[i], colname = colnames(M)[j])
      # Stata: e(switch_dates_Dsq_#) = number of first-switch dates for baseline level #
      #        (by_baseline_treat), e(switch_dates) otherwise
      sd <- if (identical(lab1(f$dfs_opt), "by_baseline_treat")) paste0("switch_dates_Dsq_", k) else "switch_dates"
      emit(spec, unit, "e_scalar", sd, num(nrow(M)))
    }
  }
  # avg_time_periods: e(avg_cumul), e(N_switch_avg_#) in Stata -- same names in R (top level)
  src <- if (!is.null(u$avg_cumul)) u else top
  if (!is.null(src$avg_cumul)) emit(spec, unit, "e_scalar", "avg_cumul", num(src$avg_cumul))
  for (nm in grep("^N_switch_avg_[0-9]+$", names(src), value = TRUE))
    emit(spec, unit, "e_scalar", nm, num(src[[nm]]))
  # predict_het(): e(effect_het_#_XX) / e(effect_het_pl_#_XX) in Stata
  ph <- R$predict_het
  if (!is.null(ph)) {
    ph <- as.data.frame(ph)
    for (r in seq_len(nrow(ph))) {
      e <- as.integer(ph$effect[r])
      nm <- if (e < 0) sprintf("effect_het_pl_%d_XX", -e) else sprintf("effect_het_%d_XX", e)
      vals <- c(ph$Estimate[r], ph$SE[r], ph$t[r], ph$LB[r], ph$UB[r], ph$N[r])
      for (j in 1:6) emit(spec, unit, "e_matrix", nm, num(vals[j]), col = j, rowname = as.character(ph$covariate[r]))
    }
  }
  TRUE
}

STATUS <- list()
OUT_FILE <- file.path(OUT, "outputs.csv"); STATUS_FILE <- file.path(OUT, "status.csv")
write.csv(as.data.frame(matrix(character(0), 0, length(OUT_COLS), dimnames = list(NULL, OUT_COLS))), OUT_FILE, row.names = FALSE)
write.csv(data.frame(spec_id = character(0), unit = character(0), status = character(0), rc = character(0),
                     seconds = character(0), message = character(0)), STATUS_FILE, row.names = FALSE)
flush_rows <- function() {
  # append this spec's rows so that a crash later keeps what was done
  if (length(ROWS)) {
    m <- do.call(rbind, ROWS); colnames(m) <- OUT_COLS
    write.table(as.data.frame(m, stringsAsFactors = FALSE), OUT_FILE, sep = ",", append = TRUE,
                col.names = FALSE, row.names = FALSE, qmethod = "double", na = "")
    ROWS <<- list()
  }
  if (length(STATUS)) {
    write.table(do.call(rbind, STATUS), STATUS_FILE, sep = ",", append = TRUE,
                col.names = FALSE, row.names = FALSE, qmethod = "double", na = "")
    STATUS <<- list()
  }
}
status <- function(spec, unit, st, secs = "", msg = "") {
  STATUS[[length(STATUS) + 1]] <<- data.frame(spec_id = spec, unit = unit, status = st,
    rc = "", seconds = as.character(secs), message = gsub("[\r\n\"]", " ", substr(msg, 1, 400)),
    stringsAsFactors = FALSE)
}

run_fit <- function(df, s, extra) {
  a <- c(list(df = df, outcome = s$outcome, group = s$group, time = s$time,
              treatment = s$treatment, graph_off = TRUE), extra)
  tryCatch(suppressMessages(suppressWarnings(do.call(did_multiplegt_dyn, a))), error = function(e) e)
}

## -- Specs -------------------------------------------------------------------
only <- strsplit(Sys.getenv("DCDH_ONLY"), " +")[[1]]
blocks <- strsplit(Sys.getenv("DCDH_BLOCKS"), " +")[[1]]
for (i in seq_len(nrow(SPECS))) {
  flush_rows()
  s <- SPECS[i, ]
  if (length(only) && !(s$spec_id %in% only)) next
  if (length(blocks) && !(s$block %in% blocks)) next
  cat(sprintf("\n=== %s: %s\n", s$spec_id, s$options))
  ba <- build(s$options)
  if (!is.null(ba$not_supported)) { status(s$spec_id, "", "not_supported", msg = ba$not_supported); next }
  df <- tryCatch(prep_data(load_ds(s$dataset), s$prep), error = function(e) e)
  if (inherits(df, "error")) { status(s$spec_id, "", "error", msg = conditionMessage(df)); next }
  t0 <- Sys.time()
  res <- run_fit(df, s, ba$args)
  secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 3)
  if (inherits(res, "error")) {
    cat("  ERROR:", conditionMessage(res), "\n")
    status(s$spec_id, "", "error", secs, conditionMessage(res)); next
  }
  if (!is.null(res$by_levels)) {
    kind <- if ("by_path" %in% ba$options) "path" else "level"
    labs <- as.character(res$by_levels)
    for (k in seq_along(labs)) {
      unit <- paste0(kind, "=", gsub(" ", "", labs[k]))
      ok <- emit_unit(s$spec_id, unit, res[[paste0("by_level_", k)]], top = res[[paste0("by_level_", k)]])
      status(s$spec_id, unit, if (ok) "ok" else "no_results", secs)
    }
  } else {
    ok <- emit_unit(s$spec_id, "", res, top = res)
    status(s$spec_id, "", if (ok) "ok" else "no_results", secs)
  }
  cat(sprintf("  done in %.1fs\n", secs))
}
flush_rows()

## -- Input checks (skipped when DCDH_SKIP_VALIDATION=1) ----------------------
if (Sys.getenv("DCDH_SKIP_VALIDATION") != "1") {
wagepan <- load_ds("wagepan")
vout <- data.frame(vid = character(0), outcome = character(0), message = character(0), stringsAsFactors = FALSE)
for (i in seq_len(nrow(VAL))) {
  v <- VAL[i, ]
  ba <- build(v$test_option)
  if (!is.null(ba$not_supported)) {
    vout[nrow(vout) + 1, ] <- list(v$vid, "not_supported", ba$not_supported); next
  }
  # value_type = str: pass by_path as text even when it looks like a number
  if (v$value_type == "str" && !is.null(ba$args$by_path))
    ba$args$by_path <- sub("^.*by_path\\(([^)]*)\\).*$", "\\1", v$test_option)
  res <- run_fit(wagepan, list(outcome = "lwage", group = "nr", time = "year", treatment = "union"),
                 c(list(effects = 2L, placebo = 0L), ba$args))
  if (inherits(res, "error")) {
    out <- "rejected"; msg <- gsub("[\r\n,\"]", " ", conditionMessage(res))
  } else {
    out <- if (!is.null(res$results) || !is.null(res$by_level_1$results)) "accepted" else "rejected"; msg <- ""
  }
  cat(sprintf("VALIDATION %s %s -> %s\n", v$vid, v$test_option, out))
  vout[nrow(vout) + 1, ] <- list(v$vid, out, substr(msg, 1, 200))
}
write.csv(vout, file.path(OUT, "validation.csv"), row.names = FALSE, na = "")
}
cat(paste0("finished_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n"), file = file.path(OUT, "meta.txt"), append = TRUE)
cat("\nR specs finished. Results in", OUT, "\n")
