# End-to-End Reproducibility Capsules with rcapsule

## Overview

`rcapsule` turns an R project into a verifiable **reproducibility
capsule**:

1.  **Scan** the repository for R packages, OS system dependencies
    (`sysreqs`), and compiled scientific toolchains.
2.  **Compile** pinned, layer-cached container specifications
    (`Dockerfile`, `docker-compose.yml`, `Apptainer.def`) and **lint**
    them for security and reproducibility best practices.
3.  **Record** a tamper-evident, optionally HMAC-SHA256-signed
    `capsule.json` provenance manifest hashing every input, script,
    container definition, and generated output.
4.  **Verify** reproducibility by re-executing the analysis in an
    isolated clean sandbox (or Docker container) and comparing outputs
    bit-for-bit or within explicit numeric tolerances, rendering a
    journal-ready verification certificate.

## 1. Create a Minimal Reproducible Study

Let’s construct a self-contained demo analysis inside a temporary
directory that reads an input CSV, runs a seeded Monte Carlo
calculation, and writes both tabular (`CSV`) and structured (`JSON`)
outputs.

``` r

library(rcapsule)

proj_dir <- tempfile("rcapsule_vignette_study_")
dir.create(file.path(proj_dir, "data"), recursive = TRUE)
dir.create(file.path(proj_dir, "results"), recursive = TRUE)

# Input dataset
raw_data <- data.frame(
  arm = c("control", "control", "control", "treatment", "treatment", "treatment"),
  outcome = c(10.2, 9.8, 10.5, 12.1, 11.9, 12.6),
  stringsAsFactors = FALSE
)
write.csv(raw_data, file.path(proj_dir, "data", "trial_data.csv"), row.names = FALSE)

# Analysis script
writeLines(
  c(
    "library(jsonlite)",
    "dat <- read.csv('data/trial_data.csv', stringsAsFactors = FALSE)",
    "eps <- as.numeric(Sys.getenv('SIM_JITTER', '0'))",
    "ctrl <- dat$outcome[dat$arm == 'control']",
    "trt  <- dat$outcome[dat$arm == 'treatment']",
    "boot_diffs <- replicate(200, mean(sample(trt, replace = TRUE)) - mean(sample(ctrl, replace = TRUE)))",
    "summary_tbl <- data.frame(",
    "  metric = c('diff_mean', 'boot_mean', 'boot_sd'),",
    "  value  = c(mean(trt) - mean(ctrl) + eps, mean(boot_diffs) + eps, sd(boot_diffs)),",
    "  stringsAsFactors = FALSE",
    ")",
    "dir.create('results', showWarnings = FALSE, recursive = TRUE)",
    "write.csv(summary_tbl, 'results/summary.csv', row.names = FALSE)",
    "write_json(",
    "  list(n = nrow(dat), diff_mean = mean(trt) - mean(ctrl) + eps, boot_mean = mean(boot_diffs) + eps),",
    "  'results/metrics.json', auto_unbox = TRUE, digits = 10, pretty = TRUE",
    ")"
  ),
  file.path(proj_dir, "run.R")
)

# Generate baseline outputs with a fixed seed
invisible(callr::rscript(
  script = NULL,
  cmdargs = c("-e", "set.seed(2026L); source('run.R')"),
  wd = proj_dir,
  fail_on_status = TRUE,
  show = FALSE
))

read.csv(file.path(proj_dir, "results", "summary.csv"))
#>      metric     value
#> 1 diff_mean 2.0333333
#> 2 boot_mean 2.0480000
#> 3   boot_sd 0.2719461
```

## 2. Scan the Full Dependency Stack

