# Cross-run capsule provenance manifest diffing (e.g., laptop vs. HPC or reviewer vs. author)

# Helper: index manifest artifact list by path
index_artifacts_by_path <- function(records) {
  if (is.null(records) || length(records) == 0L) {
    return(list())
  }
  out <- list()
  for (rec in records) {
    if (is.list(rec) && !is.null(rec$path)) {
      out[[as.character(rec$path)]] <- rec
    }
  }
  out
}

# Helper: decode verified base64 snapshot if its SHA-256 matches the recorded digest
decode_verified_snapshot <- function(manifest, rel_path, expected_sha) {
  snap <- manifest$snapshots[[rel_path]]
  if (is.null(snap) || is.null(snap$data)) {
    return(NULL)
  }
  raw_bytes <- tryCatch(openssl::base64_decode(snap$data), error = function(e) NULL)
  if (is.null(raw_bytes)) {
    return(NULL)
  }
  if (!constant_time_equal(sha256_raw(raw_bytes), as.character(expected_sha %||% ""))) {
    return(NULL)
  }
  raw_bytes
}

# Compare one artifact category (inputs, scripts, containers, outputs) across two manifests
diff_artifact_category <- function(category, manifest_a, manifest_b, tol_spec) {
  map_a <- index_artifacts_by_path(manifest_a$artifacts[[category]])
  map_b <- index_artifacts_by_path(manifest_b$artifacts[[category]])
  all_paths <- sort(unique(c(names(map_a), names(map_b))))

  if (length(all_paths) == 0L) {
    return(tibble::tibble(
      category = character(),
      path = character(),
      status = character(),
      sha256_a = character(),
      sha256_b = character(),
      bytes_a = integer(),
      bytes_b = integer(),
      max_abs_diff = numeric(),
      max_rel_diff = numeric(),
      details = character()
    ))
  }

  rows <- lapply(all_paths, function(p) {
    ra <- map_a[[p]]
    rb <- map_b[[p]]

    if (is.null(ra)) {
      return(list(
        category = category,
        path = p,
        status = "added",
        sha256_a = NA_character_,
        sha256_b = as.character(rb$sha256 %||% NA_character_),
        bytes_a = NA_integer_,
        bytes_b = as.integer(rb$bytes %||% NA_integer_),
        max_abs_diff = NA_real_,
        max_rel_diff = NA_real_,
        details = "Artifact present only in second manifest."
      ))
    }
    if (is.null(rb)) {
      return(list(
        category = category,
        path = p,
        status = "removed",
        sha256_a = as.character(ra$sha256 %||% NA_character_),
        sha256_b = NA_character_,
        bytes_a = as.integer(ra$bytes %||% NA_integer_),
        bytes_b = NA_integer_,
        max_abs_diff = NA_real_,
        max_rel_diff = NA_real_,
        details = "Artifact missing from second manifest."
      ))
    }

    sha_a <- as.character(ra$sha256 %||% "")
    sha_b <- as.character(rb$sha256 %||% "")
    if (constant_time_equal(sha_a, sha_b)) {
      return(list(
        category = category,
        path = p,
        status = "unchanged",
        sha256_a = sha_a,
        sha256_b = sha_b,
        bytes_a = as.integer(ra$bytes %||% NA_integer_),
        bytes_b = as.integer(rb$bytes %||% NA_integer_),
        max_abs_diff = 0,
        max_rel_diff = 0,
        details = "Exact SHA-256 match."
      ))
    }

    # For outputs, attempt numeric tolerance comparison if both manifests have verified snapshots
    if (identical(category, "outputs")) {
      ftol <- tol_spec$files[[p]] %||% tol_spec$default
      abs_tol <- as.numeric(ftol$abs_tol %||% ftol$atol %||% 0)
      rel_tol <- as.numeric(ftol$rel_tol %||% ftol$rtol %||% 0)

      raw_a <- decode_verified_snapshot(manifest_a, p, sha_a)
      raw_b <- decode_verified_snapshot(manifest_b, p, sha_b)
      if (!is.null(raw_a) && !is.null(raw_b)) {
        ext <- tools::file_ext(p)
        tmp_b <- tempfile("rcapsule_diff_b_", fileext = if (nzchar(ext)) paste0(".", ext) else "")
        writeBin(raw_b, tmp_b)
        on.exit(unlink(tmp_b), add = TRUE)

        cmp <- compare_artifacts(
          expected_path = NULL,
          actual_path = tmp_b,
          expected_sha256 = sha_a,
          abs_tol = abs_tol,
          rel_tol = rel_tol,
          format = ra$format %||% "auto",
          expected_raw = raw_a
        )
        return(list(
          category = category,
          path = p,
          status = if (isTRUE(cmp$passed)) "within_tolerance" else "modified",
          sha256_a = sha_a,
          sha256_b = sha_b,
          bytes_a = as.integer(ra$bytes %||% NA_integer_),
          bytes_b = as.integer(rb$bytes %||% NA_integer_),
          max_abs_diff = as.numeric(cmp$max_abs_diff %||% NA_real_),
          max_rel_diff = as.numeric(cmp$max_rel_diff %||% NA_real_),
          details = cmp$details
        ))
      }
    }

    list(
      category = category,
      path = p,
      status = "modified",
      sha256_a = sha_a,
      sha256_b = sha_b,
      bytes_a = as.integer(ra$bytes %||% NA_integer_),
      bytes_b = as.integer(rb$bytes %||% NA_integer_),
      max_abs_diff = NA_real_,
      max_rel_diff = NA_real_,
      details = "SHA-256 hash changed."
    )
  })

  tibble::tibble(
    category = vapply(rows, `[[`, character(1L), "category"),
    path = vapply(rows, `[[`, character(1L), "path"),
    status = vapply(rows, `[[`, character(1L), "status"),
    sha256_a = vapply(rows, `[[`, character(1L), "sha256_a"),
    sha256_b = vapply(rows, `[[`, character(1L), "sha256_b"),
    bytes_a = vapply(rows, `[[`, integer(1L), "bytes_a"),
    bytes_b = vapply(rows, `[[`, integer(1L), "bytes_b"),
    max_abs_diff = vapply(rows, `[[`, numeric(1L), "max_abs_diff"),
    max_rel_diff = vapply(rows, `[[`, numeric(1L), "max_rel_diff"),
    details = vapply(rows, `[[`, character(1L), "details")
  )
}

