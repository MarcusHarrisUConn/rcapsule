# Isolated reproducibility verification auditor (local sandbox and Docker runners)

# Verify a set of manifest artifact records against files currently on disk
verify_file_hashes <- function(records, root) {
  if (length(records) == 0L) {
    return(tibble::tibble(
      path = character(),
      status = character(),
      passed = logical(),
      expected_sha256 = character(),
      actual_sha256 = character(),
      details = character()
    ))
  }

  rows <- lapply(records, function(rec) {
    fp <- file.path(root, rec$path)
    if (!fs::file_exists(fp)) {
      list(
        path = rec$path,
        status = "missing",
        passed = FALSE,
        expected_sha256 = rec$sha256,
        actual_sha256 = NA_character_,
        details = "Recorded file is missing from project directory."
      )
    } else {
      act <- sha256_file(fp)
      ok <- identical(act, rec$sha256)
      list(
        path = rec$path,
        status = if (ok) "exact_match" else "mismatch",
        passed = ok,
        expected_sha256 = rec$sha256,
        actual_sha256 = act,
        details = if (ok) "Exact SHA-256 match." else "File modified since manifest creation."
      )
    }
  })

  tibble::tibble(
    path = vapply(rows, `[[`, character(1L), "path"),
    status = vapply(rows, `[[`, character(1L), "status"),
    passed = vapply(rows, `[[`, logical(1L), "passed"),
    expected_sha256 = vapply(rows, `[[`, character(1L), "expected_sha256"),
    actual_sha256 = vapply(rows, `[[`, character(1L), "actual_sha256"),
    details = vapply(rows, `[[`, character(1L), "details")
  )
}

# Stage an isolated clean sandbox directory strictly excluding recorded outputs
stage_clean_sandbox <- function(root, manifest, sandbox_dir) {
  fs::dir_create(sandbox_dir)
  output_rels <- vapply(manifest$artifacts$outputs, `[[`, character(1L), "path")

  all_files <- as.character(fs::dir_ls(root, recurse = TRUE, all = TRUE, type = "file", fail = FALSE))
  if (length(all_files) > 0L) {
    rels <- rel_path(all_files, root)
    excludes <- c(default_scan_excludes(), "capsule.json")
    keep <- !is_excluded_rel_path(rels, excludes) & !(rels %in% output_rels)
    copy_files <- all_files[keep]
    copy_rels <- rels[keep]

    for (i in seq_along(copy_files)) {
      dest <- file.path(sandbox_dir, copy_rels[[i]])
      fs::dir_create(fs::path_dir(dest))
      fs::file_copy(copy_files[[i]], dest, overwrite = TRUE)
    }
  }

  # Create empty parent directories for recorded outputs if they existed in root
  for (orel in output_rels) {
    parent <- fs::path_dir(orel)
    if (!identical(parent, ".") && fs::dir_exists(file.path(root, parent))) {
      fs::dir_create(file.path(sandbox_dir, parent))
    }
  }

  invisible(sandbox_dir)
}

# Generate deterministic runner bootstrap script for sandbox or container execution
write_runner_bootstrap <- function(sandbox_dir, entrypoint, seed, rng_kind) {
  runner_path <- file.path(sandbox_dir, ".rcapsule_runner.R")
  ext <- tolower(tools::file_ext(entrypoint))
  kind_vec <- as.character(unlist(rng_kind))
  if (length(kind_vec) < 3L) {
    kind_vec <- RNGkind()
  }

  lines <- c(
    "# Auto-generated rcapsule isolated verification bootstrap",
    sprintf(
      "RNGkind(kind = %s, normal.kind = %s, sample.kind = %s)",
      deparse(kind_vec[[1L]]), deparse(kind_vec[[2L]]), deparse(kind_vec[[3L]])
    )
  )

  if (!is.null(seed) && !is.na(seed)) {
    lines <- c(lines, sprintf("set.seed(%dL)", as.integer(seed)))
  }

  if (ext == "r") {
    lines <- c(
      lines,
      sprintf("source(%s, local = new.env(parent = globalenv()))", deparse(entrypoint))
    )
  } else if (ext == "qmd") {
    lines <- c(
      lines,
      sprintf("quarto::quarto_render(%s)", deparse(entrypoint))
    )
  } else if (ext == "rmd") {
    lines <- c(
      lines,
      sprintf("rmarkdown::render(%s, quiet = TRUE)", deparse(entrypoint))
    )
  } else {
    cli::cli_abort("Unsupported entrypoint format for verification runner: {.path {entrypoint}}.")
  }

  writeLines(lines, runner_path, useBytes = TRUE)
  runner_path
}

