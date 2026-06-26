##### File to run standardized tests for "did_multiplegt_dyn" before updating versions #####
### Version: 22.05.25 ###
### Preamble ###
################################################################################

# Load required packages
library(haven)
library(DIDmultiplegtDYN)
library(polars)

# Set the directory to load the datasets and to store the resulting log files
setwd("/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO")
df <- read_dta("_data/wagepan.dta")

# Base variables
y       <- "lwage"
g       <- "nr"
t       <- "year"
d       <- "union"

# Number of effects/placebos
n_eff   <- 5
n_pl    <- 2

# Bootstrap options
b_reps  <- 20
b_seed  <- 1234

# Controls
cont    <- "hours"

# Nonparametric trends by
nonparam <- "black"

# Weighting variable
wght    <- "educ"

# Cluster variables
clust   <- "hisp"

# by variable
by_var  <- "black"

# predict_het variable
het_var <- "black"

# effects to test in effects-equal
eff_eq  <- "all"

# Run did_multiplegt_dyn
# NOTE: The original Stata call had a syntax error (missing opening parenthesis 
# in effects). The corrected call is:
# did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') cluster(`clust')

result <- did_multiplegt_dyn(
  df        = df,
  outcome   = y,
  group     = g,
  time      = t,
  treatment = d,
  effects   = n_eff,
  placebo   = n_pl,
  cluster   = clust,
  graph_off = FALSE
)

summary(result)

# Print results
result$coef$vcov