# Compare package lists across two manifests
diff_manifest_packages <- function(pkgs_a, pkgs_b) {
  to_map <- function(lst) {
    m <- list()
    for (p in lst) {
      if (is.list(p) && !is.null(p$package)) {
        m[[as.character(p$package)]] <- as.character(p$version %||% NA_character_)
      }
    }
    m
  }
  ma <- to_map(pkgs_a %||% list())
  mb <- to_map(pkgs_b %||% list())
  all_p <- sort(unique(c(names(ma), names(mb))))

  rows <- list()
  for (pkg in all_p) {
    va <- ma[[pkg]]
    vb <- mb[[pkg]]
    if (is.null(va)) {
      rows[[length(rows) + 1L]] <- list(package = pkg, status = "added", version_a = NA_character_, version_b = vb)
    } else if (is.null(vb)) {
      rows[[length(rows) + 1L]] <- list(package = pkg, status = "removed", version_a = va, version_b = NA_character_)
    } else if (!identical(va, vb)) {
      rows[[length(rows) + 1L]] <- list(package = pkg, status = "version_changed", version_a = va, version_b = vb)
    }
  }

  if (length(rows) == 0L) {
    return(tibble::tibble(
      package = character(),
      status = character(),
      version_a = character(),
      version_b = character()
    ))
  }
  tibble::tibble(
    package = vapply(rows, `[[`, character(1L), "package"),
    status = vapply(rows, `[[`, character(1L), "status"),
    version_a = vapply(rows, `[[`, character(1L), "version_a"),
    version_b = vapply(rows, `[[`, character(1L), "version_b")
  )
}

