
* Specify the used dataset 
cd "/Users/anzony.quisperojas/Documents/GitHub/DCDH_TODO"

local today : display %tdCY-N-D date(c(current_date), "DMY")
log using "logfiles/stat_`today'.log", replace

local dataname = "wagepan"
local dataset = "_data/`dataname'.dta"
use "`dataset'",clear
	
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
	local eff_eq="all"
	
did_multiplegt_dyn `y' `g' `t' `d',  effects(`n_eff') placebo(`n_pl') bootstrap(`b_reps',`b_seed')
did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') design(,console)	
did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') predict_het(`het_var',all)
did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') by(`by_var')
did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') by_path(4)
did_multiplegt_dyn `y' `g' `t' `d', graph_off effects(`n_eff') placebo(`n_pl') cluster(`clust')	


log close
