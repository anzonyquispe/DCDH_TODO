********************************************************************************
* SIMULATION: Weak IV with Almost Non-Invertible VCOV
* Replication in Stata using ivreg2
*
* Goal: Demonstrate how near-singular vcov matrices can artificially inflate
*       F-statistics, making truly weak instruments appear strong
*
* Methodology from did_multiplegt_dyn.ado:
*   - Singular: |det| <= 1e-16
*   - Almost not invertible: condition number >= 1000
********************************************************************************

clear all
set more off
set seed 42

* Install required packages if not already installed
capture which ivreg2
if _rc {
    ssc install ivreg2
}
capture which ranktest
if _rc {
    ssc install ranktest
}

* Set number of simulations and observations
local n_sims = 500
local n_obs = 500

********************************************************************************
* Program to generate synthetic IV data
********************************************************************************

capture program drop gen_iv_data
program define gen_iv_data
    syntax, n(integer) pi(real) rho_z(real) sigma_z1(real) sigma_z2(real)

    clear
    set obs `n'

    * Generate correlated instruments using Cholesky decomposition
    * Z1, Z2 ~ N(0, Sigma) where Sigma has correlation rho_z

    gen double u1 = rnormal()
    gen double u2 = rnormal()

    * Cholesky: Z1 = sigma1 * u1
    *           Z2 = sigma2 * (rho * u1 + sqrt(1-rho^2) * u2)
    gen double Z1 = `sigma_z1' * u1
    gen double Z2 = `sigma_z2' * (`rho_z' * u1 + sqrt(1 - `rho_z'^2) * u2)

    * First stage: D = pi * (Z1 + Z2) + v
    gen double v = rnormal()
    gen double D = `pi' * Z1 + `pi' * Z2 + v

    * Structural equation: Y = beta * D + u
    * With endogeneity: corr(u, v) = 0.5
    local beta_true = 1
    gen double u = 0.5 * v + sqrt(1 - 0.5^2) * rnormal()
    gen double Y = `beta_true' * D + u

    drop u1 u2 v u
end

********************************************************************************
* Program to check VCOV condition number (Stata methodology)
********************************************************************************

capture program drop check_vcov_condition
program define check_vcov_condition, rclass
    syntax, vcov_name(string)

    * Get the variance-covariance matrix
    matrix V = `vcov_name'
    local n_rows = rowsof(V)

    * Compute eigenvalues
    matrix symeigen X eigenvals = V

    * Get max and min eigenvalues
    local lambda_max = eigenvals[1, 1]
    local lambda_min = eigenvals[1, `n_rows']

    * Compute condition number
    if `lambda_min' <= 0 {
        local cond_num = .
        local status = "SINGULAR"
    }
    else {
        local cond_num = abs(`lambda_max' / `lambda_min')
        if `cond_num' >= 1000 {
            local status = "ALMOST_NOT_INVERTIBLE"
        }
        else {
            local status = "OK"
        }
    }

    * Compute determinant
    local det_val = det(V)

    * Return results
    return scalar cond_num = `cond_num'
    return scalar det_val = `det_val'
    return scalar lambda_max = `lambda_max'
    return scalar lambda_min = `lambda_min'
    return local status = "`status'"
end

********************************************************************************
* Main Simulation
********************************************************************************

* Create results dataset
tempfile results
postfile results str40 scenario sim_id pi_true rho_z ///
    F_stat cond_num det_val lambda_max lambda_min ///
    iv_coef iv_se iv_bias str25 vcov_status ///
    using `results', replace

* Define scenarios
local scenarios `" "Weak_Good" "Weak_Corr95" "Weak_Corr99" "Weak_Corr999" "Weak_UnequalVar" "Strong_Good" "Strong_Corr99" "'

di _n
di "════════════════════════════════════════════════════════════════"
di "SIMULATION: Weak IV with Almost Non-Invertible VCOV (Stata)"
di "════════════════════════════════════════════════════════════════"
di _n

********************************************************************************
* Scenario 1: Weak IV, Good VCOV (baseline)
********************************************************************************

di "Scenario 1/7: Weak IV, Good VCOV"
forvalues i = 1/`n_sims' {
    if mod(`i', 100) == 0 {
        di "  Simulation `i'/`n_sims'"
    }

    quietly {
        gen_iv_data, n(`n_obs') pi(0.05) rho_z(0) sigma_z1(1) sigma_z2(1)

        * Run first stage to get vcov
        reg D Z1 Z2
        matrix fs_vcov = e(V)
        matrix fs_vcov_iv = fs_vcov[2..3, 2..3]

        * Check condition number
        check_vcov_condition, vcov_name(fs_vcov_iv)
        local cond_num = r(cond_num)
        local det_val = r(det_val)
        local lambda_max = r(lambda_max)
        local lambda_min = r(lambda_min)
        local vcov_status = r(status)

        * Run IV regression
        ivreg2 Y (D = Z1 Z2), first robust
        local F_stat = e(widstat)
        local iv_coef = _b[D]
        local iv_se = _se[D]
        local iv_bias = `iv_coef' - 1

        post results ("Weak IV, Good VCOV") (`i') (0.05) (0) ///
            (`F_stat') (`cond_num') (`det_val') (`lambda_max') (`lambda_min') ///
            (`iv_coef') (`iv_se') (`iv_bias') ("`vcov_status'")
    }
}

********************************************************************************
* Scenario 2: Weak IV, Correlated IVs (rho=0.95)
********************************************************************************

di "Scenario 2/7: Weak IV, Correlated IVs (rho=0.95)"
forvalues i = 1/`n_sims' {
    if mod(`i', 100) == 0 {
        di "  Simulation `i'/`n_sims'"
    }

    quietly {
        gen_iv_data, n(`n_obs') pi(0.05) rho_z(0.95) sigma_z1(1) sigma_z2(1)

        reg D Z1 Z2
        matrix fs_vcov = e(V)
        matrix fs_vcov_iv = fs_vcov[2..3, 2..3]

        check_vcov_condition, vcov_name(fs_vcov_iv)
        local cond_num = r(cond_num)
        local det_val = r(det_val)
        local lambda_max = r(lambda_max)
        local lambda_min = r(lambda_min)
        local vcov_status = r(status)

        ivreg2 Y (D = Z1 Z2), first robust
        local F_stat = e(widstat)
        local iv_coef = _b[D]
        local iv_se = _se[D]
        local iv_bias = `iv_coef' - 1

        post results ("Weak IV, Correlated (rho=0.95)") (`i') (0.05) (0.95) ///
            (`F_stat') (`cond_num') (`det_val') (`lambda_max') (`lambda_min') ///
            (`iv_coef') (`iv_se') (`iv_bias') ("`vcov_status'")
    }
}

