# Export a Journal-Ready Reproducibility Supplement Bundle

Packages container specifications (`Dockerfile`, `docker-compose.yml`,
`Apptainer.def`), the cryptographic provenance manifest
(`capsule.json`), verification certificates (`capsule_certificate.md`
and `.html`), recorded project inputs/scripts/outputs, and an
auto-generated `README_REPRODUCE.md` peer-review guide into either a
clean directory or a portable ZIP archive. Strictly enforces
project-root path confinement and zip-slip safety so no path traversal
(`..`), absolute paths, or external symlinks can enter the exported
bundle.

## Usage

``` r
export_capsule_bundle(
  path = ".",
  output,
  format = c("zip", "dir"),
  manifest = NULL,
  verification = NULL,
  certificate = NULL,
  include_inputs = TRUE,
  include_scripts = TRUE,
  include_outputs = TRUE,
  include_containers = TRUE,
  include_certificate = TRUE,
  platform = NULL,
  overwrite = FALSE
)
```

## Arguments

- path:

  Path to the project root directory. Defaults to `"."`.

- output:

  Destination path for the exported ZIP archive (when `format = "zip"`)
  or output directory (when `format = "dir"`).

- format:

  Export format: `"zip"` (default) or `"dir"`.

- manifest:

  Optional `rcapsule_manifest` object or path to `capsule.json`. If
  `NULL`, reads `file.path(path, "capsule.json")` when present or
  creates a fresh manifest via
  [`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md).

- verification:

  Optional `rcapsule_verification` object from
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md).
  When supplied and `include_certificate = TRUE`, automatically renders
  certificates into the bundle.

- certificate:

  Optional `rcapsule_certificate` object from
  [`render_certificate()`](https://marcusharrisphd.com/rcapsule/reference/render_certificate.md).

- include_inputs:

  Logical; include recorded input files (default `TRUE`).

- include_scripts:

  Logical; include recorded scripts & lockfiles (default `TRUE`).

- include_outputs:

  Logical; include recorded output artifacts (default `TRUE`).

- include_containers:

  Logical; include `Dockerfile`, `docker-compose.yml`, and
  `Apptainer.def`, compiling any missing specs on the fly (default
  `TRUE`).

- include_certificate:

  Logical; include Markdown and HTML verification certificates when
  available (default `TRUE`).

- platform:

  Optional target container platform (`"linux/amd64"`, `"linux/arm64"`,
  or `NULL`) forwarded to container compilation and
  `README_REPRODUCE.md`.

- overwrite:

  Logical; if `FALSE` (default), aborts when `output` already exists.

## Value

An S3 object of class `rcapsule_export` with fields `output_path`,
`format`, `files`, `n_files`, `size_bytes`, `sha256`, and `capsule_id`.

## Examples

``` r
tmp <- tempfile("rcapsule_export_")
dir.create(tmp)
writeLines("write.csv(data.frame(x = 1:3), 'out.csv', row.names = FALSE)",
           file.path(tmp, "run.R"))
write.csv(data.frame(x = 1:3), file.path(tmp, "out.csv"), row.names = FALSE)
m <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
v <- verify_capsule(m, path = tmp)
zip_out <- file.path(tempdir(), paste0(basename(tmp), "_supplement.zip"))
exp <- export_capsule_bundle(tmp, output = zip_out, manifest = m, verification = v)
exp
#> 
#> ── rcapsule Exported Supplement Bundle (zip) ───────────────────────────────────
#> • Destination: /tmp/RtmpThAhiB/rcapsule_export_19a97b5638c7_supplement.zip
#> • Capsule ID: "cap_378ff7ae2563"
#> • Files bundled: 9 (7.5 KiB)
#> • Archive SHA-256: "2aac30e496ce"
unlink(c(tmp, zip_out), recursive = TRUE)
```
