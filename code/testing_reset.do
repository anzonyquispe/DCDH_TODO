clear all
set more off
cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
capture log close
log using "logfiles/testing_reset.log", replace text
di as text "=== testing_reset.do  started: $S_DATE $S_TIME ==="

qui do "code/avg_cumul_periods_func.do"


* ---- build the three treatment sequences ----
* Group 1: 0 0 0 1 1 0 0 0 1 1 1 1 0
* Group 2: 0 1 1 1 2 2 2 3 3 3 3 2 2
* Group 3: 0 4 4 5 5 5 5 2 2 2 1 1   (only 12 periods)


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

// replace treatment_XX = treatment_XX + 10

* ---- (your input block above creates group_XX, time_XX, treatment_XX) ----

* set seed for reproducibility — same outcomes every run
set seed 12345

xtset group_XX time_XX

* ============================================================
* Option A: outcome with a genuine treatment effect (recommended for testing)
* Y = unit FE + time FE + beta*treatment + noise
* ============================================================

* --- unit fixed effects (one constant draw per group) ---
bysort group_XX (time_XX): gen u_g = rnormal(0, 2) if _n == 1
bysort group_XX (time_XX): replace u_g = u_g[1]      // copy to all rows of the group

* --- time fixed effects (one constant draw per period) ---
bysort time_XX (group_XX): gen f_t = rnormal(0, 1) if _n == 1
bysort time_XX (group_XX): replace f_t = f_t[1]      // copy to all groups in that period

* --- idiosyncratic noise (one draw per observation) ---
gen eps = rnormal(0, 1)