********************************************************************************
* Scenario 3: Weak IV, Correlated IVs (rho=0.99)
********************************************************************************

di "Scenario 3/7: Weak IV, Correlated IVs (rho=0.99)"
forvalues i = 1/`n_sims' {
    if mod(`i', 100) == 0 {
        di "  Simulation `i'/`n_sims'"
    }

    quietly {
        gen_iv_data, n(`n_obs') pi(0.05) rho_z(0.99) sigma_z1(1) sigma_z2(1)

        reg D Z1 Z2
        matrix fs_vcov = e(V)
        matrix fs_vcov_iv = fs_vcov[2..3, 2..3]

        check_vcov_condition, vcov_name(fs_vcov_iv)
        local cond_num = r(cond_num)
        local det_val = r(det_val)
        local lambda_max = r(lambda_max)
        local lambda_min = r(lambda_min)
        local vcov_status = r(status)

        ivreg2 Y (D = Z1 Z2), first robust
        local F_stat = e(widstat)
        local iv_coef = _b[D]
        local iv_se = _se[D]
        local iv_bias = `iv_coef' - 1

        post results ("Weak IV, Correlated (rho=0.99)") (`i') (0.05) (0.99) ///
            (`F_stat') (`cond_num') (`det_val') (`lambda_max') (`lambda_min') ///
            (`iv_coef') (`iv_se') (`iv_bias') ("`vcov_status'")
    }
}