# Build clean controlled environment vector for child execution
build_sandbox_env <- function(sandbox_dir, seed = NULL, env_vars = list()) {
  cur <- Sys.getenv()
  env <- as.list(cur)
  env$TZ <- "UTC"
  env$LC_ALL <- "C.UTF-8"
  env$LANG <- "C.UTF-8"
  env$RCAPSULE_SANDBOX <- "1"
  env$R_USER_CACHE_DIR <- file.path(sandbox_dir, ".rcapsule_cache")
  if (!is.null(seed) && !is.na(seed)) {
    env$CAPSULE_SEED <- as.character(as.integer(seed))
  }
  if (length(env_vars) > 0L) {
    for (nm in names(env_vars)) {
      env[[nm]] <- as.character(env_vars[[nm]])
    }
  }
  unlist(env)
}

# Execute pipeline inside isolated local sandbox via callr::rscript
run_in_sandbox <- function(sandbox_dir, runner_script, env, timeout) {
  t0 <- proc.time()[["elapsed"]]
  res <- tryCatch(
    callr::rscript(
      script = runner_script,
      wd = sandbox_dir,
      env = env,
      timeout = timeout,
      fail_on_status = FALSE,
      spinner = FALSE,
      show = FALSE
    ),
    error = function(e) {
      list(
        status = 1L,
        stdout = "",
        stderr = conditionMessage(e),
        timeout = FALSE
      )
    }
  )
  elapsed <- proc.time()[["elapsed"]] - t0
  list(
    exit_status = as.integer(res$status %||% 1L),
    stdout = res$stdout %||% "",
    stderr = res$stderr %||% "",
    duration_sec = round(as.numeric(elapsed), 3L)
  )
}

# Execute pipeline inside a live Docker container
run_in_docker <- function(root, sandbox_dir, docker_image, docker_tag, seed, env_vars, timeout) {
  if (!docker_available()) {
    cli::cli_abort(
      "Docker daemon is not available. Use {.code runner = \"sandbox\"} for isolated local verification or start Docker."
    )
  }
  docker_bin <- unname(Sys.which("docker"))
  t0 <- proc.time()[["elapsed"]]

  img <- docker_image
  build_out <- ""
  if (is.null(img)) {
    df_path <- file.path(root, "Dockerfile")
    if (!fs::file_exists(df_path)) {
      cli::cli_abort("No {.arg docker_image} provided and no Dockerfile found at {.path {df_path}}.")
    }
    img <- docker_tag %||% paste0("rcapsule-verify-", tolower(substr(sha256_string(root), 1L, 10L)), ":audit")
    b_res <- processx::run(
      command = docker_bin,
      args = c("build", "-t", img, "-f", df_path, root),
      timeout = timeout,
      error_on_status = FALSE
    )
    build_out <- paste(b_res$stdout, b_res$stderr, sep = "\n")
    if (!identical(b_res$status, 0L)) {
      elapsed <- proc.time()[["elapsed"]] - t0
      return(list(
        exit_status = as.integer(b_res$status),
        stdout = b_res$stdout,
        stderr = paste0("docker build failed:\n", b_res$stderr),
        duration_sec = round(as.numeric(elapsed), 3L)
      ))
    }
  }

  run_args <- c(
    "run", "--rm",
    "-e", "TZ=UTC",
    "-e", "LC_ALL=C.UTF-8",
    "-e", "LANG=C.UTF-8",
    "-e", "RCAPSULE_SANDBOX=1"
  )
  if (!is.null(seed) && !is.na(seed)) {
    run_args <- c(run_args, "-e", paste0("CAPSULE_SEED=", as.integer(seed)))
  }
  if (length(env_vars) > 0L) {
    for (nm in names(env_vars)) {
      run_args <- c(run_args, "-e", paste0(nm, "=", as.character(env_vars[[nm]])))
    }
  }
  run_args <- c(
    run_args,
    "-v", paste0(sandbox_dir, ":/capsule"),
    "-w", "/capsule",
    img,
    "Rscript", ".rcapsule_runner.R"
  )

  r_res <- processx::run(
    command = docker_bin,
    args = run_args,
    timeout = timeout,
    error_on_status = FALSE
  )
  elapsed <- proc.time()[["elapsed"]] - t0
  list(
    exit_status = as.integer(r_res$status),
    stdout = paste0(if (nzchar(build_out)) paste0(build_out, "\n") else "", r_res$stdout),
    stderr = r_res$stderr,
    duration_sec = round(as.numeric(elapsed), 3L)
  )
}

