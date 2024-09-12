*!version 1.0.1  12Sep2024
*! requires sdid and sdid_event
*! Jared Greathouse

*****************************************************

* Programmer: Jared A. Greathouse

* Institution:  Georgia State University

* Contact: 	j.greathouse200@gmail.com

* Created on : Jul 12, 2024

* Contents: 1. Purpose

*  2. Program Versions

*****************************************************

* 1. Purpose

** Programs Forward DD from 
** Li : https://doi.org/10.1287/mksc.2022.0212 

* 2. Program
/*

// New as of 8/11/2024:

Develops FDID for a Cohort ATT setting, i.e., where we
average the ATTs across cohorts and develop their confidence
intervals and inference statistics. This gets rid of the multiple frames
that were once generated, returning the SA "Staggered Adoption" matrix,
if more than one unit is treated.

Also returns the long dataframe, so users may make event-study style plots.




To Do List:

Create ACTUAL event study plots (with standard errors for each time point.)
^ This will need an additional plotting option, which should only work when
more than one units is treated.

Make the Standard Error matrix a table returned by the post-estimation.

*/
*****************************************************
set more off

prog define fdid, eclass
cap drop
qui frame 
loc originalframe: di r(currentframe)

/**********************************************************

	
	
	* Preliminaries*


If the data aren't a balanced panel, something about the
user's dataset ain't right.
**********************************************************/


cap qui xtset
if _rc {
	
	disp as err "The data are not xtset"
	exit 498
}

cap qui xtset

cap as r(balanced)=="strongly balanced"

if _rc {
	disp as err "The data must be strongly balanced"
	exit 498	
	
}

cap as r(gaps)==0


if _rc {
	disp as err "The data cannot have gaps"
	exit 498	
	
}


loc time: disp "`r(timevar)'"

loc panel: disp "`r(panelvar)'"



marksample touse

_xtstrbal `panel' `time' `touse'

	syntax anything [if], ///
		TReated(varname) /// We need a treatment variable as 0 1
		[gr1opts(string asis)] [gr2opts(string asis)] ///
		[unitnames(varlist max=1 string)]
		
		
   /* if unitname specified, grab the label here */
if "`unitnames'" != "" {
	qui frame 
	local curframe = c(frame)
	
tempname __dfcopy
cap frame drop __dfcopy

frame copy `curframe' `__dfcopy'

	cwf `__dfcopy'
	
    
	qui levelsof `panel',local(levp)
   	
	
	
	
   /* check if var exists */
    capture confirm string var `unitnames'
            if _rc {
                di as err "`unitnames' does not exist as a (string) variable in dataset"
                exit 198
            }
    /* check if it has a value for all units */
    tempvar pcheck
    qui egen `pcheck' = sd(`panel') , by(`unitnames')
    qui sum `pcheck'
    if r(sd) != 0 {
        di as err "`unitnames' varies within units of `panel' - revise unitnames variable "
        exit 198
    }
    local clab "`panel'"
    tempvar index
    gen `index' = _n
   /* now label the pvar accoringly */
    foreach i in `levp' {
        qui su `index' if `panel' == `i', meanonly
        local label = `unitnames'[`r(max)']
        local value = `panel'[`r(max)']
        qui label define `clab' `value' `"`label'"', modify
     }
   label value `panel' `clab'
   }
			


if "`: value label `panel''" == "" & "`unitnames'" == ""  {
	
	di as err "Your panel variable NEEDS to have a value label attached to it."
	
	di as err "Either specify -unitnames- or pre-assign your panel id with string value labels."
	
	exit 198
}


tempvar touse
mark `touse' `if' `in'

if (length("`if'")+length("`in'")>0) {
    
    qui keep if `touse'
}

		
gettoken depvar anything: anything

unab depvar: `depvar'

local y_lab: variable lab `depvar'

loc outlab "`y_lab'" // Grabs the label of our outcome variable

local tr_lab: variable lab `treated'

qui levelsof `panel' if `treated'==1, loc(trunit)

local nwords :  word count `trunit'

if `nwords' > 1 {
    matrix empty_matrix = J(1, 8, .)  // Initialize an empty matrix with 0 rows and 7 columns

    matrix combined_matrix = empty_matrix  // Initialize combined_matrix as empty
}