********************************************************************************
* Scenario 4: Weak IV, Near Multicollinear (rho=0.999)
********************************************************************************

di "Scenario 4/7: Weak IV, Near Multicollinear (rho=0.999)"
forvalues i = 1/`n_sims' {
    if mod(`i', 100) == 0 {
        di "  Simulation `i'/`n_sims'"
    }

    quietly {
        gen_iv_data, n(`n_obs') pi(0.05) rho_z(0.999) sigma_z1(1) sigma_z2(1)

        reg D Z1 Z2
        matrix fs_vcov = e(V)
        matrix fs_vcov_iv = fs_vcov[2..3, 2..3]

        check_vcov_condition, vcov_name(fs_vcov_iv)
        local cond_num = r(cond_num)
        local det_val = r(det_val)
        local lambda_max = r(lambda_max)
        local lambda_min = r(lambda_min)
        local vcov_status = r(status)

        ivreg2 Y (D = Z1 Z2), first robust
        local F_stat = e(widstat)
        local iv_coef = _b[D]
        local iv_se = _se[D]
        local iv_bias = `iv_coef' - 1

        post results ("Weak IV, Near Multicollinear (rho=0.999)") (`i') (0.05) (0.999) ///
            (`F_stat') (`cond_num') (`det_val') (`lambda_max') (`lambda_min') ///
            (`iv_coef') (`iv_se') (`iv_bias') ("`vcov_status'")
    }
}

********************************************************************************
* Scenario 5: Weak IV, Unequal Variance (100:1) - KEY SCENARIO
********************************************************************************

di "Scenario 5/7: Weak IV, Unequal Variance (100:1) - KEY SCENARIO"
forvalues i = 1/`n_sims' {
    if mod(`i', 100) == 0 {
        di "  Simulation `i'/`n_sims'"
    }

    quietly {
        gen_iv_data, n(`n_obs') pi(0.05) rho_z(0.5) sigma_z1(10) sigma_z2(0.1)

        reg D Z1 Z2
        matrix fs_vcov = e(V)
        matrix fs_vcov_iv = fs_vcov[2..3, 2..3]

        check_vcov_condition, vcov_name(fs_vcov_iv)
        local cond_num = r(cond_num)
        local det_val = r(det_val)
        local lambda_max = r(lambda_max)
        local lambda_min = r(lambda_min)
        local vcov_status = r(status)

        ivreg2 Y (D = Z1 Z2), first robust
        local F_stat = e(widstat)
        local iv_coef = _b[D]
        local iv_se = _se[D]
        local iv_bias = `iv_coef' - 1

        post results ("Weak IV, Unequal Variance (100:1)") (`i') (0.05) (0.5) ///
            (`F_stat') (`cond_num') (`det_val') (`lambda_max') (`lambda_min') ///
            (`iv_coef') (`iv_se') (`iv_bias') ("`vcov_status'")
    }
}

********************************************************************************
* Scenario 6: Strong IV, Good VCOV (control)
********************************************************************************

di "Scenario 6/7: Strong IV, Good VCOV"
forvalues i = 1/`n_sims' {
    if mod(`i', 100) == 0 {
        di "  Simulation `i'/`n_sims'"
    }

    quietly {
        gen_iv_data, n(`n_obs') pi(0.3) rho_z(0) sigma_z1(1) sigma_z2(1)

        reg D Z1 Z2
        matrix fs_vcov = e(V)
        matrix fs_vcov_iv = fs_vcov[2..3, 2..3]

        check_vcov_condition, vcov_name(fs_vcov_iv)
        local cond_num = r(cond_num)
        local det_val = r(det_val)
        local lambda_max = r(lambda_max)
        local lambda_min = r(lambda_min)
        local vcov_status = r(status)

        ivreg2 Y (D = Z1 Z2), first robust
        local F_stat = e(widstat)
        local iv_coef = _b[D]
        local iv_se = _se[D]
        local iv_bias = `iv_coef' - 1

        post results ("Strong IV, Good VCOV") (`i') (0.3) (0) ///
            (`F_stat') (`cond_num') (`det_val') (`lambda_max') (`lambda_min') ///
            (`iv_coef') (`iv_se') (`iv_bias') ("`vcov_status'")
    }
}