#' Diff Two Capsule Provenance Manifests Across Runs or Machines
#'
#' Compares two `capsule.json` manifests (for example, an author's laptop run
#' versus an HPC cluster run or a journal peer reviewer's reproduction).
#' Detects R, OS, architecture, package, system library, and toolchain drift,
#' Git revision and RNG seed changes, modified/added/removed inputs, scripts,
#' container specs, and outputs, including numeric-tolerance evaluation when
#' embedded output snapshots are present.
#'
#' @param manifest_a Baseline `rcapsule_manifest` object or path to
#'   `capsule.json`.
#' @param manifest_b Comparison `rcapsule_manifest` object or path to
#'   `capsule.json`.
#' @param tolerances Optional numeric tolerance configuration overriding
#'   `manifest_a$tolerances` (accepts `abs_tol`/`atol` and `rel_tol`/`rtol`).
#' @param label_a Optional human-readable label for `manifest_a` (defaults to
#'   its `capsule_id`).
#' @param label_b Optional human-readable label for `manifest_b` (defaults to
#'   its `capsule_id`).
#'
#' @return An S3 object of class `rcapsule_diff` with fields:
#'   - `label_a`, `label_b`, `capsule_id_a`, `capsule_id_b`
#'   - `identical`: logical (`TRUE` when environment, RNG, Git, and all
#'     artifacts match bit-for-bit)
#'   - `outputs_equivalent`: logical (`TRUE` when all outputs are `"unchanged"`
#'     or `"within_tolerance"` with zero added/removed/modified outputs)
#'   - `has_env_drift`, `has_input_drift`, `has_script_drift`: logical flags
#'   - `env_diff`: list of R/OS/platform/package/sysreq/toolchain diffs
#'   - `rng_diff`: list comparing RNG seed and kind
#'   - `git_diff`: list comparing Git commit, branch, and dirty status
#'   - `artifact_diffs`: named list of tibbles (`inputs`, `scripts`,
#'     `containers`, `outputs`)
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_diff_demo_")
#' dir.create(tmp)
#' writeLines("write.csv(data.frame(x = 1:3), 'out.csv', row.names = FALSE)",
#'            file.path(tmp, "run.R"))
#' write.csv(data.frame(x = 1:3), file.path(tmp, "out.csv"), row.names = FALSE)
#' m1 <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
#' write.csv(data.frame(x = c(1.0001, 2, 3)), file.path(tmp, "out.csv"), row.names = FALSE)
#' m2 <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
#' d <- diff_capsules(m1, m2, tolerances = list(atol = 1e-3))
#' d
#' unlink(tmp, recursive = TRUE)
diff_capsules <- function(manifest_a,
                          manifest_b,
                          tolerances = NULL,
                          label_a = NULL,
                          label_b = NULL) {
  if (is.character(manifest_a) && length(manifest_a) == 1L) {
    manifest_a <- read_capsule_manifest(manifest_a)
  }
  if (is.character(manifest_b) && length(manifest_b) == 1L) {
    manifest_b <- read_capsule_manifest(manifest_b)
  }
  if (!inherits(manifest_a, "rcapsule_manifest") || !inherits(manifest_b, "rcapsule_manifest")) {
    cli::cli_abort("Both {.arg manifest_a} and {.arg manifest_b} must be {.cls rcapsule_manifest} objects or file paths.")
  }

  tol_spec <- if (!is.null(tolerances)) {
    normalize_tolerances(tolerances)
  } else {
    manifest_a$tolerances %||% normalize_tolerances(NULL)
  }

  # 1. Environment & toolchain drift
  ea <- manifest_a$environment
  eb <- manifest_b$environment
  pkg_diffs <- diff_manifest_packages(ea$packages, eb$packages)
  sr_a <- as.character(unlist(ea$sysreqs %||% character()))
  sr_b <- as.character(unlist(eb$sysreqs %||% character()))
  tc_a <- as.character(unlist(ea$toolchains %||% character()))
  tc_b <- as.character(unlist(eb$toolchains %||% character()))

  env_diff <- list(
    r_version_a = ea$r_version %||% NA_character_,
    r_version_b = eb$r_version %||% NA_character_,
    r_version_changed = !identical(ea$r_version, eb$r_version),
    platform_a = ea$platform %||% NA_character_,
    platform_b = eb$platform %||% NA_character_,
    platform_changed = !identical(ea$platform, eb$platform),
    os_a = ea$os %||% NA_character_,
    os_b = eb$os %||% NA_character_,
    os_changed = !identical(ea$os, eb$os),
    digest_changed = !constant_time_equal(
      as.character(ea$environment_digest %||% ""),
      as.character(eb$environment_digest %||% "")
    ),
    packages = pkg_diffs,
    sysreqs = list(added = sort(setdiff(sr_b, sr_a)), removed = sort(setdiff(sr_a, sr_b))),
    toolchains = list(added = sort(setdiff(tc_b, tc_a)), removed = sort(setdiff(tc_a, tc_b)))
  )
  has_env_drift <- isTRUE(env_diff$r_version_changed) ||
    isTRUE(env_diff$platform_changed) ||
    isTRUE(env_diff$os_changed) ||
    isTRUE(env_diff$digest_changed) ||
    nrow(pkg_diffs) > 0L ||
    length(env_diff$sysreqs$added) > 0L ||
    length(env_diff$sysreqs$removed) > 0L ||
    length(env_diff$toolchains$added) > 0L ||
    length(env_diff$toolchains$removed) > 0L

  # 2. RNG & Git drift
  kind_a <- as.character(unlist(manifest_a$rng$kind %||% character()))
  kind_b <- as.character(unlist(manifest_b$rng$kind %||% character()))
  rng_diff <- list(
    seed_a = manifest_a$rng$seed %||% NULL,
    seed_b = manifest_b$rng$seed %||% NULL,
    seed_changed = !identical(manifest_a$rng$seed, manifest_b$rng$seed),
    kind_a = kind_a,
    kind_b = kind_b,
    kind_changed = !identical(kind_a, kind_b)
  )

  ga <- manifest_a$project$git %||% list()
  gb <- manifest_b$project$git %||% list()
  git_diff <- list(
    commit_a = ga$commit %||% NULL,
    commit_b = gb$commit %||% NULL,
    commit_changed = !identical(ga$commit, gb$commit),
    branch_a = ga$branch %||% NULL,
    branch_b = gb$branch %||% NULL,
    branch_changed = !identical(ga$branch, gb$branch),
    dirty_a = ga$dirty %||% NULL,
    dirty_b = gb$dirty %||% NULL
  )

  # 3. Artifact category diffs
  cats <- c("inputs", "scripts", "containers", "outputs")
  artifact_diffs <- lapply(cats, diff_artifact_category,
                           manifest_a = manifest_a, manifest_b = manifest_b, tol_spec = tol_spec)
  names(artifact_diffs) <- cats

  has_input_drift <- any(artifact_diffs$inputs$status != "unchanged")
  has_script_drift <- any(artifact_diffs$scripts$status != "unchanged")
  has_container_drift <- any(artifact_diffs$containers$status != "unchanged")
  outputs_exact <- all(artifact_diffs$outputs$status == "unchanged")
  outputs_equivalent <- all(artifact_diffs$outputs$status %in% c("unchanged", "within_tolerance"))

  identical_flag <- !has_env_drift &&
    !rng_diff$seed_changed &&
    !rng_diff$kind_changed &&
    !git_diff$commit_changed &&
    !has_input_drift &&
    !has_script_drift &&
    !has_container_drift &&
    outputs_exact

  structure(
    list(
      label_a = label_a %||% manifest_a$capsule_id,
      label_b = label_b %||% manifest_b$capsule_id,
      capsule_id_a = manifest_a$capsule_id,
      capsule_id_b = manifest_b$capsule_id,
      identical = identical_flag,
      outputs_equivalent = outputs_equivalent,
      has_env_drift = has_env_drift,
      has_input_drift = has_input_drift,
      has_script_drift = has_script_drift,
      has_container_drift = has_container_drift,
      env_diff = env_diff,
      rng_diff = rng_diff,
      git_diff = git_diff,
      artifact_diffs = artifact_diffs
    ),
    class = "rcapsule_diff"
  )
}

