# Compare Two Output Artifacts with Exact SHA-256 and Numeric Tolerance

Fast-paths exact bit-for-bit verification via SHA-256. When digests
differ and numeric tolerances (`abs_tol`/`atol > 0` or
`rel_tol`/`rtol > 0`) are permitted, recursively parses `csv`, `tsv`,
`json`, or `rds` artifacts (including nested lists, data frames,
matrices, and arrays) and verifies that every numeric element satisfies
`abs(a - b) <= abs_tol + rel_tol * max(|a|, |b|)` while preserving exact
`NA`/`NaN`/`Inf` alignment and exact equality for all non-numeric keys,
columns, dimensions, and labels.

## Usage

``` r
compare_artifacts(
  expected_path = NULL,
  actual_path,
  expected_sha256 = NULL,
  abs_tol = 0,
  rel_tol = 0,
  atol = NULL,
  rtol = NULL,
  format = "auto",
  ignore_attributes = FALSE,
  expected_raw = NULL
)
```

## Arguments

- expected_path:

  Path to the expected reference artifact (may be `NULL` if
  `expected_sha256` and/or `expected_raw` is supplied).

- actual_path:

  Path to the freshly reproduced artifact.

- expected_sha256:

  Optional recorded SHA-256 hex digest of the expected artifact.

- abs_tol:

  Non-negative absolute numeric tolerance (default `0`).

- rel_tol:

  Non-negative relative numeric tolerance (default `0`).

- atol:

  Optional alias for `abs_tol`; overrides `abs_tol` if non-`NULL`.

- rtol:

  Optional alias for `rel_tol`; overrides `rel_tol` if non-`NULL`.

- format:

  Artifact format: `"auto"` (default), `"csv"`, `"tsv"`, `"json"`,
  `"rds"`, `"text"`, or `"binary"`.

- ignore_attributes:

  Logical; if `TRUE`, ignores vector/matrix name attributes during RDS
  comparison.

- expected_raw:

  Optional raw vector of the expected artifact bytes (e.g., decoded from
  an embedded manifest snapshot).

## Value

A list with fields `status` (`"exact_match"`, `"within_tolerance"`,
`"mismatch"`, or `"missing"`), `passed` (logical), `expected_sha256`,
`actual_sha256`, `max_abs_diff`, `max_rel_diff`, `abs_tol`, `rel_tol`,
and `details`.

## Examples

``` r
f1 <- tempfile(fileext = ".csv")
f2 <- tempfile(fileext = ".csv")
write.csv(data.frame(k = c("a", "b"), est = c(1.0000, 2.0000)), f1, row.names = FALSE)
write.csv(data.frame(k = c("a", "b"), est = c(1.0002, 1.9999)), f2, row.names = FALSE)
compare_artifacts(f1, f2, atol = 1e-3, rtol = 1e-3)
#> $status
#> [1] "within_tolerance"
#> 
#> $passed
#> [1] TRUE
#> 
#> $expected_sha256
#> [1] "d866cc71e2f4ee64593b7fe1c6d28e12ca54dc38b01466a6897f9b65dab2273f"
#> 
#> $actual_sha256
#> [1] "ee8b465d4b8442e5980288088665f50302c446ab11957d9e9af589e0ec7f9ead"
#> 
#> $max_abs_diff
#> [1] 2e-04
#> 
#> $max_rel_diff
#> [1] 0.00019996
#> 
#> $abs_tol
#> [1] 0.001
#> 
#> $rel_tol
#> [1] 0.001
#> 
#> $details
#> [1] "Verified within tolerance (max_abs_diff=2e-04, max_rel_diff=2e-04)."
#> 
unlink(c(f1, f2))
```
