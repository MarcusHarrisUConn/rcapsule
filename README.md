# rcapsule

> Compile any R project, Quarto manuscript, or Shiny app into lean Docker/Apptainer containers with cryptographic reproducibility verification.

`rcapsule` bridges the reproducibility gap between R package lockfiles (`renv.lock`) and the underlying operating system, native libraries, compiled scientific toolchains, and output verification required for durable open science and production deployment.

## Why `rcapsule`?

- **`renv` stops at the R library layer.** Projects still break across machines due to mismatched OS system libraries (`libgdal-dev`, `libxml2-dev`, `libharfbuzz-dev`), C++ compilers, `CmdStan`, `TMB`/`RTMB`, `JAGS`, `Rust`, `Python`/`reticulate`, `Quarto`, or `LaTeX`/`TinyTeX`.
- **Multi-target portability.** Researchers need clean multi-stage `Dockerfile`s for local/cloud runs, multi-service `docker-compose.yml` stacks for Shiny apps with background workers and reverse proxies, and HPC-ready Apptainer `.def` recipes for university clusters.
- **Cryptographic proof of reproducibility.** Rather than assuming a container reproduces published numbers, `rcapsule` hashes inputs, scripts, container definitions, seeds, environment layers, and outputs into a tamper-evident, optionally HMAC-SHA256-signed `capsule.json` manifest, re-runs the pipeline in an isolated environment, and renders a journal-ready verification certificate.

## Core Capabilities

| Pillar | Key Functions | What It Does |
| :--- | :--- | :--- |
| **1. Project & Toolchain Scanner** | `scan_project()`, `sysreqs_db()`, `resolve_sysreqs()` | Parses R scripts, Quarto/Rmd chunks, `DESCRIPTION`, `renv.lock`, `_quarto.yml`, Shiny apps, and native sources to map R packages, Debian/Ubuntu `apt` system libraries, and compiled toolchains (`C++`, `CmdStan`, `TMB`/`RTMB`, `JAGS`, `Rust`, `Java`, `Python`, `Quarto`, `LaTeX`). |
| **2. Multi-Target Container Compiler & Linter** | `compile_dockerfile()`, `compile_compose()`, `compile_apptainer()`, `lint_container_spec()` | Compiles pinned, layer-cached multi-stage Dockerfiles, production Shiny + worker + proxy Compose stacks, and HPC Apptainer `.def` recipes; statically audits specs for `:latest` tags, missing `apt` cleanup, root execution, hardcoded secrets, and cache-busting layer order. |
| **3. Cryptographic Provenance Manifest** | `create_capsule_manifest()`, `read_capsule_manifest()`, `write_capsule_manifest()`, `sign_manifest()`, `verify_manifest_integrity()` | Generates `capsule.json` (schema v1.0.0) with Git state, environment digest, RNG kind/seed, SHA-256 hashes of inputs/scripts/containers/outputs, canonical `content_digest`, and keyed HMAC-SHA256 signing via `openssl`. |
| **4. Reproducibility Auditor & Certificates** | `verify_capsule()`, `compare_artifacts()`, `render_certificate()`, `build_capsule()` | Re-runs pipelines cleanly in an isolated local sandbox (`callr::rscript`) or Docker container, compares outputs via exact SHA-256 or numeric tolerances (CSV/TSV/JSON/RDS), and renders Markdown + standalone HTML5 verification certificates. |

## Installation

```r
# Install development version from GitHub
# remotes::install_github("MarcusHarrisUConn/rcapsule")
```

## Quick Start

```r
library(rcapsule)

# 1. Inspect an R analysis project, Quarto manuscript, or Shiny app
sc <- scan_project("path/to/project")
sc

# 2. Compile & statically lint multi-target container definitions
df   <- compile_dockerfile(sc, output = "Dockerfile")
comp <- compile_compose(sc, output = "docker-compose.yml")
def  <- compile_apptainer(sc, output = "Apptainer.def")

lint_container_spec(df)
lint_container_spec(comp)
lint_container_spec(def)

# 3. Record a signed cryptographic provenance manifest
manifest <- create_capsule_manifest(
  path       = "path/to/project",
  inputs     = "data/raw.csv",
  outputs    = c("results/summary.csv", "results/metrics.json"),
  seed       = 2026L,
  tolerances = list(abs_tol = 1e-4, rel_tol = 1e-3),
  key        = Sys.getenv("CAPSULE_SIGNING_KEY"),
  output     = "capsule.json"
)

# 4. Run an isolated reproducibility audit and render a verification certificate
audit <- verify_capsule(
  manifest = "capsule.json",
  path     = "path/to/project",
  runner   = "sandbox", # or "docker" when Docker daemon is available
  key      = Sys.getenv("CAPSULE_SIGNING_KEY")
)

render_certificate(audit, output = "reproducibility_certificate", format = "both")
```

Or orchestrate every step in a single call with `build_capsule()`:

```r
bundle <- build_capsule(
  path        = "path/to/project",
  targets     = c("dockerfile", "compose", "apptainer"),
  inputs      = "data/raw.csv",
  outputs     = "results/summary.csv",
  seed        = 2026L,
  verify      = TRUE,
  certificate = TRUE
)
```

## Architecture & Vignettes

- See [ARCHITECTURE.md](ARCHITECTURE.md) for the full modular system design, `capsule.json` v1.0.0 schema, and sandbox vs. Docker isolation model.
- `vignette("getting-started", package = "rcapsule")`: End-to-end reproducibility capsules, HMAC signing, tamper detection, and tolerance-aware verification.
- `vignette("multi-target-containers", package = "rcapsule")`: Compiling Quarto manuscripts, production Shiny + async worker Compose stacks, and Bayesian HPC Apptainer recipes.

## License

MIT © 2026 Marcus Harris
