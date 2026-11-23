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
