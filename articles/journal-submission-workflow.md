# Journal Submission & Peer-Review Reproducibility Workflow

## Overview

Many journals in statistics, biostatistics, economics, and ecology now
require a self-contained **computational reproducibility supplement**
alongside a submitted manuscript. A strong submission package must
answer four questions for peer reviewers and replication editors:

1.  **What exact software stack was used?** (R packages, OS libraries,
    compiled toolchains, target CPU architecture).
2.  **Have the inputs, scripts, and outputs been tampered with?**
    (Cryptographic `SHA-256` digests and optional `HMAC-SHA256`
    signatures).
3.  **Do the published results reproduce on another machine?**
    (Cross-run diffing with
    [`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md)
    and isolated execution with
    [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md)).
4.  **Can a reviewer unpack one archive and run one command?** (Bundling
    via
    [`export_capsule_bundle()`](https://marcusharrisphd.com/rcapsule/reference/export_capsule_bundle.md)
    with an auto-generated `README_REPRODUCE.md` and standalone
    HTML/Markdown certificates).

## 1. Stage a Realistic Author Study

Let’s simulate a quantitative study in a temporary directory that reads
clinical trial data and writes a summary table (`results/table1.csv`)
and model metrics (`results/fit_metrics.json`).

``` r

library(rcapsule)

study_dir <- tempfile("rcapsule_journal_study_")
dir.create(file.path(study_dir, "data"), recursive = TRUE)
dir.create(file.path(study_dir, "results"), recursive = TRUE)

trial <- data.frame(
  site = rep(c("A", "B", "C"), each = 4),
  arm = rep(c("control", "control", "treatment", "treatment"), times = 3),
  score = c(10.1, 9.9, 12.4, 12.0, 11.2, 10.8, 13.5, 13.1, 9.7, 10.3, 11.9, 12.3),
  stringsAsFactors = FALSE
)
write.csv(trial, file.path(study_dir, "data", "trial.csv"), row.names = FALSE)

writeLines(
  c(
    "library(jsonlite)",
    "dat <- read.csv('data/trial.csv', stringsAsFactors = FALSE)",
    "eps <- as.numeric(Sys.getenv('CROSS_PLATFORM_JITTER', '0'))",
    "fit <- lm(score ~ arm + site, data = dat)",
    "coefs <- summary(fit)$coefficients",
    "tbl <- data.frame(",
    "  term = rownames(coefs),",
    "  estimate = unname(coefs[, 'Estimate']) + eps,",
    "  std_error = unname(coefs[, 'Std. Error']),",
    "  stringsAsFactors = FALSE",
    ")",
    "dir.create('results', showWarnings = FALSE, recursive = TRUE)",
    "write.csv(tbl, 'results/table1.csv', row.names = FALSE)",
    "write_json(",
    "  list(n = nrow(dat), r_squared = summary(fit)$r.squared + eps),",
    "  'results/fit_metrics.json', auto_unbox = TRUE, digits = 10, pretty = TRUE",
    ")"
  ),
  file.path(study_dir, "analysis.R")
)

invisible(callr::rscript(
  script = NULL,
  cmdargs = c("-e", "set.seed(2026L); source('analysis.R')"),
  wd = study_dir,
  fail_on_status = TRUE,
  show = FALSE
))

read.csv(file.path(study_dir, "results", "table1.csv"))
#>           term estimate std_error
#> 1  (Intercept)    10.00 0.1500000
#> 2 armtreatment     2.20 0.1500000
#> 3        siteB     1.05 0.1837117
#> 4        siteC    -0.05 0.1837117
```

## 2. Build the Capsule & Sign the Provenance Manifest

Using
[`build_capsule()`](https://marcusharrisphd.com/rcapsule/reference/build_capsule.md),
we scan the repository, emit pinned `linux/amd64` containers (ideal for
x86_64 journal replication servers and HPC clusters), lint every spec,
sign `capsule.json` with `HMAC-SHA256`, verify reproducibility in an
isolated sandbox, and render certificates:

``` r

signing_key <- "replication-editor-hmac-key"

bundle <- build_capsule(
  path        = study_dir,
  targets     = c("dockerfile", "compose", "apptainer"),
  inputs      = "data/trial.csv",
  outputs     = c("results/table1.csv", "results/fit_metrics.json"),
  seed        = 2026L,
  tolerances  = list(atol = 1e-4, rtol = 1e-4),
  key         = signing_key,
  platform    = "linux/amd64",
  use_ppm     = TRUE,
  write       = TRUE,
  lint        = TRUE,
  verify      = TRUE,
  certificate = TRUE,
  metadata    = list(
    title   = "Multi-Site Clinical Trial Replication Package",
    journal = "Journal of Computational Statistics"
  )
)

bundle
#> 
#> ── rcapsule Bundle: rcapsule_journal_study_1c5335966a4f ────────────────────────
#> • Project type: "analysis" | Targets: dockerfile, compose, apptainer
#> • Lint status: dockerfile=PASS, compose=PASS, apptainer=PASS
#> • Manifest ID: "cap_ce79c1fc5979" (signed=TRUE)
#> • Verification: "verified_exact"
#> • Certificate: rendered
```

## 3. Diff Author vs. Reviewer Manifests with `diff_capsules()`

Suppose a peer reviewer executes the analysis on an x86_64 Linux cluster
running a slightly newer BLAS implementation that introduces a `5e-5`
floating-point shift in `table1.csv`. We can simulate the reviewer’s
manifest and compare both runs with
[`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md):

``` r

author_manifest <- bundle$manifest

# Simulate reviewer reproduction with minor cross-BLAS floating-point shift
reviewer_dir <- tempfile("rcapsule_reviewer_")
dir.create(file.path(reviewer_dir, "data"), recursive = TRUE)
file.copy(file.path(study_dir, "data", "trial.csv"), file.path(reviewer_dir, "data", "trial.csv"))
#> [1] TRUE
file.copy(file.path(study_dir, "analysis.R"), file.path(reviewer_dir, "analysis.R"))
#> [1] TRUE

invisible(callr::rscript(
  script = NULL,
  cmdargs = c("-e", "set.seed(2026L); source('analysis.R')"),
  wd = reviewer_dir,
  env = c(Sys.getenv(), CROSS_PLATFORM_JITTER = "0.00005"),
  fail_on_status = TRUE,
  show = FALSE
))

reviewer_manifest <- create_capsule_manifest(
  path       = reviewer_dir,
  inputs     = "data/trial.csv",
  outputs    = c("results/table1.csv", "results/fit_metrics.json"),
  seed       = 2026L,
  tolerances = list(atol = 1e-4, rtol = 1e-4)
)
# Annotate simulated Linux HPC platform metadata
reviewer_manifest$environment$platform <- "x86_64-pc-linux-gnu"
reviewer_manifest$environment$os <- "Linux 6.1.0"

diff_report <- diff_capsules(
  manifest_a = author_manifest,
  manifest_b = reviewer_manifest,
  label_a    = "Author (Laptop)",
  label_b    = "Reviewer (Linux HPC)"
)

diff_report
#> 
#> ── rcapsule Manifest Diff: OUTPUTS EQUIVALENT (DRIFT DETECTED) ─────────────────
#> • Baseline (A): "Author (Laptop)" (cap_ce79c1fc5979)
#> • Comparison (B): "Reviewer (Linux HPC)" (cap_88173bb50517)
#> • Environment drift: TRUE (R: 4.6.2 -> 4.6.2; platform: x86_64-pc-linux-gnu ->
#> x86_64-pc-linux-gnu)
#> • RNG drift: seed=2026 -> 2026
#> • Inputs drift: FALSE | Scripts drift: FALSE | Outputs equivalent: TRUE
#> 
#> ── Changed containers (3/3) ──
#> 
#> ✖ Apptainer.def [removed] - Artifact missing from second manifest.
#> ✖ docker-compose.yml [removed] - Artifact missing from second manifest.
#> ✖ Dockerfile [removed] - Artifact missing from second manifest.
#> 
#> ── Changed outputs (2/2) ──
#> 
#> ! results/fit_metrics.json [within_tolerance] - Verified within tolerance (max_abs_diff=5e-05, max_rel_diff=5.153e-05).
#> ! results/table1.csv [within_tolerance] - Verified within tolerance (max_abs_diff=5e-05, max_rel_diff=0.001).
summary(diff_report)
#> $identical
#> [1] FALSE
#> 
#> $outputs_equivalent
#> [1] TRUE
#> 
#> $has_env_drift
#> [1] TRUE
#> 
#> $n_package_changes
#> [1] 0
#> 
#> $n_input_changes
#> [1] 0
#> 
#> $n_script_changes
#> [1] 0
#> 
#> $n_container_changes
#> [1] 3
#> 
#> $n_output_changes
#> [1] 2
#> 
#> $n_outputs_within_tolerance
#> [1] 2
```

Notice how
[`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md)
highlights the platform/OS drift while confirming
`outputs_equivalent = TRUE` because the `5e-5` numerical shift falls
strictly within the declared `atol = 1e-4` bound.

## 4. Export a Zip-Slip-Safe Journal Supplement Bundle

Finally,
[`export_capsule_bundle()`](https://marcusharrisphd.com/rcapsule/reference/export_capsule_bundle.md)
packages `Dockerfile`, `docker-compose.yml`, `Apptainer.def`,
`capsule.json`, both Markdown and HTML5 verification certificates,
recorded inputs/scripts/outputs, and a tailored `README_REPRODUCE.md`
into a single archive ready for journal upload or Zenodo archival:

``` r

zip_dest <- file.path(tempdir(), "clinical_trial_supplement.zip")

exported <- export_capsule_bundle(
  path         = study_dir,
  output       = zip_dest,
  format       = "zip",
  manifest     = bundle$manifest,
  verification = bundle$verification,
  platform     = "linux/amd64",
  overwrite    = TRUE
)

exported
#> 
#> ── rcapsule Exported Supplement Bundle (zip) ───────────────────────────────────
#> • Destination: /tmp/Rtmpwl5oYS/clinical_trial_supplement.zip
#> • Capsule ID: "cap_ce79c1fc5979"
#> • Files bundled: 11 (9.7 KiB)
#> • Archive SHA-256: "31cc8cb2e690"
exported$files
#>  [1] "analysis.R"               "Apptainer.def"           
#>  [3] "capsule_certificate.html" "capsule_certificate.md"  
#>  [5] "capsule.json"             "data/trial.csv"          
#>  [7] "docker-compose.yml"       "Dockerfile"              
#>  [9] "README_REPRODUCE.md"      "results/fit_metrics.json"
#> [11] "results/table1.csv"
```
