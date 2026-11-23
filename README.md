# rcapsule

> Compile any R project, Quarto manuscript, `targets` pipeline, or Shiny app into lean Docker/Apptainer containers with cryptographic reproducibility verification.

`rcapsule` bridges the reproducibility gap between R package lockfiles (`renv.lock`) and the underlying operating system, native libraries, compiled scientific toolchains, cross-architecture builds, and output verification required for durable open science and production deployment.

- **Documentation website:** <https://marcusharrisphd.com/rcapsule/>
- **Source repository:** <https://github.com/MarcusHarrisUConn/rcapsule>

## Why `rcapsule`?

- **`renv` stops at the R library layer.** Projects still break across machines due to mismatched OS system libraries (`libgdal-dev`, `libxml2-dev`, `libharfbuzz-dev`), C++ compilers, `CmdStan`, `TMB`/`RTMB`, `JAGS`, `Rust`, `Python`/`reticulate`, `Quarto`, `LaTeX`/`TinyTeX`, or hidden `.Rprofile` traps.
- **Multi-target & cross-architecture portability.** Compile pinned, Posit PPM binary-accelerated multi-stage `Dockerfile`s (with `--platform=linux/amd64` / `linux/arm64` support), production multi-service `docker-compose.yml` stacks (Shiny + async worker + reverse proxy), and HPC-ready Apptainer `.def` recipes from a single project scan.
- **Cryptographic proof & peer-review bundles.** Hash inputs, scripts, container specs, seeds, environment digests, and outputs into a tamper-evident, optionally `HMAC-SHA256`-signed `capsule.json`, verify in an isolated sandbox (with ambient secret scrubbing) or Docker container, compare runs across machines with `diff_capsules()`, and export zip-slip-safe journal supplements via `export_capsule_bundle()`.

## Core Capabilities

| Pillar | Key Functions | What It Does |
| :--- | :--- | :--- |
| **1. Project & Toolchain Scanner** | `scan_project()`, `sysreqs_db()`, `resolve_sysreqs()` | Parses R scripts (`library`, `pacman::p_load`, `xfun::pkg_attach`, `box::use`, `::`), Quarto/Rmd chunks, `DESCRIPTION`, `renv.lock` (including non-CRAN remotes), `_targets.R`, `here::here()`, `.Rprofile` hazards, and host architecture to resolve OS `apt` libraries and toolchains (`C++`, `CmdStan`, `TMB`/`RTMB`, `JAGS`, `Rust`, `Java`, `Python`, `Quarto`, `LaTeX`). |
| **2. Multi-Target Container Compiler & Linter** | `compile_dockerfile()`, `compile_compose()`, `compile_apptainer()`, `lint_container_spec()` | Emits pinned, layer-cached multi-stage Dockerfiles (`platform`, Posit PPM binaries), hardened Shiny + worker + proxy Compose stacks, and HPC Apptainer `.def` recipes; statically audits specs for `:latest` tags, `curl\|sh`, root execution, `network_mode: host`, `docker.sock` mounts, and baked secrets. |
| **3. Cryptographic Provenance & Cross-Run Diffing** | `create_capsule_manifest()`, `read_capsule_manifest()`, `write_capsule_manifest()`, `sign_manifest()`, `verify_manifest_integrity()`, `diff_capsules()` | Generates canonical UTF-8 `capsule.json` (schema v1.0.0) with Git state, environment digest, RNG kind/seed, `SHA-256` hashes, and constant-time `HMAC-SHA256` verification; diffs runs across machines (`Laptop` vs. `HPC`). |
| **4. Isolated Auditor, Certificates & Bundler** | `verify_capsule()`, `compare_artifacts()`, `render_certificate()`, `export_capsule_bundle()`, `build_capsule()` | Re-runs pipelines in an isolated local sandbox (scrubbing ambient host credentials and detecting extra artifacts) or Docker container, compares CSV/TSV/JSON/RDS outputs with exact and `atol`/`rtol` comparators, renders CSP-hardened HTML5/Markdown certificates, and packages journal-ready ZIP supplements. |

## Installation

```r
# Install development version from GitHub
# remotes::install_github("MarcusHarrisUConn/rcapsule")
```

## Quick Start

```r
library(rcapsule)

# 1. Scan, compile (pinned linux/amd64 + Posit PPM binaries), lint, sign, and verify
bundle <- build_capsule(
  path        = "path/to/project",
  targets     = c("dockerfile", "compose", "apptainer"),
  inputs      = "data/raw.csv",
  outputs     = c("results/summary.csv", "results/metrics.json"),
  seed        = 2026L,
  tolerances  = list(atol = 1e-4, rtol = 1e-4),
  key         = Sys.getenv("CAPSULE_SIGNING_KEY"),
  platform    = "linux/amd64",
  use_ppm     = TRUE,
  verify      = TRUE,
  certificate = TRUE
)

# 2. Compare manifests across runs or machines
diff_capsules("author_capsule.json", "reviewer_capsule.json")

# 3. Export a zip-slip-safe journal peer-review supplement bundle
export_capsule_bundle(
  path         = "path/to/project",
  output       = "journal_supplement.zip",
  manifest     = bundle$manifest,
  verification = bundle$verification,
  platform     = "linux/amd64"
)
```

## Vignettes & Guides

- `vignette("getting-started", package = "rcapsule")`: End-to-end reproducibility capsules, HMAC signing, tamper detection, and tolerance-aware verification.
- `vignette("multi-target-containers", package = "rcapsule")`: Compiling Quarto manuscripts, production Shiny + async worker Compose stacks, and Bayesian HPC Apptainer recipes.
- `vignette("journal-submission-workflow", package = "rcapsule")`: Signed peer-review capsules, cross-machine `diff_capsules()`, and `export_capsule_bundle()`.
- `vignette("troubleshooting-reproducibility", package = "rcapsule")`: Monte Carlo `atol`/`rtol` tolerances, `.Rprofile` traps, `targets` pipelines, and Apple Silicon vs. `amd64` builds.
- See [ARCHITECTURE.md](ARCHITECTURE.md) and [SECURITY.md](SECURITY.md) for architecture and red-team security details.

## License

MIT © 2026 Marcus Harris
