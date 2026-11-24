# Compile a Production Multi-Service `docker-compose.yml`

Generates a validated, security-hardened `docker-compose.yml` stack
tailored to the scanned R project. For Shiny applications, compiles a
multi-service stack with the primary `app` service, an async background
`worker` service, and a pinned reverse `proxy` (`caddy:2.8.4-alpine`),
complete with health checks, resource limits, `no-new-privileges`,
read-only data mounts, named output volumes, and an isolated bridge
network. For analysis or Quarto projects, compiles a clean reproducible
execution service.

## Usage

``` r
compile_compose(
  scan,
  output = NULL,
  service_name = NULL,
  image_tag = "0.1.0",
  dockerfile = "Dockerfile",
  include_worker = NULL,
  include_proxy = NULL,
  proxy_image = "caddy:2.8.4-alpine",
  port = 3838L,
  proxy_port = 8080L,
  memory_limit = "2G",
  cpus = "2.0",
  env_vars = list(),
  volumes = NULL,
  restart_policy = NULL,
  platform = NULL
)
```

## Arguments

- scan:

  An `rcapsule_scan` object from
  [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md)
  or a path to a project directory.

- output:

  Optional file path to write `docker-compose.yml`. If `NULL`, returns
  the compiled spec in memory.

- service_name:

  Optional primary service name (defaults to `"app"` for Shiny projects,
  or a sanitized slug of `scan$project_name`).

- image_tag:

  Pinned local image tag for the built service (defaults to `"0.1.0"`).
  Must not be `"latest"`.

- dockerfile:

  Path to the Dockerfile relative to build context. Defaults to
  `"Dockerfile"`.

- include_worker:

  Logical or `NULL`. If `NULL`, automatically enables a background
  `worker` service for Shiny projects (especially when async packages or
  `worker.R` are detected).

- include_proxy:

  Logical or `NULL`. If `NULL`, automatically enables a pinned reverse
  proxy service (`caddy:2.8.4-alpine`) for Shiny projects.

- proxy_image:

  Pinned reverse proxy container image. Defaults to
  `"caddy:2.8.4-alpine"`.

- port:

  Internal application port (default `3838L` for Shiny).

- proxy_port:

  Host port mapped to the reverse proxy (default `8080L`).

- memory_limit:

  Memory limit per service (e.g., `"2G"`).

- cpus:

  CPU quota per service as character or numeric (e.g., `"2.0"`).

- env_vars:

  Named list or character vector of extra environment variables (avoid
  hardcoding secrets; use `${ENV_VAR}` interpolation).

- volumes:

  Optional character vector of extra volume mounts.

- restart_policy:

  Docker restart policy for long-running services. Defaults to
  `"unless-stopped"` for Shiny and `"no"` for batch analyses.

- platform:

  Optional target container platform (`"linux/amd64"`, `"linux/arm64"`,
  or `NULL` for host default) applied to built services.

## Value

An S3 object of class `c("rcapsule_compose", "rcapsule_spec")` with
fields `content`, `lines`, `config` (parsed list), `services`,
`platform`, `project_type`, `path`, and `scan`.

## Examples

``` r
tmp <- tempfile("rcapsule_compose_")
dir.create(tmp)
writeLines(c("library(shiny)", "shinyApp(fluidPage('Hi'), function(i, o) {})"),
           file.path(tmp, "app.R"))
comp <- compile_compose(tmp)
names(comp$config$services)
#> [1] "app"    "worker" "proxy" 
unlink(tmp, recursive = TRUE)
```
