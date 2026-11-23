# `rcapsule` Architecture

## 1. Mission & Design Principles

`rcapsule` bridges the reproducibility gap between R package lockfiles (`renv.lock`) and the underlying operating system, native libraries, compiled scientific toolchains, and output verification required for durable open science and production deployment.

Design principles:
1. **Deterministic & Offline-First**: Static scanning, system dependency resolution, container compilation, linting, cryptographic manifest generation, and local sandbox verification all execute deterministically with zero external network calls required.
2. **Composable S3 Pipeline**: Every stage produces a transparent, inspectable S3 object (`rcapsule_scan`, `rcapsule_spec`, `rcapsule_lint`, `rcapsule_manifest`, `rcapsule_verification`, `rcapsule_certificate`) that can be used independently or orchestrated end-to-end via `build_capsule()`.
3. **Security & Reproducibility by Default**: Generated containers pin explicit base image tags/digests (never `:latest`), clean apt caches, order dependency layers ahead of source code for Docker layer caching, drop root privileges (`USER capsule`), and support `no-new-privileges` in multi-service stacks.
4. **Verifiable Provenance**: Every capsule manifest (`capsule.json`) is canonicalized and hashed (`content_digest`) with optional keyed HMAC-SHA256 signing (`openssl::sha256`), enabling tamper detection across metadata, environment specs, seeds, inputs, scripts, container definitions, and generated outputs.
5. **Tolerance-Aware Scientific Auditing**: Reproducibility checks fast-path exact SHA-256 matches and fall back to structured numeric-tolerance comparators for tabular (`csv`/`tsv`), `json`, and `rds` outputs (handling floating-point BLAS differences and Monte Carlo tolerances transparently).

---

## 2. System Dataflow

