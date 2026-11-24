# Zero-dependency ecosystem handoff hooks for HPC orchestrators and external audit scripts

# Extract trimmed non-empty body lines of a named Apptainer section (e.g. "%runscript")
extract_apptainer_section <- function(lines, section_header) {
  hdr_idx <- which(trimws(lines) == section_header)
  if (length(hdr_idx) == 0L) {
    return(character())
  }
  start <- hdr_idx[[1L]] + 1L
  if (start > length(lines)) {
    return(character())
  }
  next_hdrs <- which(grepl("^%[a-z]+\\s*$", trimws(lines)))
  next_after <- next_hdrs[next_hdrs > hdr_idx[[1L]]]
  end <- if (length(next_after) > 0L) next_after[[1L]] - 1L else length(lines)
  if (end < start) {
    return(character())
  }
  body <- trimws(lines[start:end])
  body[nzchar(body) & !grepl("^#", body)]
}

# Parse `export KEY=VALUE` statements from an Apptainer %environment section into a named list
parse_apptainer_env_section <- function(lines) {
  env_lines <- extract_apptainer_section(lines, "%environment")
  out <- list()
  for (ln in env_lines) {
    m <- regmatches(ln, regexec("^export\\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$", ln, perl = TRUE))[[1L]]
    if (length(m) >= 3L) {
      out[[m[[2L]]]] <- m[[3L]]
    }
  }
  out
}

