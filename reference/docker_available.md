# Check whether Docker daemon is available

Tests whether the `docker` CLI is on `PATH` and the Docker daemon
responds cleanly to `docker info`. Useful for guarding live-container
integration tests and deciding between `"docker"` and `"sandbox"`
verification runners.

## Usage

``` r
docker_available(timeout = 5)
```

## Arguments

- timeout:

  Maximum seconds to wait for `docker info`. Defaults to `5`.

## Value

A single logical value (`TRUE` if Docker is usable, `FALSE` otherwise).

## Examples

``` r
docker_available()
#> [1] FALSE
```
