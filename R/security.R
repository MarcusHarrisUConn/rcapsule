# Centralized security, sanitization, path confinement, crypto, and env scrubbing

# -----------------------------------------------------------------------------
# 1. Input Validation & Container Injection Prevention
# -----------------------------------------------------------------------------

# Reject NUL bytes, CR/LF newlines, and ASCII control characters
assert_no_control_chars <- function(x, arg = "value") {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort("{.arg {arg}} must be a single non-NA character string.")
  }
  if (grepl("[\\x00-\\x1f\\x7f]", x, perl = TRUE)) {
    cli::cli_abort(
      "Unsafe control character or newline detected in {.arg {arg}}: rejected to prevent injection."
    )
  }
  x
}

# Validate CRAN-compliant R package name (also allows single-letter? CRAN requires >=2)
is_valid_r_pkg_name <- function(x) {
  if (!is.character(x) || length(x) == 0L) {
    return(logical())
  }
  !is.na(x) & grepl("^[A-Za-z][A-Za-z0-9.]*[A-Za-z0-9]$", x, perl = TRUE) & !grepl("\\.\\.", x)
}

validate_r_package_names <- function(pkgs, arg = "packages") {
  if (length(pkgs) == 0L) return(character())
  pkgs <- as.character(pkgs)
  bad <- !is_valid_r_pkg_name(pkgs)
  if (any(bad)) {
    bad_vals <- pkgs[bad]
    cli::cli_abort(
      "Invalid or unsafe R package name(s) in {.arg {arg}}: {.val {bad_vals}}."
    )
  }
  pkgs
}

# Validate Debian/Ubuntu apt package name (strict allowlist)
validate_apt_package_names <- function(pkgs, arg = "apt_packages") {
  if (length(pkgs) == 0L) return(character())
  pkgs <- as.character(pkgs)
  bad <- is.na(pkgs) | !grepl("^[a-z0-9][a-z0-9+.\\-]+$", pkgs, perl = TRUE)
  if (any(bad)) {
    bad_vals <- pkgs[bad]
    cli::cli_abort(
      "Invalid or unsafe apt package name(s) in {.arg {arg}}: {.val {bad_vals}}."
    )
  }
  pkgs
}

# Validate Python requirement / package specifier (safe PEP 508 subset, no flags/shell metachars)
validate_python_package_specs <- function(pkgs, arg = "python_packages") {
  if (length(pkgs) == 0L) return(character())
  pkgs <- as.character(pkgs)
  pat <- "^[A-Za-z0-9][A-Za-z0-9._\\-\\[\\],]*((==|>=|<=|~=|!=|>|<)[A-Za-z0-9._*+\\-]+)?$"
  bad <- is.na(pkgs) | !grepl(pat, pkgs, perl = TRUE)
  if (any(bad)) {
    bad_vals <- pkgs[bad]
    cli::cli_abort(
      "Invalid or unsafe Python package specifier(s) in {.arg {arg}}: {.val {bad_vals}}."
    )
  }
  pkgs
}

# Validate semantic/dotted version string (R, Quarto, CmdStan)
validate_version_string <- function(x, arg = "version") {
  assert_no_control_chars(x, arg = arg)
  if (!grepl("^[0-9]+(\\.[0-9]+){1,3}([\\-+.~][A-Za-z0-9.]+)?$", x, perl = TRUE)) {
    cli::cli_abort(
      "Invalid version string for {.arg {arg}}: {.val {x}}."
    )
  }
  x
}

# Validate Docker / OCI target platform (e.g., "linux/amd64", "linux/arm64")
validate_container_platform <- function(x, arg = "platform") {
  if (is.null(x)) return(NULL)
  assert_no_control_chars(x, arg = arg)
  valid_platforms <- c("linux/amd64", "linux/arm64", "linux/arm/v7")
  if (!(x %in% valid_platforms)) {
    cli::cli_abort(
      "{.arg {arg}} must be NULL or one of {.val {valid_platforms}}, not {.val {x}}."
    )
  }
  x
}

# Validate Posit Package Manager Linux distro codename
validate_ppm_distro <- function(x, arg = "ppm_distro") {
  assert_no_control_chars(x, arg = arg)
  valid_distros <- c("jammy", "noble", "focal", "bookworm", "bullseye")
  if (!(x %in% valid_distros)) {
    cli::cli_abort(
      "{.arg {arg}} must be one of {.val {valid_distros}}, not {.val {x}}."
    )
  }
  x
}