[`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md)
inspects scripts, lockfiles, and configuration files to identify R
packages, OS system dependencies, and scientific toolchains:

``` r

sc <- scan_project(proj_dir)
sc
#> 
#> ── rcapsule Project Scan: rcapsule_vignette_study_1be91d7c0046 ─────────────────
#> • Path: /tmp/Rtmp8Kk0TL/rcapsule_vignette_study_1be91d7c0046
#> • Project type: "analysis" (roles: analysis)
#> • R version: "4.6.2" | renv.lock: FALSE | DESCRIPTION: FALSE
#> • Entrypoint: "run.R"
#> • Files scanned: 4
#> 
#> ── R Packages (1 non-base) ──
#> 
#> jsonlite@2.0.0
#> 
#> ── Detected Toolchains (0) ──
#> 
#> Standard R runtime only
#> 
#> ── OS System Dependencies (0 apt packages) ──
#> 
#> None required
```

## 3. Compile and Lint Container Specifications

We can compile a multi-stage `Dockerfile` and an HPC `Apptainer.def`
recipe, then statically lint both to confirm zero errors or warnings:

``` r

df <- compile_dockerfile(sc, output = file.path(proj_dir, "Dockerfile"), r_version = "4.4.1")
def <- compile_apptainer(sc, output = file.path(proj_dir, "Apptainer.def"), r_version = "4.4.1")

lint_container_spec(df)
#> 
#> ── rcapsule Container Lint (dockerfile): PASS ──────────────────────────────────
#> Errors: 0 | Warnings: 0 | Info: 0
#> ✔ No issues found.
lint_container_spec(def)
#> 
#> ── rcapsule Container Lint (apptainer): PASS ───────────────────────────────────
#> Errors: 0 | Warnings: 0 | Info: 0
#> ✔ No issues found.
```

## 4. Create a Cryptographically Signed Provenance Manifest

[`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md)
records environment metadata, RNG configuration, SHA-256 digests of
every input, script, container file, and output artifact, plus an
optional keyed HMAC-SHA256 signature:

``` r

signing_key <- "journal-peer-review-demo-key"

manifest <- create_capsule_manifest(
  path       = proj_dir,
  inputs     = "data/trial_data.csv",
  outputs    = c("results/summary.csv", "results/metrics.json"),
  seed       = 2026L,
  tolerances = list(abs_tol = 1e-3, rel_tol = 1e-3),
  metadata   = list(title = "Randomized Trial Bootstrap Study", author = "M. Harris"),
  key        = signing_key,
  output     = file.path(proj_dir, "capsule.json")
)

manifest
#> 
#> ── rcapsule Provenance Manifest (cap_c8c2ec7e5920) ─────────────────────────────
#> • Schema: "1.0.0" | Created: "2026-11-24T19:32:35Z"
#> • Project: "rcapsule_vignette_study_1be91d7c0046" (analysis) | Entrypoint:
#> "run.R"
#> • Git: not a git repository
#> • Environment: R 4.6.2 | Digest: "528f6e0170b4"
#> • RNG: seed=2026 | kind=Mersenne-Twister/Inversion/Rejection
#> • Artifacts: 1 inputs, 1 scripts, 2 containers, 2 outputs
#> • Integrity: digest="927321c8edc3" | signed=TRUE
verify_manifest_integrity(file.path(proj_dir, "capsule.json"), key = signing_key)
#> 
#> ── rcapsule Manifest Integrity: VALID ──────────────────────────────────────────
#> • Content digest: OK (927321c8edc3)
#> • Signed: TRUE | Signature check: TRUE
```

