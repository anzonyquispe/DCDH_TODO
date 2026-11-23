********************************************************************************
* test_by_path.do  --  Stata side of the by_path cross-language test
*
* Runs every case in ../cases.csv and ../validation_cases.csv and writes
*   results/stata_results.csv      one row per (case, path, statistic)
*   results/stata_validation.csv   accepted / rejected for each invalid input
*   results/stata_meta.txt         which did_multiplegt_dyn.ado was used
*
* Two sources of numbers are exported for every case:
*   source = display : parsed from the log of the real by_path(#) call.
*                      Covers every path, but only at the displayed precision.
*   source = precise : full double precision. Stata does not store per-path
*                      results, but after by_path(k) the matrix mat_res_XX and
*                      e() hold the results of the LAST path estimated, i.e.
*                      the k-th most common path. Looping k = 1..# therefore
*                      recovers every path at full precision. Only done when
*                      stata_precise = 1 in cases.csv. A by_path(k) run counts
*                      for path k only if path k is the last path it printed.
*   source = enum    : every path the command enumerated (globals path_k_XX),
*                      including paths for which it printed no results.
*
* Usage (batch):
*   Windows : StataMP-64.exe /e do "tests_by_path/stata/test_by_path.do" "<path to tests_by_path>"
*   Mac/Lin : stata-mp -b do tests_by_path/stata/test_by_path.do "<path to tests_by_path>"
* The argument is optional when Stata is started from tests_by_path/ or
* tests_by_path/stata/.
*
* Which ado is tested: the env var DCDH_STATA_ADO_DIR (a folder containing
* did_multiplegt_dyn.ado). Default: ../did_multiplegt_dyn/Stata next to this
* repo. Set it to "installed" to use the version installed in Stata.
********************************************************************************

version 17
clear all
set more off
set linesize 255
set varabbrev off

args tb_arg

*------------------------------------------------------------------------------
* 0. Locate folders
*------------------------------------------------------------------------------
local tb ""
if `"`tb_arg'"' != "" local tb `"`tb_arg'"'
else if fileexists("`c(pwd)'/cases.csv") local tb "`c(pwd)'"
else if fileexists("`c(pwd)'/../cases.csv") local tb "`c(pwd)'/.."
if `"`tb'"' == "" | !fileexists(`"`tb'/cases.csv"') {
	di as error "Cannot find tests_by_path/cases.csv. Pass the tests_by_path folder as the first argument."
	exit 601
}
local proj  `"`tb'/.."'
local res   `"`tb'/results"'
local logs  `"`tb'/results/logs_stata"'
capture mkdir `"`res'"'
capture mkdir `"`logs'"'

*------------------------------------------------------------------------------
* 1. Select the did_multiplegt_dyn.ado under test
*------------------------------------------------------------------------------
local ado_dir : env DCDH_STATA_ADO_DIR
if `"`ado_dir'"' == "" local ado_dir `"`proj'/../did_multiplegt_dyn/Stata"'
if `"`ado_dir'"' != "installed" {
	if !fileexists(`"`ado_dir'/did_multiplegt_dyn.ado"') {
		di as error `"did_multiplegt_dyn.ado not found in `ado_dir'. Set DCDH_STATA_ADO_DIR or use "installed"."'
		exit 601
	}
	adopath ++ `"`ado_dir'"'
}
capture program drop did_multiplegt_dyn
discard
quietly findfile did_multiplegt_dyn.ado
local ado_used `"`r(fn)'"'
tempname fh_ado
local ado_version ""
file open `fh_ado' using `"`ado_used'"', read text
file read `fh_ado' line
while r(eof) == 0 {
	if ustrregexm(`"`macval(line)'"', "This version *: *(.*)$") {
		local ado_version = ustrregexs(1)
		continue, break
	}
	file read `fh_ado' line
}
file close `fh_ado'
di as text "Testing: `ado_used' (version `ado_version')"

