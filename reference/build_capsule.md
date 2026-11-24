# Build a Complete Reproducibility Capsule for an R Project

End-to-end orchestrator that scans an R project, compiles multi-target
container definitions (`Dockerfile`, `docker-compose.yml`,
`Apptainer.def`), statically lints every generated spec, records a
cryptographically verifiable `capsule.json` provenance manifest, and
optionally runs an isolated reproducibility verification audit and
renders journal-ready certificates.

## Usage

``` r
build_capsule(
  path = ".",
  targets = c("dockerfile", "compose", "apptainer"),
  inputs = NULL,
  outputs = NULL,
  entrypoint = NULL,
  seed = NULL,
  tolerances = NULL,
  key = NULL,
  write = TRUE,
  lint = TRUE,
  verify = FALSE,
  certificate = FALSE,
  runner = c("sandbox", "docker"),
  custom_sysreqs = NULL,
  platform = NULL,
  use_ppm = TRUE,
  metadata = list()
)
```

## Arguments

- path:

  Path to the project root directory. Defaults to `"."`.

- targets:

  Character vector of container targets to compile: any subset of
  `c("dockerfile", "compose", "apptainer")`.

- inputs:

  Optional character vector of input data file/directory paths.

- outputs:

  Optional character vector of output artifact paths to hash and verify.

- entrypoint:

  Optional runnable entrypoint override.

- seed:

  Optional integer RNG seed.

- tolerances:

  Optional numeric tolerance configuration passed to
  [`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md).

- key:

  Optional HMAC-SHA256 secret key for signing `capsule.json`.

- write:

  Logical; if `TRUE` (default), writes compiled container specs and
  `capsule.json` into `path`.

- lint:

  Logical; if `TRUE` (default), runs
  [`lint_container_spec()`](https://marcusharrisphd.com/rcapsule/reference/lint_container_spec.md)
  on every compiled container target.

- verify:

  Logical; if `TRUE`, executes
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md)
  immediately after building the manifest. Defaults to `FALSE`.

- certificate:

  Logical; if `TRUE` (and `verify = TRUE`), renders Markdown and HTML
  certificates via
  [`render_certificate()`](https://marcusharrisphd.com/rcapsule/reference/render_certificate.md).
  Defaults to `FALSE`.

- runner:

  Verification runner backend when `verify = TRUE`: `"sandbox"`
  (default) or `"docker"`.

- custom_sysreqs:

  Optional custom system dependency overrides forwarded to
  [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md).

- platform:

  Optional target container platform (`"linux/amd64"`, `"linux/arm64"`,
  or `NULL`) forwarded to
  [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md)
  and
  [`compile_compose()`](https://marcusharrisphd.com/rcapsule/reference/compile_compose.md).

- use_ppm:

  Logical; if `TRUE` (default), enables Posit Package Manager Linux
  binary repositories in
  [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md).

- metadata:

  Optional metadata list forwarded to
  [`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md).

## Value

An S3 object of class `rcapsule_bundle` containing `scan`, `specs`,
`lint`, `manifest`, `verification`, and `certificate`.

## Examples

``` r
tmp <- tempfile("rcapsule_bundle_")
dir.create(tmp)
writeLines(
  c("write.csv(data.frame(x = 1:3, y = c(2, 4, 6)), 'out.csv', row.names = FALSE)"),
  file.path(tmp, "run.R")
)
write.csv(data.frame(x = 1:3, y = c(2, 4, 6)), file.path(tmp, "out.csv"), row.names = FALSE)
bundle <- build_capsule(tmp, outputs = "out.csv", seed = 42L, verify = TRUE, certificate = TRUE)
bundle$verification$status
#> [1] "verified_exact"
unlink(tmp, recursive = TRUE)
```