#' Verify Computational Reproducibility Against a Capsule Manifest
#'
#' Audits a recorded `capsule.json` manifest by:
#' 1. Verifying cryptographic manifest integrity (`content_digest` and optional
#'    HMAC-SHA256 signature).
#' 2. Verifying SHA-256 hashes of all recorded inputs and scripts.
#' 3. Staging a clean isolated workspace strictly excluding previously generated
#'    outputs and re-executing the pipeline in either a deterministic local
#'    sandbox (`runner = "sandbox"` via [callr::rscript()]) or a live Docker
#'    container (`runner = "docker"`).
#' 4. Comparing every freshly generated output against the manifest using exact
#'    SHA-256 comparison and configured numeric-tolerance comparators for CSV,
#'    TSV, JSON, and RDS artifacts.
#'
#' @param manifest An `rcapsule_manifest` object or file path to `capsule.json`.
#' @param path Path to the project root directory. Defaults to `"."`.
#' @param runner Execution isolation backend: `"sandbox"` (default; runs locally
#'   in a clean temporary directory via `callr::rscript` without requiring a
#'   Docker daemon) or `"docker"` (executes inside a Docker container).
#' @param entrypoint Optional runnable script/document override (defaults to
#'   `manifest$project$entrypoint`).
#' @param seed Optional RNG seed override (defaults to `manifest$rng$seed`).
#' @param tolerances Optional tolerance override (same structure accepted by
#'   [create_capsule_manifest()]). Defaults to `manifest$tolerances`.
#' @param key Optional HMAC-SHA256 key to verify a signed manifest.
#' @param env_vars Optional named list of extra environment variables passed to
#'   the isolated run.
#' @param timeout Execution timeout in seconds (default `300`).
#' @param docker_image Optional pre-built Docker image reference for
#'   `runner = "docker"`. If `NULL`, builds from `Dockerfile` in `path`.
#' @param docker_tag Optional tag used when building the Docker image.
#' @param keep_sandbox Logical; if `TRUE`, retains the temporary sandbox
#'   directory on disk and records its path for debugging. Defaults to `FALSE`.
#' @param reference_dir Optional directory containing verified baseline output
#'   files for numeric-tolerance comparison (defaults to `path`; only used if
#'   a baseline file's SHA-256 matches the manifest).
#'
#' @return An S3 object of class `rcapsule_verification` containing `status`
#'   (`"verified_exact"`, `"verified_within_tolerance"`, or `"failed"`),
#'   `passed` (logical), `runner`, `verified_at`, `duration_sec`,
#'   `exit_status`, `manifest_integrity`, `input_checks`, `script_checks`,
#'   `output_checks`, `failure_reasons`, `rng`, `environment`, `stdout`,
#'   `stderr`, `sandbox_dir`, and `manifest`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_verify_")
#' dir.create(tmp)
#' writeLines(
#'   c("df <- data.frame(id = 1:3, val = rnorm(3))",
#'     "write.csv(df, 'result.csv', row.names = FALSE)"),
#'   file.path(tmp, "run.R")
#' )
#' set.seed(123)
#' write.csv(data.frame(id = 1:3, val = rnorm(3)), file.path(tmp, "result.csv"), row.names = FALSE)
#' m <- create_capsule_manifest(tmp, outputs = "result.csv", seed = 123L)
#' res <- verify_capsule(m, path = tmp, runner = "sandbox")
#' res$status
#' unlink(tmp, recursive = TRUE)
verify_capsule <- function(manifest,
                           path = ".",
                           runner = c("sandbox", "docker"),
                           entrypoint = NULL,
                           seed = NULL,
                           tolerances = NULL,
                           key = NULL,
                           env_vars = list(),
                           timeout = 300,
                           docker_image = NULL,
                           docker_tag = NULL,
                           keep_sandbox = FALSE,
                           reference_dir = NULL) {
  runner <- match.arg(runner)
  root <- normalize_project_path(path, must_exist = TRUE)
  ref_root <- if (!is.null(reference_dir)) normalize_project_path(reference_dir, must_exist = TRUE) else root

  if (is.character(manifest) && length(manifest) == 1L) {
    manifest <- read_capsule_manifest(manifest)
  }
  if (!inherits(manifest, "rcapsule_manifest")) {
    cli::cli_abort("{.arg manifest} must be an {.cls rcapsule_manifest} or path to capsule.json.")
  }

  # 1. Cryptographic manifest integrity check
  integrity <- verify_manifest_integrity(manifest, key = key)

  # 2. Verify inputs & scripts on disk
  input_checks <- verify_file_hashes(manifest$artifacts$inputs, root)
  script_checks <- verify_file_hashes(manifest$artifacts$scripts, root)

  # 3. Resolve execution settings
  eff_ep <- entrypoint %||% manifest$project$entrypoint
  eff_seed <- if (!is.null(seed)) as.integer(seed) else manifest$rng$seed
  eff_rng_kind <- unlist(manifest$rng$kind %||% RNGkind())
  eff_tols <- if (!is.null(tolerances)) {
    normalize_tolerances(tolerances)
  } else {
    manifest$tolerances %||% normalize_tolerances(NULL)
  }

  if (is.null(eff_ep) || !nzchar(eff_ep)) {
    cli::cli_abort("No runnable {.arg entrypoint} specified in manifest or arguments.")
  }

  # 4. Stage clean isolated sandbox (excluding all recorded outputs!)
  sandbox_dir <- as.character(fs::path_norm(tempfile("rcapsule_sandbox_")))
  if (!isTRUE(keep_sandbox)) {
    on.exit(unlink(sandbox_dir, recursive = TRUE, force = TRUE), add = TRUE)
  }
  stage_clean_sandbox(root, manifest, sandbox_dir)
  runner_script <- write_runner_bootstrap(sandbox_dir, eff_ep, eff_seed, eff_rng_kind)

  # 5. Execute in sandbox or Docker
  exec_res <- if (identical(runner, "sandbox")) {
    run_env <- build_sandbox_env(sandbox_dir, seed = eff_seed, env_vars = env_vars)
    run_in_sandbox(sandbox_dir, runner_script, env = run_env, timeout = timeout)
  } else {
    run_in_docker(
      root = root,
      sandbox_dir = sandbox_dir,
      docker_image = docker_image,
      docker_tag = docker_tag,
      seed = eff_seed,
      env_vars = env_vars,
      timeout = timeout
    )
  }

  # 6. Compare every recorded output artifact
  out_records <- manifest$artifacts$outputs
  out_rows <- lapply(out_records, function(rec) {
    rel <- rec$path
    file_tol <- eff_tols$files[[rel]] %||% eff_tols$default
    abs_tol <- as.numeric(file_tol$abs_tol %||% 0)
    rel_tol <- as.numeric(file_tol$rel_tol %||% 0)

    # Locate trusted baseline for tolerance comparison:
    # Either on-disk file whose hash matches manifest, or embedded manifest snapshot whose hash matches
    ref_file <- file.path(ref_root, rel)
    trusted_ref_path <- NULL
    if (fs::file_exists(ref_file) && identical(sha256_file(ref_file), rec$sha256)) {
      trusted_ref_path <- ref_file
    }

    expected_raw <- NULL
    if (is.null(trusted_ref_path) && !is.null(manifest$snapshots[[rel]])) {
      snap <- manifest$snapshots[[rel]]
      raw_bytes <- tryCatch(openssl::base64_decode(snap$data), error = function(e) NULL)
      if (!is.null(raw_bytes) && identical(sha256_raw(raw_bytes), rec$sha256)) {
        expected_raw <- raw_bytes
      }
    }

    cmp <- compare_artifacts(
      expected_path = trusted_ref_path,
      actual_path = file.path(sandbox_dir, rel),
      expected_sha256 = rec$sha256,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      format = rec$format %||% "auto",
      expected_raw = expected_raw
    )
    cmp$path <- rel
    cmp
  })

  output_checks <- if (length(out_rows) > 0L) {
    tibble::tibble(
      path = vapply(out_rows, `[[`, character(1L), "path"),
      status = vapply(out_rows, `[[`, character(1L), "status"),
      passed = vapply(out_rows, `[[`, logical(1L), "passed"),
      expected_sha256 = vapply(out_rows, `[[`, character(1L), "expected_sha256"),
      actual_sha256 = vapply(out_rows, `[[`, character(1L), "actual_sha256"),
      max_abs_diff = vapply(out_rows, `[[`, numeric(1L), "max_abs_diff"),
      max_rel_diff = vapply(out_rows, `[[`, numeric(1L), "max_rel_diff"),
      abs_tol = vapply(out_rows, `[[`, numeric(1L), "abs_tol"),
      rel_tol = vapply(out_rows, `[[`, numeric(1L), "rel_tol"),
      details = vapply(out_rows, `[[`, character(1L), "details")
    )
  } else {
    tibble::tibble(
      path = character(),
      status = character(),
      passed = logical(),
      expected_sha256 = character(),
      actual_sha256 = character(),
      max_abs_diff = numeric(),
      max_rel_diff = numeric(),
      abs_tol = numeric(),
      rel_tol = numeric(),
      details = character()
    )
  }

  # 7. Compute verdict
  failure_reasons <- character()
  if (!isTRUE(integrity$valid)) {
    failure_reasons <- c(failure_reasons, paste0("Manifest integrity failed: ", paste(integrity$issues, collapse = "; ")))
  }
  if (nrow(input_checks) > 0L && !all(input_checks$passed)) {
    bad_in <- input_checks$path[!input_checks$passed]
    failure_reasons <- c(failure_reasons, paste0("Input artifact verification failed: ", paste(bad_in, collapse = ", ")))
  }
  if (nrow(script_checks) > 0L && !all(script_checks$passed)) {
    bad_sc <- script_checks$path[!script_checks$passed]
    failure_reasons <- c(failure_reasons, paste0("Script integrity verification failed: ", paste(bad_sc, collapse = ", ")))
  }
  if (!identical(exec_res$exit_status, 0L)) {
    failure_reasons <- c(failure_reasons, paste0("Pipeline execution exited with non-zero status ", exec_res$exit_status, "."))
  }
  if (nrow(output_checks) > 0L && !all(output_checks$passed)) {
    bad_out <- output_checks$path[!output_checks$passed]
    failure_reasons <- c(failure_reasons, paste0("Output verification failed for: ", paste(bad_out, collapse = ", ")))
  }

  passed <- length(failure_reasons) == 0L
  status <- if (!passed) {
    "failed"
  } else if (any(output_checks$status == "within_tolerance")) {
    "verified_within_tolerance"
  } else {
    "verified_exact"
  }

  structure(
    list(
      status = status,
      passed = passed,
      runner = runner,
      entrypoint = eff_ep,
      verified_at = utc_now_iso(),
      duration_sec = exec_res$duration_sec,
      exit_status = exec_res$exit_status,
      manifest_integrity = integrity,
      input_checks = input_checks,
      script_checks = script_checks,
      output_checks = output_checks,
      failure_reasons = failure_reasons,
      rng = list(seed = eff_seed, kind = eff_rng_kind),
      environment = list(
        r_version = current_r_version(),
        platform = R.version$platform,
        os = paste(Sys.info()[["sysname"]], Sys.info()[["release"]])
      ),
      stdout = exec_res$stdout,
      stderr = exec_res$stderr,
      sandbox_dir = if (isTRUE(keep_sandbox)) sandbox_dir else NULL,
      manifest = manifest
    ),
    class = "rcapsule_verification"
  )
}

