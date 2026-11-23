# Multi-stage, layer-cached Dockerfile compiler for R projects

# Format pinned Docker image reference with optional SHA-256 digest
format_base_image_ref <- function(base_image, r_version, base_digest = NULL, allow_unpinned = FALSE) {
  validate_version_string(r_version, arg = "r_version")
  img <- base_image %||% paste0("rocker/r-ver:", r_version)
  validate_docker_image_ref(img, arg = "base_image")
  if (!is.null(base_digest) && nzchar(base_digest)) {
    dig <- validate_image_digest(base_digest, arg = "base_digest")
    if (!grepl("@sha256:", img, fixed = TRUE)) {
      img <- paste0(img, "@", dig)
    }
  }
  if (!allow_unpinned) {
    # Reject :latest or completely untagged/undigested images
    has_digest <- grepl("@sha256:[0-9a-fA-F]{64}$", img)
    has_tag <- grepl(":[^/@]+($|@)", img)
    is_latest <- grepl(":latest($|@)", img, ignore.case = TRUE)
    if (is_latest || (!has_tag && !has_digest)) {
      cli::cli_abort(
        "Unpinned base image {.val {img}} is disallowed for reproducible capsules. Pin an explicit tag or @sha256 digest (or set {.code allow_unpinned = TRUE})."
      )
    }
  }
  img
}

# Format a multi-line apt-get install command with --no-install-recommends and cleanup
format_apt_run_block <- function(apt_pkgs, prefix = "RUN ") {
  apt_pkgs <- sort(unique(apt_pkgs[!is.na(apt_pkgs) & nzchar(apt_pkgs)]))
  if (length(apt_pkgs) == 0L) {
    return(character())
  }
  validate_apt_package_names(apt_pkgs, arg = "apt_packages")
  pkg_lines <- paste0("      ", apt_pkgs, " \\")
  c(
    paste0(prefix, "apt-get update \\"),
    "    && apt-get install -y --no-install-recommends \\",
    pkg_lines,
    "    && rm -rf /var/lib/apt/lists/*"
  )
}

# Helper to check if a toolchain is active in a scan object
tc_active <- function(scan, name) {
  isTRUE(scan$toolchains[[name]]$detected)
}

