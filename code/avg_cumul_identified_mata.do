* ============================================================================
* "Average number of time periods over which a treatment's effect is
*  accumulated" — FORMULA over every horizon k, WITH the ado's horizon-level
*  identification restriction (the distance_to_switch tagging).  Mata version.
*
*   avg_periods = [ sum_g sum_{k=0}^{M_g-1} |D_{g,Fg+k} - D_{g,1}| * (M_g - k) ]
*               / [ sum_g sum_{k=0}^{M_g-1} |D_{g,Fg+k} - D_{g,1}|             ]
*
*   summed ONLY over (g,k) cells where the horizon-k DID effect is IDENTIFIED:
*     g is a switcher with F_g <= T_g (T_g per baseline class), and there is a
*     same-baseline-class control that is observed and NOT-yet-switched at BOTH
*     the pre-period (F_g+k-1) and the horizon period (F_g+k).
*   This replicates distance_to_switch_k == 1 / switcher_tag, so horizons with
*   no valid control are dropped (exactly what the ado does).
*
*   M_g = min(ell, T_g - F_g + 1).
*
* Verified on smalltest.csv: effects(1) -> 1.0000 ; effects(4) -> 3.6667 (=33/9)
*   (matches did_multiplegt_dyn exactly).
* ============================================================================
* In memory: g (group), t (time), d (treatment); one row per (g,t).

scalar ell_XX = 4            // <<< set to your effects() value

xtset g t
sort g t

* ---------- baseline D_{g,1} = treatment at group's first observed period ----------
bys g (t): gen double Dg1 = d[1]

* ---------- first switch F_g, ever-switch flag ----------
gen byte chg_XX = (d != Dg1)
bys g (t): egen double Fg = min(cond(chg_XX, t, .))
gen byte ever_XX = !missing(Fg)

* ---------- never-changers: F_g = T_max + 1 (so they push T_g up correctly) ----------
sum t, meanonly
scalar Tmax_XX = r(max)
gen double Fg_eff = cond(ever_XX, Fg, Tmax_XX + 1)

* ---------- per-baseline-class T_g = max(F_g_eff within class) - 1 ----------
egen long dsq_cls = group(Dg1)
bys dsq_cls: egen double Tg = max(Fg_eff)
replace Tg = Tg - 1

* ---------- M_g = min(ell, T_g - F_g + 1) ----------
gen double Mg = min(ell_XX, Tg - Fg + 1)

* ============================================================================
* Mata: for each computable switcher, sum over horizons k = 0..M_g-1, including
*       a horizon ONLY when its DID effect is identified (control unswitched and
*       observed at BOTH the pre-period and the horizon period).
* ============================================================================
preserve
keep g t d Dg1 Fg Tg ever_XX Fg_eff dsq_cls Mg
order g t d Dg1 Fg Tg ever_XX Fg_eff dsq_cls Mg
sort g t

mata:
    // ---- pull the Stata variables as column vectors (aligned, sorted by g,t) ----
    st_view(G   = ., ., "g")
    st_view(T   = ., ., "t")
    st_view(D   = ., ., "d")
    st_view(D1  = ., ., "Dg1")
    st_view(F   = ., ., "Fg")
    st_view(TG  = ., ., "Tg")
    st_view(EV  = ., ., "ever_XX")
    st_view(FE  = ., ., "Fg_eff")
    st_view(CLS = ., ., "dsq_cls")
    st_view(MG  = ., ., "Mg")
    N = rows(G)

    num = 0
    den = 0

    i = 1
    while (i <= N) {
        g_id = G[i]

        // find end of this group's block (Mata has no short-circuit: test j<=N first)
        j = i
        while (j <= N) {
            if (G[j] != g_id) break
            j++
        }
        // group g occupies rows i..j-1; group-level scalars constant in the block
        d1   = D1[i]
        Fg_  = F[i]
        Tg_  = TG[i]
        ever = EV[i]
        Mg_  = MG[i]
        cls_ = CLS[i]

        // g must be a switcher for which an effect is computable: F_g <= T_g
        if (ever == 1 & Fg_ < . & Fg_ <= Tg_) {

            // ---- inner sum over horizons k = 0 .. M_g - 1 ----
            kmax = Mg_ - 1
            for (k = 0; k <= kmax; k++) {

                period = Fg_ + k

                // look up the dose D_{g,F_g+k} at this horizon period
                dval = .
                r = i
                while (r <= j-1) {
                    if (T[r] == period) {
                        dval = D[r]
                        break
                    }
                    r++
                }

                // skip the horizon if its period is not observed for g
                if (dval < .) {

                    // ---- IDENTIFICATION: the horizon-k DID effect needs a control ----
                    // same baseline class, observed AND not-yet-switched (t < F_g_eff)
                    // at BOTH the pre-period (period-1) and the horizon period (period).
                    ctrl_pre  = 0
                    ctrl_post = 0
                    r = 1
                    while (r <= N) {
                        if (G[r] != g_id & CLS[r] == cls_) {
                            if (T[r] == period - 1 & T[r] < FE[r]) ctrl_pre  = ctrl_pre  + 1
                            if (T[r] == period     & T[r] < FE[r]) ctrl_post = ctrl_post + 1
                        }
                        r++
                    }

                    // include the term only if the effect is identified
                    if (ctrl_pre >= 1 & ctrl_post >= 1) {
                        incr   = abs(dval - d1)      // |D_{g,Fg+k} - D_{g,1}|
                        weight = Mg_ - k             // (M_g - k)

                        num = num + incr * weight    // numerator term
                        den = den + incr             // denominator term
                    }
                }
            }
        }
        i = j
    }

    avg = (den != 0 ? num/den : .)

    printf("\n{txt}Numerator   = {res}%g\n", num)
    printf("{txt}Denominator = {res}%g\n", den)
    printf("{txt}Average # of time periods over which a dose's effect is accumulated = {res}%g\n\n", avg)

    st_numscalar("num_XX", num)
    st_numscalar("den_XX", den)
    st_numscalar("avg_cumul_XX", avg)
end
restore

di as text "Average # of time periods over which a dose's effect is accumulated = " as result avg_cumul_XX