# Validate snapshot date YYYY-MM-DD for Posit Package Manager
validate_snapshot_date <- function(x, arg = "ppm_date") {
  assert_no_control_chars(x, arg = arg)
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x, perl = TRUE)) {
    cli::cli_abort("{.arg {arg}} must be an ISO date 'YYYY-MM-DD', not {.val {x}}.")
  }
  x
}

# Validate Docker / OCI image reference (no whitespace, newlines, or shell metacharacters)
validate_docker_image_ref <- function(x, arg = "base_image") {
  assert_no_control_chars(x, arg = arg)
  pat <- "^[a-zA-Z0-9][a-zA-Z0-9._/:\\-]*(?:@sha256:[0-9a-fA-F]{64})?$"
  if (!grepl(pat, x, perl = TRUE) || grepl("\\.\\.", x, fixed = TRUE)) {
    cli::cli_abort(
      "Invalid or unsafe container image reference in {.arg {arg}}: {.val {x}}."
    )
  }
  x
}

# Validate SHA-256 image digest
validate_image_digest <- function(x, arg = "base_digest") {
  assert_no_control_chars(x, arg = arg)
  dig <- if (grepl("^sha256:", x)) x else paste0("sha256:", x)
  if (!grepl("^sha256:[0-9a-fA-F]{64}$", dig, perl = TRUE)) {
    cli::cli_abort(
      "Invalid SHA-256 image digest in {.arg {arg}}: {.val {x}}."
    )
  }
  tolower(dig)
}

# Validate pinned CRAN / Posit PPM HTTP(S) URL
validate_cran_repo_url <- function(x, arg = "cran_repo") {
  assert_no_control_chars(x, arg = arg)
  if (!grepl("^https?://[A-Za-z0-9._:/\\-]+$", x, perl = TRUE)) {
    cli::cli_abort(
      "Invalid or unsafe repository URL in {.arg {arg}}: {.val {x}}."
    )
  }
  x
}

# Validate Linux non-root runtime username
validate_linux_username <- function(x, arg = "user") {
  assert_no_control_chars(x, arg = arg)
  if (!grepl("^[a-z_][a-z0-9_-]{0,31}$", x, perl = TRUE)) {
    cli::cli_abort(
      "Invalid Linux username in {.arg {arg}}: {.val {x}}."
    )
  }
  if (identical(x, "root")) {
    cli::cli_abort(
      "{.arg {arg}} cannot be {.val root}; rcapsule requires a non-root runtime user."
    )
  }
  x
}

# Validate container absolute path (e.g., WORKDIR /capsule)
validate_container_workdir <- function(x, arg = "workdir") {
  assert_no_control_chars(x, arg = arg)
  if (!grepl("^/[A-Za-z0-9._/\\-]+$", x, perl = TRUE) || grepl("(^|/)\\.\\.(/|$)", x, perl = TRUE)) {
    cli::cli_abort(
      "Invalid or unsafe container path in {.arg {arg}}: {.val {x}}."
    )
  }
  x
}

# Validate TCP port number
validate_port_number <- function(x, arg = "port") {
  val <- suppressWarnings(as.integer(x))
  if (length(val) != 1L || is.na(val) || val < 1L || val > 65535L) {
    cli::cli_abort("{.arg {arg}} must be an integer TCP port between 1 and 65535.")
  }
  val
}

# Validate relative entrypoint or Dockerfile path (no traversal, quotes, shell metachars, or control chars)
validate_safe_rel_spec_path <- function(x, arg = "entrypoint") {
  assert_no_control_chars(x, arg = arg)
  if (!nzchar(x)) {
    cli::cli_abort("{.arg {arg}} must be a non-empty relative path.")
  }
  if (grepl("^(/|~|[A-Za-z]:)", x, perl = TRUE) || grepl("\\\\", x)) {
    cli::cli_abort(
      "Absolute or backslash path rejected in {.arg {arg}}: {.val {x}}."
    )
  }
  segs <- strsplit(x, "/", fixed = TRUE)[[1L]]
  if (any(segs == "..")) {
    cli::cli_abort(
      "Path traversal ('..') rejected in {.arg {arg}}: {.val {x}}."
    )
  }
  if (grepl("[\"'`$;|&<>()!*?{}\\[\\]]", x, perl = TRUE)) {
    cli::cli_abort(
      "Unsafe shell/metacharacter detected in {.arg {arg}}: {.val {x}}."
    )
  }
  x
}

