* ============================================================================
* reset_groups : Apply the de Chaisemartin & D'Haultfoeuille "reset" option.
*
* Splits each unit into pseudo-units: a new pseudo-unit starts every time the
* treatment has been STABLE for `reset' periods following a change. This lets a
* unit that switches multiple times be treated as a sequence of distinct units,
* each observed from one change to the next.
*
* This program MODIFIES the data in memory:
*   - balances the panel to complete treatment paths (drops short units),
*   - creates a new group identifier and REPLACES the group variable with it,
*   - creates an old-group variable (for clustering) if requested.
*
* SYNTAX:
*   reset_groups groupvar timevar treatvar , reset(#) [cluster(varname) ///
*                newgroup(newvarname) oldgroup(oldvarname) replace_group]
*
*   groupvar  - name of the group/unit id variable
*   timevar   - name of the time variable
*   treatvar  - name of the treatment variable
*   reset(#)  - number of stable post-change periods that triggers a split
*               (reset(0) does nothing, matching the ado)
*
*   Options:
*   cluster(varname)  - existing cluster var; if omitted, an old-group cluster
*                       variable is created and its name returned in r(cluster)
*   newgroup(name)    - name for the new pseudo-group variable (default: new_group)
*   oldgroup(name)    - name for the preserved original-group variable
*                       (default: old_group); only created when cluster() empty
*   replace_group     - if specified, REPLACE groupvar with the new pseudo-group
*                       ids (matches the ado). If omitted, groupvar is left as-is
*                       and the new ids live only in the newgroup() variable.
*
* RETURNS:
*   r(reset)     - the reset value used
*   r(N_newgrp)  - number of pseudo-groups created
*   r(N_dropped) - number of observations dropped by the balancing step
*   r(cluster)   - name of the cluster variable (existing or newly created)
*   r(newgroup)  - name of the new pseudo-group variable
*
* EXAMPLE:
*   reset_groups group time treatment , reset(1) replace_group
*   list group time treatment, sepby(group)
* ============================================================================

capture program drop reset_groups
program define reset_groups, rclass
    version 14.0
    syntax varlist(min=3 max=3) , reset(integer) ///
        [cluster(varname) newgroup(name) oldgroup(name) replace_group]

    * ---- parse the three input variable names ----
    gettoken gvar varlist : varlist
    gettoken tvar varlist : varlist
    gettoken dvar varlist : varlist

    * ---- defaults for output names ----
    if "`newgroup'" == "" local newgroup new_group
    if "`oldgroup'" == "" local oldgroup old_group

    * ---- reset(0): do nothing (matches the ado) ----
    if `reset' == 0 {
        display as text "reset(0) specified: no splitting performed; data unchanged."
        return scalar reset     = 0
        return scalar N_newgrp  = .
        return scalar N_dropped = 0
        exit
    }

    quietly {

        * remember N before balancing, to report how many rows get dropped
        count
        scalar _N_before_XX = r(N)

        xtset `gvar' `tvar'

        * ---------- balance the panel to complete treatment paths ----------
        * drop units that have fewer non-missing treatment periods than the max
        tempvar cnt_nm_tmp cnt_nm
        gen byte `cnt_nm_tmp' = (`dvar' != .)
        bys `gvar': egen long `cnt_nm' = sum(`cnt_nm_tmp')
        summarize `cnt_nm', meanonly
        drop if `cnt_nm' < r(max)
        drop `cnt_nm_tmp' `cnt_nm'

        count
        scalar _N_after_XX = r(N)

        * ---------- periods since the last treatment change ----------
        xtset `gvar' `tvar'
        tempvar changed spell psc reset_dummy reset_count

        bysort `gvar' (`tvar'): gen byte `changed' = `dvar' != `dvar'[_n-1] if _n > 1
        bysort `gvar' (`tvar'): replace `changed' = 0 if _n == 1
        bysort `gvar' (`tvar'): gen long `spell' = sum(`changed')
        bysort `gvar' `spell' (`tvar'): gen long `psc' = _n - 1
        replace `psc' = 0 if `spell' == 0

        * ---------- split points: stable for `reset' periods after a change ----------
        gen byte `reset_dummy' = (`psc' == `reset')
        bysort `gvar' (`tvar'): gen long `reset_count' = sum(`reset_dummy')

        * ---------- build the new pseudo-group id ----------
        capture drop `newgroup'
        gegen long `newgroup' = group(`gvar' `reset_count')

        * count pseudo-groups
        summarize `newgroup', meanonly
        scalar _N_newgrp_XX = r(max)

        * ---------- clustering: preserve old group if no cluster specified ----------
        local cluster_used "`cluster'"
        if "`cluster'" == "" {
            capture drop `oldgroup'
            gen long `oldgroup' = `gvar'
            local cluster_used "`oldgroup'"
        }

        * ---------- optionally replace the group variable with the new ids ----------
        if "`replace_group'" != "" {
            * preserve type compatibility: replace values of groupvar
            capture confirm numeric variable `gvar'
            if _rc == 0 {
                replace `gvar' = `newgroup'
            }
            else {
                * string group var: overwrite with string of the new id
                tempvar ng_str
                gen `ng_str' = string(`newgroup')
                replace `gvar' = `ng_str'
            }
        }

        * tidy up temporaries (tempvars auto-drop, but reset_count etc. are temp too)
    }

    * ---- report ----
    display as text "Reset option applied (reset = `reset')."
    display as text "  Observations dropped by balancing : " as result ///
        scalar(_N_before_XX) - scalar(_N_after_XX)
    display as text "  Pseudo-groups created             : " as result scalar(_N_newgrp_XX)
    display as text "  New pseudo-group variable         : " as result "`newgroup'"
    display as text "  Cluster variable                  : " as result "`cluster_used'"
    if "`replace_group'" != "" {
        display as text "  `gvar' has been REPLACED with the new pseudo-group ids."
    }
    else {
        display as text "  `gvar' left unchanged; new ids are in `newgroup'."
    }

    * ---- returns ----
    return local  cluster   "`cluster_used'"
    return local  newgroup  "`newgroup'"
    return scalar N_dropped = scalar(_N_before_XX) - scalar(_N_after_XX)
    return scalar N_newgrp  = scalar(_N_newgrp_XX)
    return scalar reset     = `reset'

    scalar drop _N_before_XX _N_after_XX _N_newgrp_XX
end
