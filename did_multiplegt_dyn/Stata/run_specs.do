********************************************************************************
* run_specs.do  --  Stata side (the REFERENCE) of the did_multiplegt_dyn suite
*
* Runs every spec in ../specs/specs.csv and every input check in
* ../specs/validation.csv and writes, in <results>/stata/:
*   outputs.csv     one row per stored element:
*                     e() scalars, e() macros, e() matrices (every cell),
*                     the global matrices the command leaves behind
*                     (mat_res_XX, desmat, dfs#, mat_res_XX_by_<level>),
*                     r() scalars (recorded for information only)
*                   For by_path() and by() specs every path / level is a
*                   separate "unit". by_path paths are recovered at full
*                   precision by re-running by_path(k) for k = 1..#: after
*                   that call e() and mat_res_XX hold the k-th most common
*                   path. Every unit is also parsed from the log (display
*                   precision), so paths beyond the precise cap are covered.
*   status.csv      one row per spec (and per by_path(k) re-run)
*   validation.csv  accepted / rejected for each input check
*   meta.txt        which ado file was tested
*   logs/           one log per spec
*
* Usage (batch; normally called by ../run_tests.sh):
*   Windows : StataMP-64.exe /e do run_specs.do "<suite folder>" "<results folder>"
*   Mac/Lin : stata-mp -b do run_specs.do "<suite folder>" "<results folder>"
*
* Environment variables:
*   DCDH_STATA_ADO  REQUIRED. Path to did_multiplegt_dyn.ado (or the folder
*                   that contains it), or the word "installed" to use the
*                   version installed in Stata. There is no default.
*   DCDH_ONLY       space-separated spec ids to run (default: all)
*   DCDH_BLOCKS     space-separated blocks to run, e.g. "A F" (default: all)
*   DCDH_PRECISE_CAP max number of by_path(k) re-runs per spec (default 15)
********************************************************************************

version 17
clear all
set more off
set linesize 255
set varabbrev off

args suite_arg res_arg

*------------------------------------------------------------------------------
* 0. Folders
*------------------------------------------------------------------------------
local suite `"`suite_arg'"'
if `"`suite'"' == "" local suite "`c(pwd)'/.."
if !fileexists(`"`suite'/specs/specs.csv"') {
	di as error `"Cannot find specs/specs.csv under `suite'. Pass the suite folder as the first argument."'
	exit 601
}
local res `"`res_arg'"'
if `"`res'"' == "" local res `"`suite'/results"'
local out  `"`res'/stata"'
local logs `"`res'/stata/logs"'
capture mkdir `"`res'"'
capture mkdir `"`out'"'
capture mkdir `"`logs'"'
local data `"`suite'/data"'

*------------------------------------------------------------------------------
* 1. Which did_multiplegt_dyn.ado (asked of the user, never defaulted)
*------------------------------------------------------------------------------
local ado : env DCDH_STATA_ADO
if `"`ado'"' == "" {
	di as error "DCDH_STATA_ADO is not set. Say which did_multiplegt_dyn.ado to test (a file, a folder, or installed)."
	exit 198
}
if `"`ado'"' != "installed" {
	local ado = subinstr(`"`ado'"', "\", "/", .)
	if ustrregexm(`"`ado'"', "\.ado$") {
		local ado_dir = ustrregexrf(`"`ado'"', "/[^/]+$", "")
	}
	else local ado_dir `"`ado'"'
	if !fileexists(`"`ado_dir'/did_multiplegt_dyn.ado"') {
		di as error `"did_multiplegt_dyn.ado not found in `ado_dir'"'
		exit 601
	}
	adopath ++ `"`ado_dir'"'
}
capture program drop did_multiplegt_dyn
discard
quietly findfile did_multiplegt_dyn.ado
local ado_used `"`r(fn)'"'
local ado_version ""
tempname fa
file open `fa' using `"`ado_used'"', read text
file read `fa' line
while r(eof) == 0 {
	if ustrregexm(`"`macval(line)'"', "This version *: *(.*)$") {
		local ado_version = strtrim(ustrregexs(1))
		continue, break
	}
	file read `fa' line
}
file close `fa'
capture which gtools
local has_gtools = (_rc == 0)
di as text "Testing: `ado_used' (version `ado_version')"

tempname fm
file open `fm' using `"`out'/meta.txt"', write text replace
file write `fm' "language=stata" _n
file write `fm' "language_version=`c(stata_version)' `c(edition_real)'" _n
file write `fm' `"package_source=`ado_used'"' _n
file write `fm' "package_version=`ado_version'" _n
file write `fm' "gtools_installed=`has_gtools'" _n
file write `fm' "started_at=`c(current_date)' `c(current_time)'" _n
file close `fm'

*------------------------------------------------------------------------------
* 2. Helpers
*------------------------------------------------------------------------------
capture program drop _q
program define _q, rclass
	* CSV-safe quoted string
	local s = subinstr(`"`0'"', `"""', "'", .)
	return local s = char(34) + `"`s'"' + char(34)
