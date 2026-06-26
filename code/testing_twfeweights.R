# from inside the package directory
setwd("/Users/anzony.quisperojas/Documents/GitHub/clement_pkg/Untitled/twowayfeweights/R")
devtools::document()   # regenerate NAMESPACE and man/ from roxygen comments
devtools::test()       # run testthat tests
devtools::check()      # full R CMD check
devtools::build()      # produces the .tar.gz in the parent directory
devtools::install()    # install into your local R library


install.packages(
  "/Users/anzony.quisperojas/Documents/GitHub/clement_pkg/Untitled/twowayfeweights/TwoWayFEWeights_2.1.0.tar.gz",
  repos = NULL,
  type = "source"
)
library(haven); library(TwoWayFEWeights)
load(url("https://raw.githubusercontent.com/anzonyquispe/did_book/main/cc_xd_didtextbook_2025_9_30/Data%20sets/Wolfers%202006/wolfers2006_didtextbook.RData"))
rel_time_vars <- names(df)[grepl("^rel_time", names(df))]
other_rel_times <- rel_time_vars[rel_time_vars != "rel_time1"]
other_treatments <- other_rel_times[grepl("^rel_time[2-9]$|^rel_time1[0-6]$", other_rel_times)]
controls <- other_rel_times[grepl("minus", other_rel_times)]
decomp5 <- twowayfeweights(df, "div_rate", "state", "year", "rel_time1",
                           type = "feTR", test_random_weights = "year",
                           weights = df$stpop,
                           other_treatments = other_treatments,
                           controls = controls)
print(decomp5)