If anyone tampers with a recorded output hash or loosens tolerances
after signing,
[`verify_manifest_integrity()`](https://marcusharrisphd.com/rcapsule/reference/verify_manifest_integrity.md)
immediately detects the forgery:

``` r

tampered <- manifest
tampered$artifacts$outputs[[1]]$sha256 <- paste(rep("0", 64), collapse = "")
verify_manifest_integrity(tampered, key = signing_key)
#> 
#> ── rcapsule Manifest Integrity: INVALID ────────────────────────────────────────
#> • Content digest: MISMATCH (1eeb2d0a2bab)
#> • Signed: TRUE | Signature check: FALSE
#> ✖ Content digest mismatch (manifest was modified): recorded=927321c8edc3, computed=1eeb2d0a2bab
#> ✖ HMAC-SHA256 signature verification failed (invalid key or tampered manifest).
```

## 5. Exact & Numeric-Tolerance Verification in an Isolated Sandbox

To prove that outputs are genuinely reproducible from scratch rather
than stale artifacts left on disk, we delete `results/` completely and
run `verify_capsule(..., runner = "sandbox")`:

``` r

unlink(file.path(proj_dir, "results"), recursive = TRUE)

audit_exact <- verify_capsule(
  manifest = file.path(proj_dir, "capsule.json"),
  path     = proj_dir,
  runner   = "sandbox",
  key      = signing_key
)

audit_exact
#> 
#> ── rcapsule Verification Audit: VERIFIED (EXACT SHA-256) ───────────────────────
#> • Capsule: "cap_c8c2ec7e5920" (rcapsule_vignette_study_1be91d7c0046)
#> • Runner: "sandbox" | Entrypoint: "run.R" | Exit: 0 (0.193s)
#> • Manifest integrity: VALID
#> • Inputs verified: 1/1
#> • Scripts verified: 1/1
#> • Outputs verified: 2/2
#> 
#> ── Output Artifacts ──
#> 
#> ✔ results/metrics.json [exact_match] - Exact SHA-256 bit-for-bit match.
#> ✔ results/summary.csv [exact_match] - Exact SHA-256 bit-for-bit match.
```

Now suppose cross-platform BLAS or parallel MCMC execution introduces a
small `2e-4` numerical perturbation within the declared `1e-3`
tolerance:

``` r

audit_tol <- verify_capsule(
  manifest = file.path(proj_dir, "capsule.json"),
  path     = proj_dir,
  runner   = "sandbox",
  key      = signing_key,
  env_vars = list(SIM_JITTER = "0.0002")
)

audit_tol
#> 
#> ── rcapsule Verification Audit: VERIFIED (WITHIN TOLERANCE) ────────────────────
#> • Capsule: "cap_c8c2ec7e5920" (rcapsule_vignette_study_1be91d7c0046)
#> • Runner: "sandbox" | Entrypoint: "run.R" | Exit: 0 (0.192s)
#> • Manifest integrity: VALID
#> • Inputs verified: 1/1
#> • Scripts verified: 1/1
#> • Outputs verified: 2/2
#> 
#> ── Output Artifacts ──
#> 
#> ✔ results/metrics.json [within_tolerance] - Verified within tolerance (max_abs_diff=2e-04, max_rel_diff=9.835e-05).
#> ✔ results/summary.csv [within_tolerance] - Verified within tolerance (max_abs_diff=2e-04, max_rel_diff=9.835e-05).
```

## 6. Render Journal-Ready Verification Certificates

[`render_certificate()`](https://marcusharrisphd.com/rcapsule/reference/render_certificate.md)
exports both GitHub-Flavored Markdown and a self-contained HTML5
certificate suitable for journal supplementary materials:

``` r

cert <- render_certificate(
  audit_exact,
  output = file.path(proj_dir, "reproducibility_certificate"),
  format = "both"
)

cert
#> 
#> ── rcapsule Verification Certificate ───────────────────────────────────────────
#> • Title: "Reproducibility Verification Certificate:
#> rcapsule_vignette_study_1be91d7c0046"
#> • Verdict: "VERIFIED (EXACT)"
#> • Markdown: 1959 chars
#> • HTML: 8893 chars
#> • Files:
#> /tmp/Rtmp8Kk0TL/rcapsule_vignette_study_1be91d7c0046/reproducibility_certificate.md,
#> /tmp/Rtmp8Kk0TL/rcapsule_vignette_study_1be91d7c0046/reproducibility_certificate.html
cat(substr(cert$markdown, 1, 900), "...\n")
#> # Reproducibility Verification Certificate: rcapsule_vignette_study_1be91d7c0046
#> 
#> > **Verification Verdict:** **VERIFIED (EXACT)**  
#> > **Capsule ID:** `cap_c8c2ec7e5920` | **Verified At:** `2026-11-24T19:32:35Z` | **Runner:** `sandbox` (0.193s)
#> 
#> ## 1. Provenance & Environment Summary
#> 
#> | Field | Recorded Value |
#> | :--- | :--- |
#> | Project | `rcapsule_vignette_study_1be91d7c0046` (`analysis`) |
#> | Entrypoint | `run.R` |
#> | Git Revision | Not a Git repository |
#> | Manifest R Version | `4.6.2` |
#> | Verification Host | R `4.6.2` on `x86_64-pc-linux-gnu` (`Linux 7.0.0-1020-azure`) |
#> | Environment Digest | `528f6e0170b4` |
#> | Detected Toolchains | Standard R |
#> | OS System Libraries | 0 apt packages |
#> | RNG Configuration | Seed `2026` (`Mersenne-Twister / Inversion / Rejection`) |
#> | Ambient Secrets Scrubbed | 41 variable(s) |
#> | Unexpected Extra Artifacts | 0 file(s) |
#> | Execution Exit Status | `0` |
#> 
#>  ...
```
