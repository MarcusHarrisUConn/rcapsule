# Automated reproducibility drift diagnostics & ranked remediation advisor

# Severity ordering helper for consistent finding ranking
severity_rank <- function(sev) {
  switch(
    as.character(sev),
    critical = 1L,
    high = 2L,
    medium = 3L,
    low = 4L,
    info = 5L,
    6L
  )
}

# Classify a single output row from output_checks or artifact_diffs$outputs
classify_output_drift_row <- function(path, status, max_abs_diff, max_rel_diff, details,
                                      small_tol = 1e-2, seed_unset = FALSE, seed_changed = FALSE) {
  det <- as.character(details %||% "")
  ext <- tolower(tools::file_ext(path))
  is_binary_fig <- ext %in% c("pdf", "png", "jpg", "jpeg", "tiff", "bmp", "eps", "ps", "zip", "gz", "docx", "pptx", "xlsx", "parquet")

  if (status %in% c("missing", "removed")) {
    return(list(
      category = "missing_output",
      severity = "high",
      confidence = "high",
      affected = path,
      evidence = paste0("Declared output '", path, "' was not generated or was removed (", det, ")."),
      remediation = paste0("Verify the pipeline writes '", path, "' relative to the project root without hard-coded absolute paths or external side effects.")
    ))
  }

  if (status == "added") {
    return(list(
      category = "unexpected_extra_artifacts",
      severity = "low",
      confidence = "high",
      affected = path,
      evidence = paste0("Output '", path, "' is present only in the comparison manifest."),
      remediation = "Register intentional outputs in create_capsule_manifest(outputs = ...) or remove temporary scratch files before archiving."
    ))
  }

  # 1. Exact CRLF vs LF line-ending drift
  if (grepl("CRLF vs LF line endings", det, fixed = TRUE)) {
    return(list(
      category = "line_ending_drift",
      severity = "medium",
      confidence = "high",
      affected = path,
      evidence = paste0("'", path, "' differs exclusively in Windows CRLF vs Unix LF line endings."),
      remediation = "Normalize line endings with eol = '\\n' (write.table/writeLines(..., useBytes = TRUE)) and enforce '* text=auto eol=lf' in .gitattributes."
    ))
  }

  # 2. Structural schema, missing-value, type, or label drift
  schema_pat <- paste(
    c(
      "row count mismatch", "column mismatch", "column order mismatch",
      "list key mismatch", "list length mismatch", "list names/length mismatch",
      "dimension mismatch", "vector names mismatch", "dimnames mismatch",
      "object type/class mismatch", "NULL vs non-NULL mismatch",
      "NA mismatch", "NaN mismatch", "infinite", "Failed to parse artifact",
      "length mismatch"
    ),
    collapse = "|"
  )
  if (grepl(schema_pat, det, ignore.case = TRUE, perl = TRUE) ||
    grepl("expected='.*actual='", det, perl = TRUE)) {
    return(list(
      category = "schema_drift",
      severity = "high",
      confidence = "high",
      affected = path,
      evidence = paste0("Structural/schema mismatch in '", path, "': ", det),
      remediation = "Inspect upstream data transformations, factor/column ordering, and package upgrades that altered table columns, row counts, keys, or NA handling."
    ))
  }

  # 3. Binary / PDF / PNG metadata & font rendering drift
  if (is_binary_fig || grepl("non-numeric format 'binary'", det, fixed = TRUE)) {
    return(list(
      category = "binary_metadata_drift",
      severity = "medium",
      confidence = "high",
      affected = path,
      evidence = paste0("Binary/figure artifact '", path, "' changed bytes despite potential visual equivalence (", det, ")."),
      remediation = "PDF/PNG binaries often embed timestamps, Producer headers, or OS-specific font rasterization (FreeType/Cairo). Verify underlying summary CSV/RDS tables alongside figures, set deterministic graphics devices (ragg/svglite), and build inside a pinned Linux container."
    ))
  }

  # 4. Within-tolerance or small numerical / Monte Carlo / BLAS rounding drift
  has_num <- is.finite(max_abs_diff) || is.finite(max_rel_diff)
  eff_abs <- if (is.finite(max_abs_diff)) max_abs_diff else Inf
  eff_rel <- if (is.finite(max_rel_diff)) max_rel_diff else Inf

  if (identical(status, "within_tolerance")) {
    return(list(
      category = "monte_carlo_small_drift",
      severity = "info",
      confidence = "high",
      affected = path,
      evidence = paste0(
        "'", path, "' verified within tolerance (max_abs_diff=", signif(max_abs_diff, 4L),
        ", max_rel_diff=", signif(max_rel_diff, 4L), ")."
      ),
      remediation = "Small cross-platform BLAS/LAPACK or floating-point rounding drift is within configured bounds. Pin '--platform=linux/amd64' in compile_dockerfile() if bit-exact outputs are required."
    ))
  }

  if (has_num && (eff_abs <= small_tol || eff_rel <= small_tol)) {
    return(list(
      category = "monte_carlo_small_drift",
      severity = "medium",
      confidence = "high",
      affected = path,
      evidence = paste0(
        "Small numerical drift in '", path, "' (max_abs_diff=", signif(max_abs_diff, 4L),
        ", max_rel_diff=", signif(max_rel_diff, 4L), " <= small_tol=", small_tol, "): ", det
      ),
      remediation = paste0(
        "Likely caused by cross-architecture BLAS/LAPACK rounding, parallel thread reduction order, or MCMC floating-point jitter. ",
        "Configure an explicit numeric tolerance (e.g., tolerances = list(atol = ",
        signif(max(eff_abs * 2, 1e-6), 2L), ", rtol = ", signif(max(eff_rel * 2, 1e-6), 2L),
        ")) or pin the container architecture with platform = 'linux/amd64'."
      )
    ))
  }

  # 5. Large numerical divergence or unseeded stochasticity
  if (has_num && eff_abs > small_tol && eff_rel > small_tol) {
    seed_hint <- if (isTRUE(seed_unset) || isTRUE(seed_changed)) {
      "RNG seed is unset or changed across runs, strongly pointing to unseeded stochastic sampling."
    } else {
      "Magnitude exceeds typical BLAS rounding; check unseeded parallel workers, external RNGs (Stan/Python/C++), or data/algorithmic changes."
    }
    return(list(
      category = "unseeded_large_divergence",
      severity = "high",
      confidence = if (isTRUE(seed_unset) || isTRUE(seed_changed)) "high" else "medium",
      affected = path,
      evidence = paste0(
        "Large numerical divergence in '", path, "' (max_abs_diff=", signif(max_abs_diff, 4L),
        ", max_rel_diff=", signif(max_rel_diff, 4L), "): ", det
      ),
      remediation = paste0(
        seed_hint,
        " Explicitly call set.seed(), pass parallel RNG seeds (e.g., future.seed = TRUE or CmdStan seed), and record the seed in create_capsule_manifest(seed = ...)."
      )
    ))
  }

  # 6. Generic serialization / timestamp text drift (e.g. HTML/MD timestamps or uncompared hashes)
  if (ext %in% c("html", "htm", "md", "txt", "log", "svg")) {
    return(list(
      category = "binary_metadata_drift",
      severity = "medium",
      confidence = "medium",
      affected = path,
      evidence = paste0("Rendered document/text artifact '", path, "' changed SHA-256 hash (", det, ")."),
      remediation = "Rendered HTML/Markdown reports often embed timestamps, sessionInfo(), or random widget IDs. Pin Quarto/rmarkdown metadata dates and verify numeric summary CSV/RDS outputs directly."
    ))
  }

  list(
    category = "unseeded_large_divergence",
    severity = "high",
    confidence = "low",
    affected = path,
    evidence = paste0("Output artifact '", path, "' failed SHA-256 comparison (", det, ")."),
    remediation = "Re-run verify_capsule(..., keep_sandbox = TRUE) or enable embedded snapshots in create_capsule_manifest(embed_snapshots = TRUE) to inspect detailed cell-level differences."
  )
}

