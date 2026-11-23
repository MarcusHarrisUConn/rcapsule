# Internal shared utilities and runtime capability checks

#' Check whether Docker daemon is available
#'
#' Tests whether the `docker` CLI is on `PATH` and the Docker daemon responds
#' cleanly to `docker info`. Useful for guarding live-container integration
#' tests and deciding between `"docker"` and `"sandbox"` verification runners.
#'
#' @param timeout Maximum seconds to wait for `docker info`. Defaults to `5`.
#'
#' @return A single logical value (`TRUE` if Docker is usable, `FALSE`
#'   otherwise).
#' @export
#' @examples
#' docker_available()
docker_available <- function(timeout = 5) {
  docker_bin <- Sys.which("docker")
  if (!nzchar(docker_bin)) {
    return(FALSE)
  }
  res <- tryCatch(
    processx::run(
      command = unname(docker_bin),
      args = c("info", "--format", "{{.ServerVersion}}"),
      timeout = timeout,
      error_on_status = FALSE
    ),
    error = function(e) NULL
  )
  !is.null(res) && identical(res$status, 0L) && nzchar(trimws(res$stdout))
}

#' Check whether Apptainer or Singularity CLI is available
#'
#' Tests whether `apptainer` or `singularity` is installed on `PATH` and
#' responds to `--version`.
#'
#' @param timeout Maximum seconds to wait for the version check. Defaults to `5`.
#'
#' @return A single logical value (`TRUE` if Apptainer/Singularity is usable,
#'   `FALSE` otherwise).
#' @export
#' @examples
#' apptainer_available()
apptainer_available <- function(timeout = 5) {
  bin <- Sys.which("apptainer")
  if (!nzchar(bin)) {
    bin <- Sys.which("singularity")
  }
  if (!nzchar(bin)) {
    return(FALSE)
  }
  res <- tryCatch(
    processx::run(
      command = unname(bin),
      args = "--version",
      timeout = timeout,
      error_on_status = FALSE
    ),
    error = function(e) NULL
  )
  !is.null(res) && identical(res$status, 0L)
}

# Normalize and validate a project directory path
normalize_project_path <- function(path, must_exist = TRUE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    cli::cli_abort("{.arg path} must be a non-empty single character string.")
  }
  if (must_exist && !fs::dir_exists(path)) {
    cli::cli_abort("Project directory does not exist: {.path {path}}.")
  }
  as.character(fs::path_norm(fs::path_abs(path)))
}

# Compute POSIX-style relative path with forward slashes
rel_path <- function(path, start) {
  rel <- as.character(fs::path_rel(fs::path_abs(path), start = fs::path_abs(start)))
  gsub("\\\\", "/", rel)
}

