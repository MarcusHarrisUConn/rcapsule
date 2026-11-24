# Diagnose Reproducibility Failures and Cross-Run Drift

Automatically inspects a verification audit from
[`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md)
or a cross-machine manifest diff from
[`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md),
classifies every root cause of divergence, and ranks concrete
remediation steps.

## Usage

``` r
diagnose_reproducibility(x, path = NULL, small_tol = 0.01)
```

## Arguments

- x:

  An `rcapsule_verification` object from
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md)
  or an `rcapsule_diff` object from
  [`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md).

- path:

  Optional project root directory path used for supplemental byte checks
  when `x` is an `rcapsule_verification` with a retained `sandbox_dir`.

- small_tol:

  Positive numeric threshold distinguishing small numerical / Monte
  Carlo / BLAS rounding drift (`<= small_tol`) from large unseeded or
  algorithmic divergence (`> small_tol`). Defaults to `1e-2`.

## Value

An S3 object of class `rcapsule_diagnosis` containing `source_type`
(`"verification"` or `"diff"`), `status`, `primary_cause`, `n_findings`,
`findings` (a ranked tibble with columns `rank`, `category`, `severity`,
`confidence`, `affected`, `evidence`, and `remediation`), `remediations`
(deduplicated ranked action list), and `summary_text`.

## Details

Root-cause categories include:

- `hmac_signature_failure` and `manifest_tampering`

- `execution_failure` (with `stderr` clue parsing for missing packages,
  broken relative paths, syntax errors, and timeouts)

- `input_drift`, `script_drift`, and `container_drift`

- `missing_output` and `unexpected_extra_artifacts`

- `line_ending_drift` (exact `CRLF` vs. `LF` equivalence detection)

- `schema_drift` (row/column/key/type/NA/NaN/Inf changes)

- `binary_metadata_drift` (PDF/PNG/HTML timestamps and font
  rasterization)

- `monte_carlo_small_drift` vs. `unseeded_large_divergence` and
  `rng_drift`

- `environment_or_arch_drift` (R version, CPU architecture, OS,
  packages, sysreqs, or scientific toolchains)

## Examples

``` r
tmp <- tempfile("rcapsule_diag_")
dir.create(tmp)
writeLines(
  c("df <- data.frame(id = 1:3, val = rnorm(3))",
    "write.csv(df, 'out.csv', row.names = FALSE)"),
  file.path(tmp, "run.R")
)
set.seed(1)
write.csv(data.frame(id = 1:3, val = rnorm(3)), file.path(tmp, "out.csv"), row.names = FALSE)
m <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
# Simulate running with a different seed
v <- verify_capsule(m, path = tmp, seed = 999L)
diag <- diagnose_reproducibility(v)
diag
#> 
#> ── rcapsule Reproducibility Diagnosis ──────────────────────────────────────────
#> • Source: "verification" | Status: "failed"
#> • Primary cause: "rng_drift" | Findings: 2
#> 
#> ── Ranked Root Causes ──
#> 
#> ✖ #1 [HIGH | rng_drift] RNG seed: Verification used seed=999 while manifest recorded seed=1.
#> Remediation: Run verify_capsule() using the manifest seed (1) without
#> overriding the seed argument.
#> ✖ #2 [HIGH | unseeded_large_divergence] out.csv: Large numerical divergence in 'out.csv' (max_abs_diff=1.631, max_rel_diff=1.952): SHA-256 digest mismatch (exact match required; out.csv$val[1]: expected=-0.626453810742332, actual=-0.281740158905298, abs_diff=0.3447, rel_diff=0.5503).
#> Remediation: RNG seed is unset or changed across runs, strongly pointing to
#> unseeded stochastic sampling. Explicitly call set.seed(), pass parallel RNG
#> seeds (e.g., future.seed = TRUE or CmdStan seed), and record the seed in
#> create_capsule_manifest(seed = ...).
unlink(tmp, recursive = TRUE)
```