# Parse pipeline stderr for specific execution failure remediation hints
diagnose_stderr_clue <- function(stderr_text) {
  s <- as.character(stderr_text %||% "")
  if (grepl("there is no package called", s, ignore.case = TRUE)) {
    m <- regmatches(s, regexec("there is no package called\\s+[^A-Za-z0-9]*([A-Za-z0-9.]+)", s, ignore.case = TRUE, perl = TRUE))[[1L]]
    pkg <- if (length(m) >= 2L && nzchar(m[[2L]])) m[[2L]] else "<unknown>"
    return(paste0("Missing R package '", pkg, "' in verification environment. Restore dependencies with renv::restore() or run verification inside the compiled Docker/Apptainer image."))
  }
  if (grepl("cannot open (the )?connection|cannot open file|No such file or directory", s, ignore.case = TRUE, perl = TRUE)) {
    return("Pipeline failed to locate a file inside the isolated sandbox. Replace absolute paths with project-relative or here::here() paths and declare all required inputs in create_capsule_manifest(inputs = ...).")
  }
  if (grepl("unexpected|parse\\(|syntax error", s, ignore.case = TRUE, perl = TRUE)) {
    return("R syntax/parse error encountered while executing the entrypoint script. Verify the entrypoint executes cleanly in a fresh R session.")
  }
  if (grepl("timeout|timed out", s, ignore.case = TRUE, perl = TRUE)) {
    return("Pipeline exceeded execution timeout. Increase verify_capsule(..., timeout = ...) or reduce test fixture iterations.")
  }
  "Inspect verification$stderr and re-run verify_capsule(..., keep_sandbox = TRUE) to debug the failing step in isolation."
}

