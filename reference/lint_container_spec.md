# Lint a Container Specification for Reproducibility and Security Issues

Performs static analysis on a `Dockerfile`, `docker-compose.yml`, or
Apptainer `.def` recipe, accepting an `rcapsule_spec` object, a file
path, or a character vector of spec lines. Checks for unpinned `:latest`
or untagged base images, missing `apt` cache cleanup, root-only
execution, cache-busting `COPY` order, hardcoded secrets, privileged
containers, and missing safety guards.

## Usage

``` r
lint_container_spec(
  spec,
  type = c("auto", "dockerfile", "compose", "apptainer")
)
```

## Arguments

- spec:

  An `rcapsule_spec` object (from
  [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md),
  [`compile_compose()`](https://marcusharrisphd.com/rcapsule/reference/compile_compose.md),
  or
  [`compile_apptainer()`](https://marcusharrisphd.com/rcapsule/reference/compile_apptainer.md)),
  a path to a spec file, or a character string/vector containing the
  specification text.

- type:

  Spec format: `"auto"` (default) infers from class, file name, or
  contents; or explicitly `"dockerfile"`, `"compose"`, or `"apptainer"`.

## Value

An S3 object of class `rcapsule_lint` with fields:

- `spec_type`: `"dockerfile"`, `"compose"`, or `"apptainer"`

- `passed`: logical (`TRUE` when `n_errors == 0L`)

- `n_errors`, `n_warnings`, `n_info`: integer counts

- `issues`:
  [`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
  with columns `rule_id`, `severity`, `line`, `message`, and
  `suggestion`

## Examples

``` r
bad_df <- c(
  "FROM rocker/r-ver:latest",
  "RUN apt-get update && apt-get install -y libcurl4-openssl-dev",
  "COPY . ."
)
lint_container_spec(bad_df, type = "dockerfile")
#> 
#> ── rcapsule Container Lint (dockerfile): FAIL ──────────────────────────────────
#> Errors: 2 | Warnings: 2 | Info: 2
#> ✖ [DF001] (line 1) Base image 'rocker/r-ver:latest' uses mutable ':latest' tag.
#> ! [DF002] (line 2) apt-get install without cleaning /var/lib/apt/lists/* bloats image layers.
#> ! [DF003] (line 2) apt-get install missing '--no-install-recommends'.
#> ✖ [DF004] (line 1) Final stage has no non-root USER instruction; container runs as root.
#> ℹ [DF005] (line 1) No HEALTHCHECK instruction in final stage.
#> ℹ [DF009] (line 1) No WORKDIR instruction in final stage.
```
