rm(list = ls())
setwd('/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO')

sink(file.path( 'logfiles', paste0("R_", Sys.Date(), ".log")), split = TRUE)

library(DIDmultiplegtDYN)
library(polars)
library(data.table)
library(haven)



# ============================================================
# Ch4 — Part 2: §4.1.2 did_multiplegt_dyn
# ============================================================

library(haven)
library(DIDmultiplegtDYN)
library(polars)

df <- read_dta("_data/moser_voena_didtextbook.dta")

result_dyn <- did_multiplegt_dyn(
  df = as.data.frame(df),
  outcome = "patents",
  group = "subclass",
  time = "year",
  treatment = "twea",
  effects = 21,
  placebo = 18,
  trends_nonparam = "patents1900",
  graph_off = TRUE
)
print(result_dyn)

df <- read_stata('_data/wagepan.dta')


# bootstrap 
summary(did_multiplegt_dyn(
  df = df,
  outcome = "lwage",
  group = "nr",
  time = "year",
  treatment = "union",
  effects = 5,
  placebo = 2,
  bootstrap = list(20, 1234)
))

# Desing 
summary(did_multiplegt_dyn(
  df = df,
  outcome = "lwage",
  group = "nr",
  time = "year",
  treatment = "union",
  effects = 5,
  placebo = 2,
  design = c(1, "console")
))


# predict het
summary(did_multiplegt_dyn(
  df = df,
  outcome = "lwage",
  group = "nr",
  time = "year",
  treatment = "union",
  effects = 5,
  placebo = 2,
  predict_het=list('black', -1)
))

## By Option
summary(did_multiplegt_dyn(
  df = df,
  outcome = "lwage",
  group = "nr",
  time = "year",
  treatment = "union",
  effects = 5,
  placebo = 2,
  by = "black"
))

## By_path Option
df <- read_stata('_data/wagepan.dta')
summary(did_multiplegt_dyn(
  df = df,
  outcome = "lwage",
  group = "nr",
  time = "year",
  treatment = "union",
  effects = 5,
  placebo = 2,
  by_path = 4
))




## warning options
summary(did_multiplegt_dyn(
  df = df,
  outcome = "lwage",
  group = "nr",
  time = "year",
  treatment = "union",
  effects = 5,
  placebo = 2,
  cluster = "hisp"
))




sink()
# install.packages("/Users/anzony.quisperojas/Documents/GitHub/R_didgt_polars/DIDmultiplegtDYN_2.3.1.tar.gz", repos = NULL, type = "source")