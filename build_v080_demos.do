*! build_v080_demos.do
*! Rebuild the v0.8.0 demo pages (s13-s16) for the Sparkta2_Example_Site
*! gallery.  Run from the site repo root so outputs land next to index.html:
*!
*!   cd <Sparkta2_Example_Site clone>
*!   stata-mp -b do build_v080_demos.do
*!
*! Needs sparkta2 v0.8.0+ on the adopath (clone dir or installed) and the
*! two files in data/: comptroller_regions.csv (county -> Comptroller
*! economic region crosswalk) and demo_raster_surface.png (synthetic
*! gradient surface used by the raster demo).

version 17.0
clear all
set more off

capture which sparkta2
if _rc {
    display as error "sparkta2 not found on adopath -- adopath ++ <sparkta2 clone> first"
    exit 199
}

*-----------------------------------------------------------------------------
* County data + real Comptroller regions
*-----------------------------------------------------------------------------
findfile texas_county_demo.csv
import delimited using "`r(fn)'", varnames(1) stringcols(2) clear
destring fips poverty_rate uninsured_rate, replace force
label variable poverty_rate   "Poverty rate (%)"
label variable uninsured_rate "Uninsured rate (%)"

preserve
import delimited using "data/comptroller_regions.csv", varnames(1) clear
rename geoid fips
rename county county_name
keep fips county_name region
tempfile xwalk
save `xwalk'
restore
merge 1:1 fips using `xwalk', nogenerate keep(3)
* The demo CSV ships synthetic "County 48xxx" names; the crosswalk carries
* the real county names — use those everywhere a name shows.
drop county
rename county_name county
label variable region "Comptroller economic region"

* A sparse highlight variable: empty for most rows, so only the flagged
* counties get dissolved outlines — the checkbox becomes a spotlight layer.
generate str28 keystudy = ""
replace keystudy = "Key study counties (demo)" ///
    if inlist(fips, 48201, 48113, 48439, 48029, 48453, 48085, 48141, 48355)
label variable keystudy "Key study counties (demo)"

tempfile counties
save `counties'

*-----------------------------------------------------------------------------
* s13: dashtab() across geographies -- counties tab + school-districts tab
*-----------------------------------------------------------------------------
keep fips county poverty_rate
generate str9 geoid = string(fips)
rename county name
drop fips
generate int level = 1
tempfile ctylong
save `ctylong'

findfile texas_districts.geojson
local djson "`r(fn)'"
clear
python:
import json
from sfi import Data, Macro
g = json.load(open(Macro.getLocal("djson")))
ids = [f["properties"]["geoid"] for f in g["features"]]
nms = [f["properties"]["name"] for f in g["features"]]
Data.setObsTotal(len(ids))
Data.addVarStr("geoid", 9)
Data.addVarStr("name", 244)
Data.store("geoid", None, [[i] for i in ids])
Data.store("name", None, [[n] for n in nms])
end
generate double poverty_rate = 5 + mod(real(geoid), 47) * 0.55
generate int level = 2
append using `ctylong'
label define lvlL 1 "Counties" 2 "School districts"
label values level lvlL
label variable poverty_rate "Poverty rate (%)"

sparkta2 poverty_rate, id(geoid) name(name) type(choropleth) scheme(blues) ///
    dashtab(level) dashtabgeo(texas|texas_districts) dashtabidwidth(5 7)   ///
    download datatable tx2036style                                          ///
    title("One file, two aggregation levels")                               ///
    subtitle("dashtab(level) + dashtabgeo(texas|texas_districts): the tab bar swaps the entire figure - data, geography, legend")  ///
    export("s13_dashtab_multigeo.html") offline noopen

*-----------------------------------------------------------------------------
* s14: overlays() -- Comptroller regions dissolved client-side + maplabels
*-----------------------------------------------------------------------------
use `counties', clear
sparkta2 poverty_rate, id(fips) name(county) type(choropleth) scheme(blues) ///
    overlays(region states keystudy) maplabels labelsize(7)                 ///
    download datatable tx2036style                                          ///
    title("Checkbox layers: regions dissolved over counties")               ///
    subtitle("overlays(region states keystudy) + maplabels: region outlines are merged in the browser from the county polygons, and a sparse variable spotlights the key study counties - no extra shapefile") ///
    export("s14_overlays_regions.html") offline noopen

