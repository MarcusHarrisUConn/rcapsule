# Software Supply Chain (SBOM), Drift Diagnostics, and HPC/Audit Handoffs

## Overview

Modern regulatory submissions, institutional security reviews, and
reproducible open-science workflows require more than a container file:
they demand a machine-readable **Software Bill of Materials (SBOM)**,
**automated root-cause diagnostics** when verification runs diverge
across machines, and **clean handoff contracts** for HPC cluster
schedulers and external audit scripts.

This vignette walks through the v0.4.0 supply-chain and ecosystem
workflows in `rcapsule` — all running 100% offline with zero external
dependencies:

1.  **CycloneDX 1.5 SBOM generation & validation**
    ([`export_sbom()`](https://marcusharrisphd.com/rcapsule/reference/export_sbom.md),
    [`validate_sbom()`](https://marcusharrisphd.com/rcapsule/reference/validate_sbom.md)).
2.  **Automated reproducibility drift diagnostics**
    ([`diagnose_reproducibility()`](https://marcusharrisphd.com/rcapsule/reference/diagnose_reproducibility.md)).
3.  **Zero-dependency HPC & external audit handoff hooks**
    ([`as_apptainer_spec()`](https://marcusharrisphd.com/rcapsule/reference/as_apptainer_spec.md),
    [`verify_with_script()`](https://marcusharrisphd.com/rcapsule/reference/verify_with_script.md)).

## 1. Exporting and Validating a CycloneDX 1.5 SBOM

Let’s create a representative multi-language research repository using
spatial R packages (`sf`), Bayesian modeling (`cmdstanr`), Python
(`reticulate` + `requirements.txt`), a Quarto PDF manuscript, and an
`renv.lock` containing CRAN, GitHub, and Bioconductor remotes.

``` r

library(rcapsule)

proj <- tempfile("rcapsule_sbom_vig_")
dir.create(proj, recursive = TRUE)

writeLines(
  c(
    "library(sf)",
    "library(cmdstanr)",
    "library(reticulate)",
    "set.seed(2026L)",
    "write.csv(data.frame(param = c('alpha', 'beta'), est = c(1.25, -0.42)), 'summary.csv', row.names = FALSE)"
  ),
  file.path(proj, "run.R")
)
writeLines(c("numpy==1.26.4", "scipy>=1.11.0"), file.path(proj, "requirements.txt"))
writeLines(
  c("---", "title: 'Bayesian Spatial Study'", "format: pdf", "---", "", "```{r}", "1 + 1", "```"),
  file.path(proj, "manuscript.qmd")
)
jsonlite::write_json(
  list(
    R = list(Version = "4.4.2"),
    Packages = list(
      sf = list(
        Package = "sf", Version = "1.0-19", Source = "Repository",
        Repository = "CRAN", Hash = "0123456789abcdef0123456789abcdef"
      ),
      bayesutils = list(
        Package = "bayesutils", Version = "0.3.0", Source = "GitHub",
        RemoteType = "github", RemoteUsername = "StatLab",
        RemoteRepo = "bayesutils", RemoteSha = "9f86d081884c"
      ),
      Biobase = list(
        Package = "Biobase", Version = "2.64.0", Source = "Bioconductor",
        Repository = "BioCsoft"
      )
    )
  ),
  file.path(proj, "renv.lock"),
  auto_unbox = TRUE,
  pretty = TRUE
)
write.csv(
  data.frame(param = c("alpha", "beta"), est = c(1.25, -0.42)),
  file.path(proj, "summary.csv"),
  row.names = FALSE
)

manifest <- create_capsule_manifest(proj, outputs = "summary.csv", seed = 2026L)
sbom_path <- file.path(proj, "sbom.cdx.json")
sbom <- export_sbom(proj, manifest = manifest, output = sbom_path)
sbom
```

    #> 
    #> ── rcapsule CycloneDX 1.5 SBOM: rcapsule_sbom_vig_1e383e65acb7 ─────────────────
    #> • Serial number: "urn:uuid:66bea8cc-b2d5-4023-a647-256d134e6c58"
    #> • Total components: 38 (R=5, apt=25, PyPI=2, toolchains=6)
    #> • Dependencies graph entries: 4
    #> • Output file: /tmp/Rtmp5XRIRh/rcapsule_sbom_vig_1e383e65acb7/sbom.cdx.json

Every component carries a standardized Package URL (`purl`) spanning
CRAN, GitHub, Bioconductor, Debian `apt`, PyPI, and scientific
toolchains, and the root component binds cryptographically to
`capsule.json`’s `SHA-256` content digest:

``` r

head(vapply(sbom$bom$components, function(c) c$purl, character(1L)), 12L)
#>  [1] "pkg:generic/r@4.4.2"                       
#>  [2] "pkg:github/statlab/bayesutils@9f86d081884c"
#>  [3] "pkg:bioconductor/Biobase@2.64.0"           
#>  [4] "pkg:cran/cmdstanr"                         
#>  [5] "pkg:cran/reticulate"                       
#>  [6] "pkg:cran/sf@1.0-19"                        
#>  [7] "pkg:deb/debian/build-essential"            
#>  [8] "pkg:deb/debian/ca-certificates"            
#>  [9] "pkg:deb/debian/curl"                       
#> [10] "pkg:deb/debian/g%2B%2B"                    
#> [11] "pkg:deb/debian/gdal-bin"                   
#> [12] "pkg:deb/debian/libgdal-dev"

val <- validate_sbom(sbom_path)
val
#> 
#> ── CycloneDX SBOM Validation: VALID ────────────────────────────────────────────
#> • Format: "CycloneDX" | Spec version: "1.5"
#> • Components: 38 | Dependency entries: 4 | Errors: 0
```

## 2. Automated Reproducibility Drift Diagnostics

When a verification audit
([`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md))
or cross-machine comparison
([`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md))
detects divergence,
[`diagnose_reproducibility()`](https://marcusharrisphd.com/rcapsule/reference/diagnose_reproducibility.md)
classifies root causes — including manifest tampering, HMAC failure,
input/script drift, `CRLF` vs. `LF` line-ending changes, structural
schema drift, embedded PDF/PNG metadata changes, small Monte Carlo /
BLAS rounding drift, and unseeded large divergence — and outputs ranked
remediation steps.

### Example A: Detecting Windows `CRLF` vs. Unix `LF` Line-Ending Drift

``` r

crlf_proj <- tempfile("rcapsule_crlf_")
dir.create(crlf_proj)
writeLines(
  "writeLines(c('id,value', '1,3.14'), 'table.csv', sep = '\\n')",
  file.path(crlf_proj, "run.R")
)
# Reference artifact saved with Windows CRLF line endings
writeBin(charToRaw("id,value\r\n1,3.14\r\n"), file.path(crlf_proj, "table.csv"))

m_crlf <- create_capsule_manifest(crlf_proj, outputs = "table.csv", seed = 1L)
v_crlf <- verify_capsule(m_crlf, path = crlf_proj, runner = "sandbox")
diagnose_reproducibility(v_crlf)
#> 
#> ── rcapsule Reproducibility Diagnosis ──────────────────────────────────────────
#> • Source: "verification" | Status: "failed"
#> • Primary cause: "line_ending_drift" | Findings: 1
#> 
#> ── Ranked Root Causes ──
#> 
#> ! #1 [MEDIUM | line_ending_drift] table.csv: 'table.csv' differs exclusively in Windows CRLF vs Unix LF line endings.
#> Remediation: Normalize line endings with eol = '\n'
#> (write.table/writeLines(..., useBytes = TRUE)) and enforce '* text=auto eol=lf'
#> in .gitattributes.
```

### Example B: Distinguishing Small Monte Carlo Drift from Unseeded Divergence

``` r

mc_proj <- tempfile("rcapsule_mc_")
dir.create(mc_proj)
writeLines(
  "write.csv(data.frame(k = 1:3, est = c(1.0002, 2.0000, 3.0000)), 'out.csv', row.names = FALSE)",
  file.path(mc_proj, "run.R")
)
write.csv(
  data.frame(k = 1:3, est = c(1.0000, 2.0000, 3.0000)),
  file.path(mc_proj, "out.csv"),
  row.names = FALSE
)
m_mc <- create_capsule_manifest(mc_proj, outputs = "out.csv", seed = 10L)
v_mc <- verify_capsule(m_mc, path = mc_proj, runner = "sandbox")
diag_mc <- diagnose_reproducibility(v_mc, small_tol = 1e-2)
diag_mc$findings[, c("rank", "category", "severity", "affected")]
#> # A tibble: 1 × 4
#>    rank category                severity affected
#>   <int> <chr>                   <chr>    <chr>   
#> 1     1 monte_carlo_small_drift medium   out.csv
diag_mc$remediations
#> [1] "Likely caused by cross-architecture BLAS/LAPACK rounding, parallel thread reduction order, or MCMC floating-point jitter. Configure an explicit numeric tolerance (e.g., tolerances = list(atol = 4e-04, rtol = 4e-04)) or pin the container architecture with platform = 'linux/amd64'."
```

## 3. Zero-Dependency Ecosystem Handoff Hooks

### Exporting a Structured Apptainer Descriptor for HPC Orchestrators

HPC job schedulers (such as Slurm array runners) often need structured
container metadata — pinned base image, `%environment` variables, bind
mounts, runscript commands, and the `.def` recipe `SHA-256` — without
taking a hard dependency on `rcapsule`.
[`as_apptainer_spec()`](https://marcusharrisphd.com/rcapsule/reference/as_apptainer_spec.md)
provides a stable, plain-list-convertible handoff contract:

``` r

hpc_spec <- as_apptainer_spec(
  proj,
  bind_paths = c("/scratch", "/work", "/projects")
)
hpc_spec
#> 
#> ── rcapsule Apptainer Spec Descriptor: rcapsule_sbom_vig_1e383e65acb7 ──────────
#> • Base image: "rocker/r-ver:4.4.2" (Bootstrap: docker)
#> • Project type: "quarto" | R: "4.4.2" | Workdir: /capsule
#> • Entrypoint: "manuscript.qmd"
#> • Dependencies: 5 R pkg(s), 25 apt pkg(s), 2 Python pkg(s)
#> • Toolchains: cmdstan, cpp, latex, python, quarto
#> • HPC bind paths: /scratch, /work, /projects
#> • Recipe SHA-256: "18e0cc9034ec3876"...
plain_spec <- as.list(hpc_spec)
plain_spec[c("schema_version", "base_image", "toolchains", "bind_paths")]
#> $schema_version
#> [1] "1.0.0"
#> 
#> $base_image
#> [1] "rocker/r-ver:4.4.2"
#> 
#> $toolchains
#> [1] "cmdstan" "cpp"     "latex"   "python"  "quarto" 
#> 
#> $bind_paths
#> [1] "/scratch"  "/work"     "/projects"
```

### Running External Verification Scripts in a Secret-Scrubbed Sandbox

To integrate external statistical verification suites or custom reviewer
checks without risking mutation of the project directory or leakage of
host credentials (`AWS_*`, `GITHUB_TOKEN`, API keys), run any `.R`
script via
[`verify_with_script()`](https://marcusharrisphd.com/rcapsule/reference/verify_with_script.md):

``` r

audit_proj <- tempfile("rcapsule_ext_audit_")
dir.create(audit_proj)
write.csv(data.frame(group = c("A", "B"), mean = c(4.2, 6.8)), file.path(audit_proj, "results.csv"), row.names = FALSE)

ext_script <- tempfile("external_check_", fileext = ".R")
writeLines(
  c(
    "res <- read.csv('results.csv')",
    "stopifnot(nrow(res) == 2L, all(is.finite(res$mean)))",
    "writeLines(sprintf('verified_rows=%d', nrow(res)), 'audit_summary.txt')"
  ),
  ext_script
)

audit <- verify_with_script(
  script = ext_script,
  path = audit_proj,
  seed = 2026L,
  expected_outputs = "audit_summary.txt",
  scrub_secrets = TRUE
)
audit
#> 
#> ── rcapsule Isolated Script Audit: PASSED ──────────────────────────────────────
#> • Script: external_check_1e383c1389ec.R (SHA-256: 3a7f75bd059c...)
#> • Exit status: 0 | Duration: 0.127s | Scrubbed env vars: 41
#> • Created/modified artifacts: 1
#> 
#> ── Expected Output Checks ──
#> 
#> ✔ audit_summary.txt (16 bytes)
audit$artifacts
#> # A tibble: 1 × 5
#>   path              change  sha256                                  bytes format
#>   <chr>             <chr>   <chr>                                   <int> <chr> 
#> 1 audit_summary.txt created 9739d9077a1df1d068aa080e0fdccf1181110b…    16 text
```
