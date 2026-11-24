# Create a Cryptographic Provenance Manifest (`capsule.json`)

Records a complete, tamper-evident provenance manifest for a
computational R project. Captures schema version, Git
commit/branch/dirty state, R/OS/locale metadata, resolved R packages, OS
system dependencies, detected scientific toolchains, RNG kind and seed,
SHA-256 hashes of inputs, scripts, container definitions, and output
artifacts, numeric tolerance policies, and optional embedded reference
snapshots. Computes a canonical SHA-256 `content_digest` and an optional
keyed HMAC-SHA256 signature via `openssl`.

## Usage

``` r
create_capsule_manifest(
  path = ".",
  scan = NULL,
  inputs = NULL,
  scripts = NULL,
  outputs = NULL,
  containers = NULL,
  entrypoint = NULL,
  seed = NULL,
  rng_kind = RNGkind(),
  tolerances = NULL,
  metadata = list(),
  embed_snapshots = TRUE,
  max_snapshot_bytes = 262144L,
  key = NULL,
  output = NULL
)
```

## Arguments

- path:

  Path to the project root directory. Defaults to `"."`.

- scan:

  Optional pre-computed `rcapsule_scan` object. If `NULL`, calls
  [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md)
  on `path`.

- inputs:

  Optional character vector of input data file or directory paths
  (relative to `path` or absolute).

- scripts:

  Optional character vector of script/source paths. If `NULL`,
  automatically discovers R scripts, Quarto/Rmd documents,
  `DESCRIPTION`, `renv.lock`, `_quarto.yml`, `.stan`, `.py`, and
  `requirements.txt`.

- outputs:

  Optional character vector of generated output artifact paths (files or
  directories) to record and verify.

- containers:

  Optional character vector of container specification paths. If `NULL`,
  automatically includes any `Dockerfile`, `docker-compose.yml`, and
  `*.def` files present at the project root.

- entrypoint:

  Optional runnable entrypoint override (defaults to `scan$entrypoint`).

- seed:

  Optional integer RNG seed to record and enforce during verification.
  If `NULL`, uses the first statically detected
  [`set.seed()`](https://rdrr.io/r/base/Random.html) literal if present,
  or `NULL`.

- rng_kind:

  Optional character vector of length 3 from
  [`base::RNGkind()`](https://rdrr.io/r/base/Random.html). Defaults to
  the current session's
  [`RNGkind()`](https://rdrr.io/r/base/Random.html).

- tolerances:

  Optional tolerance configuration: either shorthand
  `list(abs_tol = 1e-4, rel_tol = 1e-3)` or structured
  `list(default = list(abs_tol = 0, rel_tol = 0), files = list("out.csv" = list(abs_tol = 1e-3)))`.

- metadata:

  Optional named list of extra publication metadata (e.g., `title`,
  `authors`, `journal`, `doi`).

- embed_snapshots:

  Logical; if `TRUE`, embeds base64-encoded snapshots of small
  (`<= max_snapshot_bytes`) tabular/JSON/RDS outputs inside the manifest
  so numeric-tolerance verification can run even when original output
  files are absent from disk. Defaults to `TRUE`.

- max_snapshot_bytes:

  Maximum size in bytes of an individual output file eligible for
  embedded snapshotting. Defaults to `262144L` (256 KiB).

- key:

  Optional secret key string for signing the manifest with HMAC-SHA256.

- output:

  Optional file path to write `capsule.json`. If `NULL`, returns the
  manifest object in memory.

## Value

An S3 object of class `rcapsule_manifest`.

## Examples

``` r
tmp <- tempfile("rcapsule_manifest_")
dir.create(tmp)
writeLines("write.csv(data.frame(x = 1:3), 'out.csv', row.names = FALSE)",
           file.path(tmp, "run.R"))
write.csv(data.frame(x = 1:3), file.path(tmp, "out.csv"), row.names = FALSE)
m <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 42L)
verify_manifest_integrity(m)
#> 
#> ── rcapsule Manifest Integrity: VALID ──────────────────────────────────────────
#> • Content digest: OK (db72768c9c18)
#> • Signed: FALSE | Signature check: "not verified"
unlink(tmp, recursive = TRUE)
```
