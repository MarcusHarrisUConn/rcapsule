# Sign a Capsule Manifest with HMAC-SHA256

Computes a canonical content digest and signs the manifest using a keyed
HMAC-SHA256 signature via
[`openssl::sha256()`](https://rdrr.io/pkg/openssl/man/hash.html).

## Usage

``` r
sign_manifest(manifest, key)
```

## Arguments

- manifest:

  An `rcapsule_manifest` object.

- key:

  Non-empty character string secret signing key.

## Value

Updated `rcapsule_manifest` object with populated `integrity$signature`.

## Examples

``` r
tmp <- tempfile("rcapsule_sign_")
dir.create(tmp)
writeLines("x <- 1", file.path(tmp, "run.R"))
m <- create_capsule_manifest(tmp)
m_signed <- sign_manifest(m, key = "demo-secret-key")
verify_manifest_integrity(m_signed, key = "demo-secret-key")$valid
#> [1] TRUE
unlink(tmp, recursive = TRUE)
```
