# Execute an External Verification or Audit Script Inside the Isolated Sandbox

Runs an arbitrary external or project-local R audit/verification script
(for example, a custom statistical consistency check, a `statci` CI
audit, or a peer-reviewer validation script) inside `rcapsule`'s clean,
path-confined, ambient-secret-scrubbed sandbox via
[`callr::rscript()`](https://callr.r-lib.org/reference/rscript.html).
Captures exit status, duration, `stdout`/`stderr`, scrubbed environment
variable names, SHA-256 hashes of every created or modified artifact,
and optional checks on expected output files.

## Usage

``` r
verify_with_script(
  script,
  path = ".",
  manifest = NULL,
  seed = NULL,
  rng_kind = RNGkind(),
  env_vars = list(),
  timeout = 300,
  scrub_secrets = TRUE,
  keep_sandbox = FALSE,
  expected_outputs = NULL,
  args = character()
)
```

## Arguments

- script:

  Path to an existing `.R` script to execute inside the sandbox (may
  reside outside `path`, e.g. a shared organizational audit script).

- path:

  Path to the project root directory to stage cleanly into the sandbox.
  Defaults to `"."`.

- manifest:

  Optional `rcapsule_manifest` object or path to `capsule.json` used to
  exclude previously generated outputs when staging the sandbox.

- seed:

  Optional integer RNG seed applied before sourcing `script`.

- rng_kind:

  Character vector of length 3 from
  [`base::RNGkind()`](https://rdrr.io/r/base/Random.html). Defaults to
  the current session's
  [`RNGkind()`](https://rdrr.io/r/base/Random.html).

- env_vars:

  Optional named list of explicit environment variables passed to the
  sandboxed script.

- timeout:

  Execution timeout in seconds (default `300`).

- scrub_secrets:

  Logical; if `TRUE` (default), strips ambient credential and token
  environment variables (`AWS_*`, `GITHUB_TOKEN`, `OPENAI_API_KEY`,
  `*_SECRET*`, `*_TOKEN*`, etc.) before executing `script`.

- keep_sandbox:

  Logical; if `TRUE`, retains the temporary sandbox directory on disk
  and returns its path in `sandbox_dir`. Defaults to `FALSE`.

- expected_outputs:

  Optional character vector of project-relative output paths expected to
  exist in the sandbox after `script` finishes.

- args:

  Optional character vector of string arguments forwarded to `script`
  via the `RCAPSULE_AUDIT_ARGS` environment variable (JSON array).

## Value

An S3 object of class `rcapsule_script_audit` containing `passed`,
`status` (`"passed"` or `"failed"`), `exit_status`, `duration_sec`,
`script`, `script_sha256`, `project_path`, `verified_at`, `rng`,
`scrubbed_env_vars`, `stdout`, `stderr`, `artifacts` (tibble of created
or modified files with `path`, `change`, `sha256`, `bytes`, `format`),
`expected_checks` (tibble checking `expected_outputs`), and
`sandbox_dir`.

## Examples

``` r
tmp <- tempfile("rcapsule_script_audit_")
dir.create(tmp)
write.csv(data.frame(x = 1:5), file.path(tmp, "data.csv"), row.names = FALSE)
audit_script <- tempfile("audit_", fileext = ".R")
writeLines(
  c("df <- read.csv('data.csv')",
    "stopifnot(nrow(df) == 5L)",
    "writeLines('audit_ok', 'audit_report.txt')"),
  audit_script
)
res <- verify_with_script(
  script = audit_script,
  path = tmp,
  seed = 42L,
  expected_outputs = "audit_report.txt"
)
res
#> 
#> ── rcapsule Isolated Script Audit: PASSED ──────────────────────────────────────
#> • Script: audit_19a979760bd0.R (SHA-256: e292fbf19c2c...)
#> • Exit status: 0 | Duration: 0.13s | Scrubbed env vars: 41
#> • Created/modified artifacts: 1
#> 
#> ── Expected Output Checks ──
#> 
#> ✔ audit_report.txt (9 bytes)
unlink(c(tmp, audit_script), recursive = TRUE)
```
