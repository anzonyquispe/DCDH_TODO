* Test predict_het option
cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"
use "_data/wagepan.dta", clear

* Base variables
local y = "lwage"
local g = "nr"
local t = "year"
local d = "union"

* Number of effects/placebos
local n_eff = 5
local n_pl = 2

* predict_het variable
local het_var = "black"

* Run with predict_het
did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') predict_het(`het_var', all)
