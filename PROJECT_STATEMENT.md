# NA

## Project 2: `rcapsule` — Reproducibility Capsules & Multi-Target Containerization for R

**Suggested GitHub Repo:** `rcapsule`  
**GitHub One-Liner:** *Compile any R project, Quarto manuscript, or
Shiny app into lean Docker/Apptainer containers with cryptographic
reproducibility verification.*  
**Topics:** `r-package`, `reproducibility`, `docker`, `apptainer`,
`containers`, `quarto`, `shiny`, `open-science`

### Project Statement

Computational reproducibility in R routinely breaks down at the boundary
between R and the operating system. While `renv` records R package
versions, projects still fail to reproduce across machines and over time
due to mismatched system libraries (`gdal`, `cmake`, `libxml2`), C++
toolchains, `CmdStan`, `TMB`, `JAGS`, `LaTeX`, or `reticulate`/Python
environments—and deploying a Shiny application cleanly with background
workers remains a steep DevOps hurdle for quantitative researchers.
Commercial reproducibility platforms solve part of this problem, but
lock researchers into proprietary hosted silos.

`rcapsule` is an open-source **reproducibility capsule compiler and
verifier** for R. It inspects any R analysis repo, Quarto manuscript, or
Shiny application, resolves the full stack of R packages, OS system
dependencies, and scientific toolchains, and compiles lean, reproducible
**Dockerfiles**, multi-service **`docker-compose.yml`** stacks, and
HPC-ready **Apptainer** definitions. Beyond building containers,
`rcapsule` provides a **cryptographic verification auditor**: it
executes the project inside a clean container, hashes inputs, seeds,
environment layers, and outputs into a signed `capsule.json` manifest,
and certifies whether published tables, figures, and numerical artifacts
reproduce bit-for-bit or within explicit Monte Carlo tolerances.

### Why Existing R Tools Aren’t Enough

- `renv` solves only the R library layer and breaks frequently on
  native/compiled scientific dependencies (`cmdstanr`, `sf`, `rJava`,
  `RTMB`, `Python`).
- `rix` (Nix) offers strong reproducibility but has a steep learning
  curve and poor compatibility with standard university HPC environments
  and Docker-first cloud hosts.
- `containerit` is largely stagnant and lacks modern Quarto, `CmdStan`,
  multi-service Shiny, Apptainer, and cryptographic verification
  auditing.

### Core Architectural Pillars

1.  **Full-Stack Project & Toolchain Scanner:** Parses R scripts,
    Quarto/Rmd chunks, `DESCRIPTION`, `renv.lock`, and Shiny entry
    points to map R dependencies, OS system libraries (`sysreqs`),
    compiled engines (`CmdStan`, `TMB`/`RTMB`, `JAGS`, `C++`),
    `Python`/`reticulate`, and `TinyTeX`/`LaTeX`.
2.  **Multi-Target Container Compiler:** Emits optimized, layer-cached
    multi-stage `Dockerfile`s, production `docker-compose.yml` templates
    (e.g., Shiny + worker queue + reverse proxy/healthchecks), and HPC
    Apptainer `.def` recipes with pinned base digests.
3.  **Cryptographic Provenance Manifest (`capsule.json`):** Records git
    commit, OS/R/toolchain digests, RNG seeds, and SHA-256 hashes of
    every data input and generated output artifact.
4.  **Reproducibility Verification Runner:** Runs the full analysis in a
    clean container (with a deterministic local sandbox/mock runner when
    Docker isn’t installed), compares outputs against the recorded
    manifest with exact and numeric-tolerance comparators, and renders
    an HTML/Markdown verification certificate suitable for journal peer
    review.

### v1 Definition of Done

- Accurate static scanner handling standard R scripts, Quarto
  manuscripts, Shiny apps, and `CmdStan`/`Rcpp` dependencies.
- Validated Dockerfile, `docker-compose.yml`, and Apptainer `.def`
  emitters with lint/snapshot tests.
- Working manifest generator and exact/tolerance diff verifier tested
  locally without requiring Docker (plus guarded live-Docker integration
  tests).
- Comprehensive `testthat` suite, `roxygen2` docs, vignettes, and clean
  `R CMD check`.

### New-Conversation Handoff Block

``` text
We are starting a new flagship, CRAN-grade R package in this repository: `rcapsule` — an open-source reproducibility capsule compiler and containerizer (Docker + Apptainer) for R projects, Quarto manuscripts, and Shiny apps.

Project mission: Go beyond `renv` by freezing the entire R + OS + scientific toolchain stack and cryptographically verifying computational reproducibility:
1. Full-stack project scanner inspecting R/Quarto/Shiny files, `DESCRIPTION`, and `renv.lock` to detect R packages, OS system libraries, C++/CmdStan/RTMB/JAGS toolchains, Python/reticulate, and LaTeX.
2. Multi-target container compiler generating cached multi-stage Dockerfiles, multi-service `docker-compose.yml` stacks (including Shiny + async worker templates), and HPC-compatible Apptainer `.def` recipes.
3. Cryptographic provenance manifest (`capsule.json`) recording environment digests, RNG seeds, and SHA-256 hashes of inputs/outputs.
4. Verification auditor that re-runs pipelines in isolated containers (with a deterministic local sandbox/mock runner so 100% of `testthat` tests pass on macOS even when Docker is unavailable, plus guarded live-Docker tests) and outputs a journal-ready reproducibility certificate.

Please start by inspecting this repo, designing the architecture (`ARCHITECTURE.md`) and phased build plan, and then we will build iteratively to full tests, vignettes, and a clean `R CMD check`.
```