```text
Project Directory (R scripts, .qmd/.Rmd, app.R, DESCRIPTION, renv.lock, _quarto.yml, src/)
        │
        ▼
┌──────────────────────────────────────────────────────────┐
│ 1. Full-Stack Project & Toolchain Scanner                │
│    scan_project()  ──►  rcapsule_scan                    │
│    - AST + regex R code parsing (scripts & doc chunks)   │
│    - DESCRIPTION / renv.lock / _quarto.yml / Shiny scan  │
│    - Built-in sysreqs DB + SystemRequirements resolution │
│    - Compiled toolchains: C++, CmdStan, TMB, JAGS, Rust, │
│      Java, Python/reticulate, Quarto, TinyTeX/LaTeX      │
└──────────────┬─────────────────────────┬─────────────────┘
               │                         │
               ▼                         ▼
┌───────────────────────────────────┐   ┌──────────────────────────────────────┐
│ 2. Multi-Target Container Compiler│   │ 3. Cryptographic Provenance Manifest │
│    - compile_dockerfile()         │   │    create_capsule_manifest()         │
│    - compile_compose()            │   │    - Canonical capsule.json v1.0.0   │
│    - compile_apptainer()          │   │    - Git commit/branch/dirty state   │
│    - lint_container_spec()        │   │    - R/OS/sysreqs/toolchain digest   │
│      (DF*, DC*, AP* rules)        │   │    - RNG kind & seed                 │
│                                   │   │    - SHA-256 of inputs/scripts/      │
│                                   │   │      containers/outputs              │
│                                   │   │    - Content digest & HMAC-SHA256    │
└──────────────┬────────────────────┘   └──────────────────┬───────────────────┘
               │                                           │
               └───────────────────┬───────────────────────┘
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. Isolated Reproducibility Verification Auditor & Certificate Renderer │
│    verify_capsule(manifest, runner = "sandbox" | "docker")              │
│    - Verifies manifest content_digest & optional HMAC signature         │
│    - Verifies input & script SHA-256 hashes before execution            │
│    - Executes pipeline cleanly in isolated temp sandbox (callr::rscript)│
│      or Docker container (outputs excluded from working copy)           │
│    - Compares regenerated outputs via exact SHA-256 or numeric          │
│      tolerance comparators (CSV, TSV, JSON, RDS)                        │
│    - render_certificate() ──► Journal-ready Markdown + standalone HTML  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Module Architecture

| Module (`R/`) | Public API | Responsibility |
| :--- | :--- | :--- |
| `R/utils.R` | `docker_available()`, `apptainer_available()` | Path normalization, git metadata inspection, canonical JSON serialization, safe subprocess wrappers (`processx`), base R package filtering. |
| `R/sysreqs.R` | `sysreqs_db()`, `resolve_sysreqs()` | Built-in curated OS apt/rpm system dependency registry covering spatial (`sf`, `terra`, `units`), web/crypto (`curl`, `xml2`, `openssl`), graphics (`ragg`, `magick`, `pdftools`), database (`RPostgres`, `arrow`), and scientific toolchains (`Rcpp`, `cmdstanr`, `RTMB`, `rjags`, `rextendr`, `reticulate`). Supports user overrides and `DESCRIPTION` `SystemRequirements` parsing. |
| `R/scanner.R` | `scan_project()` | Recursive project walker and static analyzer. Parses R code via `parse()` (with safe regex fallback), extracts fenced code chunks and YAML frontmatter from `.qmd`/`.Rmd`, inspects `DESCRIPTION`, `renv.lock`, `_quarto.yml`, Shiny entry points (`app.R`, `ui.R`/`server.R`), native `src/` files, `.stan`/`.jags` models, and `requirements.txt`. Classifies project type (`analysis`, `quarto`, `rmarkdown`, `shiny`, `package`) and resolves toolchains + sysreqs. |
| `R/compile_dockerfile.R` | `compile_dockerfile()` | Emits layer-cached single- or multi-stage `Dockerfile`s with pinned Rocker base image tags (and optional `@sha256:` digests), sorted `apt-get` layers with `--no-install-recommends` and list cleanup, toolchain install layers (Quarto, TinyTeX, Python venv, CmdStan, Rust/JAGS), cache-friendly `renv::restore()` / CRAN snapshot installs, non-root `USER`, `HEALTHCHECK`, OCI labels, and type-aware `ENTRYPOINT`/`CMD`. |
| `R/compile_compose.R` | `compile_compose()` | Emits validated multi-service `docker-compose.yml` stacks. Supports production Shiny deployments (`app` + async `worker` + pinned reverse `proxy` with healthchecks, internal network, read-only input volumes, named output volumes, resource limits, and `no-new-privileges`) as well as batch analysis/Quarto execution stacks. |
| `R/compile_apptainer.R` | `compile_apptainer()` | Emits HPC-compatible Apptainer/Singularity `.def` recipes (`Bootstrap: docker`, pinned `From:`, `%labels`, `%files`, `%environment`, `%post` with `set -euo pipefail`, `%runscript`, `%test`) configured for non-root HPC execution and standard scratch/data bind points. |
| `R/lint.R` | `lint_container_spec()` | Static security and reproducibility linter for Dockerfiles (`DF001`–`DF010`), Compose files (`DC001`–`DC007`), and Apptainer definitions (`AP001`–`AP006`). Detects `:latest` tags, missing apt cache cleanup, root-only containers, cache-busting `COPY` ordering, hardcoded secrets, privileged mode, and missing `%post` error guards. |
| `R/manifest.R` | `create_capsule_manifest()`, `read_capsule_manifest()`, `write_capsule_manifest()`, `sign_manifest()`, `verify_manifest_integrity()` | Builds, serializes, signs, and validates `capsule.json` (schema v1.0.0). Computes deterministic `environment_digest`, file SHA-256 hashes, optional embedded reference snapshots for tolerance checking, canonical `content_digest` for tamper detection, and keyed HMAC-SHA256 signatures via `openssl`. |
| `R/comparators.R` | `compare_artifacts()` | Dual-stage artifact comparator: fast-path SHA-256 exact match, followed by structured numeric-tolerance comparisons (`abs_tol + rel_tol * max(|a|, |b|)`) for CSV, TSV, JSON, and RDS objects with per-column/per-path diagnostics and max observed error reporting. |
| `R/verify.R` | `verify_capsule()` | End-to-end reproducibility auditor. Checks manifest integrity and input/script hashes, executes the project in an isolated clean temporary sandbox (`callr::rscript` with controlled `TZ`, locale, RNG kind/seed, and excluded stale outputs) or a live Docker container, compares all regenerated outputs, and returns a structured `rcapsule_verification` verdict. |
| `R/certificate.R` | `render_certificate()` | Renders journal-ready Markdown and self-contained HTML5 reproducibility certificates (built via `htmltools` with full HTML escaping, status badges, hash tables, tolerance metrics, and print CSS). |
| `R/capsule.R` | `build_capsule()` | High-level orchestrator chaining `scan_project()`, container compilation, linting, manifest creation, optional verification, and optional certificate rendering into one reproducible workflow. |

---

## 4. `capsule.json` Cryptographic Schema (v1.0.0)

```json
{
  "schema_version": "1.0.0",
  "rcapsule_version": "0.1.0",
  "capsule_id": "cap_<12-hex-chars>",
  "created_at": "2026-11-23T19:58:43Z",
  "project": {
    "name": "my-study",
    "type": "analysis",
    "entrypoint": "analysis.R",
    "git": {
      "is_repo": true,
      "commit": "<40-hex-sha>",
      "branch": "main",
      "dirty": false,
      "remote": "https://..."
    }
  },
  "environment": {
    "r_version": "4.6.1",
    "platform": "aarch64-apple-darwin23",
    "os": "macOS ...",
    "locale": "C.UTF-8",
    "packages": [{ "package": "dplyr", "version": "1.2.1", "source": "installed" }],
    "sysreqs": ["libcurl4-openssl-dev", "libssl-dev"],
    "toolchains": ["cpp", "cmdstan"],
    "environment_digest": "<sha256-hex>"
  },
  "rng": {
    "seed": 42,
    "kind": ["Mersenne-Twister", "Inversion", "Rejection"]
  },
  "artifacts": {
    "inputs": [{ "path": "data/raw.csv", "sha256": "...", "bytes": 1024, "format": "csv" }],
    "scripts": [{ "path": "analysis.R", "sha256": "...", "bytes": 512, "format": "r" }],
    "containers": [{ "path": "Dockerfile", "sha256": "...", "bytes": 1400, "format": "dockerfile" }],
    "outputs": [{ "path": "results/summary.csv", "sha256": "...", "bytes": 256, "format": "csv" }]
  },
  "tolerances": {
    "default": { "abs_tol": 0, "rel_tol": 0 },
    "files": {
      "results/posterior.csv": { "abs_tol": 1e-4, "rel_tol": 1e-3 }
    }
  },
  "snapshots": {},
  "metadata": {},
  "integrity": {
    "algorithm": "sha256",
    "signature_algorithm": "hmac-sha256",
    "content_digest": "<sha256-of-canonical-body>",
    "signed": true,
    "signature": "<hmac-sha256-hex>"
  }
}
```

Tamper verification guarantees:
- **Canonical Digest (`content_digest`)**: Any modification to any field in `project`, `environment`, `rng`, `artifacts`, `tolerances`, `snapshots`, or `metadata` alters the canonical JSON representation and immediately fails `verify_manifest_integrity()`.
- **Keyed Signature (`signature`)**: When signed with a secret or CI release key via HMAC-SHA256 (`openssl::sha256(body, key = key)`), an attacker cannot forge a valid `content_digest` + `signature` pair after altering recorded output hashes or loosening tolerances.

---

## 5. Sandbox vs. Live Docker Execution Model

To guarantee deterministic, offline-capable testing on macOS, Linux, and CI runners without requiring a privileged Docker daemon:
- **`runner = "sandbox"` (default in local verification & unit tests)**:
  1. Stages an isolated temp directory containing only verified `inputs`, `scripts`, and project configuration files (`outputs` are strictly omitted).
  2. Executes the entrypoint in a fresh `callr::rscript` child process with normalized `TZ=UTC`, `LC_ALL=C.UTF-8`, isolated `R_USER_CACHE_DIR`, and deterministic RNG initialization (`RNGkind()` + `set.seed()`).
  3. Captures exit code, wall-clock duration, stdout, and stderr, then compares freshly generated outputs against the manifest.
- **`runner = "docker"`**:
  1. Verifies Docker daemon reachability (`docker info`) via `docker_available()`.
  2. Builds (or uses a pre-built) container image from `Dockerfile` and runs the staged clean workspace mounted inside the container with `--rm` and UTC timezone.
  3. Guarded in `testthat` with `skip_if_not(docker_available())` so tests never fail when Docker is unavailable.
