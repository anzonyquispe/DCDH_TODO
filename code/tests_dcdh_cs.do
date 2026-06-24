clear all

cls

set obs 10

gen G = _n

expand 10

bysort G: gen T = _n

gen D = G < 5 & T >= 5
replace D = 1 if inrange(G, 5, 7) & T >= 8 // Removing this line makes DCDH and CS equivalent.


gen Y = rnormal() + 5*D


bys G: egen FirstTreat_temp = min(cond(D == 1, T, .))
bys G: egen FirstTreat = max(FirstTreat_temp)
replace FirstTreat = 0 if FirstTreat == .
drop FirstTreat_temp
gen FirstTreatImp = FirstTreat
replace FirstTreatImp = . if FirstTreat == 0

cap noisily csdid Y, ivar(G) time(T) gvar(FirstTreat) notyet method(reg) long2 agg(event)
cap noisily estat event, window(-3 3)


cap noisily did_multiplegt_dyn Y G T D, ///
    effects(4) placebo(3) cluster(G) graph_off
