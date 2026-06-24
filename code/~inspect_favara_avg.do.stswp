***** Manual inspection: did_multiplegt_dyn quirk on continuous-treated data *****
*
* CONTEXT
* The favara_imbs dataset has TWO candidate "treatment" variables:
*   - inter_bra    : binary 0/1   (the actual treatment in the original paper)
*   - Dl_vloans_b  : continuous   (loan-growth, was being used incorrectly)
*
* When we (mistakenly) ran did_multiplegt_dyn with d = Dl_vloans_b it produced:
*   Effect_1 : N_switchers = 1
*   Effect_2 : N_switchers = 1
* and avg_cumul_periods returned 0 switchers for every effect.
*
* GOAL of this dofile
*   Find out why did_multiplegt_dyn is able to identify 1 switcher per effect
*   when the treatment is continuous and (presumably) almost every group
*   "switches" every period. The result feels wrong; we want to know whether:
*     (a) did_multiplegt_dyn is silently coarsening Dl_vloans_b somehow
*     (b) there is exactly one group whose period-1 value matches the most
*         common value, and only that single group qualifies as a switcher
*     (c) something deeper in the package's internal cleaning is responsible
*
* Run interactively:   do code/inspect_favara_avg.do
* Or in batch:         stata-se -b do code/inspect_favara_avg.do
* Log:                 logfiles/inspect_favara_avg.log

clear all
set more off
cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
capture log close
log using "logfiles/inspect_favara_avg.log", replace text
di as text "=== inspect_favara_avg  started: $S_DATE $S_TIME ==="

qui do "code/avg_cumul_periods_func.do"


********************************************************************************
* PART A — Variable basics
********************************************************************************
di as text _newline "{hline 78}"
di as text "PART A — favara_imbs : describe both candidate treatments"
di as text "{hline 78}"

use "_data/favara_imbs.dta", clear

describe county year inter_bra Dl_vloans_b Dl_hpi
xtset county year

di as text _newline "inter_bra (binary) distribution:"
tab inter_bra, missing

di as text _newline "Dl_vloans_b (continuous) summary:"
sum Dl_vloans_b, detail

di as text _newline "How many DISTINCT Dl_vloans_b values per group?"
preserve
bys county Dl_vloans_b: keep if _n == 1
bys county: gen byte _one = 1
bys county: egen long _nvals = total(_one)
bys county: keep if _n == 1
tab _nvals
sum _nvals, detail
restore


********************************************************************************
* PART B — Reproduce: did_multiplegt_dyn with d = Dl_vloans_b finds 1 switcher
********************************************************************************
di as text _newline "{hline 78}"
di as text "PART B — re-run with the WRONG treatment (Dl_vloans_b)"
di as text "{hline 78}"

use "_data/favara_imbs.dta", clear

cap program drop did_multiplegt_dyn
capture noisily did_multiplegt_dyn Dl_hpi county year Dl_vloans_b, ///
    effects(5) graph_off
di as text _newline "  rc = " _rc
forvalues k = 1/5 {
    di as text "  e(N_switchers_effect_`k') = " e(N_switchers_effect_`k')
}


********************************************************************************
* PART C — Reconstruct DCDH's switcher logic by hand
*
* DCDH definition: a "switcher" at horizon ell is a group whose treatment at
* time F_g + ell - 1 differs from its period-1 value, where F_g is the first
* time the group's treatment changes. We re-create F_g, D_{g,1}, and check how
* many groups actually qualify.
********************************************************************************
di as text _newline "{hline 78}"
di as text "PART C — manual reconstruction of F_g and switcher count"
di as text "{hline 78}"

use "_data/favara_imbs.dta", clear

qui sum year, meanonly
local t_min = r(min)
di as text "First period t_min = `t_min'"

* Period-1 treatment per group (Dg1)
gen double _d_t1 = Dl_vloans_b if year == `t_min'
bys county: egen double Dg1 = max(_d_t1)
drop _d_t1

* First time the treatment differs from Dg1
gen byte _changed = (Dl_vloans_b != Dg1) & !missing(Dl_vloans_b) & !missing(Dg1)
bys county: egen double Fg = min(cond(_changed, year, .))
drop _changed

di as text _newline "Distribution of Fg (one obs per group):"
preserve
bys county: keep if _n == 1
tab Fg, missing
di as text "  -> Fg = . means group never switched"
di as text "  -> A unique Fg per group is needed to be a 'switcher' candidate"

count if !missing(Fg)
di as text "  Groups with Fg != . : " r(N)
count if missing(Fg)
di as text "  Groups with Fg == . : " r(N)
restore

* Treatment value at the period of the switch (Dg_at_Fg)
gen double _dF = Dl_vloans_b if year == Fg
bys county: egen double Dg_at_Fg = max(_dF)
drop _dF

* Number of groups whose treatment at F_g is strictly above Dg1 ("up" switchers)
* vs strictly below ("down" switchers)
preserve
bys county: keep if _n == 1
keep if !missing(Fg)
gen byte up   = (Dg_at_Fg > Dg1)
gen byte down = (Dg_at_Fg < Dg1)
gen byte eq   = (Dg_at_Fg == Dg1)
di as text _newline "Among groups with Fg != . :"
tab up
tab down
tab eq
restore


********************************************************************************
* PART D — Hypothesis check: is did_multiplegt_dyn coarsening Dl_vloans_b?
*
* If the package internally rounds the treatment to e.g. zero / non-zero, the
* count of "switchers" would collapse to a tiny number — possibly 1.
********************************************************************************
di as text _newline "{hline 78}"
di as text "PART D — does Dl_vloans_b == 0 collapse the switcher set?"
di as text "{hline 78}"

use "_data/favara_imbs.dta", clear

di as text "How many obs have Dl_vloans_b exactly == 0?"
count if Dl_vloans_b == 0
di as text "  count = " r(N)

di as text _newline "Period-1 values that are exactly 0 (per group):"
gen double _d1 = Dl_vloans_b if year == 1994
bys county: egen double Dg1 = max(_d1)
preserve
bys county: keep if _n == 1
count if Dg1 == 0
di as text "  groups with Dg1 == 0 : " r(N)
count if Dg1 != 0
di as text "  groups with Dg1 != 0 : " r(N)
restore


********************************************************************************
* PART E — Now try with the CORRECT treatment (inter_bra) for sanity
********************************************************************************
di as text _newline "{hline 78}"
di as text "PART E — same data with d = inter_bra (binary, correct)"
di as text "{hline 78}"

use "_data/favara_imbs.dta", clear
cap program drop did_multiplegt_dyn
capture noisily did_multiplegt_dyn Dl_hpi county year inter_bra, ///
    effects(5) graph_off
di as text _newline "  rc = " _rc
forvalues k = 1/5 {
    di as text "  e(N_switchers_effect_`k') = " e(N_switchers_effect_`k')
}

* And the avg_cumul_periods equivalent
capture noisily avg_cumul_periods county year inter_bra, effects(5) outcome(Dl_hpi)
di as text _newline "  avg_cumul_periods rc = " _rc
forvalues k = 1/5 {
    di as text "  r(N_switch_`k') = " r(N_switch_`k')
}


di as text _newline "=== inspect_favara_avg  finished: $S_DATE $S_TIME ==="
log close