********************************************************************************
* Scenario 7: Strong IV, Correlated (rho=0.99)
********************************************************************************

di "Scenario 7/7: Strong IV, Correlated (rho=0.99)"
forvalues i = 1/`n_sims' {
    if mod(`i', 100) == 0 {
        di "  Simulation `i'/`n_sims'"
    }

    quietly {
        gen_iv_data, n(`n_obs') pi(0.3) rho_z(0.99) sigma_z1(1) sigma_z2(1)

        reg D Z1 Z2
        matrix fs_vcov = e(V)
        matrix fs_vcov_iv = fs_vcov[2..3, 2..3]

        check_vcov_condition, vcov_name(fs_vcov_iv)
        local cond_num = r(cond_num)
        local det_val = r(det_val)
        local lambda_max = r(lambda_max)
        local lambda_min = r(lambda_min)
        local vcov_status = r(status)

        ivreg2 Y (D = Z1 Z2), first robust
        local F_stat = e(widstat)
        local iv_coef = _b[D]
        local iv_se = _se[D]
        local iv_bias = `iv_coef' - 1

        post results ("Strong IV, Correlated (rho=0.99)") (`i') (0.3) (0.99) ///
            (`F_stat') (`cond_num') (`det_val') (`lambda_max') (`lambda_min') ///
            (`iv_coef') (`iv_se') (`iv_bias') ("`vcov_status'")
    }
}

postclose results

********************************************************************************
* Analyze Results
********************************************************************************

use `results', clear

di _n
di "════════════════════════════════════════════════════════════════"
di "                    SIMULATION RESULTS                          "
di "════════════════════════════════════════════════════════════════"
di _n

* Summary statistics by scenario
di "─────────────────────────────────────────────────────────────────"
di "SUMMARY BY SCENARIO"
di "─────────────────────────────────────────────────────────────────"
di _n

collapse (mean) F_mean=F_stat cond_mean=cond_num iv_bias_mean=iv_bias ///
         (sd) F_sd=F_stat ///
         (count) n=sim_id, by(scenario pi_true rho_z)

* Calculate percentage with F > 10
tempfile summary
save `summary', replace

use `results', clear
gen F_gt_10 = F_stat > 10
gen cond_gt_1000 = cond_num >= 1000

collapse (mean) F_gt_10_pct=F_gt_10 cond_gt_1000_pct=cond_gt_1000, by(scenario)
replace F_gt_10_pct = F_gt_10_pct * 100
replace cond_gt_1000_pct = cond_gt_1000_pct * 100

merge 1:1 scenario using `summary', nogen

* Display results
format F_mean F_sd cond_mean iv_bias_mean %9.2f
format F_gt_10_pct cond_gt_1000_pct %5.1f

list scenario pi_true rho_z F_mean F_gt_10_pct cond_mean cond_gt_1000_pct, ///
    sep(0) noobs abbreviate(30)

di _n
di "─────────────────────────────────────────────────────────────────"
di "KEY FINDING: F-STATISTIC INFLATION"
di "─────────────────────────────────────────────────────────────────"
di _n

* Compare baseline vs ill-conditioned
sum F_mean if scenario == "Weak IV, Good VCOV"
local F_baseline = r(mean)

sum F_mean if scenario == "Weak IV, Unequal Variance (100:1)"
local F_unequal = r(mean)

