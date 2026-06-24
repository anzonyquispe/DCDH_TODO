rm(list = ls())
library(DIDmultiplegtDYN)
library(polars)


load(url("https://raw.githubusercontent.com/anzonyquispe/did_book/main/did_applied_book/data/deryugina_2017.RData"))

vars <- c("coastal", "land_area1970", "log_pop1969", "frac_young1969",
          "frac_old1969", "frac_black1969", "log_wage_pc1969", "emp_rate1969")
for (v in vars) df[[paste0(v, "_year")]] <- df[[v]] * df$year
controls_list <- paste0(vars, "_year")

# Mean and SD for all controls
sapply(df[, controls_list], function(x) c(mean = mean(x, na.rm = TRUE), 
                                          sd   = sd(x, na.rm = TRUE),
                                          min  = min(x, na.rm = TRUE),
                                          max  = max(x, na.rm = TRUE)))

res_t3 <- did_multiplegt_dyn(
  df        = df,
  outcome   = "log_curr_trans_ind_gov_pc",
  group     = "county_fips",
  time      = "year",
  treatment = "hurricane",
  effects   = 3,
  placebo   = 3,
  cluster   = "county_fips",
  controls  = controls_list
)
print(res_t3)
res_t3$plot

attributes(res_t3)

round(res_t3$controls_globals$inv_Denom_1_XX, 2)





library(DIDmultiplegtDYN)
library(polars)

load(url("https://raw.githubusercontent.com/anzonyquispe/did_book/main/did_applied_book/data/east_et_al_2023.RData"))

stcontrols <- c("stmarried", "stblack", "stother", "sthsdrop", "sthsgrad",
                "stsomecoll", "pop0_4", "pop5_17", "pop18_24", "pop25_44",
                "pop45_64", "urate", "incpc", "maxafdc", "abortconsent", "abortmedr")

res_t5 <- did_multiplegt_dyn(
  df            = df,
  outcome       = "lbw_detrend81",
  group         = "plborn",
  time          = "dob_y_p",
  treatment     = "newsimeli",
  effects       = 5,
  placebo       = 5,
  continuous    = 1,
  controls      = stcontrols,
  weight        = "births",
  effects_equal = "all"
)
print(res_t5)



load(url("https://raw.githubusercontent.com/anzonyquispe/did_book/main/did_applied_book/data/east_et_al_2023.RData"))
stcontrols <- c("stmarried", "stblack", "stother", "sthsdrop", "sthsgrad",
                "stsomecoll", "pop0_4", "pop5_17", "pop18_24", "pop25_44",
                "pop45_64", "urate", "incpc", "maxafdc", "abortconsent", "abortmedr")

res_t6 <- did_multiplegt_dyn(
  df                 = df,
  outcome            = "lbw_detrend81",
  group              = "plborn",
  time               = "dob_y_p",
  treatment          = "newsimeli",
  effects            = 5,
  placebo            = 5,
  continuous         = 1,
  controls           = stcontrols,
  weight             = "births",
  normalized         = TRUE,
  normalized_weights = TRUE,
  effects_equal      = "all"
)
print(res_t6)


