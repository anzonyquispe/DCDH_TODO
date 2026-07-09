library(haven); library(didimputation); library(dplyr)
load(url("https://raw.githubusercontent.com/anzonyquispe/did_book/main/cc_xd_didtextbook_2025_9_30/Data%20sets/Wolfers%202006/wolfers2006_didtextbook.RData"))
df9 <- df %>% mutate(gname = ifelse(cohort == 0, NA, cohort))
bjs_out <- did_imputation(
  data = as.data.frame(df9),
  yname = "div_rate", gname = "gname",
  tname = "year", idname = "state",
  wname = "stpop", horizon = 0:12,
  pretrends = -(1:13))
print(bjs_out)


bjs_out <- did_imputation(
  data = as.data.frame(df9),
  yname = "div_rate", gname = "gname",
  tname = "year", idname = "state",
  horizon = 0:12,
  pretrends = -(1:13))
print(bjs_out)




library(haven); library(did); library(dplyr)
load(url("https://raw.githubusercontent.com/anzonyquispe/did_book/main/cc_xd_didtextbook_2025_9_30/Data%20sets/Wolfers%202006/wolfers2006_didtextbook.RData"))
# Replace missing cohort with 0
df7 <- df %>%
  mutate(cohort_cs = ifelse(is.na(cohort), 0, cohort))

# Check missing values in key variables
cat("Missing values per variable:\n")
print(sapply(df7[, c("stpop", "state", "year", "cohort_cs", "div_rate")], function(x) sum(is.na(x))))

# Flag and drop states with any missing in key variables
df7 <- df7 %>%
  group_by(state) %>%
  mutate(has_missing = any(is.na(stpop) | is.na(state) | is.na(year) | 
                             is.na(cohort_cs) | is.na(div_rate))) %>%
  ungroup() %>%
  filter(!has_missing) %>%
  select(-has_missing)

# Drop states not observed in ALL unique years
all_years <- sort(unique(df7$year))
T_max <- length(all_years)
cat("Total unique years in dataset:", T_max, "\n")

df7 <- df7 %>%
  group_by(state) %>%
  mutate(n_unique_years = n_distinct(year)) %>%
  ungroup() %>%
  filter(n_unique_years == T_max) %>%
  select(-n_unique_years)

# Drop always-treated states (cohort == first year in data)
first_year <- min(df7$year)
cat("Dropping always-treated states with cohort ==", first_year, "\n")
df7 <- df7 %>% filter(cohort_cs != first_year)

# Confirm balance
n_check <- df7 %>%
  group_by(state) %>%
  summarise(n = n(), .groups = "drop")

stopifnot(length(unique(n_check$n)) == 1)
cat("Panel is now balanced: all remaining states have", unique(n_check$n), "observations\n")

# After running att_gt with weights                                           
cs_out <- att_gt(yname = "div_rate", gname = "cohort_cs",                     
                 idname = "state", tname = "year",                            
                 data = as.data.frame(df7),                                   
                 xformla = ~1, bstrap = FALSE, cband = FALSE,
                 faster_mode = FALSE,
                 weightsname = "stpop",                                       
                 est_method = "reg")                                          
cs_es <- aggte(cs_out, type = "dynamic", bstrap = FALSE)
summary(cs_es)



cs_out <- att_gt(yname = "div_rate", gname = "cohort_cs",
                 idname = "state", tname = "year",
                 data = as.data.frame(df7),
                 xformla = ~1, bstrap = FALSE,
                 control_group = "notyettreated",
                 est_method = "reg")
cs_es <- aggte(cs_out, type = "dynamic", bstrap = FALSE)
summary(cs_es)

cs_out <- att_gt(yname = "div_rate", gname = "cohort_cs",
                 idname = "state", tname = "year",
                 data = as.data.frame(df7),
                 control_group = "notyettreated",
                 xformla = ~1, bstrap = FALSE,cband = FALSE,
                 weightsname = "stpop", faster_mode = FALSE,
                 est_method = "reg")
cs_es <- aggte(cs_out, type = "dynamic", bstrap = FALSE)
summary(cs_es)






# After running att_gt with weights                                           
cs_out <- att_gt(yname = "div_rate", gname = "cohort_cs",                     
                 idname = "state", tname = "year",                            
                 data = as.data.frame(df7),                                   
                 xformla = ~1, bstrap = FALSE, cband = FALSE,
                 faster_mode = FALSE,
                 weightsname = "stpop",                                       
                 est_method = "reg")                                          
cs_es <- aggte(cs_out, type = "dynamic", bstrap = FALSE)
summary(cs_es)

