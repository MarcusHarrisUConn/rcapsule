# Validate a CycloneDX 1.5 SBOM Document

Validates an `rcapsule_sbom` object, a parsed CycloneDX list, or a JSON
file path against CycloneDX 1.5 structural, Package URL (PURL), hash,
unique `bom-ref`, and dependency graph referential integrity rules.

## Usage

``` r
validate_sbom(sbom, require_spec_version = "1.5")
```

## Arguments

- sbom:

  An `rcapsule_sbom` object from
  [`export_sbom()`](https://marcusharrisphd.com/rcapsule/reference/export_sbom.md),
  a parsed list, or a file path to a CycloneDX JSON file.

- require_spec_version:

  Expected CycloneDX specification version (defaults to `"1.5"`).

## Value

An S3 object of class `rcapsule_sbom_validation` containing `valid`
(logical), `bom_format`, `spec_version`, `n_components`,
`n_dependencies`, `n_errors`, and `issues` (a tibble with columns
`rule`, `severity`, `path`, and `message`).

## Examples

``` r
tmp <- tempfile("rcapsule_sbom_val_")
dir.create(tmp)
writeLines("library(jsonlite)", file.path(tmp, "run.R"))
sbom <- export_sbom(tmp)
val <- validate_sbom(sbom)
val$valid
#> [1] TRUE
unlink(tmp, recursive = TRUE)
```
