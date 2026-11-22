********************************************************************************
* manual_bootstrap.do -- Stata reference for R's bootstrap standard errors
*
* For every row of bootstrap_specs.csv with stata_manual = 1:
*   1. runs the base spec without bootstrap (Stata's point estimates);
*   2. for every resample R saved in <results>/samples/<bid>/rep_*.csv
*      (columns unit_id, count: how many times each cluster -- or group when
*      there is no cluster() -- was drawn) rebuilds the resampled data set:
*      every row of a drawn unit is duplicated "count" times and each copy
*      becomes its own group (and cluster), then runs the analytic estimator;
*   3. the bootstrap SE is the standard deviation (n-1) of those estimates;
*   4. also runs Stata's own bootstrap(reps, seed), for a plausibility check.
* Writes <results>/stata_manual.csv and <results>/stata_meta.txt.
*
* Usage: StataMP-64.exe /e do manual_bootstrap.do "<suite folder>" "<results folder>"
* Env:   DCDH_STATA_ADO (REQUIRED, as for Stata/run_specs.do), DCDH_ONLY (bids)
********************************************************************************
version 17
clear all
set more off
set linesize 255
set varabbrev off
args suite res

local data `"`suite'/data"'
capture mkdir `"`res'"'

* ---- which ado (never defaulted) -------------------------------------------
local ado : env DCDH_STATA_ADO
if `"`ado'"' == "" {
	di as error "DCDH_STATA_ADO is not set (a did_multiplegt_dyn.ado file, its folder, or installed)."
	exit 198
}
if `"`ado'"' != "installed" {
	local ado = subinstr(`"`ado'"', "\", "/", .)
	if ustrregexm(`"`ado'"', "\.ado$") local ado = ustrregexrf(`"`ado'"', "/[^/]+$", "")
	adopath ++ `"`ado'"'
}
capture program drop did_multiplegt_dyn
discard
quietly findfile did_multiplegt_dyn.ado
local ado_used `"`r(fn)'"'
tempname fm
file open `fm' using `"`res'/stata_meta.txt"', write text replace
file write `fm' `"package_source=`ado_used'"' _n
file write `fm' "started_at=`c(current_date)' `c(current_time)'" _n
file close `fm'

* ---- data preparation: same as Stata/run_specs.do -------------------------
capture program drop _prep
program define _prep
	args p
	if "`p'" == "" exit
	if "`p'" == "deryugina_year_controls" {
		foreach v in coastal land_area1970 log_pop1969 frac_young1969 frac_old1969 frac_black1969 log_wage_pc1969 emp_rate1969 {
			quietly gen double `v'_year = `v' * year
		}
	}
	else if "`p'" == "gentzkow_t11" quietly keep if year <= first_change | same_treat_after_first_change == 1
	else if "`p'" == "gentzkow_ch08" quietly keep if year < first_change | same_treat_after_first_change == 1
	else if "`p'" == "hollingsworth_t13" quietly keep if rm == 0
	else if "`p'" == "hollingsworth_t14" {
		quietly egen double fg1 = min(cond(mm == 1, year, .)), by(state)
		quietly keep if mm == 1
	}
	else exit 198
end

* the estimates of one run, as locals in r(): names and values
capture program drop _grab
program define _grab, rclass
	local names ""
	local sc : e(scalars)
	foreach s of local sc {
		if ustrregexm("`s'", "^(Effect_[0-9]+|Placebo_[0-9]+|Av_tot_effect)$") {
			local names "`names' `s'"
			return scalar `s' = e(`s')
		}
		if ustrregexm("`s'", "^(se_effect_[0-9]+|se_placebo_[0-9]+|se_avg_total_effect|N_effect_[0-9]+|N_placebo_[0-9]+|N_avg_total_effect|N_switchers_effect_[0-9]+|N_switchers_placebo_[0-9]+|N_switchers_effect_average)$") {
			return scalar `s' = e(`s')
		}
	}
	return local names "`names'"
end

* ---- specs ------------------------------------------------------------------
import delimited using `"`suite'/specs/specs.csv"', varnames(1) stringcols(_all) clear bindquote(strict) encoding(utf8)
local ns = _N
forvalues i = 1/`ns' {
	local sid = strtrim(spec_id[`i'])
	foreach f in dataset outcome group time treatment prep options {
		local `f'_`sid' = strtrim(`f'[`i'])
	}
}
import delimited using `"`suite'/R_bootstrap/bootstrap_specs.csv"', varnames(1) stringcols(_all) clear
keep if stata_manual == "1"
local nb = _N
forvalues i = 1/`nb' {
	local bid_`i' = bid[`i']
	local base_`i' = base_spec[`i']
	local reps_`i' = reps[`i']
	local sub_`i' = subsample[`i']
	local seed_`i' = seed[`i']
}

local only : env DCDH_ONLY
tempname fo
file open `fo' using `"`res'/stata_manual.csv"', write text replace
file write `fo' "bid,row,est_analytic,n_analytic,sw_analytic,se_analytic,se_manual,reps_used,se_stata_bootstrap,message" _n

forvalues i = 1/`nb' {
	local b "`bid_`i''"
	if `"`only'"' != "" & !`: list b in only' continue
	local s "`base_`i''"
	local opts `"`options_`s''"'
	local g "`group_`s''"
	local t "`time_`s''"
	local unitvar "`g'"
	local clust ""
	if ustrregexm(`"`opts'"', "cluster\(([^)]*)\)") {
		local clust = strtrim(ustrregexs(1))
		local unitvar "`clust'"
	}
	di as text _n "{hline 90}" _n "BOOTSTRAP `b' (`s'): `opts'   resampling unit: `unitvar'" _n "{hline 90}"

	use `"`data'/`dataset_`s''.dta"', clear
	_prep `prep_`s''
	if "`sub_`i''" == "groups_5pct" {
		* every 20th group in sorted-id order (same groups as in R)
		quietly egen long _grank = group(`g')
		quietly keep if mod(_grank - 1, 20) == 0
		drop _grank
	}
	tempfile prepped
	quietly save `prepped'

	* 1. analytic run
	capture noisily did_multiplegt_dyn `outcome_`s'' `g' `t' `treatment_`s'', `opts' graph_off
	if _rc | `"`e(cmd)'"' == "" {
		file write `fo' "`b',,,,,,,,,analytic run failed rc=`=_rc'" _n
		continue
	}
	_grab
	local names "`r(names)'"
	foreach n of local names {
		local a_`n' = r(`n')
		if "`n'" == "Av_tot_effect" {
			local an_`n' = r(N_avg_total_effect)
			local as_`n' = r(N_switchers_effect_average)
			local ase_`n' = r(se_avg_total_effect)
		}
		else {
			local k = ustrregexrf("`n'", "^[A-Za-z]+_", "")
			local w = cond(ustrregexm("`n'", "^Effect"), "effect", "placebo")
			local an_`n' = r(N_`w'_`k')
			local as_`n' = r(N_switchers_`w'_`k')
			local ase_`n' = r(se_`w'_`k')
		}
	}

	* 2. replay R's resamples
	local files : dir `"`res'/samples/`b'"' files "rep_*.csv"
	local files : list sort files
	tempname pf
	tempfile reps_est
	postfile `pf' str32 name double est using `reps_est', replace
	local used 0
	foreach f of local files {
		quietly import delimited using `"`res'/samples/`b'/`f'"', varnames(1) clear
		rename unit_id `unitvar'
		tempfile counts
		quietly save `counts'
		use `prepped', clear
		quietly merge m:1 `unitvar' using `counts', keep(match) nogenerate
		quietly expand count
		quietly bysort `g' `t': gen long _copy = _n
		quietly egen long _newg = group(`g' _copy)
		local o2 `"`opts'"'
		if "`clust'" != "" {
			quietly egen long _newc = group(`clust' _copy)
			local o2 = ustrregexra(`"`opts'"', "cluster\([^)]*\)", "cluster(_newc)")
		}
		capture did_multiplegt_dyn `outcome_`s'' _newg `t' `treatment_`s'', `o2' graph_off
		if _rc | `"`e(cmd)'"' == "" continue
		local ++used
		foreach n of local names {
			capture post `pf' ("`n'") (e(`n'))
		}
	}
	postclose `pf'

	* 3. SE = sd across replications
	use `reps_est', clear
	foreach n of local names {
		quietly summarize est if name == "`n'"
		local m_`n' = cond(r(N) > 1, r(sd), .)
	}

	* 4. Stata's own bootstrap (different random draws: plausibility only)
	use `prepped', clear
	capture noisily did_multiplegt_dyn `outcome_`s'' `g' `t' `treatment_`s'', `opts' bootstrap(`reps_`i'',`seed_`i'') graph_off
	local brc = _rc
	foreach n of local names {
		local sb ""
		if `brc' == 0 {
			if "`n'" == "Av_tot_effect" capture local sb = e(se_avg_total_effect)
			else {
				local k = ustrregexrf("`n'", "^[A-Za-z]+_", "")
				local w = cond(ustrregexm("`n'", "^Effect"), "effect", "placebo")
				capture local sb = e(se_`w'_`k')
			}
		}
		local row = cond("`n'" == "Av_tot_effect", "Av_tot_eff", "`n'")
		foreach v in a_`n' an_`n' as_`n' ase_`n' m_`n' sb {
			local x = ``v''
			local `v'_s = cond(missing(`x'), "", strtrim(strofreal(`x', "%21.17g")))
		}
		file write `fo' "`b',`row',`a_`n'_s',`an_`n'_s',`as_`n'_s',`ase_`n'_s',`m_`n'_s',`used',`sb_s'," _n
	}
	di as text "  `b': `used' replications replayed"
}
file close `fo'
file open `fm' using `"`res'/stata_meta.txt"', write text append
file write `fm' "finished_at=`c(current_date)' `c(current_time)'" _n
file close `fm'