# Check for environment drift between manifest$environment and verification$environment
check_verification_env_drift <- function(verification) {
  m_env <- verification$manifest$environment %||% list()
  v_env <- verification$environment %||% list()
  drifts <- character()
  if (!is.null(m_env$r_version) && !is.null(v_env$r_version) && !identical(m_env$r_version, v_env$r_version)) {
    drifts <- c(drifts, paste0("R version ", m_env$r_version, " -> ", v_env$r_version))
  }
  if (!is.null(m_env$platform) && !is.null(v_env$platform) && !identical(m_env$platform, v_env$platform)) {
    drifts <- c(drifts, paste0("platform ", m_env$platform, " -> ", v_env$platform))
  }
  if (!is.null(m_env$os) && !is.null(v_env$os) && !identical(m_env$os, v_env$os)) {
    drifts <- c(drifts, paste0("OS ", m_env$os, " -> ", v_env$os))
  }
  drifts
}

#' Diagnose Reproducibility Failures and Cross-Run Drift
#'
#' Automatically inspects a verification audit from [verify_capsule()] or a
#' cross-machine manifest diff from [diff_capsules()], classifies every root
#' cause of divergence, and ranks concrete remediation steps.
#'
#' Root-cause categories include:
#' - `hmac_signature_failure` and `manifest_tampering`
#' - `execution_failure` (with `stderr` clue parsing for missing packages,
#'   broken relative paths, syntax errors, and timeouts)
#' - `input_drift`, `script_drift`, and `container_drift`
#' - `missing_output` and `unexpected_extra_artifacts`
#' - `line_ending_drift` (exact `CRLF` vs. `LF` equivalence detection)
#' - `schema_drift` (row/column/key/type/NA/NaN/Inf changes)
#' - `binary_metadata_drift` (PDF/PNG/HTML timestamps and font rasterization)
#' - `monte_carlo_small_drift` vs. `unseeded_large_divergence` and `rng_drift`
#' - `environment_or_arch_drift` (R version, CPU architecture, OS, packages,
#'   sysreqs, or scientific toolchains)
#'
#' @param x An `rcapsule_verification` object from [verify_capsule()] or an
#'   `rcapsule_diff` object from [diff_capsules()].
#' @param path Optional project root directory path used for supplemental byte
#'   checks when `x` is an `rcapsule_verification` with a retained `sandbox_dir`.
#' @param small_tol Positive numeric threshold distinguishing small numerical /
#'   Monte Carlo / BLAS rounding drift (`<= small_tol`) from large unseeded or
#'   algorithmic divergence (`> small_tol`). Defaults to `1e-2`.
#'
#' @return An S3 object of class `rcapsule_diagnosis` containing `source_type`
#'   (`"verification"` or `"diff"`), `status`, `primary_cause`, `n_findings`,
#'   `findings` (a ranked tibble with columns `rank`, `category`, `severity`,
#'   `confidence`, `affected`, `evidence`, and `remediation`), `remediations`
#'   (deduplicated ranked action list), and `summary_text`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_diag_")
#' dir.create(tmp)
#' writeLines(
#'   c("df <- data.frame(id = 1:3, val = rnorm(3))",
#'     "write.csv(df, 'out.csv', row.names = FALSE)"),
#'   file.path(tmp, "run.R")
#' )
#' set.seed(1)
#' write.csv(data.frame(id = 1:3, val = rnorm(3)), file.path(tmp, "out.csv"), row.names = FALSE)
#' m <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
#' # Simulate running with a different seed
#' v <- verify_capsule(m, path = tmp, seed = 999L)
#' diag <- diagnose_reproducibility(v)
#' diag
#' unlink(tmp, recursive = TRUE)
diagnose_reproducibility <- function(x, path = NULL, small_tol = 1e-2) {
  if (!inherits(x, "rcapsule_verification") && !inherits(x, "rcapsule_diff")) {
    cli::cli_abort("{.arg x} must be an {.cls rcapsule_verification} or {.cls rcapsule_diff} object.")
  }
  small_tol <- as.numeric(small_tol)
  if (length(small_tol) != 1L || is.na(small_tol) || !is.finite(small_tol) || small_tol <= 0) {
    cli::cli_abort("{.arg small_tol} must be a single finite positive number.")
  }

  findings <- list()
  add_finding <- function(category, severity, confidence, affected, evidence, remediation) {
    findings[[length(findings) + 1L]] <<- list(
      category = as.character(category),
      severity = as.character(severity),
      confidence = as.character(confidence),
      affected = as.character(affected),
      evidence = as.character(evidence),
      remediation = as.character(remediation)
    )
  }

  source_type <- if (inherits(x, "rcapsule_verification")) "verification" else "diff"
  status_val <- if (identical(source_type, "verification")) {
    x$status
  } else if (isTRUE(x$identical)) {
    "identical"
  } else if (isTRUE(x$outputs_equivalent)) {
    "outputs_equivalent_with_drift"
  } else {
    "diverged"
  }

  if (identical(source_type, "verification")) {
    # 1. Manifest cryptographic integrity & HMAC signature
    if (!isTRUE(x$manifest_integrity$valid)) {
      iss <- paste(x$manifest_integrity$issues %||% "Integrity validation failed.", collapse = "; ")
      if (grepl("HMAC|signature|signing key", iss, ignore.case = TRUE, perl = TRUE)) {
        add_finding(
          "hmac_signature_failure", "critical", "high", "capsule.json",
          paste0("Manifest HMAC-SHA256 verification failed: ", iss),
          "Supply the exact signing key via verify_capsule(..., key = ...) or re-sign an unmodified manifest with sign_manifest()."
        )
      } else {
        add_finding(
          "manifest_tampering", "critical", "high", "capsule.json",
          paste0("Manifest content digest or schema integrity failed: ", iss),
          "Do not hand-edit capsule.json. Regenerate the provenance manifest from clean sources via create_capsule_manifest()."
        )
      }
    }

    # 2. Input & script drift
    if (nrow(x$input_checks) > 0L && any(!x$input_checks$passed)) {
      bad_in <- x$input_checks[!x$input_checks$passed, , drop = FALSE]
      add_finding(
        "input_drift", "high", "high", paste(bad_in$path, collapse = ", "),
        paste0("Input file(s) modified or missing since manifest creation: ", paste(paste0(bad_in$path, " [", bad_in$status, "]"), collapse = "; ")),
        "Restore the exact recorded input dataset revision (check Git/DVC/Zenodo checksums) or regenerate capsule.json if data updates are intentional."
      )
    }
    if (nrow(x$script_checks) > 0L && any(!x$script_checks$passed)) {
      bad_sc <- x$script_checks[!x$script_checks$passed, , drop = FALSE]
      add_finding(
        "script_drift", "high", "high", paste(bad_sc$path, collapse = ", "),
        paste0("Script/config file(s) changed since manifest creation: ", paste(paste0(bad_sc$path, " [", bad_sc$status, "]"), collapse = "; ")),
        "Checkout the recorded Git commit before verifying, or update capsule.json after committing code edits."
      )
    }

    # 3. Pipeline execution failure
    if (!identical(as.integer(x$exit_status), 0L)) {
      stderr_snip <- trimws(as.character(x$stderr %||% ""))
      if (nchar(stderr_snip) > 220L) {
        stderr_snip <- paste0(substr(stderr_snip, 1L, 217L), "...")
      }
      add_finding(
        "execution_failure", "critical", "high", x$entrypoint %||% "<entrypoint>",
        paste0("Pipeline exited with status ", x$exit_status, if (nzchar(stderr_snip)) paste0(": ", stderr_snip) else "."),
        diagnose_stderr_clue(x$stderr)
      )
    }

    # 4. RNG seed mismatch between manifest and verification run, or unset seed
    m_seed <- x$manifest$rng$seed
    v_seed <- x$rng$seed
    seed_changed <- !identical(m_seed, v_seed)
    seed_unset <- is.null(m_seed) && is.null(v_seed)
    if (seed_changed) {
      add_finding(
        "rng_drift", "high", "high", "RNG seed",
        paste0("Verification used seed=", v_seed %||% "unset", " while manifest recorded seed=", m_seed %||% "unset", "."),
        paste0("Run verify_capsule() using the manifest seed (", m_seed %||% "recorded seed", ") without overriding the seed argument.")
      )
    }

    # 5. Output artifact drift classification
    if (nrow(x$output_checks) > 0L) {
      for (i in seq_len(nrow(x$output_checks))) {
        row <- x$output_checks[i, ]
        if (identical(row$status, "exact_match")) next

        # Supplemental byte-level CRLF check if sandbox_dir and path were retained
        det_str <- as.character(row$details %||% "")
        if (!grepl("CRLF vs LF", det_str, fixed = TRUE) &&
          !is.null(x$sandbox_dir) && !is.null(path) &&
          fs::dir_exists(x$sandbox_dir) && fs::dir_exists(path)) {
          ref_fp <- file.path(path, row$path)
          act_fp <- file.path(x$sandbox_dir, row$path)
          fmt <- detect_artifact_format(row$path)
          if (differs_only_in_line_endings(ref_fp, act_fp, fmt)) {
            det_str <- "SHA-256 digest mismatch (exact match required; files differ only in CRLF vs LF line endings)."
          }
        }

        f <- classify_output_drift_row(
          path = row$path,
          status = row$status,
          max_abs_diff = row$max_abs_diff,
          max_rel_diff = row$max_rel_diff,
          details = det_str,
          small_tol = small_tol,
          seed_unset = seed_unset,
          seed_changed = seed_changed
        )
        add_finding(f$category, f$severity, f$confidence, f$affected, f$evidence, f$remediation)
      }
    }

    # 6. Environment drift between manifest creation and verification host
    env_drifts <- check_verification_env_drift(x)
    if (length(env_drifts) > 0L) {
      sev <- if (isTRUE(x$passed)) "info" else "medium"
      add_finding(
        "environment_or_arch_drift", sev, "high", "runtime environment",
        paste0("Verification environment differs from manifest creation host: ", paste(env_drifts, collapse = "; "), "."),
        "Re-run inside the compiled Docker or Apptainer container (with --platform=linux/amd64 when crossing arm64/x86_64 hosts) to match R, OS, and BLAS libraries."
      )
    }

    # 7. Unexpected extra artifacts
    if (length(x$extra_artifacts) > 0L) {
      sev <- if (!isTRUE(x$passed) && any(grepl("Unexpected extra output", x$failure_reasons, fixed = TRUE))) "medium" else "low"
      add_finding(
        "unexpected_extra_artifacts", sev, "high", paste(x$extra_artifacts, collapse = ", "),
        paste0("Pipeline produced ", length(x$extra_artifacts), " undeclared file(s) inside the sandbox: ", paste(x$extra_artifacts, collapse = ", "), "."),
        "Declare expected outputs in create_capsule_manifest(outputs = ...) or write intermediate scratch files to tempdir()."
      )
    }

    # 8. Unseeded warning if verification failed on outputs with no recorded seed
    if (seed_unset && !isTRUE(x$passed) && nrow(x$output_checks) > 0L && any(!x$output_checks$passed)) {
      add_finding(
        "rng_drift", "medium", "medium", "RNG seed",
        "No RNG seed is recorded in capsule.json, leaving stochastic R/MCMC calls unseeded.",
        "Add an explicit set.seed(...) call to your pipeline and pass seed = <integer> to create_capsule_manifest()."
      )
    }
  } else {
    # Source is rcapsule_diff
    # 1. Input & script drift
    if (isTRUE(x$has_input_drift)) {
      bad_in <- x$artifact_diffs$inputs[x$artifact_diffs$inputs$status != "unchanged", , drop = FALSE]
      add_finding(
        "input_drift", "high", "high", paste(bad_in$path, collapse = ", "),
        paste0("Input dataset(s) differ between runs: ", paste(paste0(bad_in$path, " [", bad_in$status, "]"), collapse = "; ")),
        "Synchronize input datasets across both machines using identical checksummed archives before comparing results."
      )
    }
    if (isTRUE(x$has_script_drift)) {
      bad_sc <- x$artifact_diffs$scripts[x$artifact_diffs$scripts$status != "unchanged", , drop = FALSE]
      add_finding(
        "script_drift", "high", "high", paste(bad_sc$path, collapse = ", "),
        paste0("Script or lockfile(s) differ between runs: ", paste(paste0(bad_sc$path, " [", bad_sc$status, "]"), collapse = "; ")),
        "Ensure both runs execute the exact same Git commit and renv.lock revision."
      )
    }

    # 2. RNG drift
    if (isTRUE(x$rng_diff$seed_changed) || isTRUE(x$rng_diff$kind_changed)) {
      rng_parts <- c(
        if (isTRUE(x$rng_diff$seed_changed)) paste0("seed ", x$rng_diff$seed_a %||% "unset", " -> ", x$rng_diff$seed_b %||% "unset") else NULL,
        if (isTRUE(x$rng_diff$kind_changed)) paste0("RNGkind ", paste(x$rng_diff$kind_a, collapse = "/"), " -> ", paste(x$rng_diff$kind_b, collapse = "/")) else NULL
      )
      add_finding(
        "rng_drift", "high", "high", "RNG configuration",
        paste0("Random number generator configuration diverged: ", paste(rng_parts, collapse = "; "), "."),
        "Pin both set.seed() and RNGkind() explicitly at pipeline startup."
      )
    }

    # 3. Environment, architecture, package, sysreq, and toolchain drift
    if (isTRUE(x$has_env_drift)) {
      ed <- x$env_diff
      parts <- c(
        if (isTRUE(ed$r_version_changed)) paste0("R ", ed$r_version_a, " -> ", ed$r_version_b) else NULL,
        if (isTRUE(ed$platform_changed)) paste0("platform ", ed$platform_a, " -> ", ed$platform_b) else NULL,
        if (isTRUE(ed$os_changed)) paste0("OS ", ed$os_a, " -> ", ed$os_b) else NULL,
        if (nrow(ed$packages) > 0L) paste0(nrow(ed$packages), " R package diff(s)") else NULL,
        if (length(ed$sysreqs$added) > 0L || length(ed$sysreqs$removed) > 0L) "OS sysreqs changed" else NULL,
        if (length(ed$toolchains$added) > 0L || length(ed$toolchains$removed) > 0L) "scientific toolchains changed" else NULL
      )
      sev <- if (isTRUE(x$outputs_equivalent)) "info" else "medium"
      add_finding(
        "environment_or_arch_drift", sev, "high", "runtime environment",
        paste0("Execution environments diverged: ", paste(parts, collapse = "; "), "."),
        "Execute both runs inside the same compiled Docker or Apptainer image (pinned with platform = 'linux/amd64' and renv.lock) to eliminate host drift."
      )
    }

    # 4. Output artifact drift
    out_tbl <- x$artifact_diffs$outputs
    if (nrow(out_tbl) > 0L) {
      for (i in seq_len(nrow(out_tbl))) {
        row <- out_tbl[i, ]
        if (identical(row$status, "unchanged")) next
        f <- classify_output_drift_row(
          path = row$path,
          status = row$status,
          max_abs_diff = row$max_abs_diff,
          max_rel_diff = row$max_rel_diff,
          details = row$details,
          small_tol = small_tol,
          seed_unset = is.null(x$rng_diff$seed_a) && is.null(x$rng_diff$seed_b),
          seed_changed = isTRUE(x$rng_diff$seed_changed)
        )
        add_finding(f$category, f$severity, f$confidence, f$affected, f$evidence, f$remediation)
      }
    }

    # 5. Container & Git metadata drift
    if (isTRUE(x$has_container_drift)) {
      bad_c <- x$artifact_diffs$containers[x$artifact_diffs$containers$status != "unchanged", , drop = FALSE]
      add_finding(
        "container_drift", "low", "high", paste(bad_c$path, collapse = ", "),
        paste0("Container recipe(s) changed between runs: ", paste(bad_c$path, collapse = ", "), "."),
        "Rebuild container images from the identical pinned Dockerfile or Apptainer.def."
      )
    }
    if (isTRUE(x$git_diff$commit_changed)) {
      add_finding(
        "git_revision_drift", "low", "high", "git HEAD",
        paste0("Git commit changed: ", x$git_diff$commit_a %||% "none", " -> ", x$git_diff$commit_b %||% "none", "."),
        "Compare manifests built from the same committed Git revision."
      )
    }
  }

  # Sort findings by severity rank then confidence
  findings_tbl <- if (length(findings) > 0L) {
    sev_ord <- vapply(findings, function(f) severity_rank(f$severity), integer(1L))
    conf_ord <- vapply(findings, function(f) switch(f$confidence, high = 1L, medium = 2L, 3L), integer(1L))
    ord <- order(sev_ord, conf_ord)
    findings <- findings[ord]
    tibble::tibble(
      rank = seq_along(findings),
      category = vapply(findings, `[[`, character(1L), "category"),
      severity = vapply(findings, `[[`, character(1L), "severity"),
      confidence = vapply(findings, `[[`, character(1L), "confidence"),
      affected = vapply(findings, `[[`, character(1L), "affected"),
      evidence = vapply(findings, `[[`, character(1L), "evidence"),
      remediation = vapply(findings, `[[`, character(1L), "remediation")
    )
  } else {
    tibble::tibble(
      rank = integer(),
      category = character(),
      severity = character(),
      confidence = character(),
      affected = character(),
      evidence = character(),
      remediation = character()
    )
  }

  primary_cause <- if (nrow(findings_tbl) > 0L) findings_tbl$category[[1L]] else "none"
  remediations <- unique(findings_tbl$remediation)
  summary_text <- if (nrow(findings_tbl) == 0L) {
    "No reproducibility drift or failures detected."
  } else {
    paste0(
      nrow(findings_tbl), " finding(s) detected; primary root cause: ", primary_cause,
      " (top severity: ", findings_tbl$severity[[1L]], ")."
    )
  }

  structure(
    list(
      source_type = source_type,
      status = status_val,
      primary_cause = primary_cause,
      n_findings = nrow(findings_tbl),
      findings = findings_tbl,
      remediations = remediations,
      summary_text = summary_text
    ),
    class = "rcapsule_diagnosis"
  )
}

