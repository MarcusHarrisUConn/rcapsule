# Write a Capsule Manifest to `capsule.json`

Serializes an `rcapsule_manifest` object as deterministic pretty-printed
JSON.

## Usage

``` r
write_capsule_manifest(manifest, path = "capsule.json")
```

## Arguments

- manifest:

  An `rcapsule_manifest` object.

- path:

  Output file path. Defaults to `"capsule.json"`.

## Value

Invisibly returns the normalized output file path.

## Examples

``` r
tmp <- tempfile("rcapsule_wm_")
dir.create(tmp)
writeLines("x <- 1", file.path(tmp, "run.R"))
m <- create_capsule_manifest(tmp)
out <- write_capsule_manifest(m, file.path(tmp, "capsule.json"))
file.exists(out)
#> [1] TRUE
unlink(tmp, recursive = TRUE)
```
