# Verify Computational Reproducibility Against a Capsule Manifest

Audits a recorded `capsule.json` manifest by:

1.  Verifying cryptographic manifest integrity (`content_digest` and
    optional HMAC-SHA256 signature).

2.  Verifying SHA-256 hashes of all recorded inputs and scripts.

3.  Staging a clean isolated workspace strictly excluding previously
    generated outputs and re-executing the pipeline in either a
    deterministic local sandbox (`runner = "sandbox"` via
    [`callr::rscript()`](https://callr.r-lib.org/reference/rscript.html))
    or a live Docker container (`runner = "docker"`).

4.  Comparing every freshly generated output against the manifest using
    exact SHA-256 comparison and configured numeric-tolerance
    comparators for CSV, TSV, JSON, and RDS artifacts.

## Usage

``` r
verify_capsule(
  manifest,
  path = ".",
  runner = c("sandbox", "docker"),
  entrypoint = NULL,
  seed = NULL,
  tolerances = NULL,
  key = NULL,
  env_vars = list(),
  timeout = 300,
  docker_image = NULL,
  docker_tag = NULL,
  keep_sandbox = FALSE,
  reference_dir = NULL,
  strict_outputs = FALSE,
  scrub_secrets = TRUE
)
```

## Arguments

- manifest:

  An `rcapsule_manifest` object or file path to `capsule.json`.

- path:

  Path to the project root directory. Defaults to `"."`.

- runner:

  Execution isolation backend: `"sandbox"` (default; runs locally in a
  clean temporary directory via
  [`callr::rscript`](https://callr.r-lib.org/reference/rscript.html)
  without requiring a Docker daemon) or `"docker"` (executes inside a
  Docker container).

- entrypoint:

  Optional runnable script/document override (defaults to
  `manifest$project$entrypoint`).

- seed:

  Optional RNG seed override (defaults to `manifest$rng$seed`).

- tolerances:

  Optional tolerance override (same structure accepted by
  [`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md)).
  Defaults to `manifest$tolerances`.

- key:

  Optional HMAC-SHA256 key to verify a signed manifest.

- env_vars:

  Optional named list of extra environment variables passed to the
  isolated run.

- timeout:

  Execution timeout in seconds (default `300`).

- docker_image:

  Optional pre-built Docker image reference for `runner = "docker"`. If
  `NULL`, builds from `Dockerfile` in `path`.

- docker_tag:

  Optional tag used when building the Docker image.

- keep_sandbox:

  Logical; if `TRUE`, retains the temporary sandbox directory on disk
  and records its path for debugging. Defaults to `FALSE`.

- reference_dir:

  Optional directory containing verified baseline output files for
  numeric-tolerance comparison (defaults to `path`; only used if a
  baseline file's SHA-256 matches the manifest).

- strict_outputs:

  Logical; if `TRUE`, fails verification when the pipeline produces
  unexpected extra artifacts not declared in
  `manifest$artifacts$outputs`. Defaults to `FALSE` (extra artifacts are
  still detected and reported in `extra_artifacts`).

- scrub_secrets:

  Logical; if `TRUE` (default), strips ambient credential and token
  environment variables (`AWS_*`, `GITHUB_TOKEN`, `GH_TOKEN`,
  `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `*_SECRET*`, `*_TOKEN*`, etc.)
  before launching the isolated sandbox subprocess.

## Value

An S3 object of class `rcapsule_verification` containing `status`
(`"verified_exact"`, `"verified_within_tolerance"`, or `"failed"`),
`passed` (logical), `runner`, `verified_at`, `duration_sec`,
`exit_status`, `manifest_integrity`, `input_checks`, `script_checks`,
`output_checks`, `extra_artifacts`, `scrubbed_env_vars`,
`failure_reasons`, `rng`, `environment`, `stdout`, `stderr`,
`sandbox_dir`, and `manifest`.

## Examples

``` r
tmp <- tempfile("rcapsule_verify_")
dir.create(tmp)
writeLines(
  c("df <- data.frame(id = 1:3, val = rnorm(3))",
    "write.csv(df, 'result.csv', row.names = FALSE)"),
  file.path(tmp, "run.R")
)
set.seed(123)
write.csv(data.frame(id = 1:3, val = rnorm(3)), file.path(tmp, "result.csv"), row.names = FALSE)
m <- create_capsule_manifest(tmp, outputs = "result.csv", seed = 123L)
res <- verify_capsule(m, path = tmp, runner = "sandbox")
res$status
#> [1] "verified_exact"
unlink(tmp, recursive = TRUE)
```