* --- the treatment effect: each unit of dose adds `beta` to the outcome ---
local beta = 1.5
gen Y_XX = u_g + f_t + `beta'*treatment_XX + eps

* clean up the building blocks (optional — keep them if you want to inspect)
drop u_g f_t eps

list group_XX time_XX treatment_XX Y_XX, sepby(group_XX) noobs


// do "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO/code/did_multiplegt_dyn_reset.do"











/*

****** Testing we are calculating Average number of periods over which a dose cumulates  correctly *******
* ---- assumes your data has g (group), t (time), d (treatment) ----
rename group_XX g
rename time_XX t
rename treatment_XX d

xtset g t
sort g t

* ============================================================
* STEP 1: per-group primitives  D_{g,1}, F_g
* ============================================================
bysort g (t): gen double Dg1 = d[1]

gen byte switched_now = (d != Dg1)
bysort g (t): egen double Fg = min(cond(switched_now, t, .))

gen byte ever_switch = !missing(Fg)

* ============================================================
* STEP 2: define T_g  (panel-wide cutoff)
* ============================================================
bysort g (t): gen double last_period_g = t[_N]
gen double avail_until = cond(ever_switch, Fg - 1, last_period_g)
quietly summarize avail_until
scalar Tbar = r(max)
gen double Tg = Tbar

* ============================================================
* STEP 2b: find the MINIMUM baseline treatment across groups
*   This is the reference dose the denominator is measured against.
*   The formula assumes the lowest possible D_{g,1}; the package
*   uses min(D_{g,1}) rather than hardcoding 0.
* ============================================================
* one D_{g,1} value per group, then take the min over groups
preserve
    bysort g (t): keep if _n == 1     // one row per group
    quietly summarize Dg1
    scalar min_Dg1 = r(min)
restore
display "Minimum baseline treatment (reference for denominator) = " min_Dg1

* ============================================================
* STEP 3: Mata computation
* ============================================================
preserve

keep g t d Dg1 Fg Tg ever_switch
order g t d Dg1 Fg Tg ever_switch
sort g t

mata:
    // ---- pull variables from Stata ----
    st_view(G  = ., ., "g")
    st_view(T  = ., ., "t")
    st_view(D  = ., ., "d")
    st_view(D1 = ., ., "Dg1")
    st_view(F  = ., ., "Fg")
    st_view(TG = ., ., "Tg")
    st_view(EV = ., ., "ever_switch")

    // the minimum baseline treatment (reference dose) from Stata
    minD1 = st_numscalar("min_Dg1")

    N = rows(G)

    num = 0     // numerator accumulator
    den = 0     // denominator accumulator

    i = 1
    while (i <= N) {
        g_id = G[i]

        j = i
        while (j <= N) {
            if (G[j] != g_id) break
            j++
        }

        d1   = D1[i]
        Fg_  = F[i]
        Tg_  = TG[i]
        ever = EV[i]

        if (ever == 1 & Fg_ < .) {
            if (Fg_ <= Tg_) {

                kmax = Tg_ - Fg_
                for (k = 0; k <= kmax; k++) {
                    period = Fg_ + k

                    dval = .
                    r = i
                    while (r <= j-1) {
                        if (T[r] == period) {
                            dval = D[r]
                            break
                        }
                        r++
                    }

                    if (dval < .) {
                        incr   = dval - d1
                        weight = Tg_ - Fg_ - k + 1

                        num = num + incr * weight

                        // denominator: only groups whose baseline equals the
                        // MINIMUM baseline (the reference dose), not hardcoded 0
                        if (d1 == minD1) den = den + incr
                    }
                }
            }
        }

        i = j
    }

    avg_periods = (den != 0 ? num/den : .)

    printf("\n{txt}Reference (min) baseline D1 = {res}%g\n", minD1)
    printf("{txt}Numerator   = {res}%g\n", num)
    printf("{txt}Denominator = {res}%g\n", den)
    printf("{txt}Average # of periods a dose cumulates = {res}%g\n\n", avg_periods)

    st_numscalar("r_num", num)
    st_numscalar("r_den", den)
    st_numscalar("avg_cumul_periods", avg_periods)
end

restore

display "Average number of periods over which a dose cumulates = " avg_cumul_periods


did_multiplegt_dyn Y_XX g t d, effects(4) placebo(1) effects_equal(all) normalized graph_off


*/






****** Testing it with reset = 1  *******

local reset 1
xtset group_XX time_XX

//////////////////// Reset option

if `reset'!=0 {

	capture drop count_d_non_miss_XX
	capture drop count_d_non_miss_temp_XX
	capture drop changed_XX 
	capture drop spell_XX 
	capture drop periods_since_change_XX 
	capture drop reset_dummy_XX 
	capture drop reset_count_XX 
	capture drop new_group_XX

	//// Balancing panel to all complete treatment paths

	gen count_d_non_miss_temp_XX=(treatment_XX!=.)
	bys group_XX: gegen count_d_non_miss_XX=sum(count_d_non_miss_temp_XX)
	sum count_d_non_miss_XX
	drop if count_d_non_miss_XX<r(max)

	//// Time since last treatment change

	xtset group_XX time_XX

	bysort group_XX (time_XX): gen changed_XX = treatment_XX != treatment_XX[_n-1] if _n > 1
	bysort group_XX (time_XX): replace changed_XX = 0 if _n == 1

	bysort group_XX (time_XX): gen spell_XX = sum(changed_XX)

	bysort group_XX spell_XX (time_XX): gen periods_since_change_XX = _n - 1
	replace periods_since_change_XX=0 if spell_XX==0

	//// Treatment paths with one treatment change and then no change for `reset' periods
	gen reset_dummy_XX=(periods_since_change_XX==`reset')

	bysort group_XX (time_XX): gen reset_count_XX=sum(reset_dummy_XX)

	//// New group variable

	gegen new_group_XX=group(group_XX reset_count_XX)

	//// Clustering at the level of the old group variable if no clustering variable was specified

	* If a clustering variable was specified, it should in principle be coarser than the old group variable (that's what is requested in the help file).
	* However, the check for that takes place below (around line 900), and will now be made with the new group variable, so a user could for instance voluntarily specify the new group variable as their clustering
	* variable to have a more granular clustering level than old group. Given that this type of behavior would need to be deliberate (not an unvoluntary mistake), I think it is fine to leave the code as is rather than
	* moving the check that the clustering variable is coarser than the group variable up. 

	if "`cluster'"==""{
		capture drop old_group_XX
		gen old_group_XX=group_XX
		local cluster = "old_group_XX"
	}

	//// Replacing the group variable by the new group variable

	replace group_XX= new_group_XX 	

	//// Dropping all variables that were created and are now unnecessary
	drop count_d_non_miss_temp_XX count_d_non_miss_XX changed_XX spell_XX periods_since_change_XX reset_dummy_XX reset_count_XX new_group_XX
	
}


tempfile 

drop old_group_XX
rename group_XX g
rename time_XX t
rename treatment_XX d
//

did_multiplegt_dyn Y_XX g t d, effects(12) placebo(4) continuous(1) graph_off
did_multiplegt_dyn Y_XX g t d, effects(12) placebo(4) graph_off
did_multiplegt_dyn Y_XX g t d, effects(1) placebo(4) graph_off

avg_cumul_periods g t d, effects(4)  outcome(Y_XX) ///
    drop_if_d_miss_before_first_switch
avg_cumul_periods g t d, effects(1)  outcome(Y_XX) ///
    drop_if_d_miss_before_first_switch

di as text "=== testing_reset.do  finished: $S_DATE $S_TIME ==="
log close