# Validate Compose service name
validate_compose_service_name <- function(x, arg = "service_name") {
  assert_no_control_chars(x, arg = arg)
  if (!grepl("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$", x, perl = TRUE)) {
    cli::cli_abort(
      "Invalid Docker Compose service name in {.arg {arg}}: {.val {x}}."
    )
  }
  x
}

# Validate Compose image tag
validate_image_tag <- function(x, arg = "image_tag") {
  assert_no_control_chars(x, arg = arg)
  if (identical(tolower(x), "latest")) {
    cli::cli_abort("{.arg {arg}} must be explicitly pinned and cannot be {.val latest}.")
  }
  if (!grepl("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", x, perl = TRUE)) {
    cli::cli_abort("Invalid image tag in {.arg {arg}}: {.val {x}}.")
  }
  x
}

# Validate environment variable names and values (no injection/newlines)
validate_env_vars <- function(env_vars, arg = "env_vars") {
  if (is.null(env_vars) || length(env_vars) == 0L) {
    return(list())
  }
  nms <- names(env_vars)
  if (is.null(nms) || any(!nzchar(nms))) {
    cli::cli_abort("{.arg {arg}} must be a named list or named character vector.")
  }
  out <- list()
  for (i in seq_along(env_vars)) {
    nm <- nms[[i]]
    if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", nm, perl = TRUE)) {
      cli::cli_abort("Invalid environment variable name in {.arg {arg}}: {.val {nm}}.")
    }
    val <- as.character(env_vars[[i]])
    if (length(val) != 1L || is.na(val)) {
      cli::cli_abort("Environment variable {.val {nm}} must have a single non-NA scalar value.")
    }
    assert_no_control_chars(val, arg = paste0(arg, "$", nm))
    out[[nm]] <- val
  }
  out
}

# Validate Compose volume mount specification (block traversal, control chars, docker.sock, host root)
validate_compose_volume <- function(vol, arg = "volumes") {
  assert_no_control_chars(vol, arg = arg)
  if (!grepl(":", vol, fixed = TRUE)) {
    cli::cli_abort("Volume mount must use 'source:target[:mode]' format: {.val {vol}}.")
  }
  parts <- strsplit(vol, ":", fixed = TRUE)[[1L]]
  src <- parts[[1L]]
  dst <- parts[[2L]]
  if (grepl("(^|/)\\.\\.(/|$)", src, perl = TRUE) || grepl("(^|/)\\.\\.(/|$)", dst, perl = TRUE)) {
    cli::cli_abort("Path traversal ('..') rejected in volume mount: {.val {vol}}.")
  }
  if (grepl("docker\\.sock$", src, ignore.case = TRUE) || identical(src, "/")) {
    cli::cli_abort("Dangerous host volume mount rejected: {.val {vol}}.")
  }
  vol
}

# Validate Compose CPU, memory limit, and restart policy
validate_compose_resources <- function(cpus, memory_limit, restart_policy) {
  cpus_s <- as.character(cpus)
  assert_no_control_chars(cpus_s, arg = "cpus")
  if (!grepl("^[0-9]+(\\.[0-9]+)?$", cpus_s, perl = TRUE) || as.numeric(cpus_s) <= 0) {
    cli::cli_abort("{.arg cpus} must be a positive numeric string (e.g., {.val 2.0}).")
  }
  mem_s <- as.character(memory_limit)
  assert_no_control_chars(mem_s, arg = "memory_limit")
  if (!grepl("^[0-9]+[bBkKmMgG]?$", mem_s, perl = TRUE)) {
    cli::cli_abort("{.arg memory_limit} must be a valid Docker memory spec (e.g., {.val 2G}, {.val 512M}).")
  }
  valid_restarts <- c("no", "always", "on-failure", "unless-stopped")
  if (!is.character(restart_policy) || length(restart_policy) != 1L || !(restart_policy %in% valid_restarts)) {
    cli::cli_abort(
      "{.arg restart_policy} must be one of {.val {valid_restarts}}, not {.val {restart_policy}}."
    )
  }
  list(cpus = cpus_s, memory_limit = mem_s, restart_policy = restart_policy)
}

