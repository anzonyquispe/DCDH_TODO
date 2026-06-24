clear all
set more off
cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
capture log close
log using "logfiles/final_test_avgtime.log", replace text
di as text "=== final_test_avgtime.do  started: $S_DATE $S_TIME ==="

//testing with _stat
qui do "code/did_multiplegt_stat-working-version.ado"
qui do "code/reset_groups_function.do"
qui do "code/avg_cumul_periods_func.do"

// ssc install did_multiplegt_stat

use "_data/gentzkowetal_didtextbook.dta", clear
xtset cnty90 year
gen treatment_XX = numdailies
gen group_XX = cnty90
gen count_d_non_miss_temp_XX=(treatment_XX!=.)
tab count_d_non_miss_temp_XX
bys group_XX: gegen count_d_non_miss_XX=sum(count_d_non_miss_temp_XX)
sum count_d_non_miss_XX
drop if count_d_non_miss_XX<r(max)
xtset cnty90 year
gen fd_treat = numdailies - L4.numdailies
gen lag_fd = L4.fd_treat
save "_data/gentzkowetal_didtextbook_balanced.dta", replace


use "_data/gentzkowetal_didtextbook_balanced.dta", clear
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4)  cluster(cnty90)  graph_off
avg_cumul_periods cnty90 year numdailies, effects(4)
reset_groups cnty90 year numdailies , reset(1) replace_group
avg_cumul_periods cnty90 year numdailies, effects(4)  outcome(prestout) 
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4)   cluster(cnty90)  graph_off


use "_data/gentzkowetal_didtextbook_balanced.dta", clear
qui do "code/did_multiplegt_dyn_reset.do"
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) save_results("_data/gentzkow_reset1_norm_option.dta") reset(1) normalized graph_off

di as text "=== final_test_avgtime.do  finished: $S_DATE $S_TIME ==="
log close
