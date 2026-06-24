***** File to run standardized tests for "did_multiplegt_dyn" before updating versions *****

						*** Version: 22.05.25 ***


							*** Preamble ***
********************************************************************************
// Set the directory to load the datasets and to store the resulting log files

clear all
set more off
capture log close

if c(username)== "anzony.quisperojas"{
	global main_path "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
}


* data path
global data_path="${main_path}/_data"
global save_path="${main_path}/logfiles"
global gitupd = "${main_path}/code/did_multiplegt_dyn_reset.do"


// global gitupd = "C:\Users\dearb\OneDrive - Universidad de los Andes\Really Credible\debug did_multiplegt_dyn\did_multiplegt_dyn_test\GitHub_updates"
// Felix
* data path
*global data_path="C:\Users\Felix\Desktop\DID_programs\did_multiplegt_dyn\testing_data"

* save path
*global save_path="C:\Users\Felix\Desktop\DID_programs\did_multiplegt_dyn\test_dyn\log"

// Diego
// Romain
// Clément


* Specify the used dataset
local dataname = "gentzkowetal_didtextbook_balanced"
local dataset = "`dataname'.dta"
* Specify version to be saved with the log file
local version = "06_12_2026"
* Whether to also run the SSC version and compare (1 = yes, 0 = no)
local run_ssc_compare = 1
* Tolerance for flagging differences between new and SSC results
local diff_tol = 1e-8

********************************************************************************
*               HELPER PROGRAMS (defined once, used many times)                *
********************************************************************************

* ---------------------------------------------------------------
* capture_dyn_results
*   Reads e() from the last did_multiplegt_dyn call and appends a
*   labelled block of rows (estimates, variances, sample sizes,
*   joint-test p-values, optional equality test) to `store'.
*
* Options:
*   name(string)        label for this specification (row header)
*   store(string)       matrix to append to (must already exist)
*   n_eff(integer 0)    number of effects requested
*   n_pl(integer 0)     number of placebos requested
*   equality            also capture e(p_equality_effects)
* ---------------------------------------------------------------
capture program drop capture_dyn_results
program capture_dyn_results
	syntax, NAme(string) STore(string) [n_eff(integer 0) n_pl(integer 0) EQuality]

	tempname lbl xx

	* Label row (single missing value carrying the row name)
	matrix `lbl' = .
	matrix rownames `lbl' = "`name'"
	matrix `store' = `store' \ `lbl'

	* Point estimates and variances for effects + ATE + placebos
	local total = `n_eff' + `n_pl' + 1
	matrix `store' = `store' \ e(estimates)[1..`total', 1]
	matrix `store' = `store' \ e(variances)[1..`total', 1]

	* Per-effect sample sizes
	forvalues j = 1/`n_eff' {
		matrix `xx' = e(N_effect_`j')
		matrix rownames `xx' = "N_effect_`j'"
		matrix `store' = `store' \ `xx'

		matrix `xx' = e(N_switchers_effect_`j')
		matrix rownames `xx' = "N_switchers_effect_`j'"
		matrix `store' = `store' \ `xx'
	}

	* Average total effect sample sizes
	matrix `xx' = e(N_avg_total_effect)
	matrix rownames `xx' = "N_avg_total_effect"
	matrix `store' = `store' \ `xx'

	matrix `xx' = e(N_switchers_effect_average)
	matrix rownames `xx' = "N_switchers_effect_average"
	matrix `store' = `store' \ `xx'

	* Per-placebo sample sizes (only when placebos were requested)
	if `n_pl' > 0 {
		forvalues j = 1/`n_pl' {
			matrix `xx' = e(N_placebo_`j')
			matrix rownames `xx' = "N_placebo_`j'"
			matrix `store' = `store' \ `xx'

			matrix `xx' = e(N_switchers_placebo_`j')
			matrix rownames `xx' = "N_switchers_placebo_`j'"
			matrix `store' = `store' \ `xx'
		}
	}

	* Joint-test p-values
	matrix `xx' = e(p_jointeffects)
	matrix rownames `xx' = "p_jointeffects"
	matrix `store' = `store' \ `xx'

	if `n_pl' > 0 {
		matrix `xx' = e(p_jointplacebo)
		matrix rownames `xx' = "p_jointplacebo"
		matrix `store' = `store' \ `xx'
	}

	* Optional: effects-equal test
	if "`equality'" != "" {
		matrix `xx' = e(p_equality_effects)
		matrix rownames `xx' = "p_equality_effects"
		matrix `store' = `store' \ `xx'
	}