*-----------------------------------------------------------------------------
* s15: rasterimage() -- georeferenced image layer under the data layer
*-----------------------------------------------------------------------------
sparkta2 poverty_rate, id(fips) name(county) type(choropleth) scheme(greens) ///
    projection(mercator)                                                     ///
    rasterimage("data/demo_raster_surface.png")                              ///
    rasterbounds(-106.7 25.8 -93.5 36.5) rasteropacity(0.55)                 ///
    rasterlabel("Synthetic surface (demo)")                                  ///
    download tx2036style                                                     ///
    title("Offline raster layer under a choropleth")                         ///
    subtitle("rasterimage() + rasterbounds(): the image is base64-embedded - one self-contained file, no tile server. Mercator keeps it aligned.") ///
    export("s15_raster_underlay.html") offline noopen

*-----------------------------------------------------------------------------
* s16: chart-side dashtab() -- one bar chart per aggregation level
*-----------------------------------------------------------------------------
use `counties', clear
preserve
collapse (mean) poverty_rate, by(region)
rename region name
generate int level = 2
tempfile reglvl
save `reglvl'
restore
gsort -poverty_rate
keep in 1/12
keep county poverty_rate
rename county name
generate int level = 1
append using `reglvl'
label define blvl 1 "Top-12 counties" 2 "Region averages"
label values level blvl
label variable poverty_rate "Poverty rate (%)"

sparkta2 poverty_rate, name(name) type(bar2) horizontal dashtab(level)   ///
    download datatable tx2036style                                        ///
    title("Chart dashtab: counties vs region averages")                   ///
    subtitle("The same higher-order tabs on a native bar2 chart - each tab is a complete re-render at a different aggregation level") ///
    export("s16_chart_dashtab.html") offline noopen

*-----------------------------------------------------------------------------
* s17: EVERYTHING TOGETHER -- bivariate + dashtab + overlays + labels +
*      filters + sliders + search + swap + export, one call
*-----------------------------------------------------------------------------
use `counties', clear
generate byte half = fips >= 48250
label define halfL 0 "Western half" 1 "Eastern half"
label values half halfL
label variable half "State half"
sparkta2 poverty_rate uninsured_rate, id(fips) name(county) type(bivariate) ///
    dashtab(half) overlays(region keystudy) maplabels labelsize(6)          ///
    filters(region) sliders(poverty_rate) search swapbutton                 ///
    download datatable tx2036style                                          ///
    title("All of v0.8.0 in one call")                                      ///
    subtitle("dashtab(half) x bivariate x overlays(region keystudy) x maplabels x filters x sliders x search x swap x export - every control coexists; each tab re-renders the lot") ///
    export("s17_kitchen_sink.html") offline noopen

*-----------------------------------------------------------------------------
* s18: dashtab as a MEASURE switcher (buttons style) + raster underlay --
*      the tab variable need not be geographic: stack two measures long
*-----------------------------------------------------------------------------
use `counties', clear
keep fips county region keystudy poverty_rate uninsured_rate
preserve
keep fips county region keystudy poverty_rate
rename poverty_rate value
generate int measure = 1
tempfile mpov
save `mpov'
restore
keep fips county region keystudy uninsured_rate
rename uninsured_rate value
generate int measure = 2
append using `mpov'
label define measL 1 "Poverty rate" 2 "Uninsured rate"
label values measure measL
label variable value "Share of residents (%)"
sparkta2 value, id(fips) name(county) type(choropleth) scheme(purples)     ///
    dashtab(measure) dashtabstyle(buttons)                                  ///
    projection(mercator)                                                    ///
    rasterimage("data/demo_raster_surface.png")                             ///
    rasterbounds(-106.7 25.8 -93.5 36.5) rasteropacity(0.4)                 ///
    rasterlabel("Synthetic surface (demo)")                                 ///
    overlays(region) download tx2036style                                   ///
    title("Dashbuttons as a measure switcher, over a raster")               ///
    subtitle("dashtab() is not only for geography: stack measures long and the buttons flip poverty vs uninsured - here over the raster underlay with region outlines on top") ///
    export("s18_measure_switch_raster.html") offline noopen

display as result _n "V080 DEMOS BUILT"
