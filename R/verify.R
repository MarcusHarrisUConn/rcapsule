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

  real_root <- canonical_real_dir(root)
  rows <- lapply(records, function(rec) {
    rel <- assert_safe_manifest_rel_path(rec$path, arg = "manifest artifact path")
    fp <- assert_confined_path(rel, root = real_root, must_exist = FALSE, arg = "manifest artifact path")
    if (!fs::file_exists(fp)) {
      list(
        path = rel,
        status = "missing",
        passed = FALSE,
        expected_sha256 = rec$sha256,
        actual_sha256 = NA_character_,
        details = "Recorded file is missing from project directory."
      )
    } else {
      act <- sha256_file(fp)
      ok <- constant_time_equal(act, as.character(rec$sha256 %||% ""))
      list(
        path = rel,
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

# Stage an isolated clean sandbox directory strictly excluding recorded outputs and external symlinks
stage_clean_sandbox <- function(root, manifest, sandbox_dir) {
  fs::dir_create(sandbox_dir)
  real_root <- canonical_real_dir(root)
  real_sandbox <- canonical_real_dir(sandbox_dir)

  output_rels <- vapply(manifest$artifacts$outputs, function(rec) {
    assert_safe_manifest_rel_path(rec$path, arg = "manifest output path")
  }, character(1L))

  all_entries <- as.character(fs::dir_ls(real_root, recurse = TRUE, all = TRUE, type = c("file", "symlink"), fail = FALSE))
  staged_rels <- character()
  if (length(all_entries) > 0L) {
    # Skip any symlink pointing outside project root or directory symlinks
    confined <- vapply(all_entries, is_confined_existing_path, logical(1L), real_root = real_root)
    is_reg_file <- vapply(all_entries, function(p) {
      !fs::dir_exists(p) && fs::file_exists(p)
    }, logical(1L))
    all_files <- all_entries[confined & is_reg_file]

    if (length(all_files) > 0L) {
      rels <- rel_path(all_files, real_root)
      excludes <- c(default_scan_excludes(), "capsule.json")
      keep <- !is_excluded_rel_path(rels, excludes) & !(rels %in% output_rels)
      copy_files <- all_files[keep]
      copy_rels <- rels[keep]

      for (i in seq_along(copy_files)) {
        rel_i <- assert_safe_manifest_rel_path(copy_rels[[i]], arg = "sandbox staged file")
        dest <- assert_confined_path(rel_i, root = real_sandbox, must_exist = FALSE, arg = "sandbox destination")
        fs::dir_create(fs::path_dir(dest))
        fs::file_copy(copy_files[[i]], dest, overwrite = TRUE)
        staged_rels <- c(staged_rels, rel_i)
      }
    }
  }

  # Create empty parent directories for recorded outputs if they existed in root
  for (orel in output_rels) {
    parent <- fs::path_dir(orel)
    if (!identical(parent, ".") && fs::dir_exists(file.path(real_root, parent))) {
      parent_dest <- assert_confined_path(parent, root = real_sandbox, must_exist = FALSE, arg = "sandbox output dir")
      fs::dir_create(parent_dest)
    }
  }

  sort(unique(staged_rels))
}

# Generate deterministic runner bootstrap script for sandbox or container execution
write_runner_bootstrap <- function(sandbox_dir, entrypoint, seed, rng_kind) {
  entrypoint <- assert_safe_manifest_rel_path(entrypoint, arg = "entrypoint")
  validate_safe_rel_spec_path(entrypoint, arg = "entrypoint")
  assert_confined_path(entrypoint, root = sandbox_dir, must_exist = TRUE, arg = "entrypoint")

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
    if (identical(tolower(basename(entrypoint)), "_targets.r")) {
      lines <- c(
        lines,
        "if (requireNamespace('targets', quietly = TRUE)) {",
        "  targets::tar_make()",
        "} else {",
        sprintf("  source(%s, local = new.env(parent = globalenv()))", deparse(entrypoint)),
        "}"
      )
    } else {
      lines <- c(
        lines,
        sprintf("source(%s, local = new.env(parent = globalenv()))", deparse(entrypoint))
      )
    }
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

# Build clean controlled environment vector for child execution with secret scrubbing
build_sandbox_env <- function(sandbox_dir, seed = NULL, env_vars = list(), scrub_secrets = TRUE) {
  clean_user_env <- validate_env_vars(env_vars, arg = "env_vars")
  cur <- as.list(Sys.getenv())

  scrubbed_names <- character()
  if (isTRUE(scrub_secrets)) {
    sc_res <- scrub_sandbox_env(cur, explicit_env_vars = clean_user_env)
    env <- sc_res$env
    scrubbed_names <- sc_res$scrubbed
  } else {
    env <- cur
  }

  env$TZ <- "UTC"
  env$LC_ALL <- "C.UTF-8"
  env$LANG <- "C.UTF-8"
  env$RCAPSULE_SANDBOX <- "1"
  env$R_USER_CACHE_DIR <- file.path(sandbox_dir, ".rcapsule_cache")
  if (!is.null(seed) && !is.na(seed)) {
    env$CAPSULE_SEED <- as.character(as.integer(seed))
  }
  if (length(clean_user_env) > 0L) {
    for (nm in names(clean_user_env)) {
      env[[nm]] <- clean_user_env[[nm]]
    }
  }
  list(env = unlist(env), scrubbed = scrubbed_names)
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

# Build docker run argument vector cleanly (testable offline without Docker daemon)
build_docker_run_args <- function(sandbox_dir, img, seed = NULL, env_vars = list(), runner_file = ".rcapsule_runner.R") {
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
  clean_user_env <- validate_env_vars(env_vars, arg = "env_vars")
  if (length(clean_user_env) > 0L) {
    for (nm in names(clean_user_env)) {
      run_args <- c(run_args, "-e", paste0(nm, "=", clean_user_env[[nm]]))
    }
  }
  c(
    run_args,
    "-v", paste0(sandbox_dir, ":/capsule"),
    "-w", "/capsule",
    img,
    "Rscript", runner_file
  )
}

# Execute pipeline inside a live Docker container
run_in_docker <- function(root, sandbox_dir, docker_image, docker_tag, seed, env_vars, timeout,
                          runner_fn = processx::run, check_available = docker_available) {
  if (!isTRUE(check_available())) {
    cli::cli_abort(
      "Docker daemon is not available. Use {.code runner = \"sandbox\"} for isolated local verification or start Docker."
    )
  }
  docker_bin <- unname(Sys.which("docker"))
  if (!nzchar(docker_bin)) docker_bin <- "docker"
  t0 <- proc.time()[["elapsed"]]

  img <- docker_image
  build_out <- ""
  if (is.null(img)) {
    df_path <- file.path(root, "Dockerfile")
    if (!fs::file_exists(df_path)) {
      cli::cli_abort("No {.arg docker_image} provided and no Dockerfile found at {.path {df_path}}.")
    }
    img <- docker_tag %||% paste0("rcapsule-verify-", tolower(substr(sha256_string(root), 1L, 10L)), ":audit")
    b_res <- runner_fn(
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

  run_args <- build_docker_run_args(sandbox_dir, img, seed = seed, env_vars = env_vars)
  r_res <- runner_fn(
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
#' @param strict_outputs Logical; if `TRUE`, fails verification when the
#'   pipeline produces unexpected extra artifacts not declared in
#'   `manifest$artifacts$outputs`. Defaults to `FALSE` (extra artifacts are
#'   still detected and reported in `extra_artifacts`).
#' @param scrub_secrets Logical; if `TRUE` (default), strips ambient credential
#'   and token environment variables (`AWS_*`, `GITHUB_TOKEN`, `GH_TOKEN`,
#'   `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `*_SECRET*`, `*_TOKEN*`, etc.)
#'   before launching the isolated sandbox subprocess.
#'
#' @return An S3 object of class `rcapsule_verification` containing `status`
#'   (`"verified_exact"`, `"verified_within_tolerance"`, or `"failed"`),
#'   `passed` (logical), `runner`, `verified_at`, `duration_sec`,
#'   `exit_status`, `manifest_integrity`, `input_checks`, `script_checks`,
#'   `output_checks`, `extra_artifacts`, `scrubbed_env_vars`,
#'   `failure_reasons`, `rng`, `environment`, `stdout`, `stderr`,
#'   `sandbox_dir`, and `manifest`.
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
                           reference_dir = NULL,
                           strict_outputs = FALSE,
                           scrub_secrets = TRUE) {
  runner <- match.arg(runner)
  root <- normalize_project_path(path, must_exist = TRUE)
  ref_root <- if (!is.null(reference_dir)) normalize_project_path(reference_dir, must_exist = TRUE) else root
  real_ref_root <- canonical_real_dir(ref_root)

  if (is.character(manifest) && length(manifest) == 1L) {
    manifest <- read_capsule_manifest(manifest)
  }
  if (!inherits(manifest, "rcapsule_manifest")) {
    cli::cli_abort("{.arg manifest} must be an {.cls rcapsule_manifest} or path to capsule.json.")
  }

  # 1. Cryptographic manifest integrity check
  integrity <- verify_manifest_integrity(manifest, key = key)

  # 2. Verify inputs & scripts on disk (with strict confinement)
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
  eff_ep <- assert_safe_manifest_rel_path(eff_ep, arg = "entrypoint")

  # 4. Stage clean isolated sandbox (excluding all recorded outputs and external symlinks!)
  sandbox_dir <- as.character(fs::path_norm(tempfile("rcapsule_sandbox_")))
  if (!isTRUE(keep_sandbox)) {
    on.exit(unlink(sandbox_dir, recursive = TRUE, force = TRUE), add = TRUE)
  }
  staged_rels <- stage_clean_sandbox(root, manifest, sandbox_dir)
  real_sandbox <- canonical_real_dir(sandbox_dir)
  runner_script <- write_runner_bootstrap(real_sandbox, eff_ep, eff_seed, eff_rng_kind)

  # 5. Execute in sandbox (with ambient secret scrubbing) or Docker
  scrubbed_env_vars <- character()
  exec_res <- if (identical(runner, "sandbox")) {
    env_bundle <- build_sandbox_env(real_sandbox, seed = eff_seed, env_vars = env_vars, scrub_secrets = scrub_secrets)
    scrubbed_env_vars <- env_bundle$scrubbed
    run_in_sandbox(real_sandbox, runner_script, env = env_bundle$env, timeout = timeout)
  } else {
    run_in_docker(
      root = root,
      sandbox_dir = real_sandbox,
      docker_image = docker_image,
      docker_tag = docker_tag,
      seed = eff_seed,
      env_vars = env_vars,
      timeout = timeout
    )
  }

  # 6. Compare every recorded output artifact (enforcing confinement & constant-time hash checks)
  out_records <- manifest$artifacts$outputs
  output_rels <- character()
  out_rows <- lapply(out_records, function(rec) {
    rel <- assert_safe_manifest_rel_path(rec$path, arg = "manifest output path")
    output_rels <<- c(output_rels, rel)
    file_tol <- eff_tols$files[[rel]] %||% eff_tols$default
    abs_tol <- as.numeric(file_tol$abs_tol %||% file_tol$atol %||% 0)
    rel_tol <- as.numeric(file_tol$rel_tol %||% file_tol$rtol %||% 0)

    # Locate trusted baseline for tolerance comparison:
    # Either confined on-disk file whose hash matches manifest, or embedded snapshot whose hash matches
    ref_file <- assert_confined_path(rel, root = real_ref_root, must_exist = FALSE, arg = "reference output path")
    trusted_ref_path <- NULL
    if (fs::file_exists(ref_file) && constant_time_equal(sha256_file(ref_file), as.character(rec$sha256 %||% ""))) {
      trusted_ref_path <- ref_file
    }

    expected_raw <- NULL
    if (is.null(trusted_ref_path) && !is.null(manifest$snapshots[[rel]])) {
      snap <- manifest$snapshots[[rel]]
      raw_bytes <- tryCatch(openssl::base64_decode(snap$data), error = function(e) NULL)
      if (!is.null(raw_bytes) && constant_time_equal(sha256_raw(raw_bytes), as.character(rec$sha256 %||% ""))) {
        expected_raw <- raw_bytes
      }
    }

    actual_fp <- assert_confined_path(rel, root = real_sandbox, must_exist = FALSE, arg = "sandbox output path")
    cmp <- compare_artifacts(
      expected_path = trusted_ref_path,
      actual_path = actual_fp,
      expected_sha256 = rec$sha256,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      format = rec$format %||% "auto",
      expected_raw = expected_raw
    )
    cmp$path <- rel
    cmp
  })

  # Detect unexpected extra artifacts created inside sandbox during execution
  post_entries <- as.character(fs::dir_ls(real_sandbox, recurse = TRUE, all = TRUE, type = "file", fail = FALSE))
  extra_artifacts <- character()
  if (length(post_entries) > 0L) {
    post_rels <- rel_path(post_entries, real_sandbox)
    internal_mask <- post_rels == ".rcapsule_runner.R" | grepl("^\\.rcapsule_cache(/|$)", post_rels)
    known_rels <- unique(c(staged_rels, output_rels))
    extra_artifacts <- sort(setdiff(post_rels[!internal_mask], known_rels))
  }

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
  if (isTRUE(strict_outputs) && length(extra_artifacts) > 0L) {
    failure_reasons <- c(
      failure_reasons,
      paste0("Unexpected extra output artifact(s) produced: ", paste(extra_artifacts, collapse = ", "))
    )
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
      extra_artifacts = extra_artifacts,
      scrubbed_env_vars = scrubbed_env_vars,
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