end


* ---------------------------------------------------------------
* run_dyn_test_battery
*   Runs the standardized battery of did_multiplegt_dyn calls and
*   pipes each call's results through capture_dyn_results into
*   the matrix passed via store(). Same battery is used for the
*   new version and the SSC version so the two are comparable.
* ---------------------------------------------------------------
capture program drop run_dyn_test_battery
program run_dyn_test_battery
	syntax varlist(min=4 max=4 numeric), STore(string) ///
		N_eff(integer) N_pl(integer) ///
		[Cont(string) Nonparam(string) Wght(string) Clust(string)] ///
		B_reps(integer) B_seed(integer) [Eff_eq(string)]

	tokenize `varlist'
	local y `1'
	local g `2'
	local t `3'
	local d `4'

	* Initialize storage matrix
	cap matrix drop `store'
	matrix `store' = J(1, 1, .)
	matrix rownames `store' = "INIT"

	di as result _newline "--- Spec: Baseline ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff')
	capture_dyn_results, name("Baseline") n_eff(`n_eff') store(`store')

	di as result _newline "--- Spec: Placebos ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl')
	capture_dyn_results, name("Placebos") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Normalized ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') normalized
	capture_dyn_results, name("Normalized") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Controls ---"
	if "`cont'" != ""{
		did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') controls(`cont')
		capture_dyn_results, name("Controls") n_eff(`n_eff') n_pl(`n_pl') store(`store')
	}
	
	di as result _newline "--- Spec: Trends_Nonparam ---"
	if "`nonparam'" != ""{
		did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') trends_nonparam(`nonparam')
		capture_dyn_results, name("Trends_Nonparam") n_eff(`n_eff') n_pl(`n_pl') store(`store')
	}
	
	di as result _newline "--- Spec: Trends_Lin ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') trends_lin
	capture_dyn_results, name("Trends_Lin") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Continuous ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') continuous(1)
	capture_dyn_results, name("Continuous") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	if "`wght'" != ""{
		di as result _newline "--- Spec: Weight ---"
		did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') weight(`wght')
		capture_dyn_results, name("Weight") n_eff(`n_eff') n_pl(`n_pl') store(`store')
	}
	

	di as result _newline "--- Spec: Cluster ---"
	if "`clust'" != ""{
		did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') cluster(`clust')
		capture_dyn_results, name("Cluster") n_eff(`n_eff') n_pl(`n_pl') store(`store')
	}
	
	di as result _newline "--- Spec: Same_Switchers ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') same_switchers
	capture_dyn_results, name("Same_Switchers") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Same_Switchers_Placebo ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') same_switchers same_switchers_pl
	capture_dyn_results, name("Same_Switchers_Placebo") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Switchers_In ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') switchers(in)
	capture_dyn_results, name("Switchers_In") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Switchers_Out ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') switchers(out)
	capture_dyn_results, name("Switchers_Out") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Only_Never_Switchers ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') only_never_switchers
	capture_dyn_results, name("Only_Never_Switchers") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: CI_Level_90 ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') ci_level(90)
	capture_dyn_results, name("CI_Level_90") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: CI_Level_99 ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') ci_level(99)
	capture_dyn_results, name("CI_Level_99") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Less_Conservative_SE ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') less_conservative_se
	capture_dyn_results, name("Less_Conservative_SE") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Bootstrap ---"
	if "`b_reps'" != ""{
		did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') bootstrap(`b_reps',`b_seed')
		capture_dyn_results, name("Bootstrap") n_eff(`n_eff') n_pl(`n_pl') store(`store')
	}
	
	di as result _newline "--- Spec: Dont_Drop_Larger_Lower ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') dont_drop_larger_lower
	capture_dyn_results, name("Dont_Drop_Larger_Lower") n_eff(`n_eff') n_pl(`n_pl') store(`store')

	di as result _newline "--- Spec: Effects_Equal ---"
	did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') effects_equal(`eff_eq')
	capture_dyn_results, name("Effects_Equal") n_eff(`n_eff') n_pl(`n_pl') store(`store') equality
	
	if "`newver'" == "Yes"{
		di as result _newline "--- Spec: Reset ---"
		did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') reset(`reset')
		capture_dyn_results, name("reset") n_eff(`n_eff') n_pl(`n_pl') store(`store') equality
	}
	
end