tempname fm
file open `fm' using `"`res'/stata_meta.txt"', write text replace
file write `fm' "language=stata" _n
file write `fm' "stata_version=`c(stata_version)' `c(edition_real)'" _n
file write `fm' `"package_file=`ado_used'"' _n
file write `fm' "package_version=`ado_version'" _n
file write `fm' "run_at=`c(current_date)' `c(current_time)'" _n
file close `fm'

*------------------------------------------------------------------------------
* 2. Helper programs
*------------------------------------------------------------------------------

* Write one CSV row. Every field is optional so empty values are safe.
capture program drop _bp_write
program define _bp_write
	syntax , fh(string) case(string) [path(string) order(string) ngroups(string) ///
		row(string) est(string) se(string) lb(string) ub(string) n(string)     ///
		sw(string) source(string) status(string) msg(string)]
	local q = char(34)
	local msg = subinstr(`"`msg'"', `"""', "'", .)
	file write `fh' `"`case',`q'`path'`q',`order',`ngroups',`row',`est',`se',`lb',`ub',`n',`sw',`source',`status',`q'`msg'`q'"' _n
end

* Full-precision string of a number; empty when missing.
capture program drop _bp_num
program define _bp_num, rclass
	args x
	if missing(`x') return local s ""
	else return local s = strtrim(strofreal(`x', "%21.17g"))
end

* Parse the text log of one by_path run and write source=display rows.
* ngroups for each path label comes from the globals left by the command.
capture program drop _bp_parse_log
program define _bp_parse_log
	args logfile fh case npaths
	forvalues k = 1/`npaths' {
		local lab_`k' `"${path_`k'_XX}"'
		local ng_`k'  `"${num_g_path_`k'_XX}"'
	}
	tempname lf
	local path ""
	local order 0
	local ng ""
	file open `lf' using `"`logfile'"', read text
	file read `lf' line
	while r(eof) == 0 {
		if ustrregexm(`"`macval(line)'"', "^ *Path \((.*)\) *$") {
			local p = ustrregexs(1)
			if `"`p'"' != `"`path'"' {
				local path `"`p'"'
				local ++order
				local ng ""
				forvalues k = 1/`npaths' {
					if `"`lab_`k''"' == `"`path'"' local ng "`ng_`k''"
				}
			}
		}
		else if `"`path'"' != "" & ustrregexm(`"`macval(line)'"', "^ *(Effect_[0-9]+|Av_tot_eff|Placebo_[0-9]+) *\|(.*)$") {
			local rn = ustrregexs(1)
			local vals = ustrregexs(2)
			tokenize `"`vals'"'
			forvalues j = 1/6 {
				if `"``j''"' == "." local `j' ""
			}
			_bp_write, fh(`fh') case(`case') path(`path') order(`order') ngroups(`ng') ///
				row(`rn') est(`1') se(`2') lb(`3') ub(`4') n(`5') sw(`6') source(display) status(ok)
		}
		else if `"`path'"' != "" & ustrregexm(`"`macval(line)'"', "Test of joint nullity of the (effects|placebos) : p-value = *([^ ]+)") {
			local which = ustrregexs(1)
			local pv = ustrregexs(2)
			if "`pv'" == "." local pv ""
			local rn = cond("`which'" == "effects", "p_joint_effects", "p_joint_placebos")
			_bp_write, fh(`fh') case(`case') path(`path') order(`order') ngroups(`ng') ///
				row(`rn') est(`pv') source(display) status(ok)
		}
		file read `lf' line
	}
	file close `lf'
end

* Return in r(last) the label of the last "Path (...)" header printed in a log.
capture program drop _bp_last_path
program define _bp_last_path, rclass
	args logfile
	tempname lf
	local last ""
	file open `lf' using `"`logfile'"', read text
	file read `lf' line
	while r(eof) == 0 {
		if ustrregexm(`"`macval(line)'"', "^ *Path \((.*)\) *$") local last = ustrregexs(1)
		file read `lf' line
	}
	file close `lf'
	return local last `"`last'"'
end

* Write source=precise rows for the last path estimated by the latest run.
capture program drop _bp_write_precise
program define _bp_write_precise
	args fh case k
	local path `"${path_`k'_XX}"'
	local ng   `"${num_g_path_`k'_XX}"'
	tempname M
	matrix `M' = mat_res_XX
	local rnames : rownames `M'
	local r 0
	foreach rn of local rnames {
		local ++r
		forvalues j = 1/6 {
			_bp_num `M'[`r',`j']
			local v`j' "`r(s)'"
		}
		_bp_write, fh(`fh') case(`case') path(`path') order(`k') ngroups(`ng') row(`rn') ///
			est(`v1') se(`v2') lb(`v3') ub(`v4') n(`v5') sw(`v6') source(precise) status(ok)
	}
	foreach w in effects placebo {
		local rn = cond("`w'" == "effects", "p_joint_effects", "p_joint_placebos")
		if `"`e(p_joint`w')'"' != "" {
			_bp_num e(p_joint`w')
			_bp_write, fh(`fh') case(`case') path(`path') order(`k') ngroups(`ng') ///
				row(`rn') est(`r(s)') source(precise) status(ok)
		}
	}
end

* Clear everything a previous run could leave behind.
capture program drop _bp_reset
program define _bp_reset
	ereturn clear
	capture matrix drop mat_res_XX
	capture macro drop path_*_XX num_g_path_*_XX
end

*------------------------------------------------------------------------------
* 3. Estimation cases
*------------------------------------------------------------------------------
import delimited using `"`tb'/cases.csv"', varnames(1) stringcols(_all) clear bindquote(strict)
local ncases = _N
local fields case_id dataset outcome group time treatment effects placebo by_path ///
	controls weight cluster normalized switchers only_never_switchers stata_precise
forvalues i = 1/`ncases' {
	foreach f of local fields {
		local `f'_`i' = strtrim(`f'[`i'])
	}
}

tempname fh
file open `fh' using `"`res'/stata_results.csv"', write text replace
file write `fh' "case_id,path,path_order,n_groups,row,estimate,se,lb_ci,ub_ci,n,switchers,source,status,message" _n

local only : env DCDH_ONLY_CASES
forvalues i = 1/`ncases' {
	local case "`case_id_`i''"
	if `"`only'"' != "" & !`: list case in only' continue

	* option string shared by the display and precise runs
	local opts "effects(`effects_`i'') placebo(`placebo_`i'') graph_off"
	if "`controls_`i''"  != "" local opts "`opts' controls(`controls_`i'')"
	if "`weight_`i''"    != "" local opts "`opts' weight(`weight_`i'')"
	if "`cluster_`i''"   != "" local opts "`opts' cluster(`cluster_`i'')"
	if "`normalized_`i''" == "1" local opts "`opts' normalized"
	if "`switchers_`i''" != "" local opts "`opts' switchers(`switchers_`i'')"
	if "`only_never_switchers_`i''" == "1" local opts "`opts' only_never_switchers"
	local vars "`outcome_`i'' `group_`i'' `time_`i'' `treatment_`i''"

	di as text _n "{hline 80}" _n "CASE `case': did_multiplegt_dyn `vars', `opts' by_path(`by_path_`i'')" _n "{hline 80}"
	use `"`proj'/`dataset_`i''"', clear

	* --- display run: the real by_path(#) call, logged and parsed -----------
	_bp_reset
	local caselog `"`logs'/`case'.log"'
	capture log close _bp
	log using `"`caselog'"', text replace name(_bp)
	timer clear 1
	timer on 1
	capture noisily did_multiplegt_dyn `vars', `opts' by_path(`by_path_`i'')
	local rc = _rc
	timer off 1
	log close _bp
	quietly timer list 1
	local secs = r(t1)
	capture confirm matrix mat_res_XX
	if `rc' != 0 | _rc != 0 {
		_bp_write, fh(`fh') case(`case') source(display) status(case_error) msg(Stata rc=`rc'; no results)
		continue
	}
	local npaths 0
	while `"${path_`=`npaths'+1'_XX}"' != "" {
		local ++npaths
	}
	_bp_parse_log `"`caselog'"' `fh' `case' `npaths'
	* every path the command enumerated, printed or not (source = enum)
	forvalues k = 1/`npaths' {
		_bp_write, fh(`fh') case(`case') path(${path_`k'_XX}) order(`k') ///
			ngroups(${num_g_path_`k'_XX}) source(enum) status(ok)
	}
	di as text "  display run: `npaths' paths in `secs's"

	* --- precise runs: by_path(k) for k = 1..# -------------------------------
	if "`stata_precise_`i''" == "1" {
		capture confirm integer number `by_path_`i''
		if _rc == 0 {
			local klog `"`logs'/_precise_tmp.log"'
			forvalues k = 1/`by_path_`i'' {
				_bp_reset
				capture log close _bpk
				log using `"`klog'"', text replace name(_bpk)
				capture noisily did_multiplegt_dyn `vars', `opts' by_path(`k')
				local rc = _rc
				log close _bpk
				* mat_res_XX belongs to path k only if path k was the last one
				* printed; when path k produces no output the matrix still holds
				* the previous path's results.
				_bp_last_path `"`klog'"'
				local last `"`r(last)'"'
				capture confirm matrix mat_res_XX
				if `rc' != 0 | _rc != 0 | `"`last'"' != `"${path_`k'_XX}"' {
					_bp_write, fh(`fh') case(`case') path(${path_`k'_XX}) order(`k') source(precise) ///
						status(path_error) msg(by_path(`k') printed no results for this path; rc=`rc')
					continue
				}
				_bp_write_precise `fh' `case' `k'
			}
			capture erase `"`klog'"'
			di as text "  precise runs: done for k = 1..`by_path_`i''"
		}
	}
}
file close `fh'

*------------------------------------------------------------------------------
* 4. Input validation cases
*------------------------------------------------------------------------------
import delimited using `"`tb'/validation_cases.csv"', varnames(1) stringcols(_all) clear bindquote(strict)
local nval = _N
forvalues i = 1/`nval' {
	foreach f in vcase_id by_path with_by {
		local v`f'_`i' = strtrim(`f'[`i'])
	}
}
tempname fv
file open `fv' using `"`res'/stata_validation.csv"', write text replace
file write `fv' "vcase_id,outcome,message" _n
use `"`proj'/_data/wagepan.dta"', clear
forvalues i = 1/`nval' {
	local extra ""
	if "`vwith_by_`i''" == "1" local extra "by(black)"
	_bp_reset
	capture noisily did_multiplegt_dyn lwage nr year union, effects(2) placebo(0) graph_off by_path(`vby_path_`i'') `extra'
	local rc = _rc
	capture confirm matrix mat_res_XX
	local has_res = (_rc == 0)
	* Stata's input checks print an error and call -exit- with rc 0, so
	* "rejected" means: an error code OR no results were produced.
	local outcome = cond(`rc' == 0 & `has_res', "accepted", "rejected")
	file write `fv' "`vvcase_id_`i'',`outcome',rc=`rc' results=`has_res'" _n
	di as text "VALIDATION `vvcase_id_`i'' by_path(`vby_path_`i'') `extra' -> `outcome'"
}
file close `fv'

* marker read by run_all.sh (Stata batch mode always exits with status 0)
file open `fm' using `"`res'/stata_meta.txt"', write text append
file write `fm' "finished_at=`c(current_date)' `c(current_time)'" _n
file close `fm'
di as text _n "Stata by_path tests finished. Results in `res'"