# Sanitize single-line human metadata for comments, OCI LABELs, and Apptainer %labels
sanitize_single_line_text <- function(x, max_len = 200L) {
  if (is.null(x) || length(x) == 0L || is.na(x[[1L]])) return("")
  s <- as.character(x[[1L]])
  s <- gsub("[\\r\\n\\x00-\\x1f\\x7f]+", " ", s, perl = TRUE)
  s <- trimws(s)
  if (nchar(s) > max_len) {
    s <- substr(s, 1L, max_len)
  }
  s
}

escape_dockerfile_label <- function(x) {
  s <- sanitize_single_line_text(x)
  s <- gsub("\\\\", "\\\\\\\\", s)
  s <- gsub("\"", "\\\\\"", s, fixed = TRUE)
  s <- gsub("\\$", "\\\\$", s)
  s
}

escape_apptainer_label <- function(x) {
  s <- sanitize_single_line_text(x)
  # Ensure a label value cannot start a new Apptainer %section
  s <- gsub("^%", "_", s)
  s
}

# Safe YAML loaders that explicitly disable R !expr code evaluation
safe_yaml_load <- function(text) {
  yaml::yaml.load(text, eval.expr = FALSE)
}

safe_yaml_read <- function(path) {
  yaml::read_yaml(path, eval.expr = FALSE)
}

# -----------------------------------------------------------------------------
# 2. Path-Traversal & Symlink-Escape Confinement
# -----------------------------------------------------------------------------

# Canonical real path with trailing slashes stripped (handles macOS /var -> /private/var)
canonical_real_dir <- function(path) {
  p <- as.character(fs::path_real(fs::path_abs(path)))
  sub("/+$", "", gsub("\\\\", "/", p))
}

# Check whether resolved child path is equal to or strictly inside resolved root
path_is_within_root <- function(real_child, real_root) {
  child_clean <- sub("/+$", "", gsub("\\\\", "/", as.character(real_child)))
  root_clean <- sub("/+$", "", gsub("\\\\", "/", as.character(real_root)))
  identical(child_clean, root_clean) || startsWith(child_clean, paste0(root_clean, "/"))
}

# Check whether a file/link inside root resolves strictly within root (blocking symlink escape)
is_confined_existing_path <- function(candidate_path, real_root) {
  cand <- as.character(fs::path_norm(fs::path_abs(candidate_path)))

  # Inspect direct symlink target first (catches dangling symlinks pointing outside root)
  if (isTRUE(fs::is_link(cand))) {
    target <- tryCatch(as.character(fs::link_path(cand)), error = function(e) NULL)
    if (is.null(target)) return(FALSE)
    resolved_target <- if (fs::is_absolute_path(target)) {
      as.character(fs::path_norm(target))
    } else {
      as.character(fs::path_norm(file.path(fs::path_dir(cand), target)))
    }
    # If the target exists, compare real path; if dangling, compare normalized absolute target
    if (fs::file_exists(resolved_target) || fs::dir_exists(resolved_target)) {
      real_t <- tryCatch(canonical_real_dir(resolved_target), error = function(e) NULL)
      if (is.null(real_t) || !path_is_within_root(real_t, real_root)) {
        return(FALSE)
      }
    } else {
      # Resolve parent if possible to handle /var -> /private/var on dangling targets
      parent_real <- tryCatch(canonical_real_dir(fs::path_dir(resolved_target)), error = function(e) NULL)
      check_p <- if (!is.null(parent_real)) file.path(parent_real, basename(resolved_target)) else resolved_target
      if (!path_is_within_root(check_p, real_root)) {
        return(FALSE)
      }
    }
  }

  real_cand <- tryCatch(canonical_real_dir(cand), error = function(e) NULL)
  if (is.null(real_cand)) {
    return(FALSE)
  }
  path_is_within_root(real_cand, real_root)
}

