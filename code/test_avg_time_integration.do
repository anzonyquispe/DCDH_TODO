***** Integration test: avg_time_periods option in did_multiplegt_dyn_reset *****
***** Compares avg_cumul_XX from the integrated option vs standalone          *****
***** avg_cumul_periods. Both should return the same value (within 1e-6).     *****

clear all
set more off
cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
capture log close
log using "logfiles/test_avg_time_integration.log", replace text
di as text "================================================================"
di as text "  test_avg_time_integration.do  started: $S_DATE $S_TIME"
di as text "================================================================"

qui do "code/avg_cumul_periods_func.do"

********************************************************************************
* Helper: write one row to the comparison CSV
********************************************************************************
capture program drop _write_csv_row
program _write_csv_row
	syntax, scenario(string) integrated(real) standalone(real) csvfile(string)
	local diff     = `integrated' - `standalone'
	local abs_diff = abs(`diff')
	local pass     = cond(`abs_diff' < 1e-6, "PASS", "FAIL")
	file open _fh using "`csvfile'", write append
	file write _fh "`scenario',`integrated',`standalone',`diff',`pass'" _n
	file close _fh
end

* Initialise CSV
local csvfile "logfiles/avg_time_integration_results.csv"
capture erase "`csvfile'"
file open _fh using "`csvfile'", write replace
file write _fh "scenario,integrated,standalone,diff,pass" _n
file close _fh

* Initialise result locals to missing so the CSV still gets a row on failure
foreach s in s1 s2 s3 s4 s5 {
	local integrated_`s' .
	local standalone_`s'  .
}


********************************************************************************
* SCENARIO 1 — Gentzkowetal balanced, effects(4), no reset
********************************************************************************
di as text _newline "{hline 72}"
di as text "SCENARIO 1: gentzkowetal_balanced  effects(4)  no reset"
di as text "{hline 72}"

* --- integrated ---
use "_data/gentzkowetal_didtextbook_balanced.dta", clear
qui do "code/did_multiplegt_dyn_reset.do"

capture noisily {
	did_multiplegt_dyn prestout cnty90 year numdailies, ///
		effects(4) graph_off avg_time_periods
}
if _rc {
	di as error "SCENARIO 1 (integrated): command failed with rc = " _rc
}
else {
	local integrated_s1 = scalar(avg_cumul_XX)
	di as result "  >> integrated avg_cumul_XX = " `integrated_s1'
}

* --- standalone ---
use "_data/gentzkowetal_didtextbook_balanced.dta", clear

capture noisily {
	avg_cumul_periods cnty90 year numdailies, effects(4) outcome(prestout)
}
if _rc {
	di as error "SCENARIO 1 (standalone): command failed with rc = " _rc
}
else {
	local standalone_s1 = r(avg)
	di as result "  >> standalone  r(avg)       = " `standalone_s1'
}

di as text "  >> difference = " `integrated_s1' - `standalone_s1'
_write_csv_row, scenario("gentzkowetal_eff4_noreset") ///
	integrated(`integrated_s1') standalone(`standalone_s1') csvfile("`csvfile'")


********************************************************************************
* SCENARIO 2 — Gentzkowetal balanced, effects(4), drop_if_d_miss
********************************************************************************
di as text _newline "{hline 72}"
di as text "SCENARIO 2: gentzkowetal_balanced  effects(4)  drop_if_d_miss"
di as text "{hline 72}"

use "_data/gentzkowetal_didtextbook_balanced.dta", clear
qui do "code/did_multiplegt_dyn_reset.do"

capture noisily {
	did_multiplegt_dyn prestout cnty90 year numdailies, ///
		effects(4) graph_off avg_time_periods drop_if_d_miss_before_first_switch
}
if _rc {
	di as error "SCENARIO 2 (integrated): command failed with rc = " _rc
}
else {
	local integrated_s2 = scalar(avg_cumul_XX)
	di as result "  >> integrated avg_cumul_XX = " `integrated_s2'
}

use "_data/gentzkowetal_didtextbook_balanced.dta", clear

capture noisily {
	avg_cumul_periods cnty90 year numdailies, effects(4) outcome(prestout) ///
		drop_if_d_miss_before_first_switch
}
if _rc {
	di as error "SCENARIO 2 (standalone): command failed with rc = " _rc
}
else {
	local standalone_s2 = r(avg)
	di as result "  >> standalone  r(avg)       = " `standalone_s2'
}

di as text "  >> difference = " `integrated_s2' - `standalone_s2'
_write_csv_row, scenario("gentzkowetal_eff4_dropmiss") ///
	integrated(`integrated_s2') standalone(`standalone_s2') csvfile("`csvfile'")


********************************************************************************
* SCENARIO 3 — Gentzkowetal balanced, effects(4), reset(1)
* Standalone: apply reset transformation manually then call avg_cumul_periods
********************************************************************************
di as text _newline "{hline 72}"
di as text "SCENARIO 3: gentzkowetal_balanced  effects(4)  reset(1)"
di as text "{hline 72}"

use "_data/gentzkowetal_didtextbook_balanced.dta", clear
qui do "code/did_multiplegt_dyn_reset.do"

capture noisily {
	did_multiplegt_dyn prestout cnty90 year numdailies, ///
		effects(4) graph_off reset(1) avg_time_periods
}
if _rc {
	di as error "SCENARIO 3 (integrated): command failed with rc = " _rc
}
else {
	local integrated_s3 = scalar(avg_cumul_XX)
	di as result "  >> integrated avg_cumul_XX = " `integrated_s3'
}

use "_data/gentzkowetal_didtextbook_balanced.dta", clear
qui do "code/reset_groups_function.do"

capture noisily {
	reset_groups cnty90 year numdailies, reset(1) replace_group
	avg_cumul_periods cnty90 year numdailies, effects(4) outcome(prestout)
}
if _rc {
	di as error "SCENARIO 3 (standalone): command failed with rc = " _rc
}
else {
	local standalone_s3 = r(avg)
	di as result "  >> standalone  r(avg)       = " `standalone_s3'
}

di as text "  >> difference = " `integrated_s3' - `standalone_s3'
_write_csv_row, scenario("gentzkowetal_eff4_reset1") ///
	integrated(`integrated_s3') standalone(`standalone_s3') csvfile("`csvfile'")


********************************************************************************
* Build fake dataset (used in scenarios 4 & 5)
********************************************************************************
di as text _newline "--- Building fake dataset ---"

clear
input group_XX time_XX treatment_XX
1 1 0
1 2 0
1 3 0
1 4 1
1 5 1
1 6 0
1 7 0
1 8 0
1 9 1
1 10 1
1 11 1
1 12 1
1 13 0
2 1 0
2 2 1
2 3 1
2 4 1
2 5 2
2 6 2
2 7 2
2 8 3
2 9 3
2 10 3
2 11 3
2 12 2
2 13 2
3 1 0
3 2 4
3 3 4
3 4 5
3 5 5
3 6 5
3 7 5
3 8 2
3 9 2
3 10 2
3 11 1
3 12 1
3 13 1
4 1 0
4 2 0
4 3 3
4 4 4
4 5 5
4 6 6
4 7 7
4 8 8
4 9 9
4 10 10
4 11 11
4 12 12
4 13 13
5 1 20
5 2 20
5 3 20
5 4 19
5 5 18
5 6 17
5 7 16
5 8 15
5 9 14
5 10 13
5 11 12
5 12 11
5 13 10
end

set seed 12345
xtset group_XX time_XX
bysort group_XX (time_XX): gen u_g = rnormal(0, 2) if _n == 1
bysort group_XX (time_XX): replace u_g = u_g[1]
bysort time_XX (group_XX): gen f_t = rnormal(0, 1) if _n == 1
bysort time_XX (group_XX): replace f_t = f_t[1]
gen eps = rnormal(0, 1)
gen Y_XX = u_g + f_t + 1.5*treatment_XX + eps
drop u_g f_t eps
rename group_XX g
rename time_XX t
rename treatment_XX d

tempfile fake_data
save "`fake_data'"
di as text "--- Fake dataset saved to tempfile ---"


********************************************************************************
* SCENARIO 4 — Fake data, effects(4)
********************************************************************************
di as text _newline "{hline 72}"
di as text "SCENARIO 4: fake data  effects(4)"
di as text "{hline 72}"

use "`fake_data'", clear
qui do "code/did_multiplegt_dyn_reset.do"

capture noisily {
	did_multiplegt_dyn Y_XX g t d, effects(4) graph_off avg_time_periods
}
if _rc {
	di as error "SCENARIO 4 (integrated): command failed with rc = " _rc
}
else {
	local integrated_s4 = scalar(avg_cumul_XX)
	di as result "  >> integrated avg_cumul_XX = " `integrated_s4'
}

use "`fake_data'", clear

capture noisily {
	avg_cumul_periods g t d, effects(4) outcome(Y_XX) ///
		drop_if_d_miss_before_first_switch
}
if _rc {
	di as error "SCENARIO 4 (standalone): command failed with rc = " _rc
}
else {
	local standalone_s4 = r(avg)
	di as result "  >> standalone  r(avg)       = " `standalone_s4'
}

di as text "  >> difference = " `integrated_s4' - `standalone_s4'
_write_csv_row, scenario("fakedata_eff4") ///
	integrated(`integrated_s4') standalone(`standalone_s4') csvfile("`csvfile'")


********************************************************************************
* SCENARIO 5 — Fake data, effects(1)
********************************************************************************
di as text _newline "{hline 72}"
di as text "SCENARIO 5: fake data  effects(1)"
di as text "{hline 72}"

use "`fake_data'", clear
qui do "code/did_multiplegt_dyn_reset.do"

capture noisily {
	did_multiplegt_dyn Y_XX g t d, effects(1) graph_off avg_time_periods
}
if _rc {
	di as error "SCENARIO 5 (integrated): command failed with rc = " _rc
}
else {
	local integrated_s5 = scalar(avg_cumul_XX)
	di as result "  >> integrated avg_cumul_XX = " `integrated_s5'
}

use "`fake_data'", clear

capture noisily {
	avg_cumul_periods g t d, effects(1) outcome(Y_XX) ///
		drop_if_d_miss_before_first_switch
}
if _rc {
	di as error "SCENARIO 5 (standalone): command failed with rc = " _rc
}
else {
	local standalone_s5 = r(avg)
	di as result "  >> standalone  r(avg)       = " `standalone_s5'
}

di as text "  >> difference = " `integrated_s5' - `standalone_s5'
_write_csv_row, scenario("fakedata_eff1") ///
	integrated(`integrated_s5') standalone(`standalone_s5') csvfile("`csvfile'")


********************************************************************************
* Final summary printed to log
********************************************************************************
di as text _newline "{hline 72}"
di as text "SUMMARY — all scenarios"
di as text "{hline 72}"
di as text %40s "Scenario" "  Integrated   Standalone        Diff"
di as text "{hline 72}"

foreach s_label in ///
	"gentzkowetal_eff4_noreset   " ///
	"gentzkowetal_eff4_dropmiss  " ///
	"gentzkowetal_eff4_reset1    " ///
	"fakedata_eff4               " ///
	"fakedata_eff1               " {
	local idx : word count `s_label'
}

local labels `" "S1 gentzkow noreset " "S2 gentzkow dropmiss" "S3 gentzkow reset1  " "S4 fakedata eff4    " "S5 fakedata eff1    " "'
local ints   `integrated_s1'   `integrated_s2'   `integrated_s3'   `integrated_s4'   `integrated_s5'
local stans  `standalone_s1'   `standalone_s2'   `standalone_s3'   `standalone_s4'   `standalone_s5'

local n_pass 0
local n_fail 0
forvalues k = 1/5 {
	local lbl  : word `k' of `labels'
	local intv : word `k' of `ints'
	local stav : word `k' of `stans'
	if missing(`intv') | missing(`stav') {
		di as text "`lbl'   (missing — see error above)"
		local ++n_fail
	}
	else {
		local d = `intv' - `stav'
		local status = cond(abs(`d') < 1e-6, "PASS", "FAIL")
		di as text "`lbl'  " %12.7g `intv' "  " %12.7g `stav' "  " %12.3e `d' "  `status'"
		if "`status'" == "PASS" local ++n_pass
		else                    local ++n_fail
	}
}

di as text "{hline 72}"
di as text "  PASS: `n_pass' / 5     FAIL: `n_fail' / 5"
di as text "{hline 72}"

di as text "CSV written to: `csvfile'"
di as text "================================================================"
di as text "  test_avg_time_integration.do  finished: $S_DATE $S_TIME"
di as text "================================================================"
log close
