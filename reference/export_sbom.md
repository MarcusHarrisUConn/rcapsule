# Export a CycloneDX 1.5 Software Bill of Materials (SBOM)

Generates a standards-compliant CycloneDX 1.5 JSON Software Bill of
Materials (`bomFormat: "CycloneDX"`, `specVersion: "1.5"`) enumerating
every dependency layer of an R research project:

- R packages with Package URLs (`pkg:cran/...`, `pkg:github/...`,
  `pkg:gitlab/...`, `pkg:bioconductor/...`) and `renv.lock` hashes when
  present.

- OS `apt` system libraries (`pkg:deb/debian/...`) linked to the R
  packages that require them.

- Python packages (`pkg:pypi/...`) discovered from `requirements.txt` or
  `reticulate` imports.

- Scientific and compiled toolchains (`R`, `CmdStan`, `Quarto`,
  `TinyTeX`, `JAGS`, `TMB/RTMB`, `C++`, `Rust`, `Python`, `Java`).

## Usage

``` r
export_sbom(
  path = ".",
  scan = NULL,
  manifest = NULL,
  output = NULL,
  format = c("cyclonedx"),
  spec_version = "1.5",
  include_base = FALSE,
  serial_number = NULL
)
```

## Arguments

- path:

  Path to the project root directory. Defaults to `"."`.

- scan:

  Optional pre-computed `rcapsule_scan` object from
  [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md).
  If `NULL`, scans `path`.

- manifest:

  Optional `rcapsule_manifest` object or path to `capsule.json` whose
  `capsule_id` and `SHA-256` content digest are bound into the SBOM root
  component metadata.

- output:

  Optional file path to write the CycloneDX JSON document (for example,
  `"sbom.cdx.json"`). If `NULL`, returns the SBOM object in memory.

- format:

  SBOM output format; currently `"cyclonedx"` (default).

- spec_version:

  CycloneDX specification version; defaults to `"1.5"`.

- include_base:

  Logical; if `TRUE`, also includes base R packages as components.
  Defaults to `FALSE`.

- serial_number:

  Optional RFC 4122 UUID URN (`"urn:uuid:..."`) for the BOM serial
  number. If `NULL`, generates a fresh cryptographic UUID v4 URN.

## Value

An S3 object of class `rcapsule_sbom` containing `bom` (structured
CycloneDX 1.5 list), `json` (pretty UTF-8 JSON string), `path` (written
file path or `NULL`), `spec_version`, `serial_number`, and `summary`
(component counts by ecosystem).

## Examples

``` r
tmp <- tempfile("rcapsule_sbom_")
dir.create(tmp)
writeLines(c("library(jsonlite)", "library(stats)", "x <- 1:5"), file.path(tmp, "run.R"))
sbom <- export_sbom(tmp)
sbom
#> 
#> ── rcapsule CycloneDX 1.5 SBOM: rcapsule_sbom_19a97e864d83 ─────────────────────
#> • Serial number: "urn:uuid:4a50c18b-7d4b-44e1-8887-08590c8b4485"
#> • Total components: 2 (R=1, apt=0, PyPI=0, toolchains=1)
#> • Dependencies graph entries: 1
#> • Output file: <in memory>
validate_sbom(sbom)
#> 
#> ── CycloneDX SBOM Validation: VALID ────────────────────────────────────────────
#> • Format: "CycloneDX" | Spec version: "1.5"
#> • Components: 2 | Dependency entries: 1 | Errors: 0
unlink(tmp, recursive = TRUE)
```
