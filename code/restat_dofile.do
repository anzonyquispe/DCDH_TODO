cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
capture log close
log using "code/did_multiplegt_comparison.log", replace text

//testing with _stat
do "code/did_multiplegt_stat-working-version.ado"
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






// Original result with the original adofile and dataset
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90)


do "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO/code/did_multiplegt_dyn_reset.do"

did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) normalized
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) save_results("_data/gentzkow_reset1_norm_option.dta") reset(1) normalized


// running the new adofile 
// fill data first
// drop if panel is not complete
do "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO/code/did_multiplegt_dyn_reset.do"
* flag missing observations -- we do not have any missing information
gen byte miss_flag = missing(numdailies)

* count missings within each county across all years
bysort cnty90: egen total_miss = total(miss_flag)

* keep only counties with zero missings in any year
keep if total_miss == 0

// Original result with the original adofile and dataset
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) save_results("_data/gentzkow_noreset_option.dta")

// Reset 4
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) save_results("_data/gentzkow_reset4_option.dta") reset(4)

// Reset 1
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) save_results("_data/gentzkow_reset1_option.dta") reset(1)

// Normalized option of effect 1
did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) save_results("_data/gentzkow_reset1_norm_option.dta") reset(1) normalized





did_multiplegt_dyn prestout cnty90 year numdailies, effects(4) placebo(4) effects_equal(all) cluster(cnty90) save_results("_data/gentzkow_reset1_norm_option.dta") reset(1) normalized

// Stat result
capture did_multiplegt_stat prestout cnty90 year numdailies if lag_fd == 0, exact_match



* pull the coefficient vector and variance-covariance matrix
matrix b = e(b)
matrix V = e(V)

* number of coefficients
local k = colsof(b)

* get the coefficient names from the column names of e(b)
local names : colnames b

* build a results matrix: estimate in col 1, se in col 2
matrix results = J(`k', 2, .)
forvalues i = 1/`k' {
    matrix results[`i', 1] = b[1, `i']              // estimate
    matrix results[`i', 2] = sqrt(V[`i', `i'])      // se = sqrt of diagonal
}
matrix colnames results = estimate se

* turn the matrix into a dataset
clear
svmat results, names(col)

* add the coefficient names as a string column
gen str coef = ""
local i = 1
foreach nm of local names {
    replace coef = "`nm'" in `i'
    local ++i
}

* reorder so coef is first
order coef estimate se

list, clean
save "_data/gentzkow_stat_option.dta", replace



* ---- close log ----
log close
