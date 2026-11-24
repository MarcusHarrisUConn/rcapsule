# rcapsule 0.4.0

## New Research-Workflow Capabilities (Zero New Dependencies)

- Added CycloneDX 1.5 Software Bill of Materials (SBOM) generation and validation via `export_sbom()` and `validate_sbom()`. Enumerates R packages (`pkg:cran/...`, `pkg:github/...`, `pkg:gitlab/...`, `pkg:bitbucket/...`, `pkg:bioconductor/...`) with `renv.lock` MD5 hashes, OS `apt` system libraries (`pkg:deb/debian/...`) linked to the R packages requiring them, Python packages (`pkg:pypi/...`), and compiled scientific toolchains (`R`, `CmdStan`, `Quarto`, `TinyTeX`, `JAGS`, `TMB/RTMB`, `C++`, `Rust`, `Python`, `OpenJDK`), cryptographically binding to `capsule.json`'s `SHA-256` content digest when provided.
- Added automated reproducibility drift diagnostics via `diagnose_reproducibility()` (with `print()` and `summary()` methods) supporting both `verify_capsule()` and `diff_capsules()` outputs. Classifies root causes (`hmac_signature_failure`, `manifest_tampering`, `execution_failure` with `stderr` clue parsing, `input_drift`, `script_drift`, `missing_output`, `line_ending_drift` detecting exact `CRLF` vs. `LF` equivalence, `schema_drift`, `binary_metadata_drift`, `monte_carlo_small_drift`, `unseeded_large_divergence`, `rng_drift`, `environment_or_arch_drift`, `unexpected_extra_artifacts`, `container_drift`, and `git_revision_drift`) into a severity-ranked tibble with actionable remediation steps.
- Added zero-dependency ecosystem handoff hooks:
  - `as_apptainer_spec()` exports a structured, plain-list-convertible Apptainer descriptor (`rcapsule_apptainer_spec`) containing pinned base image, `%environment` variables, HPC bind mount paths, `%runscript`/`%test` commands, and `.def` `SHA-256` digest for downstream HPC orchestrators.
  - `verify_with_script()` executes arbitrary external or project-local `.R` audit/verification scripts inside `rcapsule`'s path-confined, ambient-secret-scrubbed isolated sandbox, returning exit status, duration, `stdout`/`stderr`, scrubbed env vars, created/modified artifact `SHA-256` digests, and expected-output checks.

## Latent Bug Fixes & Coverage Hardening (`covr`)

- Fixed a false-positive equality bug in `compare_r_objects()` and `compare_data_frames()` where `factor` vs. `integer` (both sharing `typeof() == "integer"`) or `character` vs. `numeric` columns could silently compare equal after character coercion.
- Fixed a silent comparison gap in `compare_r_objects()` for lists containing duplicate or partially empty names, switching to exact positional comparison so duplicate/unnamed elements are never skipped.
- Fixed a macOS symlinked-root (`/var` -> `/private/var`) false security rejection in `assert_confined_path(..., must_exist = TRUE)` on non-existent confined absolute paths, and hardened parent-directory walks against dangling external symlinks (preventing uncaught `fs::dir_exists()` `ENOENT` errors).
- Enhanced `compare_artifacts()` and `diff_capsules()` to detect `CRLF` vs. `LF` line-ending-only diffs and populate diagnostic numeric/structural drift details even under exact zero-tolerance checks.
- Added a fifth executable vignette (`vignettes/sbom-and-supply-chain.Rmd`) and lifted overall test coverage past 93% via `covr`.

# rcapsule 0.3.0

## New Features & Real-World Hardening

- Added `diff_capsules()` to compare two `capsule.json` manifests across machines or runs (e.g., author laptop vs. HPC cluster or peer reviewer), reporting R/OS/platform/package/sysreq/toolchain drift, RNG and Git changes, and exact vs. numeric-tolerance output shifts with `print()` and `summary()` methods.
- Added `export_capsule_bundle()` to package `Dockerfile`, `docker-compose.yml`, `Apptainer.def`, `capsule.json`, Markdown/HTML verification certificates, confined project files, and an auto-generated `README_REPRODUCE.md` peer-review guide into a directory or zip-slip-safe ZIP archive via `zip::zipr()`.
- Added cross-architecture `platform` (`"linux/amd64"`, `"linux/arm64"`) support to `compile_dockerfile()`, `compile_compose()`, `build_capsule()`, and `export_capsule_bundle()`.
- Added Posit Public Package Manager binary repository mode (`use_ppm = TRUE`, `ppm_distro`, `ppm_date`) to `compile_dockerfile()` for faster reproducible Linux container builds.
- Expanded `scan_project()` for real-world project edge cases: `targets` pipeline detection (`_targets.R`, emitting `targets::tar_make()` in Dockerfiles/Apptainer), `here::here()` root marker detection, `.Rprofile` portability hazard auditing (custom `.libPaths()`, `setwd()`, local absolute paths, hardcoded secrets), zero-byte/binary/Unicode/whitespace filename inventories, and host architecture / Apple Silicon cross-build hints.

