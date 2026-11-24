# Resolve OS System Dependencies for a Set of R Packages

Maps R package names (and optional `DESCRIPTION` `SystemRequirements`
strings or user overrides) to deduplicated Debian/Ubuntu `apt` packages
for both build and runtime container stages.

## Usage

``` r
resolve_sysreqs(
  packages = character(),
  system_requirements = NULL,
  custom_sysreqs = NULL
)
```

## Arguments

- packages:

  Character vector of R package names.

- system_requirements:

  Optional character vector of raw `SystemRequirements` strings (e.g.,
  from a `DESCRIPTION` file).

- custom_sysreqs:

  Optional named list mapping R package names to character vectors of
  `apt` packages (e.g., `list(mypkg = c("libfoo-dev"))`).

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with columns `apt_package`, `stage`, `required_by`, and `source`.

## Examples

``` r
resolve_sysreqs(c("sf", "xml2", "cmdstanr"))
#> # A tibble: 23 × 4
#>    apt_package     stage required_by source    
#>    <chr>           <chr> <chr>       <chr>     
#>  1 build-essential build cmdstanr    builtin_db
#>  2 curl            build cmdstanr    builtin_db
#>  3 g++             build cmdstanr    builtin_db
#>  4 gdal-bin        build sf          builtin_db
#>  5 libgdal-dev     build sf          builtin_db
#>  6 libgeos-dev     build sf          builtin_db
#>  7 libproj-dev     build sf          builtin_db
#>  8 libsqlite3-dev  build sf          builtin_db
#>  9 libtbb-dev      build cmdstanr    builtin_db
#> 10 libudunits2-dev build sf          builtin_db
#> # ℹ 13 more rows
resolve_sysreqs(c("dplyr", "mypkg"), custom_sysreqs = list(mypkg = "libfoo-dev"))
#> # A tibble: 2 × 4
#>   apt_package stage   required_by source
#>   <chr>       <chr>   <chr>       <chr> 
#> 1 libfoo-dev  build   mypkg       custom
#> 2 libfoo-dev  runtime mypkg       custom
```