# Current UTC timestamp in ISO-8601 format
utc_now_iso <- function() {
  format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# Current R version as "major.minor.patch"
current_r_version <- function() {
  paste(R.version$major, R.version$minor, sep = ".")
}

# Base R packages that ship with R and do not require installation
base_r_packages <- function() {
  c(
    "base", "compiler", "datasets", "graphics", "grDevices", "grid",
    "methods", "parallel", "splines", "stats", "stats4", "tcltk",
    "tools", "translations", "utils"
  )
}

# Recommended packages shipped with standard Rocker / R installations
recommended_r_packages <- function() {
  c(
    "boot", "class", "cluster", "codetools", "foreign", "KernSmooth",
    "lattice", "MASS", "Matrix", "mgcv", "nlme", "nnet", "rpart",
    "spatial", "survival"
  )
}

# Canonicalize nested lists recursively by sorting named list keys
canonicalize_object <- function(x) {
  if (is.list(x) && !is.data.frame(x)) {
    nms <- names(x)
    if (!is.null(nms) && length(nms) > 0L) {
      ord <- order(nms)
      x <- x[ord]
    }
    x <- lapply(x, canonicalize_object)
  }
  x
}

# Deterministic compact canonical JSON representation for cryptographic hashing
to_canonical_json <- function(x) {
  canon <- canonicalize_object(x)
  as.character(jsonlite::toJSON(
    canon,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    pretty = FALSE
  ))
}

# Pretty deterministic JSON for human-readable capsule.json output
to_pretty_json <- function(x) {
  as.character(jsonlite::toJSON(
    x,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    pretty = TRUE
  ))
}

# Strip openssl hash S3 class into a plain character scalar
as_plain_hex <- function(x) {
  paste0(unclass(as.character(x)), collapse = "")
}

# SHA-256 hex digest of a file using openssl streaming
sha256_file <- function(path) {
  if (!fs::file_exists(path)) {
    cli::cli_abort("Cannot hash missing file: {.path {path}}.")
  }
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  as_plain_hex(openssl::sha256(con))
}

# SHA-256 hex digest of a raw vector
sha256_raw <- function(raw_bytes) {
  as_plain_hex(openssl::sha256(raw_bytes))
}

# SHA-256 hex digest of a character string
sha256_string <- function(text) {
  as_plain_hex(openssl::sha256(paste(text, collapse = "\n")))
}

# HMAC-SHA256 hex digest using openssl
hmac_sha256 <- function(text, key) {
  if (!is.character(key) || length(key) != 1L || is.na(key) || !nzchar(key)) {
    cli::cli_abort("{.arg key} must be a non-empty character string.")
  }
  as_plain_hex(openssl::sha256(paste(text, collapse = "\n"), key = key))
}

# Constant-time string equality check for cryptographic MAC verification
constant_time_equal <- function(a, b) {
  if (!is.character(a) || !is.character(b) || length(a) != 1L || length(b) != 1L) {
    return(FALSE)
  }
  if (is.na(a) || is.na(b)) {
    return(FALSE)
  }
  ra <- charToRaw(a)
  rb <- charToRaw(b)
  if (length(ra) != length(rb)) {
    return(FALSE)
  }
  diff_bits <- bitwXor(as.integer(ra), as.integer(rb))
  identical(sum(diff_bits), 0L)
}

# Inspect git metadata for a project directory safely
detect_git_info <- function(path) {
  default_info <- list(
    is_repo = FALSE,
    commit = NULL,
    short_commit = NULL,
    branch = NULL,
    dirty = NA,
    remote = NULL
  )
  git_bin <- Sys.which("git")
  if (!nzchar(git_bin)) {
    return(default_info)
  }
  run_git <- function(args) {
    tryCatch(
      processx::run(
        command = unname(git_bin),
        args = args,
        wd = path,
        timeout = 5,
        error_on_status = FALSE
      ),
      error = function(e) NULL
    )
  }

  check <- run_git(c("rev-parse", "--is-inside-work-tree"))
  if (is.null(check) || !identical(check$status, 0L) || trimws(check$stdout) != "true") {
    return(default_info)
  }

  commit_res <- run_git(c("rev-parse", "HEAD"))
  commit <- if (!is.null(commit_res) && identical(commit_res$status, 0L)) {
    trimws(commit_res$stdout)
  } else {
    NULL
  }

  branch_res <- run_git(c("rev-parse", "--abbrev-ref", "HEAD"))
  branch <- if (!is.null(branch_res) && identical(branch_res$status, 0L)) {
    trimws(branch_res$stdout)
  } else {
    NULL
  }

  status_res <- run_git(c("status", "--porcelain"))
  dirty <- if (!is.null(status_res) && identical(status_res$status, 0L)) {
    nzchar(trimws(status_res$stdout))
  } else {
    NA
  }

  remote_res <- run_git(c("config", "--get", "remote.origin.url"))
  remote <- if (!is.null(remote_res) && identical(remote_res$status, 0L) &&
    nzchar(trimws(remote_res$stdout))) {
    trimws(remote_res$stdout)
  } else {
    NULL
  }

  list(
    is_repo = TRUE,
    commit = commit,
    short_commit = if (!is.null(commit)) substr(commit, 1L, 7L) else NULL,
    branch = branch,
    dirty = dirty,
    remote = remote
  )
}

# Detect artifact format from file path/extension
detect_artifact_format <- function(path) {
  bn <- basename(path)
  if (grepl("^Dockerfile(\\..+)?$", bn, ignore.case = FALSE)) {
    return("dockerfile")
  }
  if (grepl("^docker-compose(\\.[^.]+)?\\.ya?ml$", bn, ignore.case = TRUE)) {
    return("compose")
  }
  ext <- tolower(tools::file_ext(bn))
  switch(
    ext,
    "csv" = "csv",
    "tsv" = "tsv",
    "tab" = "tsv",
    "json" = "json",
    "rds" = "rds",
    "r" = "r",
    "qmd" = "quarto",
    "rmd" = "rmarkdown",
    "def" = "apptainer",
    "yml" = "yaml",
    "yaml" = "yaml",
    "txt" = "text",
    "md" = "markdown",
    "html" = "html",
    "htm" = "html",
    "png" = "binary",
    "jpg" = "binary",
    "jpeg" = "binary",
    "pdf" = "binary",
    "svg" = "text",
    "zip" = "binary",
    "gz" = "binary",
    "parquet" = "binary",
    "stan" = "stan",
    if (nzchar(ext)) "text" else "binary"
  )
}

# Sanitize a project name into a valid container/service slug
sanitize_slug <- function(x, default = "capsule") {
  if (is.null(x) || !nzchar(x)) {
    return(default)
  }
  slug <- tolower(gsub("[^a-zA-Z0-9_-]+", "-", x))
  slug <- gsub("^-+|-+$", "", slug)
  if (!nzchar(slug)) default else slug
}

# Ensure a scan object is available whether given a path or rcapsule_scan
as_rcapsule_scan <- function(x) {
  if (inherits(x, "rcapsule_scan")) {
    return(x)
  }
  if (is.character(x) && length(x) == 1L && nzchar(x)) {
    return(scan_project(x))
  }
  cli::cli_abort(
    "{.arg scan} must be an {.cls rcapsule_scan} object or a project directory path."
  )
}