#' @export
print.rcapsule_diagnosis <- function(x, ...) {
  cli::cli_h1("rcapsule Reproducibility Diagnosis")
  cli::cli_ul(c(
    "Source: {.val {x$source_type}} | Status: {.val {x$status}}",
    "Primary cause: {.val {x$primary_cause}} | Findings: {.val {x$n_findings}}"
  ))
  if (nrow(x$findings) > 0L) {
    cli::cli_h2("Ranked Root Causes")
    for (i in seq_len(nrow(x$findings))) {
      row <- x$findings[i, ]
      msg <- paste0("#", row$rank, " [", toupper(row$severity), " | ", row$category, "] ", row$affected, ": ", row$evidence)
      if (row$severity %in% c("critical", "high")) {
        cli::cli_alert_danger("{msg}")
      } else if (row$severity == "medium") {
        cli::cli_alert_warning("{msg}")
      } else {
        cli::cli_alert_info("{msg}")
      }
      cli::cli_text("   Remediation: {row$remediation}")
    }
  } else {
    cli::cli_alert_success("No reproducibility drift or failures detected.")
  }
  invisible(x)
}

#' @export
summary.rcapsule_diagnosis <- function(object, ...) {
  sev_counts <- list(
    critical = sum(object$findings$severity == "critical"),
    high = sum(object$findings$severity == "high"),
    medium = sum(object$findings$severity == "medium"),
    low = sum(object$findings$severity == "low"),
    info = sum(object$findings$severity == "info")
  )
  list(
    source_type = object$source_type,
    status = object$status,
    primary_cause = object$primary_cause,
    n_findings = object$n_findings,
    severity_counts = sev_counts,
    categories = unique(object$findings$category),
    remediations = object$remediations
  )
}