#' Compile a Layer-Cached Multi-Stage Dockerfile
#'
#' Compiles an `rcapsule_scan` (or project directory path) into a lean,
#' reproducible, layer-cached `Dockerfile`. Uses pinned Rocker base images
#' (with optional `@sha256:` digests), installs resolved OS system libraries
#' and detected scientific toolchains (`Quarto`, `TinyTeX`, `Python`,
#' `CmdStan`, `TMB`, `JAGS`, `Rust`, `C++`), orders R dependency restoration
#' before project files for optimal Docker cache reuse, drops root privileges,
#' and adds an appropriate `HEALTHCHECK` and `CMD`/`ENTRYPOINT`.
#'
#' @param scan An `rcapsule_scan` object from [scan_project()] or a path to a
#'   project directory.
#' @param output Optional file path to write the compiled `Dockerfile` (e.g.,
#'   `"Dockerfile"`). If `NULL`, returns the compiled spec without writing.
#' @param base_image Optional base Docker image with an explicit pinned tag
#'   (defaults to `paste0("rocker/r-ver:", r_version)`).
#' @param r_version Optional R version string overriding `scan$r_version`.
#' @param base_digest Optional SHA-256 image digest (e.g., `"sha256:..."`)
#'   appended to `base_image` for immutable image pinning.
#' @param platform Optional target container platform (`"linux/amd64"`,
#'   `"linux/arm64"`, or `NULL` for host default). Useful when building
#'   `x86_64` HPC or cloud images on Apple Silicon (`arm64`) hosts.
#' @param cran_repo Optional custom pinned CRAN or Posit Public Package Manager
#'   repository URL used when `renv.lock` is not present. If `NULL` (default),
#'   automatically selects a pinned Posit Package Manager URL controlled by
#'   `use_ppm`, `ppm_distro`, and `ppm_date`.
#' @param use_ppm Logical; if `TRUE` (default) and `cran_repo` is `NULL`, uses
#'   Posit Public Package Manager Linux binary repositories for dramatically
#'   faster reproducible container builds.
#' @param ppm_distro Linux distribution codename for Posit Package Manager
#'   binaries (`"jammy"`, `"noble"`, `"focal"`, `"bookworm"`, or `"bullseye"`).
#'   Defaults to `"jammy"` (Ubuntu 22.04 LTS matching Rocker).
#' @param ppm_date Pinned Posit Package Manager snapshot date (`"YYYY-MM-DD"`).
#'   Defaults to `"2026-01-15"`.
#' @param quarto_version Pinned Quarto CLI version installed when Quarto is
#'   detected. Defaults to `"1.5.57"`.
#' @param cmdstan_version Pinned CmdStan version installed when `cmdstanr` or
#'   `.stan` models are detected. Defaults to `"2.35.0"`.
#' @param user Non-root Linux username for the runtime container. Defaults to
#'   `"capsule"`.
#' @param workdir Working directory inside the container. Defaults to
#'   `"/capsule"`.
#' @param port Port exposed for Shiny apps (defaults to `3838L` when project
#'   type is `"shiny"`, otherwise `NULL`).
#' @param entrypoint Optional override for the runnable entrypoint script or
#'   document.
#' @param multi_stage Logical; if `TRUE` (default), emits a two-stage
#'   `builder` + `runtime` Dockerfile to minimize final image size.
#' @param include_healthcheck Logical; if `TRUE` (default), adds a
#'   `HEALTHCHECK` instruction.
#' @param allow_unpinned Logical; if `FALSE` (default), refuses `:latest` or
#'   untagged base images.
#'
#' @return An S3 object of class `c("rcapsule_dockerfile", "rcapsule_spec")`
#'   with fields `content`, `lines`, `base_image`, `platform`, `cran_repo`,
#'   `use_ppm`, `stages`, `project_type`, `path`, and `scan`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_df_")
#' dir.create(tmp)
#' writeLines(c("library(jsonlite)", "cat('ok\\n')"), file.path(tmp, "run.R"))
#' df <- compile_dockerfile(tmp)
#' cat(df$content)
#' unlink(tmp, recursive = TRUE)
compile_dockerfile <- function(scan,
                               output = NULL,
                               base_image = NULL,
                               r_version = NULL,
                               base_digest = NULL,
                               platform = NULL,
                               cran_repo = NULL,
                               use_ppm = TRUE,
                               ppm_distro = "jammy",
                               ppm_date = "2026-01-15",
                               quarto_version = "1.5.57",
                               cmdstan_version = "2.35.0",
                               user = "capsule",
                               workdir = "/capsule",
                               port = NULL,
                               entrypoint = NULL,
                               multi_stage = TRUE,
                               include_healthcheck = TRUE,
                               allow_unpinned = FALSE) {
  scan <- as_rcapsule_scan(scan)
  r_ver <- validate_version_string(as.character(r_version %||% scan$r_version), arg = "r_version")
  base_ref <- format_base_image_ref(base_image, r_ver, base_digest, allow_unpinned = allow_unpinned)
  platform <- validate_container_platform(platform, arg = "platform")
  ppm_distro <- validate_ppm_distro(ppm_distro, arg = "ppm_distro")
  ppm_date <- validate_snapshot_date(ppm_date, arg = "ppm_date")
  if (is.null(cran_repo)) {
    cran_repo <- if (isTRUE(use_ppm)) {
      paste0("https://packagemanager.posit.co/cran/__linux__/", ppm_distro, "/", ppm_date)
    } else {
      paste0("https://packagemanager.posit.co/cran/", ppm_date)
    }
  }
  validate_cran_repo_url(cran_repo, arg = "cran_repo")
  validate_version_string(quarto_version, arg = "quarto_version")
  validate_version_string(cmdstan_version, arg = "cmdstan_version")
  validate_linux_username(user, arg = "user")
  validate_container_workdir(workdir, arg = "workdir")

  ep <- entrypoint %||% scan$entrypoint
  if (!is.null(ep) && !identical(ep, ".")) {
    validate_safe_rel_spec_path(ep, arg = "entrypoint")
  }
  expose_port <- if (!is.null(port)) {
    validate_port_number(port, arg = "port")
  } else if (identical(scan$project_type, "shiny")) {
    3838L
  } else {
    NULL
  }

  safe_proj_comment <- sanitize_single_line_text(scan$project_name)
  safe_proj_label <- escape_dockerfile_label(scan$project_name)

  has_quarto <- tc_active(scan, "quarto")
  has_latex <- tc_active(scan, "latex")
  has_python <- tc_active(scan, "python")
  has_cmdstan <- tc_active(scan, "cmdstan")
  has_jags <- tc_active(scan, "jags")
  has_rust <- tc_active(scan, "rust")
  has_java <- tc_active(scan, "java")

  build_apt <- unique(c(
    "ca-certificates",
    scan$sysreqs$apt_package[scan$sysreqs$stage == "build"]
  ))
  runtime_apt <- unique(c(
    "ca-certificates",
    scan$sysreqs$apt_package[scan$sysreqs$stage == "runtime"]
  ))
  if (has_quarto) {
    build_apt <- unique(c(build_apt, "curl"))
  }
  if (identical(scan$project_type, "shiny")) {
    runtime_apt <- unique(c(runtime_apt, "curl"))
  }
  if (has_cmdstan) {
    runtime_apt <- unique(c(runtime_apt, "build-essential", "g++", "make", "libtbb12"))
  }
  if (has_jags) {
    runtime_apt <- unique(c(runtime_apt, "jags"))
  }
  if (has_python) {
    runtime_apt <- unique(c(runtime_apt, "python3", "python3-venv"))
  }
  if (has_java) {
    runtime_apt <- unique(c(runtime_apt, "default-jre-headless"))
  }

  req_r_pkgs <- validate_r_package_names(
    scan$packages$package[!scan$packages$is_base & scan$packages$required],
    arg = "scan$packages"
  )
  # Recommended packages ship in rocker/r-ver; keep them out unless explicitly pinned in renv
  install_r_pkgs <- setdiff(req_r_pkgs, recommended_r_packages())

  lines <- c(
    "# syntax=docker/dockerfile:1.7",
    paste0("# Generated by rcapsule ", as.character(utils::packageVersion("rcapsule"))),
    paste0("# Project: ", safe_proj_comment, " (", scan$project_type, ") | R ", r_ver),
    ""
  )

  # --- Stage 1: Builder (or single-stage) ---
  from_prefix <- if (!is.null(platform)) paste0("FROM --platform=", platform, " ") else "FROM "
  if (isTRUE(multi_stage)) {
    lines <- c(lines, paste0(from_prefix, base_ref, " AS builder"))
  } else {
    lines <- c(lines, paste0(from_prefix, base_ref))
  }

  lines <- c(
    lines,
    "",
    "ENV DEBIAN_FRONTEND=noninteractive \\",
    "    TZ=UTC \\",
    "    LANG=C.UTF-8 \\",
    "    LC_ALL=C.UTF-8 \\",
    paste0("    R_REPOS=", cran_repo)
  )

  if (scan$has_renv) {
    lines <- c(
      lines,
      "ENV RENV_PATHS_LIBRARY=/opt/renv/library \\",
      "    RENV_CONFIG_AUTOLOADER_ENABLED=FALSE"
    )
  }

  lines <- c(lines, "", "# 1. OS system dependencies (build + runtime)")
  lines <- c(lines, format_apt_run_block(build_apt))

  # Toolchain layers (ordered from most stable to most specific)
  if (has_quarto) {
    lines <- c(
      lines,
      "",
      paste0("# 2. Quarto CLI (", quarto_version, ")"),
      paste0("ARG QUARTO_VERSION=", quarto_version),
      "RUN ARCH=$(dpkg --print-architecture) \\",
      "    && mkdir -p /opt/quarto \\",
      "    && curl -fsSL \"https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${ARCH}.tar.gz\" \\",
      "       -o /tmp/quarto.tar.gz \\",
      "    && tar -xzf /tmp/quarto.tar.gz -C /opt/quarto --strip-components=1 \\",
      "    && ln -sf /opt/quarto/bin/quarto /usr/local/bin/quarto \\",
      "    && rm -f /tmp/quarto.tar.gz"
    )
  }

  if (has_latex) {
    lines <- c(
      lines,
      "",
      "# TinyTeX / LaTeX distribution",
      "ENV TINYTEX_DIR=/opt/TinyTeX \\",
      "    PATH=\"/opt/TinyTeX/bin/x86_64-linux:/opt/TinyTeX/bin/aarch64-linux:${PATH}\"",
      "RUN Rscript -e \"install.packages('tinytex', repos = Sys.getenv('R_REPOS')); tinytex::install_tinytex(dir = '/opt/TinyTeX', force = TRUE)\""
    )
  }

  if (has_python) {
    lines <- c(
      lines,
      "",
      "# Python virtual environment for reticulate / Jupyter",
      "ENV VIRTUAL_ENV=/opt/venv \\",
      "    RETICULATE_PYTHON=/opt/venv/bin/python \\",
      "    PATH=\"/opt/venv/bin:${PATH}\"",
      "RUN python3 -m venv /opt/venv \\",
      "    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip"
    )
    has_req_txt <- "requirements.txt" %in% tolower(scan$files$path)
    if (has_req_txt) {
      req_rel <- validate_safe_rel_spec_path(
        scan$files$path[tolower(scan$files$path) == "requirements.txt"][[1L]],
        arg = "requirements.txt"
      )
      lines <- c(
        lines,
        paste0("COPY ", req_rel, " /tmp/requirements.txt"),
        "RUN /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt \\",
        "    && rm -f /tmp/requirements.txt"
      )
    } else if (length(scan$python_packages) > 0L) {
      py_specs <- validate_python_package_specs(scan$python_packages, arg = "python_packages")
      py_list <- paste(sprintf("'%s'", py_specs), collapse = " ")
      lines <- c(
        lines,
        paste0("RUN /opt/venv/bin/pip install --no-cache-dir ", py_list)
      )
    }
  }

  if (has_rust) {
    lines <- c(
      lines,
      "",
      "# Rust toolchain configuration",
      "ENV CARGO_HOME=/opt/cargo \\",
      "    PATH=\"/opt/cargo/bin:${PATH}\""
    )
  }

  lines <- c(lines, "", paste0("WORKDIR ", workdir))

  # R dependency layer BEFORE copying full project sources (preserves Docker build cache!)
  lines <- c(lines, "", "# R package dependencies (cached independently of project code)")
  if (scan$has_renv) {
    lines <- c(lines, "COPY renv.lock ./")
    if (".Rprofile" %in% scan$files$path) {
      lines <- c(lines, "COPY .Rprofile ./")
    }
    if ("renv/activate.R" %in% scan$files$path) {
      lines <- c(lines, "COPY renv/activate.R renv/activate.R")
    }
    lines <- c(
      lines,
      "RUN mkdir -p /opt/renv/library \\",
      "    && Rscript -e \"install.packages('renv', repos = Sys.getenv('R_REPOS')); renv::restore(prompt = FALSE)\""
    )
  } else if (scan$has_description) {
    lines <- c(
      lines,
      "COPY DESCRIPTION ./",
      "RUN Rscript -e \"install.packages('remotes', repos = Sys.getenv('R_REPOS')); remotes::install_deps('.', dependencies = FALSE, upgrade = 'never', repos = Sys.getenv('R_REPOS'))\""
    )
  } else if (length(install_r_pkgs) > 0L) {
    pkg_vec <- paste(sprintf("'%s'", sort(unique(install_r_pkgs))), collapse = ", ")
    lines <- c(
      lines,
      paste0(
        "RUN Rscript -e \"install.packages(c(", pkg_vec,
        "), repos = Sys.getenv('R_REPOS'), Ncpus = parallel::detectCores())\""
      )
    )
  } else {
    lines <- c(lines, "# Base R packages only; no external CRAN installs required.")
  }

  if (has_cmdstan) {
    lines <- c(
      lines,
      "",
      paste0("# CmdStan toolchain (", cmdstan_version, ")"),
      paste0("ARG CMDSTAN_VERSION=", cmdstan_version),
      paste0("ENV CMDSTAN=/opt/cmdstan/cmdstan-", cmdstan_version),
      "RUN mkdir -p /opt/cmdstan \\",
      "    && Rscript -e \"if (!requireNamespace('cmdstanr', quietly = TRUE)) install.packages('cmdstanr', repos = c('https://stan-dev.r-universe.dev', Sys.getenv('R_REPOS'))); cmdstanr::install_cmdstan(dir = '/opt/cmdstan', version = Sys.getenv('CMDSTAN_VERSION'), cores = parallel::detectCores(), quiet = FALSE)\""
    )
  }

  # --- Stage 2: Runtime ---
  if (isTRUE(multi_stage)) {
    lines <- c(
      lines,
      "",
      "# =============================================================================",
      "# Runtime stage: lean non-root execution image",
      "# =============================================================================",
      paste0(from_prefix, base_ref, " AS runtime"),
      ""
    )
  } else {
    lines <- c(lines, "")
  }

  # OCI & rcapsule metadata labels
  rev_val <- escape_dockerfile_label(scan$git$commit %||% "uncommitted")
  lines <- c(
    lines,
    paste0("LABEL org.opencontainers.image.title=\"", safe_proj_label, "\" \\"),
    paste0("      org.opencontainers.image.revision=\"", rev_val, "\" \\"),
    paste0("      org.rcapsule.version=\"", as.character(utils::packageVersion("rcapsule")), "\" \\"),
    paste0("      org.rcapsule.project_type=\"", scan$project_type, "\" \\"),
    paste0("      org.rcapsule.r_version=\"", r_ver, "\""),
    ""
  )

  # Runtime environment variables
  env_pairs <- c(
    "TZ=UTC",
    "LANG=C.UTF-8",
    "LC_ALL=C.UTF-8"
  )
  if (scan$has_renv) {
    env_pairs <- c(
      env_pairs,
      "RENV_PATHS_LIBRARY=/opt/renv/library",
      "R_LIBS_USER=/opt/renv/library"
    )
  }
  if (has_python) {
    env_pairs <- c(
      env_pairs,
      "VIRTUAL_ENV=/opt/venv",
      "RETICULATE_PYTHON=/opt/venv/bin/python"
    )
  }
  if (has_cmdstan) {
    env_pairs <- c(env_pairs, paste0("CMDSTAN=/opt/cmdstan/cmdstan-", cmdstan_version))
  }
  if (has_latex) {
    env_pairs <- c(env_pairs, "TINYTEX_DIR=/opt/TinyTeX")
  }
  extra_paths <- character()
  if (has_python) extra_paths <- c(extra_paths, "/opt/venv/bin")
  if (has_quarto) extra_paths <- c(extra_paths, "/opt/quarto/bin")
  if (has_latex) extra_paths <- c(extra_paths, "/opt/TinyTeX/bin/x86_64-linux", "/opt/TinyTeX/bin/aarch64-linux")
  if (length(extra_paths) > 0L) {
    env_pairs <- c(env_pairs, paste0("PATH=\"", paste(extra_paths, collapse = ":"), ":${PATH}\""))
  }

  if (length(env_pairs) == 1L) {
    lines <- c(lines, paste0("ENV ", env_pairs[[1L]]))
  } else {
    lines <- c(
      lines,
      paste0("ENV ", env_pairs[[1L]], " \\"),
      paste0("    ", env_pairs[seq(2L, length(env_pairs) - 1L)], " \\")[length(env_pairs) > 2L],
      paste0("    ", env_pairs[[length(env_pairs)]])
    )
  }

  if (isTRUE(multi_stage)) {
    lines <- c(lines, "", "# Runtime-only OS libraries")
    lines <- c(lines, format_apt_run_block(runtime_apt))
    lines <- c(
      lines,
      "",
      "# Copy compiled R libraries and toolchains from builder",
      "COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library"
    )
    if (scan$has_renv) {
      lines <- c(lines, "COPY --from=builder /opt/renv/library /opt/renv/library")
    }
    if (has_quarto) {
      lines <- c(
        lines,
        "COPY --from=builder /opt/quarto /opt/quarto",
        "RUN ln -sf /opt/quarto/bin/quarto /usr/local/bin/quarto"
      )
    }
    if (has_latex) {
      lines <- c(lines, "COPY --from=builder /opt/TinyTeX /opt/TinyTeX")
    }
    if (has_python) {
      lines <- c(lines, "COPY --from=builder /opt/venv /opt/venv")
    }
    if (has_cmdstan) {
      lines <- c(lines, "COPY --from=builder /opt/cmdstan /opt/cmdstan")
    }
  }

  # Non-root user, WORKDIR, and project copy
  lines <- c(
    lines,
    "",
    "# Create dedicated non-root runtime user",
    paste0(
      "RUN groupadd --system ", user,
      " && useradd --system --gid ", user,
      " --create-home ", user,
      " && mkdir -p ", workdir,
      " && chown -R ", user, ":", user, " ", workdir
    ),
    "",
    paste0("WORKDIR ", workdir),
    paste0("COPY --chown=", user, ":", user, " . ", workdir, "/"),
    ""
  )

  if (identical(scan$project_type, "package")) {
    lines <- c(
      lines,
      "RUN R CMD INSTALL --no-multiarch --with-keep.source .",
      ""
    )
  }

  lines <- c(lines, paste0("USER ", user))

  if (!is.null(expose_port)) {
    lines <- c(lines, "", paste0("EXPOSE ", as.integer(expose_port)))
  }

  if (isTRUE(include_healthcheck)) {
    hc_cmd <- if (identical(scan$project_type, "shiny")) {
      paste0("curl -fsS http://127.0.0.1:", as.integer(expose_port %||% 3838L), "/ || exit 1")
    } else {
      "Rscript -e \"quit(status = 0)\" || exit 1"
    }
    lines <- c(
      lines,
      "",
      paste0(
        "HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \\\n",
        "    CMD ", hc_cmd
      )
    )
  }

  # Entrypoint / CMD
  cmd_line <- if (identical(scan$project_type, "shiny")) {
    paste0(
      "CMD [\"Rscript\", \"-e\", \"shiny::runApp('", workdir,
      "', host = '0.0.0.0', port = ", as.integer(expose_port %||% 3838L), "L)\"]"
    )
  } else if (identical(scan$project_type, "quarto")) {
    if (isTRUE(scan$has_quarto_yml)) {
      "CMD [\"quarto\", \"render\"]"
    } else {
      paste0("CMD [\"quarto\", \"render\", \"", ep %||% "index.qmd", "\"]")
    }
  } else if (identical(scan$project_type, "rmarkdown")) {
    paste0("CMD [\"Rscript\", \"-e\", \"rmarkdown::render('", ep %||% "report.Rmd", "')\"]")
  } else if (identical(scan$project_type, "package")) {
    "CMD [\"R\", \"--no-save\"]"
  } else {
    if (!is.null(ep) && identical(tolower(basename(ep)), "_targets.r")) {
      "CMD [\"Rscript\", \"-e\", \"targets::tar_make()\"]"
    } else if (!is.null(ep)) {
      paste0("CMD [\"Rscript\", \"", ep, "\"]")
    } else {
      "CMD [\"R\", \"--no-save\"]"
    }
  }

  lines <- c(lines, "", cmd_line)
  # Flatten any embedded newlines cleanly
  lines <- unlist(strsplit(lines, "\n", fixed = TRUE), use.names = FALSE)
  content <- paste0(paste(lines, collapse = "\n"), "\n")

  written_path <- NULL
  if (!is.null(output)) {
    fs::dir_create(fs::path_dir(output))
    writeLines(lines, output, useBytes = TRUE)
    written_path <- as.character(fs::path_norm(output))
  }

  structure(
    list(
      spec_type = "dockerfile",
      content = content,
      lines = lines,
      base_image = base_ref,
      platform = platform,
      cran_repo = cran_repo,
      use_ppm = isTRUE(use_ppm),
      stages = if (isTRUE(multi_stage)) c("builder", "runtime") else "single",
      project_type = scan$project_type,
      path = written_path,
      scan = scan
    ),
    class = c("rcapsule_dockerfile", "rcapsule_spec")
  )
}

#' @export
as.character.rcapsule_spec <- function(x, ...) {
  x$content
}

#' @export
print.rcapsule_spec <- function(x, ...) {
  cli::cli_h1("rcapsule Compiled Spec ({x$spec_type})")
  cli::cli_ul(c(
    "Project: {.val {x$scan$project_name}} ({x$project_type})",
    "Lines: {length(x$lines)}",
    "Written to: {.path {x$path %||% '<in-memory>'}}"
  ))
  preview_n <- min(length(x$lines), 25L)
  cli::cli_verbatim(paste(x$lines[seq_len(preview_n)], collapse = "\n"))
  if (length(x$lines) > preview_n) {
    cli::cli_text("{.emph ... ({length(x$lines) - preview_n} more lines; use cat(x$content) to view all)}")
  }
  invisible(x)
}