# Strictly validate and resolve an artifact/manifest path within project root
assert_confined_path <- function(p, root, must_exist = TRUE, arg = "path") {
  assert_no_control_chars(p, arg = arg)
  if (!nzchar(p)) {
    cli::cli_abort("{.arg {arg}} must be a non-empty path.")
  }

  real_root <- canonical_real_dir(root)
  norm_p <- gsub("\\\\", "/", p)

  if (!fs::is_absolute_path(p)) {
    segs <- strsplit(norm_p, "/", fixed = TRUE)[[1L]]
    if (any(segs == "..")) {
      cli::cli_abort(
        "Path traversal ('..') outside project root is forbidden in {.arg {arg}}: {.path {p}}."
      )
    }
    cand <- as.character(fs::path_norm(file.path(real_root, norm_p)))
  } else {
    cand <- as.character(fs::path_norm(p))
  }

  # Check if symlink or ancestor symlink escapes root
  if (isTRUE(fs::is_link(cand)) || fs::file_exists(cand) || fs::dir_exists(cand)) {
    if (!is_confined_existing_path(cand, real_root)) {
      cli::cli_abort(
        "Path or symlink escapes project root {.path {root}} in {.arg {arg}}: {.path {p}}."
      )
    }
    return(canonical_real_dir(cand))
  }

  # Non-existent path: verify normalized path & nearest existing parent stay inside root
  if (must_exist) {
    # Check if it's outside root first to give security error rather than missing-file error
    if (!path_is_within_root(cand, real_root)) {
      cli::cli_abort(
        "Path outside project root {.path {root}} is forbidden in {.arg {arg}}: {.path {p}}."
      )
    }
    cli::cli_abort("Artifact path does not exist: {.path {p}}.")
  }

  # Walk up to nearest existing parent to check for symlink escapes
  cur <- cand
  while (!fs::dir_exists(cur) && !identical(cur, fs::path_dir(cur))) {
    cur <- as.character(fs::path_dir(cur))
  }
  real_parent <- tryCatch(canonical_real_dir(cur), error = function(e) NULL)
  if (is.null(real_parent) || !path_is_within_root(real_parent, real_root)) {
    cli::cli_abort(
      "Path escapes project root {.path {root}} in {.arg {arg}}: {.path {p}}."
    )
  }
  rel_tail <- if (identical(cur, cand)) "" else as.character(fs::path_rel(cand, start = cur))
  resolved <- if (nzchar(rel_tail)) file.path(real_parent, rel_tail) else real_parent
  if (!path_is_within_root(resolved, real_root)) {
    cli::cli_abort(
      "Path escapes project root {.path {root}} in {.arg {arg}}: {.path {p}}."
    )
  }
  as.character(fs::path_norm(resolved))
}

# Validate a manifest-recorded relative path (rejects absolute paths, .., backslashes, control chars)
assert_safe_manifest_rel_path <- function(p, arg = "manifest path") {
  assert_no_control_chars(p, arg = arg)
  if (!nzchar(p) || fs::is_absolute_path(p) || grepl("^(/|~|[A-Za-z]:)", p, perl = TRUE) || grepl("\\\\", p)) {
    cli::cli_abort(
      "Unsafe non-relative path in {.arg {arg}}: {.val {p}}."
    )
  }
  segs <- strsplit(p, "/", fixed = TRUE)[[1L]]
  if (any(segs == "..") || any(segs == "")) {
    cli::cli_abort(
      "Path traversal or malformed path in {.arg {arg}}: {.val {p}}."
    )
  }
  p
}

# -----------------------------------------------------------------------------
# 3. Cryptographic Constant-Time Comparison & UTF-8 Normalization
# -----------------------------------------------------------------------------

# Constant-time UTF-8 byte comparison eliminating early-exit timing leaks
constant_time_equal <- function(a, b) {
  if (!is.character(a) || !is.character(b) || length(a) != 1L || length(b) != 1L) {
    return(FALSE)
  }
  if (is.na(a) || is.na(b)) {
    return(FALSE)
  }
  ra <- charToRaw(enc2utf8(a))
  rb <- charToRaw(enc2utf8(b))

  # Compare fixed-length SHA-256 hashes when lengths differ to avoid short-circuiting
  len_equal <- identical(length(ra), length(rb))
  if (!len_equal) {
    ha <- as.raw(openssl::sha256(ra))
    hb <- as.raw(openssl::sha256(rb))
    acc <- 1L
    for (i in seq_along(ha)) {
      acc <- bitwOr(acc, bitwXor(as.integer(ha[[i]]), as.integer(hb[[i]])))
    }
    return(FALSE)
  }

  acc <- 0L
  for (i in seq_along(ra)) {
    acc <- bitwOr(acc, bitwXor(as.integer(ra[[i]]), as.integer(rb[[i]])))
  }
  identical(acc, 0L)
}

