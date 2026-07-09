***** Batch 4: wagepan — reset(4), effects(600)                            *****
***** Reset is applied to the DATA via reset_groups, then BOTH commands    *****
***** (did_multiplegt_dyn, avg_cumul_periods) are run with no reset option *****
***** Run in parallel with b1, b2, b3, b5, b6                              *****

clear all
set more off
cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
capture log close
log using "logfiles/test_switchers_b4.log", replace text
di as text "=== test_switchers_b4  started: $S_DATE $S_TIME ==="

qui do "code/avg_cumul_periods_func.do"
qui do "code/reset_groups_function.do"

local csvfile "logfiles/switchers_b4.csv"
capture erase "`csvfile'"
file open _fh using "`csvfile'", write replace
file write _fh "dataset,spec,reset,effect_num,N_did,N_avg,diff,pass" _n
file close _fh

capture program drop _swrow
program _swrow
    syntax, dataset(string) spec(string) reset(integer) ///
        effnum(integer) ndid(string) navg(string) csvfile(string)
    if missing(real("`ndid'")) | missing(real("`navg'")) {
        local diff .
        local pass "MISS"
    }
    else {
        local diff = real("`ndid'") - real("`navg'")
        local pass = cond(`diff' == 0, "PASS", "FAIL")
    }
    file open _fh using "`csvfile'", write append
    file write _fh "`dataset',`spec',`reset',`effnum',`ndid',`navg',`diff',`pass'" _n
    file close _fh
    if "`pass'" == "FAIL" di as error "  FAIL  `dataset' `spec' k=`effnum'  did=`ndid'  avg=`navg'"
    else if "`pass'" == "MISS" di as error "  MISS  `dataset' `spec' k=`effnum'  did=`ndid'  avg=`navg'"
    else                       di as text  "  PASS  `dataset' `spec' k=`effnum'  did=`ndid'  avg=`navg'"
end

capture program drop _diagrow
program _diagrow
    syntax, dataset(string) spec(string) reset(integer) msg(string) csvfile(string)
    file open _fh using "`csvfile'", write append
    file write _fh "`dataset',`spec',`reset',-1,.,.,.,ERROR:`msg'" _n
    file close _fh
end

********************************************************************************
* WAGEPAN — reset(4) applied via reset_groups, then no-reset commands
********************************************************************************
local ds    "wagepan"
local data  "_data/wagepan.dta"
local y     lwage
local g     nr
local t     year
local d     union
local spec  "reset4"
local rst   4
local neff  600

di as text _newline "{hline 60}"
di as text "`ds'  effects(`neff')  reset(`rst') applied to data"
di as text "{hline 60}"

* --- SSC did_multiplegt_dyn on reset-modified data ---
use "`data'", clear
local n_did 0
local did_failed 0
capture noisily reset_groups `g' `t' `d', reset(`rst') replace_group
if _rc {
    local rs_rc = _rc
    di as error "  ERROR reset_groups (for did side) failed rc=`rs_rc'"
    local did_failed 1
    _diagrow, dataset("`ds'") spec("`spec'") reset(`rst') ///
        msg("reset_groups_did_rc_`rs_rc'") csvfile("`csvfile'")
}
if !`did_failed' {
    cap program drop did_multiplegt_dyn
    capture noisily did_multiplegt_dyn `y' `g' `t' `d', effects(`neff') graph_off
    if _rc {
        local did_rc = _rc
        di as error "  ERROR did_multiplegt_dyn failed rc=`did_rc'"
        local did_failed 1
        _diagrow, dataset("`ds'") spec("`spec'") reset(`rst') ///
            msg("did_multiplegt_dyn_rc_`did_rc'") csvfile("`csvfile'")
    }
}
* Try to read e() scalars regardless of _rc
local stop_did = 0
forvalues i = 1/`neff' {
    if `stop_did' == 0 {
        local chk = e(N_switchers_effect_`i')
        if missing(real("`chk'")) | real("`chk'") == 0 {
            local stop_did = 1
        }
        else {
            local did_`i' = real("`chk'")
            local n_did = `i'
        }
    }
}
di as text "  -> N_did effects found: `n_did'"

* --- avg_cumul_periods on reset-modified data ---
use "`data'", clear
local n_avg 0
local avg_failed 0
capture noisily reset_groups `g' `t' `d', reset(`rst') replace_group
if _rc {
    local rs_rc = _rc
    di as error "  ERROR reset_groups (for avg side) failed rc=`rs_rc'"
    local avg_failed 1
    _diagrow, dataset("`ds'") spec("`spec'") reset(`rst') ///
        msg("reset_groups_avg_rc_`rs_rc'") csvfile("`csvfile'")
}
if !`avg_failed' {
    capture noisily avg_cumul_periods `g' `t' `d', effects(`neff') outcome(`y')
    if _rc {
        local avg_rc = _rc
        di as error "  ERROR avg_cumul_periods failed rc=`avg_rc'"
        local avg_failed 1
        _diagrow, dataset("`ds'") spec("`spec'") reset(`rst') ///
            msg("avg_cumul_periods_rc_`avg_rc'") csvfile("`csvfile'")
    }
}
* Try to read r() scalars regardless of _rc
local stop_avg = 0
forvalues i = 1/`neff' {
    if `stop_avg' == 0 {
        local chk = r(N_switch_`i')
        if missing(real("`chk'")) | real("`chk'") == 0 {
            local stop_avg = 1
        }
        else {
            local avg_`i' = real("`chk'")
            local n_avg = `i'
        }
    }
}
di as text "  -> N_avg effects found: `n_avg'"

* --- Write CSV rows ---
local n_max = max(`n_did', `n_avg')
if `n_max' == 0 {
    di as error "  No effects from either side — diagnostic rows written."
}
else {
    forvalues i = 1/`n_max' {
        local did_i = cond(`i' <= `n_did', "`did_`i''", ".")
        local avg_i = cond(`i' <= `n_avg', "`avg_`i''", ".")
        _swrow, dataset("`ds'") spec("`spec'") reset(`rst') ///
            effnum(`i') ndid(`did_i') navg(`avg_i') csvfile("`csvfile'")
    }
}

di as text _newline "CSV written to: `csvfile'"
di as text "=== test_switchers_b4  finished: $S_DATE $S_TIME ==="
log close
