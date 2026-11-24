# Changelog

## rcapsule 0.5.1

### Cross-Platform Windows & Linux CI Hardening

- Fixed a Windows UCRT locale bug in `build_sandbox_env()`
  (`R/verify.R`) where setting POSIX `LC_ALL = "C.UTF-8"` /
  `LANG = "C.UTF-8"` downgraded Windows child R sessions to a non-UTF-8
  `"C"` locale, altering RDS v3 header bytes during exact `SHA-256`
  verification of `.rds` artifacts.
- Fixed `build_docker_run_args()` (`R/verify.R`) to permit valid Windows
  drive-letter prefixes (`C:\...` / `C:/...`, slash-normalized for
  Docker mounts) while still rejecting any `:` elsewhere in
  `sandbox_dir`.
- Hardened `canonical_real_dir()`, `path_is_within_root()`, and
  `rel_path()` (`R/security.R`, `R/utils.R`) for Windows 8.3 short paths
  (`RUNNER~1` vs. long usernames), backslash normalization, and
  case-insensitive drive path comparisons.
- Hardened cross-platform test fixtures in `tests/testthat/` against
  Linux host platform/R version collisions (`test-v030-workflows.R`,
  `test-v040-sbom-diagnose-handoff.R`), Windows text-mode CRLF
  line-ending translation (`test-v040-sbom-diagnose-handoff.R`), Windows
  NTFS illegal filename characters (`test-peer-redteam.R`), and
  unprivileged Windows symlink creation (`test-adversarial-security.R`).

## rcapsule 0.5.0

### Security Hardening & Independent Peer Red-Team Remediation

Remediated all 16 confirmed findings (1 critical, 7 high, 6 medium, 2
low) from an independent peer red-team security, accuracy, and
cross-package interop audit, with permanent regression coverage in
`tests/testthat/test-peer-redteam.R`:

- **Eliminated `cli`/`glue` template injection (`CRITICAL-1`)**: Wrapped
  all dynamic messages across `print.rcapsule_lint()`,
  `print.rcapsule_verification()`, `print.rcapsule_diagnosis()`,
  `print.rcapsule_diff()`, `print.rcapsule_integrity()`, and
  `print.rcapsule_scan()` in single-level `{...}` placeholders so
  untrusted container specs, `renv.lock` entries, `capsule.json` fields,
  or diff diagnostics can never execute arbitrary R expressions during
  printing; also enforced strict version validation in
  `parse_renv_lock()`.