## CRAN Readiness, Documentation & Website

- Expanded documentation to 4 executable vignettes (`getting-started`, `multi-target-containers`, `journal-submission-workflow`, `troubleshooting-reproducibility`), added `inst/CITATION`, runnable examples in `inst/examples/`, `inst/WORDLIST` for zero-misspelling `spelling` checks, `cran-comments.md`, and GitHub Actions workflows (`.github/workflows/R-CMD-check.yaml` and `pkgdown.yaml`).
- Added `_pkgdown.yml` website configuration and a standalone PDF Reproducibility & Container Field Guide (`inst/guides/rcapsule-guide.Rmd`).
- Audited `DESCRIPTION` and all manual pages for strict `R CMD check --as-cran` compliance (`0 errors | 0 warnings | 0 notes`).

# rcapsule 0.2.0

## Security & Sandbox Hardening

- Added centralized validation, sanitization, path confinement, constant-time cryptography, environment scrubbing, and HTML/Markdown escaping in `R/security.R` (documented in `SECURITY.md`).
- Hardened `compile_dockerfile()`, `compile_compose()`, `compile_apptainer()`, and `resolve_sysreqs()` against shell, Dockerfile, YAML, and Apptainer `%post` injection via strict allowlists for R packages, Debian `apt` packages, Python PEP 508 specs, version strings, image references/digests, CRAN URLs, Linux usernames (rejecting `root`), workdirs, relative entrypoints, service names, env vars, and Compose volumes.
- Enforced strict project-root path-traversal and symlink-escape confinement in `scan_project()`, `create_capsule_manifest()`, and `verify_capsule()`, blocking `..`, external absolute paths, and external/dangling symlinks (`skipped_external_symlinks` recorded during scanning).
- Added automatic ambient secret scrubbing (`scrub_secrets = TRUE`) in `verify_capsule()` before launching `callr::rscript` sandboxes, removing `AWS_*`, `GITHUB_*`, `GH_*`, `OPENAI_*`, `ANTHROPIC_*`, `*_SECRET*`, `*_TOKEN*`, `*_PASSWORD*`, `*_API_KEY*`, and related credential variables while reporting scrubbed variable names (never values).
- Upgraded `constant_time_equal()` with explicit UTF-8 normalization, bitwise-OR byte comparison, and fixed-length SHA-256 fallback on length mismatch; applied constant-time verification across manifest, file, snapshot, and artifact SHA-256/HMAC checks.
- Added unexpected extra artifact detection (`extra_artifacts` and `strict_outputs = TRUE` mode) to `verify_capsule()`.
- Hardened `render_certificate()` against HTML/XSS and Markdown table injection (stripping `htmltools::HTML()` bypasses and adding a `Content-Security-Policy` meta tag to standalone HTML5 certificates) and disabled R `!expr` YAML evaluation (`eval.expr = FALSE`) across all YAML loaders.

## Scanner, Comparator & Linter Accuracy

- Expanded `scan_project()` AST extraction to detect `pacman::p_load()`, `pacman::p_load_gh()`, `xfun::pkg_attach()`, `xfun::pkg_attach2()`, `xfun::pkg_load2()`, and `box::use()` (ignoring relative `./` and `../` local modules), while ignoring comments, string literals, plain fenced Markdown blocks, and double-backtick verbatim spans.
- Preserved non-CRAN `renv.lock` provenance (`GitHub`, `GitLab`, `Bioconductor`, `URL`) in `scan$packages$source` and `scan$non_cran_packages`.
- Enhanced `compare_artifacts()` with `atol`/`rtol` aliases (alongside `abs_tol`/`rel_tol`), deeper recursive diffing for nested JSON/RDS lists, matrices/arrays (`dimnames` + `(row, col)` diagnostics), `Date`/`POSIXt`, `NA`/`NaN`/`+Inf`/`-Inf` alignment, and missing/extra column & key diagnostics.
- Expanded `lint_container_spec()` with `DF011`/`AP007` (`curl|sh` / `wget|bash`), `DC008` (`network_mode`/`pid`/`ipc: host`), `DC009` (dangerous host mounts like `docker.sock`), `AP008` (`--no-install-recommends` in `%post`), and broader baked-secret detection (`DF008`/`DC006`).

# rcapsule 0.1.0

- Initial CRAN-grade release of `rcapsule`: full-stack R/Quarto/Shiny/toolchain scanner (`scan_project()`, `sysreqs_db()`, `resolve_sysreqs()`), multi-target container compilers (`compile_dockerfile()`, `compile_compose()`, `compile_apptainer()`), static container linter (`lint_container_spec()`), cryptographic provenance manifest (`create_capsule_manifest()`, `sign_manifest()`, `verify_manifest_integrity()`), isolated reproducibility verifier (`verify_capsule()`, `compare_artifacts()`), journal-ready Markdown/HTML certificates (`render_certificate()`), and end-to-end `build_capsule()` orchestrator.
