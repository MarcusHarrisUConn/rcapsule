# Verify Cryptographic Integrity and Signature of a Capsule Manifest

Recomputes the canonical SHA-256 `content_digest` over the manifest body
to detect any tampering with project metadata, environment
specifications, RNG seeds, artifact hashes, or tolerances. If the
manifest is signed or a `key` is supplied, also verifies the HMAC-SHA256
signature using constant-time comparison.

## Usage

``` r
verify_manifest_integrity(manifest, key = NULL)
```

## Arguments

- manifest:

  An `rcapsule_manifest` object or path to a `capsule.json` file.

- key:

  Optional secret signing key for verifying HMAC-SHA256 signatures.

## Value

An S3 object of class `rcapsule_integrity` with fields:

- `valid`: logical (`TRUE` only if both content digest and signature
  checks pass)

- `content_valid`: logical

- `signed`: logical (whether the manifest carries a signature)

- `signature_valid`: logical or `NA` (when unsigned and no `key` given)

- `recorded_digest`, `computed_digest`: SHA-256 hex strings

- `issues`: character vector describing any integrity failures

## Examples

``` r
tmp <- tempfile("rcapsule_int_")
dir.create(tmp)
writeLines("x <- 1", file.path(tmp, "run.R"))
m <- create_capsule_manifest(tmp, key = "secret")
verify_manifest_integrity(m, key = "secret")
#> 
#> ── rcapsule Manifest Integrity: VALID ──────────────────────────────────────────
#> • Content digest: OK (25f9722f2b87)
#> • Signed: TRUE | Signature check: TRUE
unlink(tmp, recursive = TRUE)
```