- **Sealed sandbox `.Renviron`, `.Rprofile`, `.netrc`, and `HOME`
  isolation (`HIGH-1`)**: Updated `stage_clean_sandbox()` to exclude
  `.Renviron`, `.Rprofile`, `.env`, `.env.*`, and `.netrc`; updated
  `build_sandbox_env()` to bind an isolated temporary `HOME`
  (`.rcapsule_home`) and neutralize `R_ENVIRON_USER`, `R_ENVIRON`,
  `R_PROFILE_USER`, `R_PROFILE`, and `NETRC`; passed
  `user_profile = FALSE`, `system_profile = FALSE`, and
  `cmdargs = c("--no-environ", "--no-init-file")` to
  [`callr::rscript()`](https://callr.r-lib.org/reference/rscript.html).
- **Stripped plaintext Git remote credentials (`HIGH-2`)**: Added
  `sanitize_git_remote_url()` in `detect_git_info()` to strip embedded
  HTTP(S) `userinfo@` tokens and SCP passwords before recording
  `scan$git$remote`, writing `capsule.json`, or exporting archival
  supplement bundles.
- **Closed silent false-positive verification gaps in
  [`compare_artifacts()`](https://marcusharrisphd.com/rcapsule/reference/compare_artifacts.md)
  (`HIGH-3`)**: Switched `compare_data_frames()` to positional column
  indexing (catching duplicate CSV/TSV column names), checked
  [`dim()`](https://rdrr.io/r/base/dim.html)/[`names()`](https://rdrr.io/r/base/names.html)/[`dimnames()`](https://rdrr.io/r/base/dimnames.html)
  on non-numeric matrices/arrays, compared factor
  [`levels()`](https://rdrr.io/r/base/levels.html) and
  [`is.ordered()`](https://rdrr.io/r/base/factor.html), checked
  `data.frame` `row.names`, `POSIXt` `tzone`, and S3 list `class` when
  `ignore_attributes = FALSE`, and distinguished empty JSON objects
  ([`{}`](https://rdrr.io/r/base/Paren.html)) from empty JSON arrays
  (`[]`).
- **Closed PCRE `$` trailing-newline bypasses (`HIGH-4`)**: Replaced
  `^...$` with `\A...\z` plus explicit ASCII control-character rejection
  across all `R/security.R` validators (including `env_vars` names) and
  `R/sbom.R` UUID/PURL/timestamp/hash validators.
- **Hardened `rcapsule` \<-\> HPC orchestrator interop (`HIGH-5`)**:
  Updated
  [`as_apptainer_spec()`](https://marcusharrisphd.com/rcapsule/reference/as_apptainer_spec.md)
  to return class `c("rcapsule_apptainer_spec", "rcapsule")`, expose
  both `bind_paths`/`binds`, both `def_sha256`/`content_digest`, an
  always-populated `sif_path`, and `def_path` preservation across all
  overrides (including `cran_repo`, `quarto_version`, `cmdstan_version`,
  and optional `output`); aligned
  [`compile_apptainer()`](https://marcusharrisphd.com/rcapsule/reference/compile_apptainer.md)
  return fields accordingly.
- **Hardened Docker verification CLI arguments (`HIGH-6`)**: Validated
  `docker_image` and `docker_tag` via `validate_docker_image_ref()`,
  rejected `:` in `sandbox_dir` volume mounts, and added
  `--network=none`, `--cap-drop=ALL`,
  `--security-opt=no-new-privileges:true`, and `Rscript --vanilla` in
  `build_docker_run_args()`.
- **Fixed higher-order AST scanning crash (`HIGH-7`)**: Guarded
  `parse_r_code_signals()` with `is.symbol(fn[[1L]])` and recursed into
  call heads so idioms like `scales::col_numeric("Blues", c(0, 1))(0.5)`
  parse cleanly and extract the package dependency.
- **Expanded ambient secret scrubbing (`MEDIUM-1`)**: Extended
  `secret_env_var_patterns()` to scrub `APIKEY`, `_PASS`, `_PWD`,
  `DATABASE_URL`, database `_(URL|URI|DSN|PASS|PWD|TOKEN|KEY)` vars,
  `CONN_STR`, `PGPASSFILE`, `NETRC`, `AUTHORIZATION`, `JWT`,
  `KUBECONFIG`, `PAT_*`, and `(SSH|HMAC|S3|GROQ|COHERE|...)_KEY`
  variables.
- **Hardened Compose volume validation, registry-port pinning, and
  service-name collision guards (`MEDIUM-2`, `MEDIUM-3`, `MEDIUM-4`)**:
  Normalized host path slashes and blocked sensitive host mounts (`/`,
  `/etc`, `/root`, `/proc`, `/sys`, `/dev`, `/var/run`, `/run`,
  `docker.sock`, `podman.sock`) plus malformed mounts in
  `validate_compose_volume()` and
  [`lint_container_spec()`](https://marcusharrisphd.com/rcapsule/reference/lint_container_spec.md);
  centralized `has_pinned_image_tag_or_digest()` across Dockerfile,
  Compose, and Apptainer compilers/linters so registry ports
  (`localhost:5000/img`) cannot bypass pinning; aborted cleanly when
  `service_name` collides with enabled `worker` or `proxy` companion
  services.
- **Hardened Markdown/HTML escaping (`MEDIUM-5`)**: Escaped backticks
  (`&#96;`) in `sanitize_markdown_cell()` and
  `sanitize_markdown_inline()` to prevent code-span breakout in
  certificates and applied `sanitize_markdown_inline()` to
  `included_files` in `README_REPRODUCE.md`.
- **Hardened CycloneDX SBOM parsing and validation (`MEDIUM-6`)**:
  Preserved pip `#egg=` fragments in `parse_requirements_txt()`, handled
  PEP 508 environment markers, direct URLs, and VCS URLs cleanly in
  `parse_pypi_spec()`/[`export_sbom()`](https://marcusharrisphd.com/rcapsule/reference/export_sbom.md),
  and guarded
  [`validate_sbom()`](https://marcusharrisphd.com/rcapsule/reference/validate_sbom.md)
  against atomic JSON elements in `hashes` and `dependencies`.
- **Fixed `renv.lock` atomic entry resilience, secret `.Rprofile`
  copying, and
  [`verify_with_script()`](https://marcusharrisphd.com/rcapsule/reference/verify_with_script.md)
  coercion warning (`LOW-1`, `LOW-2`)**: Guarded `parse_renv_lock()`
  against atomic entries, skipped `COPY .Rprofile ./` with a warning
  when `secret_in_rprofile` is detected in
  [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md),
  and coerced named character `env_vars` to list before appending
  `RCAPSULE_AUDIT_ARGS` in
  [`verify_with_script()`](https://marcusharrisphd.com/rcapsule/reference/verify_with_script.md).

## rcapsule 0.4.0

### New Research-Workflow Capabilities (Zero New Dependencies)

- Added CycloneDX 1.5 Software Bill of Materials (SBOM) generation and
  validation via
  [`export_sbom()`](https://marcusharrisphd.com/rcapsule/reference/export_sbom.md)
  and
  [`validate_sbom()`](https://marcusharrisphd.com/rcapsule/reference/validate_sbom.md).
  Enumerates R packages (`pkg:cran/...`, `pkg:github/...`,
  `pkg:gitlab/...`, `pkg:bitbucket/...`, `pkg:bioconductor/...`) with
  `renv.lock` MD5 hashes, OS `apt` system libraries
  (`pkg:deb/debian/...`) linked to the R packages requiring them, Python
  packages (`pkg:pypi/...`), and compiled scientific toolchains (`R`,
  `CmdStan`, `Quarto`, `TinyTeX`, `JAGS`, `TMB/RTMB`, `C++`, `Rust`,
  `Python`, `OpenJDK`), cryptographically binding to `capsule.json`’s
  `SHA-256` content digest when provided.
- Added automated reproducibility drift diagnostics via
  [`diagnose_reproducibility()`](https://marcusharrisphd.com/rcapsule/reference/diagnose_reproducibility.md)
  (with [`print()`](https://rdrr.io/r/base/print.html) and
  [`summary()`](https://rdrr.io/r/base/summary.html) methods) supporting
  both
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md)
  and
  [`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md)
  outputs. Classifies root causes (`hmac_signature_failure`,
  `manifest_tampering`, `execution_failure` with `stderr` clue parsing,
  `input_drift`, `script_drift`, `missing_output`, `line_ending_drift`
  detecting exact `CRLF` vs. `LF` equivalence, `schema_drift`,
  `binary_metadata_drift`, `monte_carlo_small_drift`,
  `unseeded_large_divergence`, `rng_drift`, `environment_or_arch_drift`,
  `unexpected_extra_artifacts`, `container_drift`, and
  `git_revision_drift`) into a severity-ranked tibble with actionable
  remediation steps.
- Added zero-dependency ecosystem handoff hooks:
  - [`as_apptainer_spec()`](https://marcusharrisphd.com/rcapsule/reference/as_apptainer_spec.md)
    exports a structured, plain-list-convertible Apptainer descriptor
    (`rcapsule_apptainer_spec`) containing pinned base image,
    `%environment` variables, HPC bind mount paths, `%runscript`/`%test`
    commands, and `.def` `SHA-256` digest for downstream HPC
    orchestrators.
  - [`verify_with_script()`](https://marcusharrisphd.com/rcapsule/reference/verify_with_script.md)
    executes arbitrary external or project-local `.R` audit/verification
    scripts inside `rcapsule`’s path-confined, ambient-secret-scrubbed
    isolated sandbox, returning exit status, duration,
    `stdout`/`stderr`, scrubbed env vars, created/modified artifact
    `SHA-256` digests, and expected-output checks.

### Latent Bug Fixes & Coverage Hardening (`covr`)

- Fixed a false-positive equality bug in `compare_r_objects()` and
  `compare_data_frames()` where `factor` vs. `integer` (both sharing
  `typeof() == "integer"`) or `character` vs. `numeric` columns could
  silently compare equal after character coercion.
- Fixed a silent comparison gap in `compare_r_objects()` for lists
  containing duplicate or partially empty names, switching to exact
  positional comparison so duplicate/unnamed elements are never skipped.
- Fixed a macOS symlinked-root (`/var` -\> `/private/var`) false
  security rejection in `assert_confined_path(..., must_exist = TRUE)`
  on non-existent confined absolute paths, and hardened parent-directory
  walks against dangling external symlinks (preventing uncaught
  [`fs::dir_exists()`](https://fs.r-lib.org/reference/file_access.html)
  `ENOENT` errors).
- Enhanced
  [`compare_artifacts()`](https://marcusharrisphd.com/rcapsule/reference/compare_artifacts.md)
  and
  [`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md)
  to detect `CRLF` vs. `LF` line-ending-only diffs and populate
  diagnostic numeric/structural drift details even under exact
  zero-tolerance checks.
- Added a fifth executable vignette
  (`vignettes/sbom-and-supply-chain.Rmd`) and lifted overall test
  coverage past 93% via `covr`.

## rcapsule 0.3.0

### New Features & Real-World Hardening

- Added
  [`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md)
  to compare two `capsule.json` manifests across machines or runs (e.g.,
  author laptop vs. HPC cluster or peer reviewer), reporting
  R/OS/platform/package/sysreq/toolchain drift, RNG and Git changes, and
  exact vs. numeric-tolerance output shifts with
  [`print()`](https://rdrr.io/r/base/print.html) and
  [`summary()`](https://rdrr.io/r/base/summary.html) methods.
- Added
  [`export_capsule_bundle()`](https://marcusharrisphd.com/rcapsule/reference/export_capsule_bundle.md)
  to package `Dockerfile`, `docker-compose.yml`, `Apptainer.def`,
  `capsule.json`, Markdown/HTML verification certificates, confined
  project files, and an auto-generated `README_REPRODUCE.md` peer-review
  guide into a directory or zip-slip-safe ZIP archive via
  [`zip::zipr()`](https://r-lib.github.io/zip/reference/zip.html).
- Added cross-architecture `platform` (`"linux/amd64"`, `"linux/arm64"`)
  support to
  [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md),
  [`compile_compose()`](https://marcusharrisphd.com/rcapsule/reference/compile_compose.md),
  [`build_capsule()`](https://marcusharrisphd.com/rcapsule/reference/build_capsule.md),
  and
  [`export_capsule_bundle()`](https://marcusharrisphd.com/rcapsule/reference/export_capsule_bundle.md).
- Added Posit Public Package Manager binary repository mode
  (`use_ppm = TRUE`, `ppm_distro`, `ppm_date`) to
  [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md)
  for faster reproducible Linux container builds.
- Expanded
  [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md)
  for real-world project edge cases: `targets` pipeline detection
  (`_targets.R`, emitting `targets::tar_make()` in
  Dockerfiles/Apptainer), `here::here()` root marker detection,
  `.Rprofile` portability hazard auditing (custom
  [`.libPaths()`](https://rdrr.io/r/base/libPaths.html),
  [`setwd()`](https://rdrr.io/r/base/getwd.html), local absolute paths,
  hardcoded secrets), zero-byte/binary/Unicode/whitespace filename
  inventories, and host architecture / Apple Silicon cross-build hints.

### CRAN Readiness, Documentation & Website

- Expanded documentation to 4 executable vignettes (`getting-started`,
  `multi-target-containers`, `journal-submission-workflow`,
  `troubleshooting-reproducibility`), added `inst/CITATION`, runnable
  examples in `inst/examples/`, `inst/WORDLIST` for zero-misspelling
  `spelling` checks, `cran-comments.md`, and GitHub Actions workflows
  (`.github/workflows/R-CMD-check.yaml` and `pkgdown.yaml`).
- Added `_pkgdown.yml` website configuration and a standalone PDF
  Reproducibility & Container Field Guide
  (`inst/guides/rcapsule-guide.Rmd`).
- Audited `DESCRIPTION` and all manual pages for strict
  `R CMD check --as-cran` compliance
  (`0 errors | 0 warnings | 0 notes`).

## rcapsule 0.2.0

### Security & Sandbox Hardening

- Added centralized validation, sanitization, path confinement,
  constant-time cryptography, environment scrubbing, and HTML/Markdown
  escaping in `R/security.R` (documented in `SECURITY.md`).
- Hardened
  [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md),
  [`compile_compose()`](https://marcusharrisphd.com/rcapsule/reference/compile_compose.md),
  [`compile_apptainer()`](https://marcusharrisphd.com/rcapsule/reference/compile_apptainer.md),
  and
  [`resolve_sysreqs()`](https://marcusharrisphd.com/rcapsule/reference/resolve_sysreqs.md)
  against shell, Dockerfile, YAML, and Apptainer `%post` injection via
  strict allowlists for R packages, Debian `apt` packages, Python PEP
  508 specs, version strings, image references/digests, CRAN URLs, Linux
  usernames (rejecting `root`), workdirs, relative entrypoints, service
  names, env vars, and Compose volumes.
- Enforced strict project-root path-traversal and symlink-escape
  confinement in
  [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md),
  [`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md),
  and
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md),
  blocking `..`, external absolute paths, and external/dangling symlinks
  (`skipped_external_symlinks` recorded during scanning).
- Added automatic ambient secret scrubbing (`scrub_secrets = TRUE`) in
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md)
  before launching
  [`callr::rscript`](https://callr.r-lib.org/reference/rscript.html)
  sandboxes, removing `AWS_*`, `GITHUB_*`, `GH_*`, `OPENAI_*`,
  `ANTHROPIC_*`, `*_SECRET*`, `*_TOKEN*`, `*_PASSWORD*`, `*_API_KEY*`,
  and related credential variables while reporting scrubbed variable
  names (never values).
- Upgraded `constant_time_equal()` with explicit UTF-8 normalization,
  bitwise-OR byte comparison, and fixed-length SHA-256 fallback on
  length mismatch; applied constant-time verification across manifest,
  file, snapshot, and artifact SHA-256/HMAC checks.
- Added unexpected extra artifact detection (`extra_artifacts` and
  `strict_outputs = TRUE` mode) to
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md).
- Hardened
  [`render_certificate()`](https://marcusharrisphd.com/rcapsule/reference/render_certificate.md)
  against HTML/XSS and Markdown table injection (stripping
  [`htmltools::HTML()`](https://rstudio.github.io/htmltools/reference/HTML.html)
  bypasses and adding a `Content-Security-Policy` meta tag to standalone
  HTML5 certificates) and disabled R `!expr` YAML evaluation
  (`eval.expr = FALSE`) across all YAML loaders.

### Scanner, Comparator & Linter Accuracy

- Expanded
  [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md)
  AST extraction to detect `pacman::p_load()`, `pacman::p_load_gh()`,
  [`xfun::pkg_attach()`](https://rdrr.io/pkg/xfun/man/pkg_attach.html),
  [`xfun::pkg_attach2()`](https://rdrr.io/pkg/xfun/man/pkg_attach.html),
  [`xfun::pkg_load2()`](https://rdrr.io/pkg/xfun/man/pkg_attach.html),
  and `box::use()` (ignoring relative `./` and `../` local modules),
  while ignoring comments, string literals, plain fenced Markdown
  blocks, and double-backtick verbatim spans.
- Preserved non-CRAN `renv.lock` provenance (`GitHub`, `GitLab`,
  `Bioconductor`, `URL`) in `scan$packages$source` and
  `scan$non_cran_packages`.
- Enhanced
  [`compare_artifacts()`](https://marcusharrisphd.com/rcapsule/reference/compare_artifacts.md)
  with `atol`/`rtol` aliases (alongside `abs_tol`/`rel_tol`), deeper
  recursive diffing for nested JSON/RDS lists, matrices/arrays
  (`dimnames` + `(row, col)` diagnostics), `Date`/`POSIXt`,
  `NA`/`NaN`/`+Inf`/`-Inf` alignment, and missing/extra column & key
  diagnostics.
- Expanded
  [`lint_container_spec()`](https://marcusharrisphd.com/rcapsule/reference/lint_container_spec.md)
  with `DF011`/`AP007` (`curl|sh` / `wget|bash`), `DC008`
  (`network_mode`/`pid`/`ipc: host`), `DC009` (dangerous host mounts
  like `docker.sock`), `AP008` (`--no-install-recommends` in `%post`),
  and broader baked-secret detection (`DF008`/`DC006`).

## rcapsule 0.1.0

- Initial CRAN-grade release of `rcapsule`: full-stack
  R/Quarto/Shiny/toolchain scanner
  ([`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md),
  [`sysreqs_db()`](https://marcusharrisphd.com/rcapsule/reference/sysreqs_db.md),
  [`resolve_sysreqs()`](https://marcusharrisphd.com/rcapsule/reference/resolve_sysreqs.md)),
  multi-target container compilers
  ([`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md),
  [`compile_compose()`](https://marcusharrisphd.com/rcapsule/reference/compile_compose.md),
  [`compile_apptainer()`](https://marcusharrisphd.com/rcapsule/reference/compile_apptainer.md)),
  static container linter
  ([`lint_container_spec()`](https://marcusharrisphd.com/rcapsule/reference/lint_container_spec.md)),
  cryptographic provenance manifest
  ([`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md),
  [`sign_manifest()`](https://marcusharrisphd.com/rcapsule/reference/sign_manifest.md),
  [`verify_manifest_integrity()`](https://marcusharrisphd.com/rcapsule/reference/verify_manifest_integrity.md)),
  isolated reproducibility verifier
  ([`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md),
  [`compare_artifacts()`](https://marcusharrisphd.com/rcapsule/reference/compare_artifacts.md)),
  journal-ready Markdown/HTML certificates
  ([`render_certificate()`](https://marcusharrisphd.com/rcapsule/reference/render_certificate.md)),
  and end-to-end
  [`build_capsule()`](https://marcusharrisphd.com/rcapsule/reference/build_capsule.md)
  orchestrator.
