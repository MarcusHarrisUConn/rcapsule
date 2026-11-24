# Check whether Apptainer or Singularity CLI is available

Tests whether `apptainer` or `singularity` is installed on `PATH` and
responds to `--version`.

## Usage

``` r
apptainer_available(timeout = 5)
```

## Arguments

- timeout:

  Maximum seconds to wait for the version check. Defaults to `5`.

## Value

A single logical value (`TRUE` if Apptainer/Singularity is usable,
`FALSE` otherwise).

## Examples

``` r
apptainer_available()
#> [1] FALSE
```
