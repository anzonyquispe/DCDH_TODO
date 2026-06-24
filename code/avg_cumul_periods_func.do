* ============================================================================
* avg_cumul_periods : "Average number of time periods over which a treatment's
*                      effect is accumulated" + per-effect switcher counts.
*                      FULL unbalanced-panel handling (mirrors did_multiplegt_dyn).
*
*   avg = [ sum_g sum_k |D_{g,Fg+k}-D_{g,1}| * (M_g - k) ]
*       / [ sum_g sum_k |D_{g,Fg+k}-D_{g,1}|             ]
*   over horizons k with an IDENTIFIED DID effect.
*
*   *** MODIFICACION: T_g redefinido por-horizonte ***
*   En lugar del T_g a nivel de clase ( bys Dg1: max(F_g_trunc)-1 ), que
*   sobreestima la ventana de cada grupo, se redefine T_g POR GRUPO como el
*   ultimo periodo P (>= F_g) para el cual EXISTE un control valido:
*     - g' de la misma clase d_sq, g' != g
*     - F_g' > P            (g' aun no ha cambiado en P)
*     - Y(g',P) observado   Y  Y(g', F_g-1) observado
*   (y el switcher mismo debe tener Y observado en P y en F_g-1).
*   Con este T_g, M_g = min(ell, T_g-F_g+1) refleja los horizontes REALMENTE
*   identificables, y el peso (M_g - k) ya no se infla por horizontes fantasma.
*   El conteo de switchers usa el mismo T_g.
*
* SYNTAX:
*   avg_cumul_periods groupvar timevar treatvar , effects(#) ///
*        [outcome(varname) drop_if_d_miss_before_first_switch]
* ============================================================================

capture program drop avg_cumul_periods
program define avg_cumul_periods, rclass
    version 14.0
    syntax varlist(min=3 max=3) , [effects(integer 1) outcome(varname) ///
        drop_if_d_miss_before_first_switch]

    gettoken gvar  varlist : varlist
    gettoken tvar  varlist : varlist
    gettoken dvar  varlist : varlist

    if `effects' < 1 {
        di as error "effects() must be a positive integer"
        exit 198
    }

    preserve
    quietly {

        if "`outcome'" != "" {
            keep `gvar' `tvar' `dvar' `outcome'
            drop if missing(`gvar') | missing(`tvar')
            tempvar y
            gen double `y' = `outcome'
        }
        else {
            keep `gvar' `tvar' `dvar'
            drop if missing(`gvar') | missing(`tvar')
            tempvar y
            gen double `y' = 0
        }

        tempvar g t d
        gen double `g' = `gvar'
        gen double `t' = `tvar'
        gen double `d' = `dvar'

        scalar ell_XX = `effects'

        tempvar auxt
        egen `auxt' = group(`t')
        replace `t' = `auxt'
        drop `auxt'

        xtset `g' `t'
        summarize `t', meanonly
        scalar T_max_XX = r(max)
        scalar t_min_XX = r(min)

        * ---- per-group first/last non-missing D, first non-missing Y ----
        tempvar tdnm min_tdnm max_tdnm tynm min_tynm tdmiss min_tdmiss
        gen double `tdnm' = `t' if `d' != .
        bys `g': egen double `min_tdnm' = min(`tdnm')
        bys `g': egen double `max_tdnm' = max(`tdnm')
        gen double `tynm' = `t' if `y' != .
        bys `g': egen double `min_tynm' = min(`tynm')
        gen double `tdmiss' = `t' if `d'==. & `t'>=`min_tynm'
        bys `g': egen double `min_tdmiss' = min(`tdmiss')

        tempvar dsq_tmp Dg1
        gen double `dsq_tmp' = `d' if `t'==`min_tdnm'
        bys `g': egen double `Dg1' = mean(`dsq_tmp')

        * ---- Design Restriction 2 ----
        tempvar diff_sq ever_inc ever_dec drop_cell
        gen double `diff_sq' = `d' - `Dg1'
        sort `g' `t'
        gen byte `ever_inc' = (`diff_sq' > 0 & `d' != .)
        replace `ever_inc' = 1 if `ever_inc'[_n-1]==1 & `g'==`g'[_n-1]
        gen byte `ever_dec' = (`diff_sq' < 0 & `d' != .)
        replace `ever_dec' = 1 if `ever_dec'[_n-1]==1 & `g'==`g'[_n-1]
        gen byte `drop_cell' = (`ever_inc'==1 & `ever_dec'==1)
        count if `drop_cell'==1
        scalar _N_dr2_XX = r(N)
        drop if `drop_cell'==1
        drop `diff_sq' `ever_inc' `ever_dec' `drop_cell'

        * ---- ever-changed treatment, and first switch F_g ----
        tempvar diff2 everchg tempFg Fg
        gen double `diff2' = `d' - `Dg1'
        gen byte `everchg' = (abs(`diff2')>0 & `d'!=.)
        sort `g' `t'
        by `g': replace `everchg' = 1 if `everchg'[_n-1]==1
        by `g': gen double `tempFg' = `t' if `everchg'==1 & (_n==1 | `everchg'[_n-1]==0)
        bys `g': egen double `Fg' = min(`tempFg')
        replace `Fg' = 0 if missing(`Fg')

        * ---- Design Restriction 1 ----
        tempvar varFg
        bys `Dg1': egen double `varFg' = sd(`Fg')
        drop if `varFg'==0
        drop `varFg'

        * ---- per-baseline-class control-availability drop ----
        tempvar neverchg ctrl_time
        gen byte `neverchg' = 1 - `everchg'
        bys `t' `Dg1': egen byte `ctrl_time' = max(`neverchg')
        drop if `ctrl_time'==0
        drop `neverchg' `ctrl_time'

        replace `Fg' = T_max_XX + 1 if `Fg'==0

        if "`drop_if_d_miss_before_first_switch'" != "" {
            replace `y' = . if `min_tdmiss' < `Fg' & `t' >= `min_tdmiss'
        }

        * ---- MISSING-TREATMENT CONVENTIONS ----
        tempvar ldbf_t ldbf
        gen double `ldbf_t' = `t' if `t'<`Fg' & `d'!=.
        bys `g': egen double `ldbf' = max(`ldbf_t')

        replace `y' = . if `t' < `min_tdnm'
        replace `d' = `Dg1' if `Fg'<T_max_XX+1 & `d'==. & `t'<`ldbf' & `t'>`min_tdnm'

        tempvar trunc_control
        replace `y' = . if `Fg'<T_max_XX+1 & `t'>`ldbf' & `ldbf'<`Fg'-1
        gen double `trunc_control' = `ldbf' + 1 if `Fg'<T_max_XX+1 & `ldbf'<`Fg'-1
        replace `Fg' = T_max_XX+1 if `Fg'<T_max_XX+1 & `ldbf'<`Fg'-1

        tempvar dfg_tmp dfg
        gen double `dfg_tmp' = `d' if `t'==`Fg'
        bys `g': egen double `dfg' = mean(`dfg_tmp')
        replace `d' = `dfg' if `Fg'<T_max_XX+1 & `d'==. & `t'>`Fg' & `ldbf'==`Fg'-1

        replace `d' = `Dg1' if `Fg'==T_max_XX+1 & `d'==. & `t'>`min_tdnm' & `t'<`max_tdnm'
        replace `y' = . if `Fg'==T_max_XX+1 & `t'>`max_tdnm'
        replace `trunc_control' = `max_tdnm'+1 if `Fg'==T_max_XX+1

        * ---- fillin (rectangularize) and recompute per-group constants ----
        tempvar fillin_tag
        fillin `g' `t'
        tempvar Dg1n Fgn tcn
        bys `g': egen double `Dg1n' = mean(`Dg1')
        replace `Dg1' = `Dg1n'
        bys `g': egen double `Fgn' = mean(`Fg')
        replace `Fg' = `Fgn'
        bys `g': egen double `tcn' = mean(`trunc_control')
        replace `trunc_control' = `tcn'
        drop `Dg1n' `Fgn' `tcn'

        tempvar Ngt
        gen byte `Ngt' = 1
        replace `Ngt' = 0 if `y'==. | `d'==.

        * =====================================================================
        * T_g : VERSION POR-HORIZONTE (restriccion de control real)
        *   Tg_class = bys Dg1: max(F_g_trunc)-1  (cota superior del escaneo).
        *   Luego, en Mata, T_g por grupo = ultimo P en [F_g, Tg_class] con
        *   control valido (misma clase, no-cambiado en P, Y obs en P y F_g-1).
        * =====================================================================
        tempvar Fg_trunc Tg_class
        gen double `Fg_trunc' = `Fg'
        replace `Fg_trunc' = min(`Fg', `trunc_control') if `trunc_control'!=.
        bys `Dg1': egen double `Tg_class' = max(`Fg_trunc')
        replace `Tg_class' = `Tg_class' - 1

        tempvar ever dsq_cls Fg_eff
        gen byte `ever' = (`Fg' < T_max_XX + 1)
        egen long `dsq_cls' = group(`Dg1')
        gen double `Fg_eff' = cond(`ever', `Fg', T_max_XX+1)

        * ---- S_g + no-first-stage-switcher drop ----
        * Use the class-level Tg_class window (matching did_multiplegt_dyn line 1089-1106).
        * Groups whose average post-switch treatment over [Fg, Tg_class] equals the
        * baseline have no first stage and must be excluded before _compute_Tg so they
        * cannot serve as controls either.
        tempvar post_sum post_cnt_tmp post_cnt avg_post Sg aux
        bys `g': egen double `post_sum' = total(cond(`t'>=`Fg' & `t'<=`Tg_class', `d', .))
        gen byte `post_cnt_tmp' = (`d'!=.) if `t'>=`Fg' & `t'<=`Tg_class'
        bys `g': egen double `post_cnt' = total(`post_cnt_tmp')
        gen double `avg_post' = `post_sum' / `post_cnt'

        drop if `avg_post'==`Dg1' & `Fg'!=`Tg_class'+1 & `Fg' < T_max_XX+1

        gen byte `Sg' = (`avg_post' > `Dg1') if `Fg'!=T_max_XX+1
        bys `g': egen double `aux' = min(`avg_post')
        replace `Sg' = . if `aux'==.

        * ---- Per-horizon Tg (run AFTER S_g drop so filtered groups cannot be controls) ----
        tempvar Tg
        gen double `Tg' = .
        sort `g' `t'
        mata: _compute_Tg("`g'","`t'","`y'","`Fg'","`Tg_class'","`ever'", "`Fg_eff'","`dsq_cls'","`Ngt'","`Tg'")

        tempvar Mg
        gen double `Mg' = min(ell_XX, `Tg' - `Fg' + 1)

        sort `g' `t'
        mata: _avg_cumul("`g'","`t'","`d'","`y'","`Dg1'","`Fg'","`Tg'","`ever'","`Fg_eff'","`dsq_cls'","`Mg'","`Ngt'","`Sg'", `effects')
    }
    restore

    local switch_list ""
    matrix nswitch_XX = J(1, `effects', .)
    forvalues k = 1/`effects' {
        local cnt_k = nswitch_mata_XX[1, `k']
        local switch_list "`switch_list' `cnt_k'"
        matrix nswitch_XX[1, `k'] = `cnt_k'
        return scalar N_switch_`k' = `cnt_k'
    }
    local switch_list = strtrim("`switch_list'")
    local cnames ""
    forvalues k = 1/`effects' {
        local cnames "`cnames' Effect_`k'"
    }
    matrix colnames nswitch_XX = `cnames'

    display as text "Average number of time periods over which a treatment's effect is accumulated = " ///
        as result scalar(avg_cumul_XX)
    if scalar(_N_dr2_XX) > 0 {
        display as text "Cells dropped by Design Restriction 2: " as result scalar(_N_dr2_XX)
    }
    display as text "Number of switchers per effect:"
    forvalues k = 1/`effects' {
        display as text "   Effect_`k' : " as result nswitch_XX[1,`k']
    }

    capture matrix drop nswitch_mata_XX
    return local  switchers "`switch_list'"
    return scalar N_dr2 = scalar(_N_dr2_XX)
    return scalar den = scalar(den_XX)
    return scalar num = scalar(num_XX)
    return scalar avg = scalar(avg_cumul_XX)
    return matrix switch_mat = nswitch_XX
    scalar drop _N_dr2_XX
end

* ----------------------------------------------------------------------------
* Mata worker #1: T_g POR-HORIZONTE.
* Para cada grupo switcher g (ever==1), recorre P = F_g .. Tg_class y halla el
* ULTIMO P para el cual existe un control valido:
*   - g' misma clase (CLS), g' != g
*   - F_g_eff(g') > P            (g' aun no cambia en P)
*   - Y(g',P) observado (N_gt==1) y Y(g', F_g-1) observado
* y para el cual el switcher mismo tiene Y observado en P y en F_g-1.
* Escribe ese ultimo P en Tg. Si no hay P valido, Tg = F_g-1 (=> L_g<=0).
* ----------------------------------------------------------------------------
capture mata: mata drop _compute_Tg()
mata:
void _compute_Tg(string scalar gv, string scalar tv, string scalar yv,
                 string scalar fv, string scalar tgcv, string scalar evv,
                 string scalar fev, string scalar clsv, string scalar ngtv,
                 string scalar tgoutv)
{
    real colvector G, T, Y, F, TGC, EV, FE, CLS, NGT, TGOUT
    st_view(G,    ., gv)
    st_view(T,    ., tv)
    st_view(Y,    ., yv)
    st_view(F,    ., fv)
    st_view(TGC,  ., tgcv)
    st_view(EV,   ., evv)
    st_view(FE,   ., fev)
    st_view(CLS,  ., clsv)
    st_view(NGT,  ., ngtv)
    st_view(TGOUT,., tgoutv)

    real scalar N, i, j, r, s, e, u, P, refp, Fg_, Tgc_, ever, cls_, last_P
    real scalar own_ref, own_P, has_ctrl, cg, c_fe, c_yref, c_yP, g_id

    N = rows(G)
    i = 1
    while (i <= N) {
        g_id = G[i]
        j = i
        while (j <= N) {
            if (G[j] != g_id) break
            j++
        }

        Fg_  = F[i]
        Tgc_ = TGC[i]
        ever = EV[i]
        cls_ = CLS[i]
        refp = Fg_ - 1
        last_P = Fg_ - 1

        if (ever == 1 & Fg_ < .) {

            own_ref = 0
            r = i
            while (r <= j-1) {
                if (T[r] == refp) {
                    if (NGT[r] == 1 & Y[r] < .) own_ref = 1
                    break
                }
                r++
            }

            if (own_ref == 1) {
                P = Fg_
                while (P <= Tgc_) {

                    own_P = 0
                    r = i
                    while (r <= j-1) {
                        if (T[r] == P) {
                            if (NGT[r] == 1 & Y[r] < .) own_P = 1
                            break
                        }
                        r++
                    }

                    if (own_P == 1) {
                        has_ctrl = 0
                        s = 1
                        while (s <= N) {
                            cg = G[s]
                            e = s
                            while (e <= N) {
                                if (G[e] != cg) break
                                e++
                            }
                            if (cg != g_id & CLS[s] == cls_) {
                                c_fe = FE[s]
                                if (c_fe > P) {
                                    c_yref = 0
                                    c_yP   = 0
                                    u = s
                                    while (u <= e-1) {
                                        if (T[u] == refp & NGT[u] == 1 & Y[u] < .) c_yref = 1
                                        if (T[u] == P    & NGT[u] == 1 & Y[u] < .) c_yP   = 1
                                        u++
                                    }
                                    if (c_yref == 1 & c_yP == 1) has_ctrl = 1
                                }
                            }
                            if (has_ctrl == 1) break
                            s = e
                        }
                        if (has_ctrl == 1) last_P = P
                    }
                    P++
                }
            }
        }

        r = i
        while (r <= j-1) {
            TGOUT[r] = last_P
            r++
        }
        i = j
    }
}
end

* ----------------------------------------------------------------------------
* Mata worker #2: num/den + per-effect switcher counts (uses the per-horizon Tg).
* A (g,t) cell counts only if N_gt==1. Weight = M_g - k with the corrected M_g.
* ----------------------------------------------------------------------------
capture mata: mata drop _avg_cumul()
mata:
void _avg_cumul(string scalar gv,  string scalar tv,  string scalar dv,
                string scalar yv,
                string scalar d1v, string scalar fv,  string scalar tgv,
                string scalar evv, string scalar fev, string scalar clsv,
                string scalar mgv, string scalar ngtv, string scalar sgv, real scalar ell)
{
    real colvector G, T, D, Y, D1, F, TG, EV, FE, CLS, MG, NGT, SG
    st_view(G,   ., gv)
    st_view(T,   ., tv)
    st_view(D,   ., dv)
    st_view(Y,   ., yv)
    st_view(D1,  ., d1v)
    st_view(F,   ., fv)
    st_view(TG,  ., tgv)
    st_view(EV,  ., evv)
    st_view(FE,  ., fev)
    st_view(CLS, ., clsv)
    st_view(MG,  ., mgv)
    st_view(NGT, ., ngtv)
    st_view(SG,  ., sgv)

    real scalar N, i, j, r, s, e, u, k, kmax, period, refp
    real scalar d1, Fg_, Tg_, ever, Mg_, cls_, dval, y_ref, y_hor
    real scalar d_ref_real, hor_ok, has_ctrl, cg, c_fe, c_yref, c_yhor
    real scalar incr, weight, num, den, avg, g_id
    real rowvector nswitch

    N = rows(G)
    num = 0
    den = 0
    nswitch = J(1, ell, 0)

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
        Mg_  = MG[i]
        cls_ = CLS[i]

        if (ever == 1 & Fg_ < . & Fg_ <= Tg_) {

            refp = Fg_ - 1

            y_ref = .
            d_ref_real = 0
            r = i
            while (r <= j-1) {
                if (T[r] == refp) {
                    if (NGT[r] == 1) {
                        y_ref = Y[r]
                        d_ref_real = 1
                    }
                    break
                }
                r++
            }

            kmax = Mg_ - 1
            for (k = 0; k <= kmax; k++) {

                period = Fg_ + k

                dval   = .
                y_hor  = .
                hor_ok = 0
                r = i
                while (r <= j-1) {
                    if (T[r] == period) {
                        if (NGT[r] == 1) {
                            dval   = D[r]
                            y_hor  = Y[r]
                            hor_ok = 1
                        }
                        break
                    }
                    r++
                }

                if (dval < . & d_ref_real == 1 & hor_ok == 1 & y_ref < . & y_hor < .) {

                    has_ctrl = 0
                    s = 1
                    while (s <= N) {
                        cg = G[s]
                        e = s
                        while (e <= N) {
                            if (G[e] != cg) break
                            e++
                        }
                        if (cg != g_id & CLS[s] == cls_) {
                            c_fe = FE[s]
                            if (c_fe > period) {
                                c_yref = 0
                                c_yhor = 0
                                u = s
                                while (u <= e-1) {
                                    if (T[u] == refp   & NGT[u] == 1 & Y[u] < .) c_yref = 1
                                    if (T[u] == period & NGT[u] == 1 & Y[u] < .) c_yhor = 1
                                    u++
                                }
                                if (c_yref == 1 & c_yhor == 1) has_ctrl = 1
                            }
                        }
                        if (has_ctrl == 1) break
                        s = e
                    }

                    if (has_ctrl == 1) {
                        incr   = abs(dval - d1)
                        weight = Mg_ - k
                        num = num + incr * weight
                        den = den + incr
                        nswitch[1, k+1] = nswitch[1, k+1] + 1
                    }
                }
            }
        }
        i = j
    }

    avg = (den != 0 ? num/den : .)
    st_numscalar("num_XX", num)
    st_numscalar("den_XX", den)
    st_numscalar("avg_cumul_XX", avg)
    st_matrix("nswitch_mata_XX", nswitch)
}
end
