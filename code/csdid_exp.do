* ssc install did_imputation, replace
copy "https://raw.githubusercontent.com/anzonyquispe/did_book/main/cc_xd_didtextbook_2025_9_30/Data%20sets/Wolfers%202006/wolfers2006_didtextbook.dta" "wolfers2006_didtextbook.dta", replace
use "wolfers2006_didtextbook.dta", clear
replace cohort = . if cohort == 0
did_imputation div_rate state year cohort [aweight=stpop], horizons(0/12) autosample minn(0) pre(13)

did_imputation div_rate state year cohort, horizons(0/12) autosample minn(0) pre(13)



copy "https://raw.githubusercontent.com/anzonyquispe/did_book/main/cc_xd_didtextbook_2025_9_30/Data%20sets/Wolfers%202006/wolfers2006_didtextbook.dta" "wolfers2006_didtextbook.dta", replace
* Restore and drop unbalanced states
use "wolfers2006_didtextbook.dta", clear
replace cohort = 0 if cohort == .
misstable summarize stpop state year cohort
gen row_missing = missing(stpop) | missing(state) | missing(year) | missing(cohort) | missing(div_rate)
bysort state: egen has_missing = max(row_missing)
drop if has_missing
drop row_missing has_missing

* Drop states not observed in ALL years
quietly levelsof year, local(all_years)
local T : word count `all_years'

bysort state year: gen dup = (_n == 1)
bysort state: egen n_unique_years = total(dup)
drop dup
drop if n_unique_years != `T'
drop n_unique_years

* Also drop always-treated states (cohort == first year in data)
quietly summarize year
drop if cohort == r(min)

* Confirm balance
bysort state: gen n_check = _N
quietly summarize n_check
assert r(min) == r(max)
di "Panel is now balanced: all remaining states have " r(max) " observations"
drop n_check

* Run csdid
* Normalize stpop to sum to 1 (mimics R's internal normalization)
bysort year: egen total_pop = total(stpop)
gen stpop_norm = stpop / total_pop

* Run csdid with normalized weights
csdid div_rate, ivar(state) time(year) gvar(cohort) notyet agg(event) asinr
csdid div_rate [weight=stpop], asinr ivar(state) time(year) gvar(cohort) notyet agg(event) asinr


bysort year: egen total_wgt = total(stpop)                                    
egen overall_mean_wgt = mean(stpop)                                           
gen stpop_r_norm = stpop / overall_mean_wgt   // R-style normalization        
																			
* Run csdid with R-style normalized weights                   
csdid div_rate [weight=stpop], ivar(state) time(year) gvar(cohort) agg(event) method(reg)  asinr