foreach x of loc trunit {

local curframe = c(frame)

if "`curframe'" != "`__dfcopy'" {

tempname __dfcopy
frame copy `curframe' `__dfcopy'
}
frame `__dfcopy' {


loc trunitstr: display "`: label (`panel') `x''"

if "`cfframename'" == "" {
	
	cap frame drop fdid_cfframe`x'
	
	loc defname fdid_cfframe`x'
}

else if `nwords' > 1 {
	
	loc defname `cfframename'`x'
}

else {
	
	loc defname `cfframename'
}

numcheck, unit(`panel') ///
	time(`time') ///
	transform(`transform') ///
	depvar(`depvar') /// Routine 1
	treated(`treated') cfframe(`defname') trnum(`x')


// Routine 2

treatprocess, time(`time') ///
	unit(`panel') ///
	treated(`treated') trnum(`x')
	
loc trdate = e(interdate)

	
/**********************************************************

	
	
	* Estimation*


This is where we do estimation if the dataset above passes.
**********************************************************/

est_dd, time(`time') ///
	interdate(`trdate') ///
	intname(`tr_lab') ///
	outlab(`outlab') ///
	gr1opts(`gr1opts') ///
	gr2opts(`gr2opts') ///
	treatst(`trunitstr') ///
	panel(`panel') ///
	outcome(`depvar') ///
	trnum(`x') treatment(`treated') ///
	cfframe(`defname') ntr(`nwords') copyname(`__dfcopy')
	
        if `nwords' > 1 {
            matrix resmat = e(results)
            matrix combined_matrix = combined_matrix \ resmat
        }

}

if `nwords'==1 {


mat series = e(series)
ereturn mat series= series
}
}

if `nwords' > 1 {
	
/*
mkf fdidmatrixres
cwf fdidmatrixres
	
* Convert the matrix "results" into a dataset named "myresults"
qui svmat combined_matrix, names(col)
keep c1 c2 c3

qui drop in 1

qui rename (*) (ATT PATT SE)

qui su ATT, mean

// Calculate the combined ATT
scalar ATT_combined = r(mean)

qui su PATT, mean

scalar PATT_combined = r(mean)

qui su SE

// Calculate the combined variance
scalar var_combined = r(Var)

// Calculate the combined SE
scalar SE_combined = sqrt(scalar(var_combined))

// Calculate the 95% Confidence Interval
scalar CI_lower = scalar(ATT_combined) - (invnormal(0.975) * scalar(SE_combined))
scalar CI_upper = scalar(ATT_combined) + (invnormal(0.975) * scalar(SE_combined))

    // Assume you have already computed ATT_combined and SE_combined
    // Calculate t-statistic
    scalar tstat = scalar(ATT_combined) / scalar(SE_combined)

    // Calculate p-value (two-sided)
    scalar p_value = 2 * (1 - normal(abs(scalar(tstat))))

di as res "`tabletitle'" "
di as text "{hline 13}{c TT}{hline 63}"
di as text %12s abbrev("`depvar'",12) " {c |}     ATT     Std. Err.     t      P>|t|    [95% Conf. Interval]" 
di as text "{hline 13}{c +}{hline 63}"
di as text %12s abbrev("`treated'",12) " {c |} " as result %9.5f scalar(ATT_combined) "  " %9.5f scalar(SE_combined) %9.2f scalar(tstat) %9.3f scalar(p_value) "   " %9.5f scalar(CI_lower) "   " %9.5f scalar(CI_upper)
di as text "{hline 13}{c BT}{hline 63}"
di as text "See Li (2024) for technical details."
di as text "Effects are calculated in event-time using never-treated units."


tempname my_matrix
matrix `my_matrix' = (scalar(ATT_combined), scalar(PATT_combined), scalar(SE_combined), scalar(tstat), scalar(CI_lower), scalar(CI_upper))
matrix colnames `my_matrix' = ATT PATT SE t LB UB

matrix rownames `my_matrix' = Result
ereturn clear

matrix b=scalar(ATT_combined)
matrix V=scalar(SE_combined)^2
matrix colnames b=`treated'
matrix rownames b=`depvar'
matrix colnames V=`treated'
matrix rownames V=`treated'
ereturn post b V, depname(`depvar')

ereturn mat results= `my_matrix'

cwf `originalframe'
qui cap frame drop fdidmatrixres
*/

* Create a new macro to store the filtered elements
local new_color

qui frame dir

loc color `r(frames)'

* Loop through each element in the `color` macro and check if it contains "blue"
foreach col of local color {
    if strpos("`col'", "fdid_cfframe") {
        local new_color `new_color' `col'
    }
}

loc nmulti: word count `new_color'

loc firstframe: word 1 of `new_color'

cwf `firstframe'

forv i = 2/`nmulti' {

loc change: word `i' of `new_color'
qui frlink 1:1 `time', frame(`change')

qui frget *, from(`change')
frame drop `change'
}

frame put *, into(wideframe)

frame put *, into(multiframe)

frame multiframe {
qui reshape long `depvar' cf te eventtime cfdd ymeandid ymeanfdid ddte, i(`time') j(`panel')
sort `panel' `time'

tempname cohort

qbys `panel': egen `cohort' = min(`time') if eventtime==0

qbys `panel': egen cohort = max(`cohort')
qui drop fdid*

qui xtset

qui replace eventtime = eventtime / r(tdelta)

qui g residsq = te^2 if eventtime < 0

qbys cohort: egen totpost = max(eventtime+1) // Total Post by Cohort T_post^a

qbys cohort: egen totpre = max(abs(eventtime)) if eventtime < 0 // T_pre_a

egen max_totpost = max(totpost)


qbys cohort: egen ATT = mean(te) if eventtime >=0 // Cohort ATT, tau_a (totpost/max_totpost)*

tempvar tag

egen `tag' = tag(id)

egen NCohort = total(`tag'), by(cohort) // Number of Units per Cohort

// By Cohort, Mean of Residuals Squared

qbys cohort: egen CohortMSE = mean(residsq) if eventtime < 0 // Cohort Pre-Intervention MSE

// Puts all of these into a frame

frame put cohort ATT NCohort totpost totpre CohortMSE max_totpost, into(EffectFrame)

cwf EffectFrame

collapse (firstnm) ATT NCohort totpost totpre CohortMSE max_totpost, by(cohort)


// Standard Error of the Cohort ATT

qbys cohort: g SECohort = sqrt((totpost/totpre)*CohortMSE+CohortMSE)/sqrt(totpost)

qbys cohort: g tstat = abs(ATT/SECohort)

qbys cohort: g p_value = 2 * (1 - normal(tstat))

qbys cohort: g LB = ATT - (invnormal(0.975) * SECohort)

qbys cohort: g UB = ATT + (invnormal(0.975) * SECohort)
ereturn clear
tempname SA

qui mkmat cohort ATT NCohort, mat(`SA') rowpre("Cohort ") // tstat p_value LB UB


ereturn mat SA= `SA'


}
cwf multiframe
drop residsq-CohortMSE
frame drop `firstframe'
frame drop EffectFrame
frame drop wideframe
}
cwf `originalframe'
cap frame drop `defname'
cap frame drop multiframe
end

/**********************************************************

	*Section 1: Data Setup
	
**********************************************************/

prog numcheck, eclass
// Original Data checking
syntax, ///
	unit(varname) ///
	time(varname) ///
	depvar(varname) ///
	[transform(string)] ///
	treated(varname) cfframe(string) trnum(numlist min=1 max=1 >=1 int)
	
		
/*#########################################################

	* Section 1.1: Extract panel vars

	Before DD can be done, we need panel data.
	
	a) Numeric
	b) Non-missing and
	c) Non-Constant
	
*########################################################*/

/*
di as txt "{hline}"
di as txt "Forward Difference in Differences"
di as txt "{hline}"
*/


/*The panel should be balanced, but in case it isn't somehow, we drop any variable
without the maximum number of observations (unbalanced) */


	foreach v of var `unit' `time' `depvar' {
	cap {	
		conf numeric v `v', ex // Numeric?
		
		as !mi(`v') // Not missing?
		
		qui: su `v'
		
		as r(sd) ~= 0 // Does the unit ID change?
	}
	}
	
	if _rc {
		
		
		
		disp as err "All variables `unit' (ID), `time' (Time) and `depvar' must be numeric, not missing and non-constant."
		exit 498
	}
	


frame put `time' if `unit' == `trnum', into(`cfframe')
	
end


prog treatprocess, eclass
        
syntax, time(varname) unit(varname) treated(varname) trnum(numlist min=1 max=1 >=1 int)

/*#########################################################

	* Section 1.2: Check Treatment Variable

	Before DD can be done, we need a treatment variable.
	
	
	The treatment enters at a given time and never leaves.
*########################################################*/


qui xtset
loc time_format: di r(tsfmt)

qui su `time' if `treated' ==1 & `unit'==`trnum'

loc last_date = r(max)
loc interdate = r(min)

qui su `unit' if `treated'==1

loc treated_unit = r(mean)

qui insp `time' if `treated' ~= 1 & `unit'==`treated_unit'

loc npp = r(N)


	if !_rc {
		
		su `unit' if `treated' ==1, mean
		
		loc clab: label (`unit') `treated_unit'
		loc adidtreat_lab: disp "`clab'"
		
		
		qui: levelsof `unit' if `treated' == 0 & `time' > `interdate', l(labs)

		local lab : value label `unit'

		foreach l of local labs {
		    local all `all' `: label `lab' `l'',
		}

		loc controls: display "`all'"

		//display "Treatment is measured from " `time_format' `interdate' " to " `time_format'  `last_date' " (`npp' pre-periods)"
		
		
		qui su `unit' if `treated' == 0
		
		loc dp_num = r(N) - 1
		
		cap as `dp_num' >= 2
		if _rc {
			
		di in red "You need at least 2 donors for every treated unit"
		exit 489
		}
		//di as res "{hline}"

	}	

ereturn loc interdate = `interdate'


end



prog est_dd, eclass
	
syntax, ///
	time(varname) ///
	interdate(numlist min=1 max=1 >=1 int) ///
	[intname(string)] ///
	[outlab(string)] ///
	[gr1opts(string asis)] ///
	[gr2opts(string asis)] ///
	treatst(string asis) ///
	panel(string asis) ///
	outcome(string asis) ///
	trnum(numlist min=1 max=1 >=1 int) ///
	treatment(string) [outlab(string asis)] ///
	cfframe(string) ntr(numlist min=1 max=1 >=1 int) copyname(string asis)

	
local curframe = c(frame)

tempname __reshape

frame copy `curframe' `__reshape'

cwf `__reshape'


qbys `panel': egen et = max(`treatment')

qui keep if et ==0 | `panel'==`trnum'


qui keep `panel' `time' `outcome'


qui reshape wide `outcome', j(`panel') i(`time')

qui: tsset `time'
loc time_format: di r(tsfmt)


format `time' `time_format'

order `outcome'`trnum', a(`time')

qui ds

loc temp: word 1 of `r(varlist)'

loc time: disp "`temp'"

loc t: word 2 of `r(varlist)'

loc treated_unit: disp "`t'"

local strings `r(varlist)'


local trtime `treated_unit' `time'

local predictors: list strings- trtime

loc N0: word count `predictors'

// Set U is a now empty set. It denotes the order of all units whose values,
// when added to DID maximize the pre-period r-squared.

local U

// We use the mean of the y control units as our predictor in DID regression.
// cfp= counterfactual predictions, used to calculate the R2/fit metrics.

tempvar ym cfp


// Here is the placeholder for max r2.
tempname max_r2


// Forward Selection Algorithm ...
  
qui summarize `treated_unit'
local mean_observed = r(mean)
    
* Calculate the Total Sum of Squares (TSS)
qui generate double tss = (`treated_unit' - `mean_observed')^2
qui summarize tss
local TSS = r(sum) 

while ("`predictors'" != "") {

scalar `max_r2' = 0

	foreach var of local predictors {
	
	// Drops these, as we need them for each R2 calculation
	
	cap drop rss
	cap drop tss

		 {
			
		// We take the mean of each element of set U and each new predictor.
			
		    
		 egen `ym' = rowmean(`U' `var')
		    
		 // The coefficient for the control average has to be 1.
		    
		 constraint 1 `ym' = 1
		    
		 // We use constrained OLS for this purpose.
		    
		 * 45 is the treatment date for HongKong, but this will be
		 * any date as specified by the treat variable input by the
		 * user.
		 
		    
		qui cnsreg `outcome'`trnum' `ym' if `time' < `interdate' , constraint(1)
		    
		// We predict our counterfactual
		    
		qui predict `cfp' if e(sample)
		
		// Now we calculate the pre-intervention R2 statistic.


		* Calculate the Residual Sum of Squares (RSS)
		qui generate double rss = (`treated_unit' - `cfp')^2
		qui summarize rss
		local RSS = r(sum)


		loc r2 = 1 - (`RSS' / `TSS')


		    
		    if `r2' > scalar(`max_r2') {
		    	
			
			scalar `max_r2' = `r2'
			local new_U `var'
			
		    }
		    
		    // Here we determine which unit's values maximize the r2.
		    
		    drop `ym'
		    drop `cfp'
		    
		    // We get rid of these now as they've served their purpose.
		    
		}

		}

		
	local U `U' `new_U' // We add the newly selected unit to U.
	
	// and get rid of it from the predictors list.

	local predictors : list predictors - new_U
	
	    if `r2' < 0 {
	    	


        continue, break
    }

}


// we don't need to, but I put time first.

order `time', first

order `U', a(`treated_unit')

// Now we have the set of units sorted in the order of which maximizes the R2
// For each subsequent sub-DID estimation


* Now that we have them in order, we start with the first unit, estimate DID, and calculate
* the R2 statistic. We then in succession add the next best unit, and the next best one...
* until we have estimated N0 DID models. We wish to get the model which maximizes R2.

tempvar ymean rss tss

egen ymeandid = rowmean(`U')


constraint define 1 ymeandid = 1


qui cnsreg `treated_unit' ymeandid if `time' < `interdate', constraints(1)

qui predict cfdd`trnum'

* Calculate the mean of observed values
qui summarize `treated_unit' if `time' < `interdate'
local mean_observed = r(mean)

* Calculate the Total Sum of Squares (TSS)
qui generate double `tss' = (`treated_unit' - `mean_observed')^2 if `time' < `interdate'
qui summarize `tss' if `time' < `interdate'
local TSS = r(sum)

* Calculate the Residual Sum of Squares (RSS)
qui generate double `rss' = (`treated_unit' - cfdd`trnum')^2 if `time' < `interdate'
qui summarize `rss' if `time' < `interdate'
local RSS = r(sum)

* Calculate and display R-squared
loc r2dd = 1 - (`RSS' / `TSS')

scalar DDr2 = `r2dd'
	

* Initialize an empty local to build the variable list

local varlist
local best_r2 = -1
local best_model = ""

* Loop through each variable in the list

* Calculate the mean of observed values
qui summarize `treated_unit'
local mean_observed = r(mean)
tempvar tss
* Calculate the Total Sum of Squares (TSS)
qui generate double `tss' = (`treated_unit' - `mean_observed')^2
qui summarize `tss'
local TSS = r(sum)


qui foreach x of loc U {
tempname cfiter	
	* Drop previous variables
	
	cap drop cfiter
	cap drop ymeaniter 
	tempvar rss
	* Add the current variable to the list
	local varlist `varlist' `x'


	egen ymeaniter = rowmean(`varlist')


	constraint define 1 ymeaniter = 1


	qui cnsreg `treated_unit' ymeaniter if `time' < `interdate', constraints(1)

	qui predict `cfiter' if e(sample)

	* Calculate the Residual Sum of Squares (RSS)
	qui generate double `rss' = (`treated_unit' - `cfiter')^2
	qui summarize `rss'
	local RSS = r(sum)

	* Calculate and display R-squared
	loc r2 = 1 - (`RSS' / `TSS')

    
	* Check if the current R-squared is the highest
	if (`r2' > `best_r2') {
		local best_r2 = `r2'
		local best_model = "`varlist'"
	}
} // end of Forward Selection

