# Export a Structured Apptainer Recipe Descriptor for HPC Orchestrators

Converts an `rcapsule_scan`, `rcapsule_apptainer`, `rcapsule_bundle`, or
project directory path into a self-contained, plain-list-convertible
Apptainer specification descriptor (`rcapsule_apptainer_spec`). Designed
as a zero-dependency handoff contract for downstream HPC job
orchestrators (such as Slurm array/container runners) that need pinned
base images, environment variables, HPC bind mounts, runscript commands,
and the SHA-256 digest of the `.def` recipe without coupling to
`rcapsule` internals.

## Usage

``` r
as_apptainer_spec(
  x,
  base_image = NULL,
  r_version = NULL,
  base_digest = NULL,
  cran_repo = "https://packagemanager.posit.co/cran/2026-01-15",
  quarto_version = "1.5.57",
  cmdstan_version = "2.35.0",
  workdir = "/capsule",
  entrypoint = NULL,
  bind_paths = c("/scratch", "/work", "/data"),
  output = NULL,
  allow_unpinned = FALSE
)
```

## Arguments

- x:

  An `rcapsule_scan`, `rcapsule_apptainer`, `rcapsule_bundle`, or path
  to a project directory.

- base_image:

  Optional pinned Docker base image override forwarded to
  [`compile_apptainer()`](https://marcusharrisphd.com/rcapsule/reference/compile_apptainer.md).

- r_version:

  Optional R version string override.

- base_digest:

  Optional SHA-256 image digest appended to `base_image`.

- cran_repo:

  Pinned CRAN or Posit Package Manager repository URL.

- quarto_version:

  Pinned Quarto CLI version when Quarto is detected.

- cmdstan_version:

  Pinned CmdStan version when CmdStan is detected.

- workdir:

  Project directory inside the container image. Defaults to
  `"/capsule"`.

- entrypoint:

  Optional override for the `%runscript` entrypoint.

- bind_paths:

  Character vector of absolute HPC bind mount paths (default
  `c("/scratch", "/work", "/data")`).

- output:

  Optional file path to write the compiled `.def` recipe when compiling
  or overriding settings.

- allow_unpinned:

  Logical; if `FALSE` (default), rejects `:latest` or untagged base
  images.

## Value

An S3 object of class `c("rcapsule_apptainer_spec", "rcapsule")`
(convertible to a plain list via
[`as.list()`](https://rdrr.io/r/base/list.html)) with fields
`schema_version`, `project_name`, `project_type`, `r_version`,
`bootstrap`, `base_image`, `workdir`, `entrypoint`, `r_packages`,
`apt_packages`, `python_packages`, `toolchains`, `env_vars`,
`bind_paths`, `binds`, `runscript`, `test_commands`, `def_content`,
`def_sha256`, `content_digest`, `def_path`, and `sif_path`.

## Examples

``` r
tmp <- tempfile("rcapsule_hpc_spec_")
dir.create(tmp)
writeLines(c("library(jsonlite)", "cat('ok\\n')"), file.path(tmp, "run.R"))
spec <- as_apptainer_spec(tmp)
spec
#> 
#> ── rcapsule Apptainer Spec Descriptor: rcapsule_hpc_spec_18be190505b4 ──────────
#> • Base image: "rocker/r-ver:4.6.2" (Bootstrap: docker)
#> • Project type: "analysis" | R: "4.6.2" | Workdir: /capsule
#> • Entrypoint: "run.R"
#> • Dependencies: 1 R pkg(s), 1 apt pkg(s), 0 Python pkg(s)
#> • Toolchains: standard R
#> • HPC bind paths: /scratch, /work, /data
#> • Recipe SHA-256: "1badce64f73d9d64"...
names(as.list(spec))
#>  [1] "schema_version"  "project_name"    "project_type"    "r_version"      
#>  [5] "bootstrap"       "base_image"      "workdir"         "entrypoint"     
#>  [9] "r_packages"      "apt_packages"    "python_packages" "toolchains"     
#> [13] "env_vars"        "bind_paths"      "binds"           "runscript"      
#> [17] "test_commands"   "def_content"     "def_sha256"      "content_digest" 
#> [21] "def_path"        "sif_path"       
unlink(tmp, recursive = TRUE)
```
