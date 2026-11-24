# Diff Two Capsule Provenance Manifests Across Runs or Machines

Compares two `capsule.json` manifests (for example, an author's laptop
run versus an HPC cluster run or a journal peer reviewer's
reproduction). Detects R, OS, architecture, package, system library, and
toolchain drift, Git revision and RNG seed changes,
modified/added/removed inputs, scripts, container specs, and outputs,
including numeric-tolerance evaluation when embedded output snapshots
are present.

## Usage

``` r
diff_capsules(
  manifest_a,
  manifest_b,
  tolerances = NULL,
  label_a = NULL,
  label_b = NULL
)
```

## Arguments

- manifest_a:

  Baseline `rcapsule_manifest` object or path to `capsule.json`.

- manifest_b:

  Comparison `rcapsule_manifest` object or path to `capsule.json`.

- tolerances:

  Optional numeric tolerance configuration overriding
  `manifest_a$tolerances` (accepts `abs_tol`/`atol` and
  `rel_tol`/`rtol`).

- label_a:

  Optional human-readable label for `manifest_a` (defaults to its
  `capsule_id`).

- label_b:

  Optional human-readable label for `manifest_b` (defaults to its
  `capsule_id`).

## Value

An S3 object of class `rcapsule_diff` with fields:

- `label_a`, `label_b`, `capsule_id_a`, `capsule_id_b`

- `identical`: logical (`TRUE` when environment, RNG, Git, and all
  artifacts match bit-for-bit)

- `outputs_equivalent`: logical (`TRUE` when all outputs are
  `"unchanged"` or `"within_tolerance"` with zero added/removed/modified
  outputs)

- `has_env_drift`, `has_input_drift`, `has_script_drift`: logical flags

- `env_diff`: list of R/OS/platform/package/sysreq/toolchain diffs

- `rng_diff`: list comparing RNG seed and kind

- `git_diff`: list comparing Git commit, branch, and dirty status

- `artifact_diffs`: named list of tibbles (`inputs`, `scripts`,
  `containers`, `outputs`)

## Examples

``` r
tmp <- tempfile("rcapsule_diff_demo_")
dir.create(tmp)
writeLines("write.csv(data.frame(x = 1:3), 'out.csv', row.names = FALSE)",
           file.path(tmp, "run.R"))
write.csv(data.frame(x = 1:3), file.path(tmp, "out.csv"), row.names = FALSE)
m1 <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
write.csv(data.frame(x = c(1.0001, 2, 3)), file.path(tmp, "out.csv"), row.names = FALSE)
m2 <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
d <- diff_capsules(m1, m2, tolerances = list(atol = 1e-3))
d
#> 
#> ── rcapsule Manifest Diff: OUTPUTS EQUIVALENT (DRIFT DETECTED) ─────────────────
#> • Baseline (A): "cap_1811ec1e0616" (cap_1811ec1e0616)
#> • Comparison (B): "cap_714bf7869861" (cap_714bf7869861)
#> • Environment drift: FALSE (R: 4.6.2 -> 4.6.2; platform: x86_64-pc-linux-gnu ->
#> x86_64-pc-linux-gnu)
#> • RNG drift: seed=1 -> 1
#> • Inputs drift: FALSE | Scripts drift: FALSE | Outputs equivalent: TRUE
#> 
#> ── Changed outputs (1/1) ──
#> 
#> ! out.csv [within_tolerance] - Verified within tolerance (max_abs_diff=1e-04, max_rel_diff=9.999e-05).
unlink(tmp, recursive = TRUE)
```
