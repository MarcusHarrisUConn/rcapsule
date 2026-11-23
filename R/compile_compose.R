# Production multi-service docker-compose.yml compiler

#' Compile a Production Multi-Service `docker-compose.yml`
#'
#' Generates a validated, security-hardened `docker-compose.yml` stack tailored
#' to the scanned R project. For Shiny applications, compiles a multi-service
#' stack with the primary `app` service, an async background `worker` service,
#' and a pinned reverse `proxy` (`caddy:2.8.4-alpine`), complete with health
#' checks, resource limits, `no-new-privileges`, read-only data mounts, named
#' output volumes, and an isolated bridge network. For analysis or Quarto
#' projects, compiles a clean reproducible execution service.
#'
#' @param scan An `rcapsule_scan` object from [scan_project()] or a path to a
#'   project directory.
#' @param output Optional file path to write `docker-compose.yml`. If `NULL`,
#'   returns the compiled spec in memory.
#' @param service_name Optional primary service name (defaults to `"app"` for
#'   Shiny projects, or a sanitized slug of `scan$project_name`).
#' @param image_tag Pinned local image tag for the built service (defaults to
#'   `"0.1.0"`). Must not be `"latest"`.
#' @param dockerfile Path to the Dockerfile relative to build context. Defaults
#'   to `"Dockerfile"`.
#' @param include_worker Logical or `NULL`. If `NULL`, automatically enables a
#'   background `worker` service for Shiny projects (especially when async
#'   packages or `worker.R` are detected).
#' @param include_proxy Logical or `NULL`. If `NULL`, automatically enables a
#'   pinned reverse proxy service (`caddy:2.8.4-alpine`) for Shiny projects.
#' @param proxy_image Pinned reverse proxy container image. Defaults to
#'   `"caddy:2.8.4-alpine"`.
#' @param port Internal application port (default `3838L` for Shiny).
#' @param proxy_port Host port mapped to the reverse proxy (default `8080L`).
#' @param memory_limit Memory limit per service (e.g., `"2G"`).
#' @param cpus CPU quota per service as character or numeric (e.g., `"2.0"`).
#' @param env_vars Named list or character vector of extra environment
#'   variables (avoid hardcoding secrets; use `${ENV_VAR}` interpolation).
#' @param volumes Optional character vector of extra volume mounts.
#' @param restart_policy Docker restart policy for long-running services.
#'   Defaults to `"unless-stopped"` for Shiny and `"no"` for batch analyses.
#'
#' @return An S3 object of class `c("rcapsule_compose", "rcapsule_spec")`
#'   with fields `content`, `lines`, `config` (parsed list), `services`,
#'   `project_type`, `path`, and `scan`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_compose_")
#' dir.create(tmp)
#' writeLines(c("library(shiny)", "shinyApp(fluidPage('Hi'), function(i, o) {})"),
#'            file.path(tmp, "app.R"))
#' comp <- compile_compose(tmp)
#' names(comp$config$services)
#' unlink(tmp, recursive = TRUE)
compile_compose <- function(scan,
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
                            restart_policy = NULL) {
  scan <- as_rcapsule_scan(scan)
  is_shiny <- identical(scan$project_type, "shiny")

  image_tag <- validate_image_tag(as.character(image_tag), arg = "image_tag")
  dockerfile <- validate_safe_rel_spec_path(as.character(dockerfile), arg = "dockerfile")
  port <- validate_port_number(port, arg = "port")
  proxy_port <- validate_port_number(proxy_port, arg = "proxy_port")

  slug <- sanitize_slug(scan$project_name, default = "capsule")
  primary_svc <- if (!is.null(service_name)) {
    validate_compose_service_name(as.character(service_name), arg = "service_name")
  } else if (is_shiny) {
    "app"
  } else {
    slug
  }
  with_worker <- if (is.null(include_worker)) is_shiny else isTRUE(include_worker)
  with_proxy <- if (is.null(include_proxy)) is_shiny else isTRUE(include_proxy)
  restart_raw <- restart_policy %||% if (is_shiny) "unless-stopped" else "no"
  res_cfg <- validate_compose_resources(cpus = cpus, memory_limit = memory_limit, restart_policy = restart_raw)
  cpus <- res_cfg$cpus
  memory_limit <- res_cfg$memory_limit
  restart <- res_cfg$restart_policy
  app_image <- paste0(slug, ":", image_tag)

  base_env <- list(
    TZ = "UTC",
    LC_ALL = "C.UTF-8"
  )
  if (is_shiny) {
    base_env$SHINY_PORT <- as.character(port)
    base_env$R_CONFIG_ACTIVE <- "${R_CONFIG_ACTIVE:-production}"
  }
  if (length(scan$seeds_detected) > 0L) {
    base_env$CAPSULE_SEED <- as.character(scan$seeds_detected[[1L]])
  }
  clean_env <- validate_env_vars(env_vars, arg = "env_vars")
  if (length(clean_env) > 0L) {
    for (nm in names(clean_env)) {
      base_env[[nm]] <- clean_env[[nm]]
    }
  }

  base_vols <- c(
    "./data:/capsule/data:ro",
    "capsule-output:/capsule/output"
  )
  if (!is.null(volumes)) {
    extra_vols <- vapply(as.character(volumes), validate_compose_volume, character(1L), USE.NAMES = FALSE)
    base_vols <- unique(c(base_vols, extra_vols))
  }

  primary_hc <- if (is_shiny) {
    list(
      test = c("CMD", "curl", "-fsS", paste0("http://127.0.0.1:", as.integer(port), "/")),
      interval = "30s",
      timeout = "5s",
      retries = 3L,
      start_period = "15s"
    )
  } else {
    list(
      test = c("CMD", "Rscript", "-e", "quit(status = 0)"),
      interval = "30s",
      timeout = "5s",
      retries = 3L,
      start_period = "10s"
    )
  }

  svc_def <- list(
    build = list(
      context = ".",
      dockerfile = dockerfile
    ),
    image = app_image,
    restart = restart,
    environment = base_env,
    volumes = base_vols,
    security_opt = list("no-new-privileges:true"),
    healthcheck = primary_hc,
    deploy = list(
      resources = list(
        limits = list(
          cpus = as.character(cpus),
          memory = as.character(memory_limit)
        )
      )
    ),
    networks = list("capsule-net")
  )

  if (is_shiny) {
    if (with_proxy) {
      svc_def$expose <- list(as.character(as.integer(port)))
    } else {
      svc_def$ports <- list(paste0(as.integer(port), ":", as.integer(port)))
    }
  }

  services <- list()
  services[[primary_svc]] <- svc_def

  # Optional async background worker service
  if (with_worker) {
    has_worker_script <- any(tolower(basename(scan$files$path)) %in% c("worker.r", "workers.r"))
    worker_cmd <- if (has_worker_script) {
      wpath <- validate_safe_rel_spec_path(
        scan$files$path[tolower(basename(scan$files$path)) %in% c("worker.r", "workers.r")][[1L]],
        arg = "worker_script"
      )
      c("Rscript", wpath)
    } else {
      c("Rscript", "-e", "message('rcapsule async worker started'); while (TRUE) Sys.sleep(60)")
    }
    worker_env <- base_env
    worker_env$CAPSULE_ROLE <- "worker"

    services$worker <- list(
      build = list(
        context = ".",
        dockerfile = dockerfile
      ),
      image = app_image,
      command = worker_cmd,
      restart = restart,
      environment = worker_env,
      volumes = base_vols,
      security_opt = list("no-new-privileges:true"),
      healthcheck = list(
        test = c("CMD", "Rscript", "-e", "quit(status = 0)"),
        interval = "30s",
        timeout = "5s",
        retries = 3L,
        start_period = "15s"
      ),
      deploy = list(
        resources = list(
          limits = list(
            cpus = as.character(cpus),
            memory = as.character(memory_limit)
          )
        )
      ),
      networks = list("capsule-net")
    )
  }

  # Optional reverse proxy service (pinned Caddy tag)
  if (with_proxy) {
    validate_docker_image_ref(proxy_image, arg = "proxy_image")
    if (grepl(":latest($|@)", proxy_image, ignore.case = TRUE) ||
      (!grepl(":", proxy_image, fixed = TRUE) && !grepl("@sha256:", proxy_image, fixed = TRUE))) {
      cli::cli_abort("{.arg proxy_image} must use an explicit pinned tag, not {.val {proxy_image}}.")
    }
    dep_list <- list()
    dep_list[[primary_svc]] <- list(condition = "service_healthy")

    services$proxy <- list(
      image = proxy_image,
      restart = restart,
      command = c(
        "caddy", "reverse-proxy",
        "--from", ":80",
        "--to", paste0("http://", primary_svc, ":", as.integer(port))
      ),
      ports = list(paste0(as.integer(proxy_port), ":80")),
      depends_on = dep_list,
      security_opt = list("no-new-privileges:true"),
      healthcheck = list(
        test = c("CMD", "wget", "--spider", "-q", "http://127.0.0.1:80/"),
        interval = "30s",
        timeout = "5s",
        retries = 3L,
        start_period = "10s"
      ),
      deploy = list(
        resources = list(
          limits = list(
            cpus = "0.5",
            memory = "256M"
          )
        )
      ),
      networks = list("capsule-net")
    )
  }

  compose_obj <- list(
    services = services,
    volumes = list(
      `capsule-output` = structure(list(), names = character())
    ),
    networks = list(
      `capsule-net` = list(driver = "bridge")
    )
  )

  yaml_body <- yaml::as.yaml(compose_obj, indent = 2L, indent.mapping.sequence = TRUE)
  # Ensure empty map for capsule-output renders cleanly as "{}" rather than "[]"
  yaml_body <- gsub("capsule-output: \\[\\]", "capsule-output: {}", yaml_body)

  header <- c(
    paste0("# Generated by rcapsule ", as.character(utils::packageVersion("rcapsule"))),
    paste0("# Project: ", sanitize_single_line_text(scan$project_name), " (", scan$project_type, ")")
  )
  content <- paste0(paste(header, collapse = "\n"), "\n", yaml_body)
  lines <- unlist(strsplit(content, "\n", fixed = TRUE), use.names = FALSE)

  # Validate generated YAML round-trips cleanly (with eval.expr = FALSE)
  parsed <- safe_yaml_load(content)
  if (!is.list(parsed) || is.null(parsed$services)) {
    cli::cli_abort("Internal error: compiled docker-compose.yml failed YAML validation.")
  }

  written_path <- NULL
  if (!is.null(output)) {
    fs::dir_create(fs::path_dir(output))
    writeLines(lines, output, useBytes = TRUE)
    written_path <- as.character(fs::path_norm(output))
  }

  structure(
    list(
      spec_type = "compose",
      content = content,
      lines = lines,
      config = parsed,
      services = names(services),
      project_type = scan$project_type,
      path = written_path,
      scan = scan
    ),
    class = c("rcapsule_compose", "rcapsule_spec")
  )
}