cwf `cfframe'

qui frlink 1:1 `time', frame(`__reshape')

qui frget `treated_unit' `best_model'  cfdd`trnum' ymeandid, from(`__reshape') //
tempname longframeone
frame put `time' `treated_unit' `best_model', into(`longframeone')

frame `longframeone' {
qui reshape long `outcome', i(`time') j(id)
qui g treat = cond(id==`trnum'& `time'>=`interdate',1,0)

qui su treat if treat==1

loc post = r(N)

qui xtset id `time'

qui sdid_event `outcome' id `time' treat, method(did) brep(1000) placebo(all)
loc  plase= e(H)[1,2]
local row `= rowsof(e(H))' 


mat res = e(H)[2..`row',1..4]

tempname newframe2
mkf `newframe2'
cwf `newframe2'

qui svmat res

qui rename (res1 res2 res3 res4) (eff se lb ub)

g t = eff/se, a(se)


gen eventtime = _n - 1 if !missing(eff)
qui replace eventtime = `post' - _n if _n > `post' & !missing(eff)
sort eventtime


qui mkmat *, mat(longframe)

}

//di as txt "{hline}"

egen ymeanfdid = rowmean(`best_model')


// And estimate DID again.

* Define the constraint
constraint define 1 ymeanfdid = 1

* Run the constrained regression
qui cnsreg `treated_unit' ymeanfdid if `time' < `interdate', constraints(1)
loc RMSE = e(rmse)

qui predict cf`trnum'

* Generate residuals
qui gen residual = `treated_unit' - cf`trnum' if `time' < `interdate'

* Calculate SS_res
qui gen ss_res = residual^2 if `time' < `interdate'
qui sum ss_res
scalar SS_res = r(sum)

* Calculate SS_tot
qui sum `treated_unit' if `time' < `interdate'
scalar meantr = r(mean) 
qui gen ss_tot = (`treated_unit' - meantr)^2 if `time' < `interdate'
qui sum ss_tot if `time' < `interdate'
scalar SS_tot = r(sum)

* Calculate R2 manually
scalar r2 = 1 - SS_res / SS_tot

// Now we calculate our ATT

qui su `treated_unit' if `time' >= `interdate'

loc yobs = r(mean)

* Here is the plot

if ("`gr1opts'" ~= "") {

if "`outlab'"=="" {
	
	loc outlab `outcome'
	
}


local fitname = "fit" + "`treatst'"

local fitname_cleaned = subinstr("`fitname'", " ", "", .)

// Define the string
local myString "`gr1opts'"

// Check if the word "name" is in the string
local contains_name = strpos("`myString'", "name")

// Return 1 if the string contains the word "name", otherwise return 0
local namecont = cond(`contains_name' > 0, 1, 0)

cap as `namecont'==1

if _rc != 0 {


local fitname = "fit" + "`treatst'"

local fitname_cleaned = subinstr("`fitname'", " ", "", .)

loc fitname_cleaned: di ustrregexra("`fitname_cleaned'", "[?@#!{}%()]", "")


loc grname name(`fitname_cleaned', replace)	
	
}

twoway (line `treated_unit' `time', lcol(black) lwidth(medthick) lpat(solid)) ///
(line cf`trnum' `time', lpat(longdash) lwidth(thin) lcol(black)) ///
(line cfdd`trnum' `time', lpat(shortdash) lwidth(medthick) lcol(gs8)), ///
yti("`treatst' `outlab'") ///
legend(order(1 "Observed" 2 "FDID" 3 "DD")) ///
xli(`interdate', lcol(gs6) lpat(--)) `grname' `gr1opts'

}



lab var cf`trnum' "FDID `treatst'"
lab var `treated_unit'"Observed `treatst'"

frame `copyname' {

local n = ustrregexra("`best_model'","\D"," ")

loc selected ""

local nwords :  word count `n'


// We see which units were selected

* Loop through each word in the macro `n`
forv i = 1/`nwords' {
    
    local current_word : word `i' of `n'

    * Extract the ith word from the macro `n`
    local units: display "`: label (`panel') `current_word''"
    
    local selected `selected' `: label (`panel') `current_word'',
    
    loc controls: display "`selected'"
    
    
}

frame `cfframe': qui note: The selected units are "`controls'"

}


// see prop 2.1 of Li


qui su `time' if `time' >=`interdate', d
tempname t2
scalar `t2' = r(N)

qui su `time' if `time' <`interdate', d
tempname t1
scalar `t1' = r(N)


g te`trnum' = `treated_unit' - cf`trnum'

g ddte`trnum' =`treated_unit'-cfdd`trnum'

lab var te`trnum' "Pointwise Treatment Effect"
lab var ddte`trnum' "Pointwise DD Treatment Effect"

qui g eventtime`trnum' = `time'-`interdate'
tempvar residsq

qui g `residsq' = te`trnum'^2 if eventtime`trnum' <0

qui su if eventtime`trnum' <0
scalar t1 = r(N)

qui su eventtime`trnum' if eventtime`trnum' >=0
scalar t2 = r(N)

qui su `residsq', mean
scalar o1hat=(scalar(t2) / scalar(t1))*(r(mean))


qui su `residsq', mean
scalar o2hat = (r(mean))

scalar ohat = sqrt(scalar(o1hat) + scalar(o2hat))

qui su te`trnum' if `time' >= `interdate'


scalar ATT = r(mean)

qui su cf`trnum' if eventtime`trnum' >=0 

scalar pATT =  100*scalar(ATT)/r(mean)


scalar CILB = scalar(ATT) - (((invnormal(0.975) * `plase')))

scalar CIUB =  scalar(ATT) + (((invnormal(0.975) * `plase')))

qui su ddte`trnum' if eventtime`trnum' >= 0, mean
scalar DDATT = r(mean)


qui su cfdd`trnum' if eventtime`trnum' >=0 

scalar pATTDD =  100*scalar(DDATT)/r(mean)

qui rename (ymeandid ymeanfdid) (ymeandid`trnum' ymeanfdid`trnum')

loc rmseround: di %9.5f `RMSE'
tempvar time2 coef se

if ("`gr2opts'" ~= "") {
	

// Define the string
local myString "`gr2opts'"

// Check if the word "name" is in the string
local contains_name = strpos("`myString'", "name")

// Return 1 if the string contains the word "name", otherwise return 0
local namecont = cond(`contains_name' > 0, 1, 0)

	
cap as `namecont'==1

if _rc != 0 {


local fitname = "te_" + "`treatst'"

local fitname_cleaned = subinstr("`fitname'", " ", "", .)

loc fitname_cleaned: di ustrregexra("`fitname_cleaned'", "[?@#!{}%()]", "")


loc grname name(`fitname_cleaned', replace)	
}

frame `newframe2' {
        twoway (rarea  lb ub eventtime, fcolor(gs10%20) lcolor(gs10%20)) ///
	(scatter eff eventtime, mc(black) ms(d) msize(*.5)), ///
	legend(off) ///
	title(Dynamic Effects) xtitle("t-`=ustrunescape("\u2113")' until Treatment") ///
	ytitle(Pointwise Effect) ///
	yline(0,lc(gs5) lp(-)) xline(0, lc(black) lp(solid))  `grname' `gr2opts'
	}
}
qui keep eventtime`trnum' `time' `treated_unit' cf`trnum' cfdd`trnum' te`trnum' ddte`trnum' ymeanfdid`trnum' ymeandid`trnum' //ci_top`trnum' ci_bottom`trnum'

qui mkmat *, mat(series)

scalar SE = `plase' //scalar(ohat)/sqrt(scalar(t2))
scalar tstat = abs(scalar(ATT)/(scalar(SE)))

tempname my_matrix
matrix `my_matrix' = (scalar(ATT), scalar(pATT), scalar(SE), scalar(tstat), scalar(CILB), scalar(CIUB), scalar(r2), `rmseround')
matrix colnames `my_matrix' = ATT PATT SE t LB UB R2 RMSE
ereturn clear

matrix b=scalar(ATT)
matrix V=scalar(SE)^2
matrix colnames b=`treatment'
matrix rownames b=`outcome'
matrix colnames V=`treatment'
matrix rownames V=`treatment'

ereturn post b V, depname(`outcome')



matrix rownames `my_matrix' = Statistics
ereturn mat dyneff = longframe
ereturn loc U "`controls'"
ereturn mat results = `my_matrix'

ereturn mat series = series

ereturn scalar T1 = `t1'
ereturn scalar T0= `interdate'
ereturn scalar T2 = `t2'

ereturn scalar T= `t1'+`t2'


* Assuming you want to round to 3 decimal places for most values and 2 for others
* Round the scalar r2 to 3 decimal places
ereturn scalar r2 = round(scalar(r2), 0.0001)

* Round the scalar DDr2 to 3 decimal places
ereturn scalar DDr2 = round(scalar(DDr2), 0.0001)

* Round the scalar rmse to 3 decimal places
ereturn scalar rmse = round(`RMSE', 0.0001)

* Assign the local N0U to the count of words in best_model and round if needed
local N0U: word count `best_model'
ereturn scalar N0U = `N0U'  // No rounding needed as this is a count

* Round the scalar DDATT to 3 decimal places
ereturn scalar DDATT = round(scalar(DDATT), 0.0001)

* Round the scalar pDDATT to 3 decimal places
ereturn scalar pDDATT = round(scalar(pATTDD), 0.0001)

* Round the scalar pATT to 3 decimal places
ereturn scalar pATT = round(scalar(pATT), 0.0001)

* Round the scalar CILB to 3 decimal places
ereturn scalar CILB = round(scalar(CILB), 0.0001)

* Round the scalar ATT to 3 decimal places
ereturn scalar ATT = round(scalar(ATT), 0.0001)

* Round the scalar CIUB to 3 decimal places
ereturn scalar CIUB = round(scalar(CIUB), 0.0001)

* Round the scalar se to 3 decimal places
ereturn scalar se = round(scalar(SE), 0.0001) // scalar(SE)

* Round the scalar tstat to 2 decimal places
ereturn scalar tstat = round(scalar(tstat), 0.01)


scalar p_value = 2 * (1 - normal(scalar(tstat)))

local tabletitle "Forward Difference-in-Differences   "

if `ntr' == 1 {

di ""
di ""

di as res "`tabletitle'{c |}   "      " " "T0 R2: " %5.3f scalar(r2) "  T0 RMSE: " %5.3f `RMSE'
di as text "{hline 13}{c TT}{hline 63}"
di as text %12s abbrev("`outcome'",12) " {c |}     ATT     Std. Err.     t      P>|t|    [95% Conf. Interval]" 
di as text "{hline 13}{c +}{hline 63}"
di as text %12s abbrev("`treatment'",12) " {c |} " as result %9.5f scalar(ATT) "  " %9.5f scalar(SE) %9.2f scalar(tstat) %9.3f scalar(p_value) "   " %9.5f scalar(CILB) "   " %9.5f scalar(CIUB)
di as text "{hline 13}{c BT}{hline 63}"
* Display the footer information
di as text "Treated Unit: `treatst'"
di as res "FDID selects `controls' as the optimal donors."
di as text "See Li (2024) for technical details."


}
end