sum F_gt_10_pct if scenario == "Weak IV, Good VCOV"
local pct_baseline = r(mean)

sum F_gt_10_pct if scenario == "Weak IV, Unequal Variance (100:1)"
local pct_unequal = r(mean)

di "Baseline (Weak IV, Good VCOV):"
di "  Mean F-statistic: " %6.2f `F_baseline'
di "  % with F > 10:    " %5.1f `pct_baseline' "%"
di _n
di "Ill-conditioned (Weak IV, Unequal Variance):"
di "  Mean F-statistic: " %6.2f `F_unequal'
di "  % with F > 10:    " %5.1f `pct_unequal' "%"
di _n
di "F-statistic inflation factor: " %5.1f (`F_unequal' / `F_baseline') "x"
di _n

if `pct_unequal' > `pct_baseline' + 10 {
    di "*** WARNING: Ill-conditioned VCOV significantly inflates F-statistic! ***"
    di "This can make WEAK instruments appear STRONG."
}

di _n
di "─────────────────────────────────────────────────────────────────"
di "VCOV STATUS DISTRIBUTION"
di "─────────────────────────────────────────────────────────────────"
di _n

use `results', clear
tab scenario vcov_status, row

di _n
di "─────────────────────────────────────────────────────────────────"
di "FALSE STRONG INSTRUMENTS (Weak IV appearing Strong)"
di "─────────────────────────────────────────────────────────────────"
di _n

* Count false strong cases
count if pi_true <= 0.05 & F_stat > 10 & cond_num >= 100
local n_false_strong = r(N)
count if pi_true <= 0.05
local n_weak = r(N)

di "Cases where:"
di "  - True pi <= 0.05 (weak instrument)"
di "  - F-statistic > 10 (appears strong)"
di "  - Condition number >= 100 (ill-conditioned)"
di _n
di "Found " `n_false_strong' " false strong cases out of " `n_weak' " weak IV simulations"
di "(" %5.1f (100 * `n_false_strong' / `n_weak') "% of weak IV cases)"

di _n
di "Breakdown by scenario:"
tab scenario if pi_true <= 0.05 & F_stat > 10 & cond_num >= 100

********************************************************************************
* Save results
********************************************************************************

save "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO/code/iv_analysis/LLXZ_rep/simulation_stata_results.dta", replace

export excel using "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO/code/iv_analysis/LLXZ_rep/simulation_stata_results.xlsx", ///
    firstrow(variables) replace

di _n
di "════════════════════════════════════════════════════════════════"
di "Results saved to:"
di "  - simulation_stata_results.dta"
di "  - simulation_stata_results.xlsx"
di "════════════════════════════════════════════════════════════════"

********************************************************************************
* Final Summary Table
********************************************************************************

di _n
di "╔══════════════════════════════════════════════════════════════════════════╗"
di "║                    FINAL SUMMARY TABLE                                   ║"
di "╠══════════════════════════════════════════════════════════════════════════╣"
di "║ Scenario                          │ True π │ Mean F │ F>10 % │ Cond>=1k ║"
di "╠══════════════════════════════════════════════════════════════════════════╣"

use `summary', clear
merge 1:1 scenario using `results', nogen keepusing(F_gt_10_pct cond_gt_1000_pct)

levelsof scenario, local(scenarios)
foreach s of local scenarios {
    sum pi_true if scenario == "`s'"
    local pi = r(mean)
    sum F_mean if scenario == "`s'"
    local f = r(mean)
    sum F_gt_10_pct if scenario == "`s'"
    local f10 = r(mean)
    sum cond_gt_1000_pct if scenario == "`s'"
    local c1k = r(mean)

    local s_short = substr("`s'", 1, 35)
    di "║ " %-35s "`s_short'" "│ " %5.2f `pi' " │ " %6.1f `f' " │ " %5.1f `f10' "% │ " %5.1f `c1k' "% ║"
}

di "╚══════════════════════════════════════════════════════════════════════════╝"