#' @export
print.rcapsule_diff <- function(x, ...) {
  verdict <- if (isTRUE(x$identical)) {
    "IDENTICAL"
  } else if (isTRUE(x$outputs_equivalent)) {
    "OUTPUTS EQUIVALENT (DRIFT DETECTED)"
  } else {
    "OUTPUTS DIVERGED"
  }
  cli::cli_h1("rcapsule Manifest Diff: {verdict}")
  cli::cli_ul(c(
    "Baseline (A): {.val {x$label_a}} ({x$capsule_id_a})",
    "Comparison (B): {.val {x$label_b}} ({x$capsule_id_b})",
    "Environment drift: {.val {x$has_env_drift}} (R: {x$env_diff$r_version_a} -> {x$env_diff$r_version_b}; platform: {x$env_diff$platform_a} -> {x$env_diff$platform_b})",
    "RNG drift: seed={x$rng_diff$seed_a %||% 'unset'} -> {x$rng_diff$seed_b %||% 'unset'}",
    "Inputs drift: {.val {x$has_input_drift}} | Scripts drift: {.val {x$has_script_drift}} | Outputs equivalent: {.val {x$outputs_equivalent}}"
  ))

  if (nrow(x$env_diff$packages) > 0L) {
    cli::cli_h2("Package Changes ({nrow(x$env_diff$packages)})")
    for (i in seq_len(nrow(x$env_diff$packages))) {
      r <- x$env_diff$packages[i, ]
      cli::cli_alert_info("{r$package}: {r$status} ({r$version_a %||% 'none'} -> {r$version_b %||% 'none'})")
    }
  }

  for (cat_nm in c("inputs", "scripts", "containers", "outputs")) {
    tbl <- x$artifact_diffs[[cat_nm]]
    changed <- tbl[tbl$status != "unchanged", , drop = FALSE]
    if (nrow(changed) > 0L) {
      cli::cli_h2("Changed {cat_nm} ({nrow(changed)}/{nrow(tbl)})")
      for (i in seq_len(nrow(changed))) {
        r <- changed[i, ]
        msg <- paste0(r$path, " [", r$status, "] - ", r$details)
        if (r$status == "within_tolerance") {
          cli::cli_alert_warning(msg)
        } else {
          cli::cli_alert_danger(msg)
        }
      }
    }
  }
  invisible(x)
}

#' @export
summary.rcapsule_diff <- function(object, ...) {
  count_changed <- function(tbl) sum(tbl$status != "unchanged")
  list(
    identical = object$identical,
    outputs_equivalent = object$outputs_equivalent,
    has_env_drift = object$has_env_drift,
    n_package_changes = nrow(object$env_diff$packages),
    n_input_changes = count_changed(object$artifact_diffs$inputs),
    n_script_changes = count_changed(object$artifact_diffs$scripts),
    n_container_changes = count_changed(object$artifact_diffs$containers),
    n_output_changes = count_changed(object$artifact_diffs$outputs),
    n_outputs_within_tolerance = sum(object$artifact_diffs$outputs$status == "within_tolerance")
  )
}