end

capture program drop _num
program define _num, rclass
	args x
	if missing(`x') return local s ""
	else return local s = strtrim(strofreal(`x', "%21.17g"))
end

* one output row
capture program drop _w
program define _w
	syntax , fh(string) spec(string) [unit(string) kind(string) name(string) ///
		row(string) col(string) rowname(string) colname(string) value(string) prec(string)]
	foreach f in unit name rowname colname value {
		_q ``f''
		local `f' `"`r(s)'"'
	}
	file write `fh' `"`spec',`unit',`kind',`name',`row',`col',`rowname',`colname',`value',`prec'"' _n
end

* every cell of a matrix
capture program drop _wmat
program define _wmat
	args fh spec unit kind mname src
	tempname M
	capture matrix `M' = `src'
	if _rc exit
	tempname R C
	forvalues i = 1/`=rowsof(`M')' {
		matrix `R' = `M'[`i', 1...]
		local rr : rownames `R'
		forvalues j = 1/`=colsof(`M')' {
			matrix `C' = `M'[1..., `j']
			local cc : colnames `C'
			_num `M'[`i',`j']
			_w, fh(`fh') spec(`spec') unit(`unit') kind(`kind') name(`mname') row(`i') col(`j') ///
				rowname(`rr') colname(`cc') value(`r(s)') prec(full)
		}
	}
end

* dump e(), whitelisted global matrices and r() for one estimation unit
capture program drop _dump
program define _dump
	args fh spec unit
	local sc : e(scalars)
	foreach s of local sc {
		_num e(`s')
		_w, fh(`fh') spec(`spec') unit(`unit') kind(e_scalar) name(`s') value(`r(s)') prec(full)
	}
	local mc : e(macros)
	foreach m of local mc {
		_w, fh(`fh') spec(`spec') unit(`unit') kind(e_macro) name(`m') value(`"`e(`m')'"') prec(full)
	}
	local mt : e(matrices)
	foreach m of local mt {
		_wmat `fh' `spec' "`unit'" e_matrix `m' e(`m')
	}
	* global matrices left by the command
	local gm : all matrices
	foreach m of local gm {
		if "`m'" == "mat_res_XX" | "`m'" == "desmat" | ustrregexm("`m'", "^dfs[0-9]+$") {
			_wmat `fh' `spec' "`unit'" matrix `m' `m'
		}
	}
end

* r() scalars, for information only (r() is left over from internal commands)
capture program drop _dump_r
program define _dump_r
	args fh spec unit
	local rs : r(scalars)
	foreach s of local rs {
		_num r(`s')
		_w, fh(`fh') spec(`spec') unit(`unit') kind(r_scalar) name(`s') value(`r(s)') prec(full)
	}
end

capture program drop _clr_r
program define _clr_r, rclass
	version 17
	local nothing ""
end

* clear everything a previous run could leave behind
capture program drop _reset
program define _reset
	ereturn clear
	matrix drop _all
	* NB: "macro drop path_*_XX" is not valid Stata (wildcards only at the end)
	forvalues k = 1/2000 {
		if `"${path_`k'_XX}"' == "" & `"${num_g_path_`k'_XX}"' == "" & `k' > 50 continue, break
		global path_`k'_XX
		global num_g_path_`k'_XX
	}
	_clr_r
end

* parse a log: every Effect/Av_tot_eff/Placebo row and p-value, per unit
* (unit = "path=<labels>" after a "Path (...)" header, "level=<v>" after "By: x = v")
capture program drop _parse_log
program define _parse_log
	args logfile fh spec
	tempname lf
	local unit ""
	file open `lf' using `"`logfile'"', read text
	file read `lf' line
	while r(eof) == 0 {
		if ustrregexm(`"`macval(line)'"', "^ *Path \((.*)\) *$") {
			local unit = "path=" + subinstr(ustrregexs(1), " ", "", .)
		}
		else if ustrregexm(`"`macval(line)'"', "^ *By: *[^=]+= *(.*?) *$") {
			local unit = "level=" + strtrim(ustrregexs(1))
		}
		else if ustrregexm(`"`macval(line)'"', "^ *(Effect_[0-9]+|Av_tot_eff|Placebo_[0-9]+) *\|(.*)$") {
			local rn = ustrregexs(1)
			local vals = ustrregexs(2)
			tokenize `"`vals'"'
			forvalues j = 1/6 {
				local v "``j''"
				if "`v'" == "." local v ""
				_w, fh(`fh') spec(`spec') unit(`unit') kind(display) name(mat_res_XX) row(.) col(`j') ///
					rowname(`rn') value(`v') prec(display)
			}
		}
		else if ustrregexm(`"`macval(line)'"', "joint nullity of the (effects|placebos) *: *p-value *= *([^ ]+)") {
			local which = ustrregexs(1)
			local pv = ustrregexs(2)
			if "`pv'" == "." local pv ""
			local nm = cond("`which'" == "effects", "p_jointeffects", "p_jointplacebo")
			_w, fh(`fh') spec(`spec') unit(`unit') kind(display) name(`nm') value(`pv') prec(display)
		}
		else if ustrregexm(`"`macval(line)'"', "equality of the effects *: *p-value *= *([^ ]+)") {
			local pv = ustrregexs(1)
			if "`pv'" == "." local pv ""
			_w, fh(`fh') spec(`spec') unit(`unit') kind(display) name(p_equality_effects) value(`pv') prec(display)
		}
		file read `lf' line
	}
	file close `lf'
end

* last "Path (...)" header printed in a log
capture program drop _last_path
program define _last_path, rclass
	args logfile
	tempname lf
	local last ""
	file open `lf' using `"`logfile'"', read text
	file read `lf' line
	while r(eof) == 0 {
		if ustrregexm(`"`macval(line)'"', "^ *Path \((.*)\) *$") local last = subinstr(ustrregexs(1), " ", "", .)
		file read `lf' line
	}
	file close `lf'
	return local last `"`last'"'
end

* name of an option the ado rejected ("option xxx not allowed"), if any
capture program drop _not_allowed
program define _not_allowed, rclass
	args logfile
	tempname lf
	local opt ""
	file open `lf' using `"`logfile'"', read text
	file read `lf' line
	while r(eof) == 0 {
		if ustrregexm(`"`macval(line)'"', "^ *option ([A-Za-z_0-9]+)(\(\))? not allowed") local opt = ustrregexs(1)
		file read `lf' line
	}
	file close `lf'
	return local opt "`opt'"
end

* data preparation shared by all three languages (see README, "prep")
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
	else {
		di as error "unknown prep `p'"
		exit 198
	}
end

capture program drop _status
program define _status
	syntax , fh(string) spec(string) [unit(string) status(string) rc(string) secs(string) msg(string)]
	_q `unit'
	local unit `"`r(s)'"'
	_q `msg'
	local msg `"`r(s)'"'
	file write `fh' `"`spec',`unit',`status',`rc',`secs',`msg'"' _n
end

*------------------------------------------------------------------------------
* 3. Specs
*------------------------------------------------------------------------------
import delimited using `"`suite'/specs/specs.csv"', varnames(1) stringcols(_all) clear bindquote(strict) encoding(utf8)
local nspecs = _N
foreach f in spec_id block dataset outcome group time treatment prep options {
	forvalues i = 1/`nspecs' {
		local `f'_`i' = strtrim(`f'[`i'])
	}
}

local only   : env DCDH_ONLY
local blocks : env DCDH_BLOCKS
local cap    : env DCDH_PRECISE_CAP
if "`cap'" == "" local cap 15

tempname fo fs
file open `fo' using `"`out'/outputs.csv"', write text replace
file write `fo' "spec_id,unit,kind,name,row,col,rowname,colname,value,precision" _n
file open `fs' using `"`out'/status.csv"', write text replace
file write `fs' "spec_id,unit,status,rc,seconds,message" _n

forvalues i = 1/`nspecs' {
	local s "`spec_id_`i''"
	if `"`only'"' != "" & !`: list s in only' continue
	local b "`block_`i''"
	if `"`blocks'"' != "" & !`: list b in blocks' continue

	local opts `"`options_`i''"'
	local vars "`outcome_`i'' `group_`i'' `time_`i'' `treatment_`i''"
	di as text _n "{hline 100}" _n "SPEC `s': did_multiplegt_dyn `vars', `opts' graph_off" _n "{hline 100}"

	capture noisily use `"`data'/`dataset_`i''.dta"', clear
	if _rc {
		_status, fh(`fs') spec(`s') status(error) rc(`=_rc') msg(cannot load `dataset_`i''.dta)
		continue
	}
	capture noisily _prep `prep_`i''
	if _rc {
		_status, fh(`fs') spec(`s') status(error) rc(`=_rc') msg(prep `prep_`i'' failed)
		continue
	}
	tempfile prepped
	capture quietly save `prepped'
	if _rc {
		_status, fh(`fs') spec(`s') status(error) rc(`=_rc') msg(cannot save the prepared data)
		continue
	}

	* --- main run -------------------------------------------------------------
	_reset
	local slog `"`logs'/`s'.log"'
	capture log close _sp
	log using `"`slog'"', text replace name(_sp)
	timer clear 1
	timer on 1
	capture noisily did_multiplegt_dyn `vars', `opts' graph_off
	local rc = _rc
	timer off 1
	log close _sp
	quietly timer list 1
	local secs = r(t1)
	if `rc' != 0 | `"`e(cmd)'"' == "" {
		* an option this ado does not have -> not_supported, otherwise error
		_not_allowed `"`slog'"'
		if `"`r(opt)'"' != "" {
			_status, fh(`fs') spec(`s') status(not_supported) rc(`rc') secs(`secs') msg(option `r(opt)' not allowed in this ado)
		}
		else {
			_status, fh(`fs') spec(`s') status(error) rc(`rc') secs(`secs') msg(no e() results; see logs/`s'.log)
		}
		continue
	}

	local is_bp = ustrregexm(`"`opts'"', "by_path\(([^)]*)\)")
	local bp_arg ""
	if `is_bp' local bp_arg = strtrim(ustrregexs(1))
	local is_by = ustrregexm(`"`opts'"', "(^| )by\(")

	if !`is_bp' & !`is_by' {
		_dump_r `fo' `s' ""
		_dump `fo' `s' ""
		_status, fh(`fs') spec(`s') status(ok) rc(0) secs(`secs')
		continue
	}

	* --- by() / by_path(): every unit from the log (display precision) -------
	_parse_log `"`slog'"' `fo' `s'
	_status, fh(`fs') spec(`s') status(ok) rc(0) secs(`secs') msg(display run)

	if `is_by' {
		* the command leaves one mat_res_XX_by_<level> per level (full precision)
		local gm : all matrices
		foreach m of local gm {
			if ustrregexm("`m'", "^mat_res_XX_by_(.+)$") {
				local lv = ustrregexs(1)
				_wmat `fo' `s' "level=`lv'" matrix mat_res_XX `m'
			}
		}
		continue
	}

	* by_path: enumerate the paths, then re-run by_path(k) for full precision
	local npaths 0
	while `"${path_`=`npaths'+1'_XX}"' != "" {
		local ++npaths
	}
	forvalues k = 1/`npaths' {
		local lab_`k' = subinstr(`"${path_`k'_XX}"', " ", "", .)
		_w, fh(`fo') spec(`s') unit(path=`lab_`k'') kind(path_enum) name(n_groups) row(`k') ///
			value(${num_g_path_`k'_XX}) prec(full)
	}
	local kmax = `npaths'
	capture confirm integer number `bp_arg'
	if _rc == 0 local kmax = min(`bp_arg', `npaths')
	local kmax = min(`kmax', `cap')
	local base_opts = ustrregexra(`"`opts'"', "by_path\([^)]*\)", "")
	local klog `"`logs'/_bp_tmp.log"'
	local done ""
	forvalues k = 1/`kmax' {
		capture use `prepped', clear
		if _rc continue
		_reset
		capture log close _bk
		log using `"`klog'"', text replace name(_bk)
		timer clear 2
		timer on 2
		capture noisily did_multiplegt_dyn `vars', `base_opts' by_path(`k') graph_off
		local rc = _rc
		timer off 2
		log close _bk
		quietly timer list 2
		local ks = r(t2)
		* by_path(k) prints the k most common paths; after it, e() holds the
		* LAST path printed. (With by_path(all) the globals path_k_XX are not
		* in frequency order, so match on the printed label, not on k.)
		_last_path `"`klog'"'
		local last `"`r(last)'"'
		if `rc' != 0 | `"`e(cmd)'"' == "" | `"`last'"' == "" | `: list last in done' {
			_status, fh(`fs') spec(`s') unit(by_path(`k')) status(no_results) rc(`rc') secs(`ks') ///
				msg(by_path(`k') added no new path with results)
			continue
		}
		local done `"`done' `last'"'
		_dump `fo' `s' "path=`last'"
		_status, fh(`fs') spec(`s') unit(path=`last') status(ok) rc(0) secs(`ks') msg(precise by_path(`k'))
	}
	capture erase `"`klog'"'
}
file close `fo'
file close `fs'

*------------------------------------------------------------------------------
* 4. Input checks (skipped when DCDH_SKIP_VALIDATION=1, e.g. one job per spec)
*------------------------------------------------------------------------------
local skipval : env DCDH_SKIP_VALIDATION
if "`skipval'" != "1" {
import delimited using `"`suite'/specs/validation.csv"', varnames(1) stringcols(_all) clear bindquote(strict)
local nval = _N
forvalues i = 1/`nval' {
	local vid_`i' = strtrim(vid[`i'])
	local vopt_`i' = strtrim(test_option[`i'])
}
tempname fv
file open `fv' using `"`out'/validation.csv"', write text replace
file write `fv' "vid,outcome,message" _n
forvalues i = 1/`nval' {
	use `"`data'/wagepan.dta"', clear
	_reset
	capture log close _v
	log using `"`logs'/_validation_`vid_`i''.log"', text replace name(_v)
	capture noisily did_multiplegt_dyn lwage nr year union, effects(2) placebo(0) graph_off `vopt_`i''
	local rc = _rc
	log close _v
	_not_allowed `"`logs'/_validation_`vid_`i''.log"'
	local na `"`r(opt)'"' 
	* Stata's input checks print an error and exit with rc 0, so "rejected"
	* means an error code OR no e() results.
	local outcome = cond(`rc' == 0 & `"`e(cmd)'"' != "", "accepted", "rejected")
	if `"`na'"' != "" local outcome "not_supported"
	file write `fv' "`vid_`i'',`outcome',rc=`rc' `na'" _n
	di as text "VALIDATION `vid_`i'' `vopt_`i'' -> `outcome'"
}
file close `fv'
}

file open `fm' using `"`out'/meta.txt"', write text append
file write `fm' "finished_at=`c(current_date)' `c(current_time)'" _n
file close `fm'
di as text _n "Stata specs finished. Results in `out'"
