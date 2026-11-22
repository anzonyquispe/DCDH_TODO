## common.R -- helpers shared by R/run_specs.R and R_bootstrap/run_bootstrap.R
##   load_package()        load the DIDmultiplegtDYN chosen in DCDH_R_PKG (never defaulted)
##   build_args()          Stata option string -> R arguments (specs/option_map.csv)
##   load_data(), prep()   datasets in data/ and the shared data preparations

suppressPackageStartupMessages({
  library(haven)
  library(polars)   # DIDmultiplegtDYN needs polars attached, not only installed
})

load_package <- function(out_dir) {
  pkg <- Sys.getenv("DCDH_R_PKG")
  if (!nzchar(pkg)) stop("DCDH_R_PKG is not set. Say which DIDmultiplegtDYN to test (installed, a source folder, a .tar.gz, or a library folder).")
  version <- NA_character_
  if (pkg == "installed") {
    suppressPackageStartupMessages(library(DIDmultiplegtDYN))
    source <- find.package("DIDmultiplegtDYN")
  } else if (grepl("\\.tar\\.gz$", pkg)) {
    lib <- file.path(out_dir, "_lib"); dir.create(lib, recursive = TRUE, showWarnings = FALSE)
    install.packages(pkg, repos = NULL, type = "source", lib = lib, quiet = TRUE)
    suppressPackageStartupMessages(library(DIDmultiplegtDYN, lib.loc = lib))
    source <- normalizePath(pkg)
  } else if (file.exists(file.path(pkg, "DESCRIPTION"))) {
    pkgload::load_all(pkg, quiet = TRUE, export_all = FALSE)
    source <- normalizePath(pkg)
    version <- as.character(read.dcf(file.path(pkg, "DESCRIPTION"), fields = "Version"))
  } else if (dir.exists(file.path(pkg, "DIDmultiplegtDYN"))) {
    suppressPackageStartupMessages(library(DIDmultiplegtDYN, lib.loc = pkg))
    source <- normalizePath(file.path(pkg, "DIDmultiplegtDYN"))
  } else {
    stop("DCDH_R_PKG = ", pkg, " is not 'installed', a source folder, a .tar.gz or a library folder")
  }
  if (is.na(version)) version <- as.character(packageVersion("DIDmultiplegtDYN"))
  list(source = source, version = version, formals = names(formals(did_multiplegt_dyn)))
}

read_spec_file <- function(suite, f) read.csv(file.path(suite, "specs", f), colClasses = "character",
                                              na.strings = character(0), strip.white = TRUE, encoding = "UTF-8")

parse_stata_options <- function(s) {
  m <- gregexpr("[A-Za-z_][A-Za-z_0-9]*(\\((?:[^()]|\\([^()]*\\))*\\))?", s, perl = TRUE)
  lapply(regmatches(s, m)[[1]], function(t) list(
    name = sub("\\(.*$", "", t),
    arg = if (grepl("\\(", t)) sub("^[^(]*\\((.*)\\)$", "\\1", t) else NA_character_))
}

split_comma <- function(a) trimws(strsplit(a, ",", fixed = TRUE)[[1]])

convert_option <- function(kind, arg) {
  switch(kind,
    int = as.numeric(arg),
    flag = TRUE,
    varlist = strsplit(trimws(arg), "\\s+")[[1]],
    var = trimws(arg),
    string = trimws(arg),
    effects_equal = if (tolower(trimws(arg)) == "all") "all" else trimws(arg),
    by_path = if (grepl("^-?[0-9.]+$", trimws(arg))) as.numeric(arg) else trimws(arg),
    design = { p <- split_comma(arg); f <- if (length(p) && nzchar(p[1])) as.numeric(p[1]) else 1
               list(f, if (length(p) >= 2) p[2] else "console") },
    predict_het = { p <- split_comma(arg); w <- if (length(p) >= 2 && p[2] != "all") as.numeric(strsplit(p[2], "\\s+")[[1]]) else -1
                    list(strsplit(p[1], "\\s+")[[1]], w) },
    date_first_switch = { p <- split_comma(arg); list(if (length(p) && nzchar(p[1])) p[1] else "", if (length(p) >= 2) p[2] else "console") },
    bootstrap = as.numeric(split_comma(arg)),
    stop("unknown option kind ", kind))
}

build_args <- function(opts, optmap, notsup, formals) {
  a <- list(); ns <- NULL; used <- character(0)
  for (o in parse_stata_options(opts)) {
    used <- c(used, o$name)
    row <- optmap[optmap$stata_option == o$name, , drop = FALSE]
    if (nrow(row) == 0) { ns <- c(ns, paste0("unknown option ", o$name)); next }
    hit <- notsup[notsup$option == o$name & notsup$scope == "spec", , drop = FALSE]
    if (nrow(hit)) { ns <- c(ns, hit$reason[1]); next }
    if (!nzchar(row$r_arg) || !(row$r_arg %in% formals)) {
      ns <- c(ns, sprintf("option %s has no argument in this DIDmultiplegtDYN", o$name)); next
    }
    a[[row$r_arg]] <- convert_option(row$kind, o$arg)
  }
  list(args = a, not_supported = if (length(ns)) paste(ns, collapse = "; ") else NULL, options = used)
}

load_data <- function(data_dir, ds) as.data.frame(zap_labels(read_dta(file.path(data_dir, paste0(ds, ".dta")))))

prep_data <- function(df, p) {
  if (!nzchar(p)) return(df)
  # Stata treats a missing value as larger than any number
  le <- function(x, y) !is.na(x) & (is.na(y) | x <= y)
  lt <- function(x, y) !is.na(x) & (is.na(y) | x < y)
  eq1 <- function(x) !is.na(x) & x == 1
  switch(p,
    deryugina_year_controls = {
      for (v in c("coastal", "land_area1970", "log_pop1969", "frac_young1969", "frac_old1969",
                  "frac_black1969", "log_wage_pc1969", "emp_rate1969"))
        df[[paste0(v, "_year")]] <- df[[v]] * df$year
      df },
    gentzkow_t11 = df[le(df$year, df$first_change) | eq1(df$same_treat_after_first_change), , drop = FALSE],
    gentzkow_ch08 = df[lt(df$year, df$first_change) | eq1(df$same_treat_after_first_change), , drop = FALSE],
    hollingsworth_t13 = df[!is.na(df$rm) & df$rm == 0, , drop = FALSE],
    hollingsworth_t14 = {
      fg <- ave(ifelse(!is.na(df$mm) & df$mm == 1, df$year, NA), df$state,
                FUN = function(x) suppressWarnings(min(x, na.rm = TRUE)))
      fg[!is.finite(fg)] <- NA
      df$fg1 <- fg
      df[!is.na(df$mm) & df$mm == 1, , drop = FALSE] },
    stop("unknown prep ", p))
}