#' @export
print.rcapsule_verification <- function(x, ...) {
  badge <- switch(
    x$status,
    verified_exact = "VERIFIED (EXACT SHA-256)",
    verified_within_tolerance = "VERIFIED (WITHIN TOLERANCE)",
    "FAILED"
  )
  cli::cli_h1("rcapsule Verification Audit: {badge}")
  cli::cli_ul(c(
    "Capsule: {.val {x$manifest$capsule_id}} ({x$manifest$project$name})",
    "Runner: {.val {x$runner}} | Entrypoint: {.val {x$entrypoint}} | Exit: {.val {x$exit_status}} ({x$duration_sec}s)",
    "Manifest integrity: {if (isTRUE(x$manifest_integrity$valid)) 'VALID' else 'INVALID'}",
    "Inputs verified: {sum(x$input_checks$passed)}/{nrow(x$input_checks)}",
    "Scripts verified: {sum(x$script_checks$passed)}/{nrow(x$script_checks)}",
    "Outputs verified: {sum(x$output_checks$passed)}/{nrow(x$output_checks)}"
  ))

  if (nrow(x$output_checks) > 0L) {
    cli::cli_h2("Output Artifacts")
    for (i in seq_len(nrow(x$output_checks))) {
      row <- x$output_checks[i, ]
      line <- paste0(row$path, " [", row$status, "] - ", row$details)
      if (isTRUE(row$passed)) {
        cli::cli_alert_success(line)
      } else {
        cli::cli_alert_danger(line)
      }
    }
  }

  if (length(x$failure_reasons) > 0L) {
    cli::cli_h2("Failure Diagnostics")
    for (fr in x$failure_reasons) cli::cli_alert_danger(fr)
  }

  invisible(x)
}
