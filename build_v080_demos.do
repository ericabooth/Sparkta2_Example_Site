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
keep fips region
tempfile xwalk
save `xwalk'
restore
merge 1:1 fips using `xwalk', nogenerate keep(3)
label variable region "Comptroller economic region"
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
    overlays(region states) maplabels labelsize(7)                          ///
    download datatable tx2036style                                          ///
    title("Checkbox layers: regions dissolved over counties")               ///
    subtitle("overlays(region states) + maplabels: the region outlines are merged in the browser from the county polygons - no extra shapefile") ///
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

display as result _n "V080 DEMOS BUILT"
