# Troubleshooting Reproducibility: Tolerances, .Rprofile Traps, and Cross-Architecture Builds

## Overview

Even well-intentioned R projects fail to reproduce in subtle real-world
ways. This guide covers the four most common failure modes—and how
`rcapsule` detects and resolves each one:

1.  **Hidden `.Rprofile` portability hazards** (machine-specific
    [`.libPaths()`](https://rdrr.io/r/base/libPaths.html),
    [`setwd()`](https://rdrr.io/r/base/getwd.html), or hardcoded API
    keys).
2.  **Apple Silicon (`linux/arm64`) vs. HPC/Cloud (`linux/amd64`)
    architecture mismatches** and slow source-package builds.
3.  **Monte Carlo and BLAS floating-point drift** requiring explicit
    per-file numeric tolerances (`atol`/`rtol`).
4.  **Non-deterministic binary/plot metadata** (embedded timestamps in
    PNG/PDF graphics) and unexpected extra artifacts.

## 1. Catching `.Rprofile` Portability Traps and `targets` / `here` Projects

Local `.Rprofile` files often silently break containers when copied to
another machine.
[`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md)
inspects `.Rprofile` (ignoring benign `source("renv/activate.R")` lines)
and surfaces concrete hazards alongside `targets` pipelines,
`here::here()` markers, zero-byte files, and unusual filenames:

``` r

library(rcapsule)

proj <- tempfile("rcapsule_troubleshoot_")
dir.create(file.path(proj, "data"), recursive = TRUE)

writeLines(
  c(
    "source('renv/activate.R')",
    ".libPaths('/Users/alex/R/custom-lib')",
    "setwd('/Users/alex/Desktop/my-paper')",
    "Sys.setenv(GITHUB_TOKEN = 'ghp_do_not_commit_me')"
  ),
  file.path(proj, ".Rprofile")
)

writeLines(
  c(
    "library(targets)",
    "library(here)",
    "list(tar_target(clean, read.csv(here::here('data', 'survey wave 1.csv'))))"
  ),
  file.path(proj, "_targets.R")
)
writeLines("", file.path(proj, ".here"))
write.csv(data.frame(id = 1:3, y = c(1, 2, 3)),
          file.path(proj, "data", "survey wave 1.csv"), row.names = FALSE)

sc <- scan_project(proj)
sc$rprofile_hazards
#> # A tibble: 5 × 4
#>    line hazard               severity message                                   
#>   <int> <chr>                <chr>    <chr>                                     
#> 1     2 custom_libpaths      warning  .Rprofile modifies .libPaths(); hardcoded…
#> 2     2 hardcoded_local_path warning  .Rprofile references a machine-specific a…
#> 3     3 setwd_call           error    .Rprofile calls setwd(); use relative pat…
#> 4     3 hardcoded_local_path warning  .Rprofile references a machine-specific a…
#> 5     4 secret_in_rprofile   error    .Rprofile sets an apparent secret/token v…
sc$has_targets
#> [1] TRUE
sc$uses_here
#> [1] TRUE
sc$unusual_filenames
#> [1] "data/survey wave 1.csv"
```

When `_targets.R` is detected as the entrypoint,
[`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md)
and
[`compile_apptainer()`](https://marcusharrisphd.com/rcapsule/reference/compile_apptainer.md)
automatically emit `targets::tar_make()` as the container command:

``` r

df_tar <- compile_dockerfile(sc, r_version = "4.4.1")
tail(df_tar$lines, 5)
#> [1] "COPY --chown=capsule:capsule . /capsule/"                                 
#> [2] "USER capsule"                                                             
#> [3] "HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \\"
#> [4] "    CMD Rscript -e \"quit(status = 0)\" || exit 1"                        
#> [5] "CMD [\"Rscript\", \"-e\", \"targets::tar_make()\"]"
```

## 2. Apple Silicon (`arm64`) vs. HPC (`amd64`) & Posit PPM Binaries

Developers on Apple Silicon laptops (`arm64`) frequently deploy
containers to `x86_64` cloud hosts or university HPC clusters (`amd64`).
[`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md)
records host architecture hints in `scan$architecture`, and both
[`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md)
and
[`compile_compose()`](https://marcusharrisphd.com/rcapsule/reference/compile_compose.md)
support explicit `platform` pinning plus Posit Package Manager
(`use_ppm = TRUE`) binary repositories:

``` r

sc$architecture
#> $host_arch
#> [1] "amd64"
#> 
#> $host_platform
#> [1] "x86_64-pc-linux-gnu"
#> 
#> $is_apple_silicon
#> [1] FALSE
#> 
#> $recommended_container_platform
#> [1] "linux/amd64"
#> 
#> $hpc_target_platform
#> [1] "linux/amd64"
#> 
#> $notes
#> character(0)

df_amd64 <- compile_dockerfile(
  sc,
  r_version  = "4.4.1",
  platform   = "linux/amd64",
  use_ppm    = TRUE,
  ppm_distro = "jammy",
  ppm_date   = "2026-01-15"
)

grep("^(FROM|    R_REPOS=)", df_amd64$lines, value = TRUE)
#> [1] "FROM --platform=linux/amd64 rocker/r-ver:4.4.1 AS builder"                  
#> [2] "    R_REPOS=https://packagemanager.posit.co/cran/__linux__/jammy/2026-01-15"
#> [3] "FROM --platform=linux/amd64 rocker/r-ver:4.4.1 AS runtime"
```

Passing `use_ppm = FALSE` switches back to source package snapshots when
compiling against custom system libraries or niche architectures.

## 3. Configuring Exact vs. Per-File Monte Carlo Tolerances

Deterministic summary tables should verify bit-for-bit
(`atol = 0, rtol = 0`), while MCMC posterior summaries or cross-BLAS
matrix decompositions may warrant explicit numeric tolerances.
[`compare_artifacts()`](https://marcusharrisphd.com/rcapsule/reference/compare_artifacts.md)
and
[`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md)
support nested JSON, RDS (including matrices, data frames, and
`NA`/`NaN`/`Inf` alignment), CSV, and TSV tolerances via `atol`/`rtol`
(or `abs_tol`/`rel_tol`):

``` r

f_ref <- tempfile(fileext = ".rds")
f_run <- tempfile(fileext = ".rds")

baseline <- list(
  posterior_mean = c(alpha = 1.2500, beta = -0.4000),
  cov_matrix = matrix(c(0.04, 0.01, 0.01, 0.09), nrow = 2),
  diagnostics = list(rhat = c(1.001, 1.002), divergent = 0L)
)
reproduced <- baseline
reproduced$posterior_mean <- c(alpha = 1.2503, beta = -0.3998)
reproduced$cov_matrix[1, 2] <- 0.0102

saveRDS(baseline, f_ref)
saveRDS(reproduced, f_run)

# Strict zero tolerance fails on SHA-256 mismatch
compare_artifacts(f_ref, f_run, atol = 0, rtol = 0)$status
#> [1] "mismatch"

# Explicit Monte Carlo tolerance passes and reports exact max observed error
res_mc <- compare_artifacts(f_ref, f_run, atol = 1e-3, rtol = 1e-3)
res_mc[c("status", "passed", "max_abs_diff", "max_rel_diff", "details")]
#> $status
#> [1] "within_tolerance"
#> 
#> $passed
#> [1] TRUE
#> 
#> $max_abs_diff
#> [1] 3e-04
#> 
#> $max_rel_diff
#> [1] 0.01960784
#> 
#> $details
#> [1] "Verified within tolerance (max_abs_diff=3e-04, max_rel_diff=0.01961)."
```

## 4. Handling Non-Deterministic Plot Metadata & Extra Artifacts

Binary PDF and PNG files often embed creation timestamps or
graphics-engine metadata that change SHA-256 digests across OS versions
even when the plotted data are identical. Best practice in `rcapsule`:

1.  **Always save the underlying numerical data table**
    (`results/fig1_data.csv` or `.rds`) alongside the rendered figure
    and register the numerical table in `outputs` with exact or
    tolerance bounds.
2.  **Use `strict_outputs = TRUE`** in
    [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md)
    during CI gating to catch scripts that unexpectedly drop temporary
    files or log artifacts into the workspace.
3.  **Keep ambient host secrets safe**:
    `verify_capsule(..., scrub_secrets = TRUE)` automatically strips
    `AWS_*`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, and other credential
    variables before executing the isolated sandbox.
