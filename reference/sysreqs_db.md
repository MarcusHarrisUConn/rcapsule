# Built-in OS System Dependency (sysreqs) Registry

Returns the curated built-in mapping from R packages to Debian/Ubuntu
`apt` system packages, runtime-only `apt` packages, associated
scientific toolchains, and explanatory notes.

## Usage

``` r
sysreqs_db()
```

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with columns `package`, `apt_build`, `apt_runtime`, `toolchain`, and
`notes`.

## Examples

``` r
db <- sysreqs_db()
head(db)
#> # A tibble: 6 × 5
#>   package apt_build apt_runtime toolchain notes                                 
#>   <chr>   <list>    <list>      <chr>     <chr>                                 
#> 1 sf      <chr [6]> <chr [6]>   NA        GDAL/GEOS/PROJ/UDUNITS geospatial sta…
#> 2 terra   <chr [4]> <chr [4]>   NA        Spatial raster/vector C++ engine      
#> 3 s2      <chr [3]> <chr [1]>   cpp       Spherical geometry C++ library        
#> 4 units   <chr [1]> <chr [1]>   NA        UDUNITS2 physical units               
#> 5 lwgeom  <chr [2]> <chr [2]>   NA        PostGIS lwgeom                        
#> 6 rgdal   <chr [2]> <chr [2]>   NA        Legacy GDAL bindings                  
db[db$package %in% c("sf", "cmdstanr", "ragg"), ]
#> # A tibble: 3 × 5
#>   package  apt_build apt_runtime toolchain notes                                
#>   <chr>    <list>    <list>      <chr>     <chr>                                
#> 1 sf       <chr [6]> <chr [6]>   NA        GDAL/GEOS/PROJ/UDUNITS geospatial st…
#> 2 ragg     <chr [6]> <chr [6]>   NA        AGG high-DPI raster graphics         
#> 3 cmdstanr <chr [5]> <chr [4]>   cmdstan   CmdStan Bayesian HMC compiler        
```
