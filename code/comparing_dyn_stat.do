cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
capture log close
log using "code/did_multiplegt_stat_vs_dyn.log", replace text

//testing with _stat
do "code/did_multiplegt_stat-working-version.ado"
// ssc install did_multiplegt_stat


use "_data/gentzkowetal_didtextbook.dta", clear
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


did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) save_results("_data/gentzkow_reset1_norm_option.dta") reset(1) normalized

// Stat result
capture did_multiplegt_stat prestout cnty90 year numdailies if lag_fd == 0, exact_match

did_multiplegt_stat prestout cnty90 year numdailies if lag_fd == 0, exact_match

log close