#' Export a Structured Apptainer Recipe Descriptor for HPC Orchestrators
#'
#' Converts an `rcapsule_scan`, `rcapsule_apptainer`, `rcapsule_bundle`, or
#' project directory path into a self-contained, plain-list-convertible
#' Apptainer specification descriptor (`rcapsule_apptainer_spec`). Designed as
#' a zero-dependency handoff contract for downstream HPC job orchestrators
#' (such as Slurm array/container runners) that need pinned base images,
#' environment variables, HPC bind mounts, runscript commands, and the SHA-256
#' digest of the `.def` recipe without coupling to `rcapsule` internals.
#'
#' @param x An `rcapsule_scan`, `rcapsule_apptainer`, `rcapsule_bundle`, or
#'   path to a project directory.
#' @param base_image Optional pinned Docker base image override forwarded to
#'   [compile_apptainer()].
#' @param r_version Optional R version string override.
#' @param base_digest Optional SHA-256 image digest appended to `base_image`.
#' @param cran_repo Pinned CRAN or Posit Package Manager repository URL.
#' @param quarto_version Pinned Quarto CLI version when Quarto is detected.
#' @param cmdstan_version Pinned CmdStan version when CmdStan is detected.
#' @param workdir Project directory inside the container image. Defaults to
#'   `"/capsule"`.
#' @param entrypoint Optional override for the `%runscript` entrypoint.
#' @param bind_paths Character vector of absolute HPC bind mount paths (default
#'   `c("/scratch", "/work", "/data")`).
#' @param allow_unpinned Logical; if `FALSE` (default), rejects `:latest` or
#'   untagged base images.
#'
#' @return An S3 object of class `rcapsule_apptainer_spec` (convertible to a
#'   plain list via `as.list()`) with fields `schema_version`, `project_name`,
#'   `project_type`, `r_version`, `bootstrap`, `base_image`, `workdir`,
#'   `entrypoint`, `r_packages`, `apt_packages`, `python_packages`,
#'   `toolchains`, `env_vars`, `bind_paths`, `runscript`, `test_commands`,
#'   `def_content`, `def_sha256`, and `def_path`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_hpc_spec_")
#' dir.create(tmp)
#' writeLines(c("library(jsonlite)", "cat('ok\\n')"), file.path(tmp, "run.R"))
#' spec <- as_apptainer_spec(tmp)
#' spec
#' names(as.list(spec))
#' unlink(tmp, recursive = TRUE)
as_apptainer_spec <- function(x,
                              base_image = NULL,
                              r_version = NULL,
                              base_digest = NULL,
                              cran_repo = "https://packagemanager.posit.co/cran/2026-01-15",
                              quarto_version = "1.5.57",
                              cmdstan_version = "2.35.0",
                              workdir = "/capsule",
                              entrypoint = NULL,
                              bind_paths = c("/scratch", "/work", "/data"),
                              allow_unpinned = FALSE) {
  if (!is.character(bind_paths)) {
    cli::cli_abort("{.arg bind_paths} must be a character vector of absolute container mount paths.")
  }
  for (bp in bind_paths) {
    validate_container_workdir(bp, arg = "bind_paths")
  }
  bind_paths <- unique(bind_paths)

  has_overrides <- !is.null(base_image) || !is.null(r_version) || !is.null(base_digest) ||
    !identical(workdir, "/capsule") || !is.null(entrypoint) || isTRUE(allow_unpinned)

  app_obj <- NULL
  sc <- NULL
  if (inherits(x, "rcapsule_apptainer")) {
    sc <- x$scan
    if (!has_overrides) {
      app_obj <- x
    }
  } else if (inherits(x, "rcapsule_bundle")) {
    sc <- x$scan
    if (!has_overrides && !is.null(x$specs$apptainer)) {
      app_obj <- x$specs$apptainer
    }
  } else if (inherits(x, "rcapsule_scan") || (is.character(x) && length(x) == 1L)) {
    sc <- as_rcapsule_scan(x)
  } else {
    cli::cli_abort(
      "{.arg x} must be an {.cls rcapsule_scan}, {.cls rcapsule_apptainer}, {.cls rcapsule_bundle}, or project path."
    )
  }

  if (is.null(app_obj)) {
    app_obj <- compile_apptainer(
      scan = sc,
      output = NULL,
      base_image = base_image,
      r_version = r_version,
      base_digest = base_digest,
      cran_repo = cran_repo,
      quarto_version = quarto_version,
      cmdstan_version = cmdstan_version,
      workdir = workdir,
      entrypoint = entrypoint,
      allow_unpinned = allow_unpinned
    )
  }

  env_vars <- parse_apptainer_env_section(app_obj$lines)
  eff_workdir <- env_vars$CAPSULE_DIR %||% workdir
  r_pkgs <- sort(unique(sc$packages$package[!sc$packages$is_base & sc$packages$required]))
  apt_pkgs <- sort(unique(c("ca-certificates", sc$sysreqs$apt_package)))
  active_tcs <- sort(names(sc$toolchains)[vapply(sc$toolchains, function(t) isTRUE(t$detected), logical(1L))])

  structure(
    list(
      schema_version = "1.0.0",
      project_name = sc$project_name,
      project_type = sc$project_type,
      r_version = as.character(r_version %||% sc$r_version),
      bootstrap = "docker",
      base_image = app_obj$base_image,
      workdir = eff_workdir,
      entrypoint = entrypoint %||% sc$entrypoint,
      r_packages = r_pkgs,
      apt_packages = apt_pkgs,
      python_packages = sc$python_packages %||% character(),
      toolchains = active_tcs,
      env_vars = env_vars,
      bind_paths = bind_paths,
      runscript = extract_apptainer_section(app_obj$lines, "%runscript"),
      test_commands = extract_apptainer_section(app_obj$lines, "%test"),
      def_content = app_obj$content,
      def_sha256 = sha256_string(app_obj$content),
      def_path = app_obj$path
    ),
    class = "rcapsule_apptainer_spec"
  )
}

#' @export
as.list.rcapsule_apptainer_spec <- function(x, ...) {
  unclass(x)
}

#' @export
print.rcapsule_apptainer_spec <- function(x, ...) {
  cli::cli_h1("rcapsule Apptainer Spec Descriptor: {x$project_name}")
  cli::cli_ul(c(
    "Base image: {.val {x$base_image}} (Bootstrap: {x$bootstrap})",
    "Project type: {.val {x$project_type}} | R: {.val {x$r_version}} | Workdir: {.path {x$workdir}}",
    "Entrypoint: {.val {x$entrypoint %||% '<interactive R>'}}",
    "Dependencies: {length(x$r_packages)} R pkg(s), {length(x$apt_packages)} apt pkg(s), {length(x$python_packages)} Python pkg(s)",
    "Toolchains: {if (length(x$toolchains) > 0L) paste(x$toolchains, collapse = ', ') else 'standard R'}",
    "HPC bind paths: {paste(x$bind_paths, collapse = ', ')}",
    "Recipe SHA-256: {.val {substr(x$def_sha256, 1L, 16L)}}..."
  ))
  invisible(x)
}

