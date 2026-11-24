# Read a Capsule Manifest from `capsule.json`

Reads and validates the structure of a serialized `capsule.json`
manifest.

## Usage

``` r
read_capsule_manifest(path = "capsule.json")
```

## Arguments

- path:

  Path to a `capsule.json` file.

## Value

An S3 object of class `rcapsule_manifest`.

## Examples

``` r
tmp <- tempfile("rcapsule_rm_")
dir.create(tmp)
writeLines("x <- 1", file.path(tmp, "run.R"))
m <- create_capsule_manifest(tmp, output = file.path(tmp, "capsule.json"))
m2 <- read_capsule_manifest(file.path(tmp, "capsule.json"))
m2$capsule_id == m$capsule_id
#> [1] TRUE
unlink(tmp, recursive = TRUE)
```
