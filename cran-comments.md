## Test environments

* local macOS aarch64, R 4.5.2
* local Ubuntu 24.04 aarch64, R 4.4.2
* win-builder (devel and release)

## R CMD check results

0 errors | 0 warnings | 1 note

* `polars` is listed in `Suggests` and ships from
  `https://rpolars.r-universe.dev` (declared in `Additional_repositories`).
  All code that uses `polars` is gated on `requireNamespace("polars")`, so
  the package installs and runs every code path that does not require the
  optional accelerator without it.

## Downstream dependencies

We checked the reverse dependencies of `DIDmultiplegtDYN` reported by
`revdepcheck::revdep_check()`: 0 packages.

## Changes since 2.3.4

This is a minor release. Highlights (full list in `NEWS.md`):

* New options: `reset` and `avg_time_periods` (ports of the corresponding
  Stata `did_multiplegt_dyn.ado` options).
* C++ ports of the two Mata routines that back `avg_time_periods`
  (`compute_Tg_cpp`, `avg_cumul_cpp`) for performance.
* Bug fixes in argument-type checking: integer scalars (e.g.
  `effects = 5L`, `bootstrap = 100L`) no longer trip
  `inherits(x, "numeric")`, and the `bootstrap` argument now accepts a
  numeric scalar, a `c(reps, seed)` vector, or a named vector.
* Dropped the unused `matlib` dependency.
