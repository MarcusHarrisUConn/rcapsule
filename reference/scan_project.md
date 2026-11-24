# Scan an R Project for Dependencies, System Libraries, and Scientific Toolchains

Recursively inspects an R analysis project, Quarto manuscript, R
Markdown report, R package, or Shiny application. Parses R scripts,
notebook code chunks, `DESCRIPTION`, `renv.lock`, `_quarto.yml`, Shiny
entry points, and native source files to build a full-stack dependency
and toolchain profile.

## Usage

``` r
scan_project(path = ".", exclude = NULL, custom_sysreqs = NULL)
```

## Arguments

- path:

  Path to the project root directory. Defaults to `"."`.

- exclude:

  Optional character vector of additional relative paths or directory
  names to ignore during scanning.

- custom_sysreqs:

  Optional named list mapping R package names to Debian/Ubuntu `apt`
  system packages to merge with
  [`sysreqs_db()`](https://marcusharrisphd.com/rcapsule/reference/sysreqs_db.md).

## Value

An S3 object of class `rcapsule_scan` containing:

- `project_path`, `project_name`, `project_type`, `roles`, `entrypoint`

- `r_version`, `has_renv`, `renv_lock_path`, `has_description`,
  `has_quarto_yml`

- `shiny_async`: logical indicating async worker patterns in Shiny apps

- `files`: tibble of scanned project files

- `packages`: tibble of discovered R packages (`package`, `version`,
  `source`, `found_in`, `is_base`, `required`)

- `sysreqs`: tibble of resolved OS `apt` system dependencies
  (`apt_package`, `stage`, `required_by`, `source`)

- `toolchains`: named list of toolchain detection summaries (`cpp`,
  `cmdstan`, `tmb`, `jags`, `rust`, `java`, `python`, `quarto`, `latex`)

- `python_packages`: character vector of detected Python
  packages/requirements

- `seeds_detected`: integer vector of static
  [`set.seed()`](https://rdrr.io/r/base/Random.html) literals discovered

- `git`: list of Git repository metadata

- `scanned_at`: ISO-8601 UTC timestamp

## Examples

``` r
tmp <- tempfile("rcapsule_scan_demo_")
dir.create(tmp)
writeLines(c("library(stats)", "x <- rnorm(10)"), file.path(tmp, "analysis.R"))
sc <- scan_project(tmp)
sc
#> 
#> ── rcapsule Project Scan: rcapsule_scan_demo_19a941a7718f ──────────────────────
#> • Path: /tmp/RtmpThAhiB/rcapsule_scan_demo_19a941a7718f
#> • Project type: "analysis" (roles: analysis)
#> • R version: "4.6.2" | renv.lock: FALSE | DESCRIPTION: FALSE
#> • Entrypoint: "analysis.R"
#> • Files scanned: 1
#> 
#> ── R Packages (0 non-base) ──
#> 
#> None detected (base R only)
#> 
#> ── Detected Toolchains (0) ──
#> 
#> Standard R runtime only
#> 
#> ── OS System Dependencies (0 apt packages) ──
#> 
#> None required
unlink(tmp, recursive = TRUE)
```