#' Execute an External Verification or Audit Script Inside the Isolated Sandbox
#'
#' Runs an arbitrary external or project-local R audit/verification script (for
#' example, a custom statistical consistency check, a `statci` CI audit, or a
#' peer-reviewer validation script) inside `rcapsule`'s clean, path-confined,
#' ambient-secret-scrubbed sandbox via [callr::rscript()]. Captures exit status,
#' duration, `stdout`/`stderr`, scrubbed environment variable names, SHA-256
#' hashes of every created or modified artifact, and optional checks on
#' expected output files.
#'
#' @param script Path to an existing `.R` script to execute inside the sandbox
#'   (may reside outside `path`, e.g. a shared organizational audit script).
#' @param path Path to the project root directory to stage cleanly into the
#'   sandbox. Defaults to `"."`.
#' @param manifest Optional `rcapsule_manifest` object or path to `capsule.json`
#'   used to exclude previously generated outputs when staging the sandbox.
#' @param seed Optional integer RNG seed applied before sourcing `script`.
#' @param rng_kind Character vector of length 3 from [base::RNGkind()].
#'   Defaults to the current session's `RNGkind()`.
#' @param env_vars Optional named list of explicit environment variables passed
#'   to the sandboxed script.
#' @param timeout Execution timeout in seconds (default `300`).
#' @param scrub_secrets Logical; if `TRUE` (default), strips ambient credential
#'   and token environment variables (`AWS_*`, `GITHUB_TOKEN`, `OPENAI_API_KEY`,
#'   `*_SECRET*`, `*_TOKEN*`, etc.) before executing `script`.
#' @param keep_sandbox Logical; if `TRUE`, retains the temporary sandbox
#'   directory on disk and returns its path in `sandbox_dir`. Defaults to
#'   `FALSE`.
#' @param expected_outputs Optional character vector of project-relative output
#'   paths expected to exist in the sandbox after `script` finishes.
#' @param args Optional character vector of string arguments forwarded to
#'   `script` via the `RCAPSULE_AUDIT_ARGS` environment variable (JSON array).
#'
#' @return An S3 object of class `rcapsule_script_audit` containing `passed`,
#'   `status` (`"passed"` or `"failed"`), `exit_status`, `duration_sec`,
#'   `script`, `script_sha256`, `project_path`, `verified_at`, `rng`,
#'   `scrubbed_env_vars`, `stdout`, `stderr`, `artifacts` (tibble of created or
#'   modified files with `path`, `change`, `sha256`, `bytes`, `format`),
#'   `expected_checks` (tibble checking `expected_outputs`), and `sandbox_dir`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_script_audit_")
#' dir.create(tmp)
#' write.csv(data.frame(x = 1:5), file.path(tmp, "data.csv"), row.names = FALSE)
#' audit_script <- tempfile("audit_", fileext = ".R")
#' writeLines(
#'   c("df <- read.csv('data.csv')",
#'     "stopifnot(nrow(df) == 5L)",
#'     "writeLines('audit_ok', 'audit_report.txt')"),
#'   audit_script
#' )
#' res <- verify_with_script(
#'   script = audit_script,
#'   path = tmp,
#'   seed = 42L,
#'   expected_outputs = "audit_report.txt"
#' )
#' res
#' unlink(c(tmp, audit_script), recursive = TRUE)
verify_with_script <- function(script,
                               path = ".",
                               manifest = NULL,
                               seed = NULL,
                               rng_kind = RNGkind(),
                               env_vars = list(),
                               timeout = 300,
                               scrub_secrets = TRUE,
                               keep_sandbox = FALSE,
                               expected_outputs = NULL,
                               args = character()) {
  if (!is.character(script) || length(script) != 1L || is.na(script) || !nzchar(script)) {
    cli::cli_abort("{.arg script} must be a non-empty path to an R script.")
  }
  assert_no_control_chars(script, arg = "script")
  if (!fs::file_exists(script) || fs::dir_exists(script)) {
    cli::cli_abort("Audit script does not exist: {.path {script}}.")
  }
  if (!identical(tolower(tools::file_ext(script)), "r")) {
    cli::cli_abort("{.arg script} must be an {.val .R} script, got {.path {script}}.")
  }

  root <- normalize_project_path(path, must_exist = TRUE)
  if (is.character(manifest) && length(manifest) == 1L) {
    manifest <- read_capsule_manifest(manifest)
  }
  if (!is.null(manifest) && !inherits(manifest, "rcapsule_manifest")) {
    cli::cli_abort("{.arg manifest} must be an {.cls rcapsule_manifest} or path to capsule.json.")
  }
  stage_manifest <- manifest %||% list(artifacts = list(outputs = list()))

  exp_rels <- character()
  if (!is.null(expected_outputs)) {
    if (!is.character(expected_outputs)) {
      cli::cli_abort("{.arg expected_outputs} must be a character vector of relative paths.")
    }
    exp_rels <- vapply(expected_outputs, assert_safe_manifest_rel_path, character(1L),
                       arg = "expected_outputs", USE.NAMES = FALSE)
  }

  script_abs <- as.character(fs::path_norm(fs::path_abs(script)))
  script_sha <- sha256_file(script_abs)

  # Stage clean isolated sandbox strictly enforcing path confinement & external symlink filtering
  sandbox_dir <- as.character(fs::path_norm(tempfile("rcapsule_script_sandbox_")))
  if (!isTRUE(keep_sandbox)) {
    on.exit(unlink(sandbox_dir, recursive = TRUE, force = TRUE), add = TRUE)
  }
  staged_rels <- stage_clean_sandbox(root, stage_manifest, sandbox_dir)
  real_sandbox <- canonical_real_dir(sandbox_dir)

  # Snapshot pre-execution SHA-256 digests so modified vs newly created files are tracked
  pre_hashes <- structure(character(length(staged_rels)), names = staged_rels)
  for (rel in staged_rels) {
    fp <- file.path(real_sandbox, rel)
    if (fs::file_exists(fp)) {
      pre_hashes[[rel]] <- sha256_file(fp)
    }
  }

  # Copy audit script into sandbox and generate deterministic bootstrap
  staged_script_name <- ".rcapsule_audit_script.R"
  fs::file_copy(script_abs, file.path(real_sandbox, staged_script_name), overwrite = TRUE)

  kind_vec <- as.character(unlist(rng_kind))
  if (length(kind_vec) < 3L) {
    kind_vec <- RNGkind()
  }
  eff_seed <- if (!is.null(seed) && !is.na(seed)) as.integer(seed) else NULL

  boot_lines <- c(
    "# Auto-generated rcapsule isolated audit script bootstrap",
    sprintf(
      "RNGkind(kind = %s, normal.kind = %s, sample.kind = %s)",
      deparse(kind_vec[[1L]]), deparse(kind_vec[[2L]]), deparse(kind_vec[[3L]])
    )
  )
  if (!is.null(eff_seed)) {
    boot_lines <- c(boot_lines, sprintf("set.seed(%dL)", eff_seed))
  }
  boot_lines <- c(
    boot_lines,
    sprintf("source(%s, local = new.env(parent = globalenv()))", deparse(staged_script_name))
  )
  runner_script <- file.path(real_sandbox, ".rcapsule_audit_runner.R")
  writeLines(boot_lines, runner_script, useBytes = TRUE)

  eff_env <- env_vars
  if (length(args) > 0L) {
    eff_env$RCAPSULE_AUDIT_ARGS <- to_canonical_json(as_json_array(as.character(args)))
  }

  env_bundle <- build_sandbox_env(real_sandbox, seed = eff_seed, env_vars = eff_env, scrub_secrets = scrub_secrets)
  exec_res <- run_in_sandbox(real_sandbox, runner_script, env = env_bundle$env, timeout = timeout)

  # Collect newly created or modified artifacts inside the sandbox
  post_entries <- as.character(fs::dir_ls(real_sandbox, recurse = TRUE, all = TRUE, type = "file", fail = FALSE))
  art_rows <- list()
  if (length(post_entries) > 0L) {
    post_rels <- rel_path(post_entries, real_sandbox)
    internal_mask <- post_rels %in% c(".rcapsule_audit_runner.R", ".rcapsule_audit_script.R") |
      grepl("^\\.rcapsule_cache(/|$)", post_rels)
    cand_rels <- sort(post_rels[!internal_mask])
    for (rel in cand_rels) {
      fp <- file.path(real_sandbox, rel)
      cur_sha <- sha256_file(fp)
      prev_sha <- if (rel %in% names(pre_hashes)) pre_hashes[[rel]] else NULL
      if (is.null(prev_sha)) {
        art_rows[[length(art_rows) + 1L]] <- list(
          path = rel,
          change = "created",
          sha256 = cur_sha,
          bytes = as.integer(file.info(fp)$size),
          format = detect_artifact_format(rel)
        )
      } else if (!constant_time_equal(cur_sha, prev_sha)) {
        art_rows[[length(art_rows) + 1L]] <- list(
          path = rel,
          change = "modified",
          sha256 = cur_sha,
          bytes = as.integer(file.info(fp)$size),
          format = detect_artifact_format(rel)
        )
      }
    }
  }

  artifacts_tbl <- if (length(art_rows) > 0L) {
    tibble::tibble(
      path = vapply(art_rows, `[[`, character(1L), "path"),
      change = vapply(art_rows, `[[`, character(1L), "change"),
      sha256 = vapply(art_rows, `[[`, character(1L), "sha256"),
      bytes = vapply(art_rows, `[[`, integer(1L), "bytes"),
      format = vapply(art_rows, `[[`, character(1L), "format")
    )
  } else {
    tibble::tibble(
      path = character(),
      change = character(),
      sha256 = character(),
      bytes = integer(),
      format = character()
    )
  }

  expected_checks <- if (length(exp_rels) > 0L) {
    exp_rows <- lapply(exp_rels, function(rel) {
      fp <- assert_confined_path(rel, root = real_sandbox, must_exist = FALSE, arg = "expected_outputs")
      ex <- fs::file_exists(fp)
      list(
        path = rel,
        exists = ex,
        sha256 = if (ex) sha256_file(fp) else NA_character_,
        bytes = if (ex) as.integer(file.info(fp)$size) else NA_integer_
      )
    })
    tibble::tibble(
      path = vapply(exp_rows, `[[`, character(1L), "path"),
      exists = vapply(exp_rows, `[[`, logical(1L), "exists"),
      sha256 = vapply(exp_rows, `[[`, character(1L), "sha256"),
      bytes = vapply(exp_rows, `[[`, integer(1L), "bytes")
    )
  } else {
    tibble::tibble(
      path = character(),
      exists = logical(),
      sha256 = character(),
      bytes = integer()
    )
  }

  passed <- identical(exec_res$exit_status, 0L) &&
    (nrow(expected_checks) == 0L || all(expected_checks$exists))

  structure(
    list(
      passed = passed,
      status = if (passed) "passed" else "failed",
      exit_status = exec_res$exit_status,
      duration_sec = exec_res$duration_sec,
      script = script_abs,
      script_sha256 = script_sha,
      project_path = root,
      verified_at = utc_now_iso(),
      rng = list(seed = eff_seed, kind = kind_vec),
      scrubbed_env_vars = env_bundle$scrubbed,
      stdout = exec_res$stdout,
      stderr = exec_res$stderr,
      artifacts = artifacts_tbl,
      expected_checks = expected_checks,
      sandbox_dir = if (isTRUE(keep_sandbox)) sandbox_dir else NULL
    ),
    class = "rcapsule_script_audit"
  )
}

#' @export
print.rcapsule_script_audit <- function(x, ...) {
  badge <- if (isTRUE(x$passed)) "PASSED" else "FAILED"
  cli::cli_h1("rcapsule Isolated Script Audit: {badge}")
  cli::cli_ul(c(
    "Script: {.path {basename(x$script)}} (SHA-256: {substr(x$script_sha256, 1L, 12L)}...)",
    "Exit status: {.val {x$exit_status}} | Duration: {x$duration_sec}s | Scrubbed env vars: {length(x$scrubbed_env_vars)}",
    "Created/modified artifacts: {.val {nrow(x$artifacts)}}"
  ))
  if (nrow(x$expected_checks) > 0L) {
    cli::cli_h2("Expected Output Checks")
    for (i in seq_len(nrow(x$expected_checks))) {
      row <- x$expected_checks[i, ]
      if (isTRUE(row$exists)) {
        cli::cli_alert_success("{row$path} ({row$bytes} bytes)")
      } else {
        cli::cli_alert_danger("{row$path} (missing)")
      }
    }
  }
  invisible(x)
}
