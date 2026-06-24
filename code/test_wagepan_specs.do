***** test_wagepan_specs.do                                                    *
***** Cross-check: e(N_switchers_effect_k) == e(N_switch_avg_k)                *
***** across every Bookmark #1 option combination on the wagepan dataset.      *
*                                                                              *
* For each spec we call the DEV did_multiplegt_dyn (loaded from                 *
* did_multiplegt_dyn_reset.do) with that spec's options PLUS avg_time_periods. *
* After each call we capture both sets of switcher counts and emit one CSV     *
* row per (spec, effect_num). The Python script then surfaces any divergence.  *
*                                                                              *
* Output: logfiles/wagepan_specs.csv                                           *
* Log   : logfiles/test_wagepan_specs.log                                      *

clear all
set more off
cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
capture log close
log using "logfiles/test_wagepan_specs.log", replace text
di as text "=== test_wagepan_specs  started: $S_DATE $S_TIME ==="

* Load the DEV version (overrides any SSC version of did_multiplegt_dyn)
qui do "code/did_multiplegt_dyn_reset.do"

********************************************************************************
* Dataset & spec configuration
********************************************************************************
local data    "_data/wagepan.dta"
local y       lwage
local g       nr
local t       year
local d       union
local cont    hours
local nonparam black
local wght    educ
local clust   hisp
local n_eff   5
local n_pl    2
local b_reps  20
local b_seed  1234
local eff_eq  all

********************************************************************************
* CSV setup
********************************************************************************
local csvfile "logfiles/wagepan_specs.csv"
capture erase "`csvfile'"
file open _fh using "`csvfile'", write replace
file write _fh "spec,effect_num,N_std,N_avg,diff,pass" _n
file close _fh

capture program drop _wrow
program _wrow
    syntax, spec(string) effnum(integer) nstd(string) navg(string) csvfile(string)
    if missing(real("`nstd'")) | missing(real("`navg'")) {
        local diff .
        local pass "MISS"
    }
    else {
        local diff = real("`nstd'") - real("`navg'")
        local pass = cond(`diff' == 0, "PASS", "FAIL")
    }
    file open _fh using "`csvfile'", write append
    file write _fh "`spec',`effnum',`nstd',`navg',`diff',`pass'" _n
    file close _fh
    if "`pass'" == "FAIL" di as error "    FAIL `spec' eff=`effnum'  std=`nstd'  avg=`navg'"
    else if "`pass'" == "MISS" di as error "    MISS `spec' eff=`effnum'  std=`nstd'  avg=`navg'"
    else                       di as text  "    PASS `spec' eff=`effnum'  std=`nstd'  avg=`navg'"
end

capture program drop _err
program _err
    syntax, spec(string) msg(string) csvfile(string)
    file open _fh using "`csvfile'", write append
    file write _fh "`spec',-1,.,.,.,ERROR:`msg'" _n
    file close _fh
end

********************************************************************************
* Helper macro: run one spec, capture, write rows
*   Usage: _run_spec "spec_label" "did options without leading comma"
*   Always appends avg_time_periods to the options.
********************************************************************************
capture program drop _run_spec
program _run_spec
    args spec opts
    di as text _newline "{hline 78}"
    di as text "SPEC: `spec'    options: `opts'"
    di as text "{hline 78}"

    use "$data_path_int", clear
    capture noisily did_multiplegt_dyn $y_int $g_int $t_int $d_int, ///
        `opts' avg_time_periods graph_off
    local rc = _rc
    di as text "  rc = `rc'"

    if `rc' != 0 & `rc' != 111 {
        _err, spec("`spec'") msg("rc_`rc'") csvfile("$csvfile_int")
        exit
    }

    forvalues k = 1/$n_eff_int {
        local nstd = e(N_switchers_effect_`k')
        local navg = e(N_switch_avg_`k')
        if missing(real("`nstd'")) & missing(real("`navg'")) {
            continue, break
        }
        _wrow, spec("`spec'") effnum(`k') ///
            nstd("`nstd'") navg("`navg'") csvfile("$csvfile_int")
    }
end

* Export config via globals so _run_spec can see them
global data_path_int   "`data'"
global y_int           "`y'"
global g_int           "`g'"
global t_int           "`t'"
global d_int           "`d'"
global n_eff_int       "`n_eff'"
global csvfile_int     "`csvfile'"

********************************************************************************
* Spec list (Bookmark #1) — only specs where avg_time_periods is meaningful
* (continuous() is skipped by the avg_time_periods block per the dev file).
********************************************************************************

_run_spec "Baseline"               "effects(`n_eff')"
_run_spec "Placebos"               "effects(`n_eff') placebo(`n_pl')"
_run_spec "Normalized"             "effects(`n_eff') placebo(`n_pl') normalized"
_run_spec "Controls"               "effects(`n_eff') placebo(`n_pl') controls(`cont')"
_run_spec "Trends_Nonparam"        "effects(`n_eff') placebo(`n_pl') trends_nonparam(`nonparam')"
* trends_lin is excluded: avg_time_periods cannot be computed under trends_lin
_run_spec "Weight"                 "effects(`n_eff') placebo(`n_pl') weight(`wght')"
_run_spec "Cluster"                "effects(`n_eff') placebo(`n_pl') cluster(`clust')"
_run_spec "Same_Switchers"         "effects(`n_eff') placebo(`n_pl') same_switchers"
_run_spec "Same_Switchers_Pl"      "effects(`n_eff') placebo(`n_pl') same_switchers same_switchers_pl"
_run_spec "Switchers_In"           "effects(`n_eff') placebo(`n_pl') switchers(in)"
_run_spec "Switchers_Out"          "effects(`n_eff') placebo(`n_pl') switchers(out)"
_run_spec "Only_Never_Switchers"   "effects(`n_eff') placebo(`n_pl') only_never_switchers"
_run_spec "CI_Level_90"            "effects(`n_eff') placebo(`n_pl') ci_level(90)"
_run_spec "CI_Level_99"            "effects(`n_eff') placebo(`n_pl') ci_level(99)"
_run_spec "Less_Conservative_SE"   "effects(`n_eff') placebo(`n_pl') less_conservative_se"
_run_spec "Dont_Drop_Larger_Lower" "effects(`n_eff') placebo(`n_pl') dont_drop_larger_lower"
_run_spec "Effects_Equal"          "effects(`n_eff') placebo(`n_pl') effects_equal(`eff_eq')"

* continuous() specs: avg_time_periods uses the binary control-existence check
* (same as N_switchers_effect_k), so counts match across all polynomial degrees.
* Continuous_8 is omitted: wagepan hits Stata's variable limit (rc=900) when
* the standard pipeline tries to generate degree-8 polynomial controls.
_run_spec "Continuous_1"           "effects(`n_eff') continuous(1)"
_run_spec "Continuous_4"           "effects(`n_eff') continuous(4)"

di as text _newline "CSV written to: `csvfile'"
di as text "=== test_wagepan_specs  finished: $S_DATE $S_TIME ==="
log close