# -----------------------------------------------------------------------------
# 4. Sandbox Ambient Secret Environment Variable Scrubbing
# -----------------------------------------------------------------------------

# Patterns identifying ambient credential/secret environment variables to scrub
secret_env_var_patterns <- function() {
  c(
    "^AWS_",
    "^GITHUB_",
    "^GH_",
    "^GITLAB_",
    "^OPENAI_",
    "^ANTHROPIC_",
    "^GEMINI_",
    "^GOOGLE_API",
    "^GOOGLE_APPLICATION_CREDENTIALS$",
    "^AZURE_",
    "^GCP_",
    "^HF_TOKEN$",
    "^HUGGING_FACE",
    "^NPM_TOKEN$",
    "^PYPI_",
    "^DOCKER_",
    "^SLACK_",
    "^STRIPE_",
    "^TWILIO_",
    "^SENDGRID_",
    "^DATABRICKS_",
    "^SNOWFLAKE_",
    "^PGPASSWORD$",
    "^MYSQL_PWD$",
    "^DATABASE_URL$",
    "^CAPSULE_SIGNING_KEY$",
    "SECRET",
    "TOKEN",
    "PASSWORD",
    "PASSWD",
    "API_KEY",
    "ACCESS_KEY",
    "PRIVATE_KEY",
    "SIGNING_KEY",
    "CREDENTIAL",
    "AUTH_KEY",
    "BEARER",
    "_PAT$"
  )
}

# Identify which environment variable names match ambient secret patterns
is_secret_env_var <- function(names_vec) {
  if (length(names_vec) == 0L) return(logical())
  pat <- paste(secret_env_var_patterns(), collapse = "|")
  grepl(pat, names_vec, ignore.case = TRUE, perl = TRUE)
}

# Scrub sensitive ambient environment variables prior to launching an isolated sandbox
# NOTE: callr::rscript() merges `env` over the parent process environment, so scrubbed
# variables MUST be explicitly mapped to NA_character_ to unset them in the child OS env.
scrub_sandbox_env <- function(env_list, explicit_env_vars = list()) {
  if (length(env_list) == 0L) {
    return(list(env = character(), scrubbed = character()))
  }
  nms <- names(env_list)
  explicit_nms <- names(explicit_env_vars) %||% character()
  drop_mask <- is_secret_env_var(nms) & !(nms %in% explicit_nms)
  scrubbed <- sort(nms[drop_mask])
  kept <- env_list[!drop_mask]
  if (length(scrubbed) > 0L) {
    for (s_nm in scrubbed) {
      kept[[s_nm]] <- NA_character_
    }
  }
  list(env = kept, scrubbed = scrubbed)
}

# -----------------------------------------------------------------------------
# 5. HTML / XSS & Markdown Output Escaping
# -----------------------------------------------------------------------------

# Coerce any value (even htmltools::HTML!) to plain escaped text for safe HTML rendering
safe_html_text <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  s <- paste(as.character(x), collapse = " ")
  if (is.na(s)) return("")
  # Strip any "html" S3 class so htmltools NEVER bypasses escaping
  unclass(s)
}

# Explicit HTML escaping helper for raw template interpolation (e.g., <title>)
escape_html_strict <- function(x) {
  htmltools::htmlEscape(safe_html_text(x), attribute = TRUE)
}

# Escape Markdown table cell text to prevent table breakage or raw HTML injection
sanitize_markdown_cell <- function(x) {
  s <- safe_html_text(x)
  s <- gsub("[\\r\\n]+", " ", s, perl = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  s <- gsub("\\|", "\\\\|", s)
  s
}

# Escape Markdown inline text (titles, bullet items) to neutralize embedded HTML/script tags
sanitize_markdown_inline <- function(x) {
  s <- safe_html_text(x)
  s <- gsub("[\\r\\n]+", " ", s, perl = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  s
}