* ---------------------------------------------------------------
* compare_dyn_matrices
*   Element-wise comparison of two stored result matrices.
*   Lists every row whose absolute difference exceeds tol().
* ---------------------------------------------------------------
capture program drop compare_dyn_matrices
program compare_dyn_matrices
	syntax, NEW(string) SSC(string) [TOL(real 1e-8)]

	local nr_new = rowsof(`new')
	local nr_ssc = rowsof(`ssc')
	di as result _newline "=== Comparison: NEW vs SSC ==="
	di as text "Rows in NEW matrix: `nr_new'"
	di as text "Rows in SSC matrix: `nr_ssc'"

	if `nr_new' != `nr_ssc' {
		di as error "Dimension mismatch -- cannot do element-wise comparison."
		exit 198
	}

	matrix diff_results = `new' - `ssc'

	scalar n_diff = 0
	scalar max_abs_diff = 0
	local rownames : rowfullnames diff_results

	forvalues i = 1/`nr_new' {
		local v = diff_results[`i', 1]
		if !missing(`v') {
			if abs(`v') > `tol' {
				scalar n_diff = n_diff + 1
				if abs(`v') > max_abs_diff scalar max_abs_diff = abs(`v')
			}
		}
	}

	di as result "Rows with |diff| > `tol': " n_diff
	di as result "Maximum absolute difference: " max_abs_diff

	di as text _newline "Differing rows:"
	forvalues i = 1/`nr_new' {
		local v = diff_results[`i', 1]
		if !missing(`v') & abs(`v') > `tol' {
			local rname : word `i' of `rownames'
			di as text "  Row " %4.0f `i' "  `rname'" _col(45) ///
				"NEW=" %14.7g `new'[`i',1] "  SSC=" %14.7g `ssc'[`i',1] "  diff=" %14.7g `v'
		}
	}
end


********************************************************************************
*** Load data and initialize all variables for the corresponding dataset ***
********************************************************************************

if "`dataset'"=="wagepan.dta"{

	use "$data_path/`dataset'",clear

	* Base variables
	local y = "lwage"
	local g = "nr"
	local t = "year"
	local d = "union"

	* Number of effects/placebos
	local n_eff = 5
	local n_pl = 2

	* Bootstrap options
	local b_reps = 20
	local b_seed = 1234

	* Controls
	local cont = "hours"

	* Nonparametric trends by
	local nonparam = "black"

	* Weighting variable
	local wght = "educ"

	* Cluster variables
	local clust = "hisp"

	* by variable
	local by_var = "black"

	* predict_het variable
	local het_var = "black"

	* effects to test in effects-equal
	local eff_eq = "all"
}

if "`dataset'"=="favara_imbs.dta"{

	use "$data_path/`dataset'",clear

	* Base variables
	local y = ""
	local g = ""
	local t = ""
	local d = ""

	* Number of effects/placebos
	local n_eff = 5
	local n_pl = 2

	* Bootstrap options
	local b_reps = 20
	local b_seed = 1234

	* Controls
	local cont = ""

	* Nonparametric trends by
	local nonparam = ""

	* Weighting variable
	local wght = ""

	* Cluster variables
	local clust = ""
}

if "`dataset'"=="gentzkowetal_didtextbook.dta"{

	use "$data_path/`dataset'",clear

	* Base variables
	local y = ""
	local g = ""
	local t = ""
	local d = ""

	* Number of effects/placebos
	local n_eff = 5
	local n_pl = 2

	* Bootstrap options
	local b_reps = 20
	local b_seed = 1234

	* Controls
	local cont = ""

	* Nonparametric trends by
	local nonparam = ""

	* Weighting variable
	local wght = ""

	* Cluster variables
	local clust = ""
	
	
}

if "`dataset'"=="gentzkowetal_didtextbook_balanced.dta"{

	use "$data_path/`dataset'",clear

	* Base variables
	local y = "prestout"
	local g = "cnty90"
	local t = "year"
	local d = "numdailies"

	* Number of effects/placebos
	local n_eff = 4
	local n_pl = 4

	* Bootstrap options
	local b_reps = 20
	local b_seed = 1234

	* Controls
	local cont = ""

	* Nonparametric trends by
	local nonparam = ""

	* Weighting variable
	local wght = ""

	* Cluster variables
	local clust = ""

	* Number of reset
	local reset 4
}

********************************************************************************
*                       *** Run 1: NEW version ***                             *
* Loads did_multiplegt_dyn from the in-progress reset dofile and runs the
* full battery.
********************************************************************************

* Make sure we're loading the development version cleanly
cap program drop did_multiplegt_dyn
cap program drop did_multiplegt_dyn_core_new
do "$gitupd"

capture log close
log using "$save_path/log_main_`version'_`dataname'_new.log", replace text
di as text "=== NEW version run started: $S_DATE $S_TIME ==="

run_dyn_test_battery `y' `g' `t' `d', store(store_results_new) ///
	n_eff(`n_eff') n_pl(`n_pl') ///
	cont(`cont') nonparam(`nonparam') wght(`wght') clust(`clust') ///
	b_reps(`b_reps') b_seed(`b_seed') eff_eq(`eff_eq')

di as text "=== NEW version run finished: $S_DATE $S_TIME ==="
log close

********************************************************************************
*               *** Run 2 (NEW TEST): SSC version comparison ***                *
* Drops the in-memory dev version so the next call to did_multiplegt_dyn is
* served from the SSC-installed ado on the adopath, then re-runs the same
* battery into store_results_ssc and compares element-wise.
*
* Pre-requisite: the SSC version must be installed
*     (run once outside this dofile if needed: ssc install did_multiplegt_dyn, replace)
********************************************************************************

if `run_ssc_compare' == 1 {

	* Drop dev programs so Stata reloads the SSC ado from the adopath
	cap program drop did_multiplegt_dyn
	cap program drop did_multiplegt_dyn_core_new

	* Sanity check: the SSC ado must be findable
	cap which did_multiplegt_dyn
	if _rc {
		di as error "SSC did_multiplegt_dyn is not on the adopath. " ///
			"Install with: ssc install did_multiplegt_dyn, replace"
		exit 111
	}

	capture log close
	log using "$save_path/log_main_`version'_`dataname'_ssc.log", replace text
	di as text "=== SSC version run started: $S_DATE $S_TIME ==="

	run_dyn_test_battery `y' `g' `t' `d', store(store_results_ssc) ///
		n_eff(`n_eff') n_pl(`n_pl') ///
		cont(`cont') nonparam(`nonparam') wght(`wght') clust(`clust') ///
		b_reps(`b_reps') b_seed(`b_seed') eff_eq(`eff_eq')

	di as text "=== SSC version run finished: $S_DATE $S_TIME ==="
	log close

	* Element-wise comparison
	capture log close
	log using "$save_path/log_compare_`version'_`dataname'.log", replace text
	di as text "=== Comparison started: $S_DATE $S_TIME ==="
	compare_dyn_matrices, new(store_results_new) ssc(store_results_ssc) tol(`diff_tol')
	di as text "=== Comparison finished: $S_DATE $S_TIME ==="
	log close
}

********************************************************************************
*** Translate results vector(s) into a dataset for downstream inspection      ***
********************************************************************************

* Stata variable names are limited to 32 characters.  Build a short suffix
* (max 19 chars) so that even the longest prefix "results_diff_" (13 chars)
* stays within the limit.
local vn = substr("`version'_`dataname'", 1, 19)

* New-version results (preserves the prior file's output format)
* svmat2 replacement: svmat + manual row-name extraction
local _rownames_new : rowfullnames store_results_new
local _nrows_new = rowsof(store_results_new)
svmat store_results_new
rename store_results_new1 store_results_new
gen str80 Effect = ""
forvalues _i = 1/`_nrows_new' {
	local _rn : word `_i' of `_rownames_new'
	replace Effect = "`_rn'" if _n == `_i'
}

rename store_results_new results_`vn'
preserve
	keep Effect results_`vn'
	order Effect results_`vn'
	local dim = `_nrows_new'
	drop if _n > `dim'
	save "$save_path/datasets/data_`version'_`dataname'.dta", replace
restore

* Side-by-side NEW vs SSC dataset for the comparison test
if `run_ssc_compare' == 1 {
	svmat store_results_ssc
	rename store_results_ssc1 store_results_ssc
	rename store_results_ssc results_ssc_`vn'
	gen results_diff_`vn' = results_`vn' - results_ssc_`vn'
	preserve
		keep Effect results_`vn' results_ssc_`vn' results_diff_`vn'
		order Effect results_`vn' results_ssc_`vn' results_diff_`vn'
		local dim = rowsof(store_results_new)
		drop if _n > `dim'
		save "$save_path/datasets/data_compare_`version'_`dataname'.dta", replace
		* Also export CSV for Python comparison
		export delimited using "$save_path/datasets/data_compare_`version'_`dataname'.csv", ///
			replace
	restore
}

