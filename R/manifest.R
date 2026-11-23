# Cryptographic provenance manifest (capsule.json v1.0.0)

# Ensure a named map serializes as JSON object {} even when empty
as_json_map <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(structure(list(), names = character()))
  }
  x
}

# Ensure a vector/list serializes as JSON array [] even when length 0 or 1
as_json_array <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(list())
  }
  unname(as.list(x))
}

# Hash a vector of project-relative or absolute paths into sorted artifact records
hash_artifact_paths <- function(paths, root) {
  if (is.null(paths) || length(paths) == 0L) {
    return(list())
  }
  resolved <- vapply(paths, function(p) {
    if (fs::is_absolute_path(p)) as.character(fs::path_norm(p)) else as.character(fs::path_norm(file.path(root, p)))
  }, character(1L), USE.NAMES = FALSE)

  # Expand any directories recursively into files
  expanded <- character()
  for (rp in resolved) {
    if (fs::dir_exists(rp)) {
      subfiles <- as.character(fs::dir_ls(rp, recurse = TRUE, type = "file"))
      expanded <- c(expanded, subfiles)
    } else if (fs::file_exists(rp)) {
      expanded <- c(expanded, rp)
    } else {
      cli::cli_abort("Artifact path does not exist: {.path {rp}}.")
    }
  }
  expanded <- unique(expanded)
  if (length(expanded) == 0L) {
    return(list())
  }

  rels <- rel_path(expanded, root)
  ord <- order(rels)
  expanded <- expanded[ord]
  rels <- rels[ord]

  records <- lapply(seq_along(expanded), function(i) {
    fp <- expanded[[i]]
    list(
      path = rels[[i]],
      sha256 = sha256_file(fp),
      bytes = as.integer(fs::file_size(fp)),
      format = detect_artifact_format(rels[[i]])
    )
  })
  unname(records)
}

# Normalize tolerance specification into canonical list(default = ..., files = ...)
normalize_tolerances <- function(tolerances = NULL) {
  default_tol <- list(abs_tol = 0, rel_tol = 0)
  file_tols <- as_json_map(list())

  if (is.null(tolerances)) {
    return(list(default = default_tol, files = file_tols))
  }
  if (!is.list(tolerances)) {
    cli::cli_abort("{.arg tolerances} must be a list (e.g., `list(abs_tol = 1e-4, rel_tol = 1e-3)` or `list(default = ..., files = ...)`).")
  }

  if (!is.null(tolerances$default) || !is.null(tolerances$files)) {
    if (!is.null(tolerances$default)) {
      default_tol$abs_tol <- as.numeric(tolerances$default$abs_tol %||% 0)
      default_tol$rel_tol <- as.numeric(tolerances$default$rel_tol %||% 0)
    }
    if (!is.null(tolerances$files) && length(tolerances$files) > 0L) {
      ft <- list()
      for (nm in sort(names(tolerances$files))) {
        entry <- tolerances$files[[nm]]
        ft[[nm]] <- list(
          abs_tol = as.numeric(entry$abs_tol %||% default_tol$abs_tol),
          rel_tol = as.numeric(entry$rel_tol %||% default_tol$rel_tol)
        )
      }
      file_tols <- ft
    }
  } else {
    # Shorthand: list(abs_tol = ..., rel_tol = ...)
    default_tol$abs_tol <- as.numeric(tolerances$abs_tol %||% 0)
    default_tol$rel_tol <- as.numeric(tolerances$rel_tol %||% 0)
  }

  list(default = default_tol, files = as_json_map(file_tols))
}

# Extract the manifest body (everything except the integrity envelope)
manifest_body <- function(manifest) {
  body <- unclass(manifest)
  body$integrity <- NULL
  body
}

# Compute deterministic canonical JSON of a manifest body
manifest_canonical_body_json <- function(manifest) {
  body <- manifest_body(manifest)
  # Round-trip canonicalize through JSON to guarantee identical hashing in-memory and after disk IO
  j1 <- to_canonical_json(body)
  parsed <- jsonlite::fromJSON(j1, simplifyVector = FALSE)
  to_canonical_json(parsed)
}

#' Create a Cryptographic Provenance Manifest (`capsule.json`)
#'
#' Records a complete, tamper-evident provenance manifest for a computational R
#' project. Captures schema version, Git commit/branch/dirty state, R/OS/locale
#' metadata, resolved R packages, OS system dependencies, detected scientific
#' toolchains, RNG kind and seed, SHA-256 hashes of inputs, scripts, container
#' definitions, and output artifacts, numeric tolerance policies, and optional
#' embedded reference snapshots. Computes a canonical SHA-256 `content_digest`
#' and an optional keyed HMAC-SHA256 signature via `openssl`.
#'
#' @param path Path to the project root directory. Defaults to `"."`.
#' @param scan Optional pre-computed `rcapsule_scan` object. If `NULL`, calls
#'   [scan_project()] on `path`.
#' @param inputs Optional character vector of input data file or directory paths
#'   (relative to `path` or absolute).
#' @param scripts Optional character vector of script/source paths. If `NULL`,
#'   automatically discovers R scripts, Quarto/Rmd documents, `DESCRIPTION`,
#'   `renv.lock`, `_quarto.yml`, `.stan`, `.py`, and `requirements.txt`.
#' @param outputs Optional character vector of generated output artifact paths
#'   (files or directories) to record and verify.
#' @param containers Optional character vector of container specification paths.
#'   If `NULL`, automatically includes any `Dockerfile`, `docker-compose.yml`,
#'   and `*.def` files present at the project root.
#' @param entrypoint Optional runnable entrypoint override (defaults to
#'   `scan$entrypoint`).
#' @param seed Optional integer RNG seed to record and enforce during
#'   verification. If `NULL`, uses the first statically detected `set.seed()`
#'   literal if present, or `NULL`.
#' @param rng_kind Optional character vector of length 3 from [base::RNGkind()].
#'   Defaults to the current session's `RNGkind()`.
#' @param tolerances Optional tolerance configuration: either shorthand
#'   `list(abs_tol = 1e-4, rel_tol = 1e-3)` or structured
#'   `list(default = list(abs_tol = 0, rel_tol = 0), files = list("out.csv" = list(abs_tol = 1e-3)))`.
#' @param metadata Optional named list of extra publication metadata (e.g.,
#'   `title`, `authors`, `journal`, `doi`).
#' @param embed_snapshots Logical; if `TRUE`, embeds base64-encoded snapshots
#'   of small (`<= max_snapshot_bytes`) tabular/JSON/RDS outputs inside the
#'   manifest so numeric-tolerance verification can run even when original
#'   output files are absent from disk. Defaults to `TRUE`.
#' @param max_snapshot_bytes Maximum size in bytes of an individual output file
#'   eligible for embedded snapshotting. Defaults to `262144L` (256 KiB).
#' @param key Optional secret key string for signing the manifest with
#'   HMAC-SHA256.
#' @param output Optional file path to write `capsule.json`. If `NULL`, returns
#'   the manifest object in memory.
#'
#' @return An S3 object of class `rcapsule_manifest`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_manifest_")
#' dir.create(tmp)
#' writeLines("write.csv(data.frame(x = 1:3), 'out.csv', row.names = FALSE)",
#'            file.path(tmp, "run.R"))
#' write.csv(data.frame(x = 1:3), file.path(tmp, "out.csv"), row.names = FALSE)
#' m <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 42L)
#' verify_manifest_integrity(m)
#' unlink(tmp, recursive = TRUE)
create_capsule_manifest <- function(path = ".",
                                    scan = NULL,
                                    inputs = NULL,
                                    scripts = NULL,
                                    outputs = NULL,
                                    containers = NULL,
                                    entrypoint = NULL,
                                    seed = NULL,
                                    rng_kind = RNGkind(),
                                    tolerances = NULL,
                                    metadata = list(),
                                    embed_snapshots = TRUE,
                                    max_snapshot_bytes = 262144L,
                                    key = NULL,
                                    output = NULL) {
  root <- normalize_project_path(path, must_exist = TRUE)
  sc <- if (is.null(scan)) scan_project(root) else as_rcapsule_scan(scan)

  # Resolve output relative paths first so auto-discovered scripts/inputs exclude outputs
  output_records <- hash_artifact_paths(outputs, root)
  output_rels <- vapply(output_records, `[[`, character(1L), "path")

  # Auto-discover container definitions if not explicitly supplied
  if (is.null(containers)) {
    cand_cont <- sc$files$path[
      grepl("(^|/)Dockerfile(\\..+)?$", sc$files$path) |
        grepl("(^|/)docker-compose(\\.[^.]+)?\\.ya?ml$", sc$files$path, ignore.case = TRUE) |
        grepl("\\.def$", sc$files$path, ignore.case = TRUE)
    ]
    cand_cont <- setdiff(cand_cont, output_rels)
    containers <- cand_cont
  }
  container_records <- hash_artifact_paths(containers, root)
  container_rels <- vapply(container_records, `[[`, character(1L), "path")

  # Auto-discover scripts & project config if not explicitly supplied
  if (is.null(scripts)) {
    script_mask <- grepl("\\.(r|qmd|rmd|stan|jags|bug|py|cpp|cc|c|h|hpp|f90|tex)$", sc$files$path, ignore.case = TRUE) |
      basename(sc$files$path) %in% c("DESCRIPTION", "NAMESPACE", "renv.lock", "_quarto.yml", "_quarto.yaml", "requirements.txt", "pyproject.toml")
    cand_scripts <- sc$files$path[script_mask]
    cand_scripts <- setdiff(cand_scripts, c(output_rels, container_rels))
    # Exclude renv internal activation files
    cand_scripts <- cand_scripts[!grepl("^renv/", cand_scripts)]
    scripts <- cand_scripts
  }
  script_records <- hash_artifact_paths(scripts, root)
  input_records <- hash_artifact_paths(inputs, root)

  # Embed optional compact snapshots for numeric-tolerance outputs
  snapshots <- list()
  if (isTRUE(embed_snapshots) && length(output_records) > 0L) {
    for (rec in output_records) {
      if (rec$format %in% c("csv", "tsv", "json", "rds") && rec$bytes <= max_snapshot_bytes) {
        fp <- file.path(root, rec$path)
        raw_bytes <- readBin(fp, what = "raw", n = rec$bytes)
        snapshots[[rec$path]] <- list(
          encoding = "base64",
          format = rec$format,
          bytes = rec$bytes,
          sha256 = rec$sha256,
          data = openssl::base64_encode(raw_bytes)
        )
      }
    }
  }

  # Environment snapshot
  non_base <- sc$packages[!sc$packages$is_base & sc$packages$required, , drop = FALSE]
  pkg_records <- if (nrow(non_base) > 0L) {
    unname(lapply(seq_len(nrow(non_base)), function(i) {
      list(
        package = non_base$package[[i]],
        version = if (is.na(non_base$version[[i]])) NULL else non_base$version[[i]],
        source = non_base$source[[i]]
      )
    }))
  } else {
    list()
  }

  build_sysreqs <- sort(unique(sc$sysreqs$apt_package[sc$sysreqs$stage == "build"]))
  active_tcs <- sort(names(sc$toolchains)[vapply(sc$toolchains, function(t) isTRUE(t$detected), logical(1L))])

  env_core <- list(
    r_version = sc$r_version,
    platform = R.version$platform,
    os = paste(Sys.info()[["sysname"]], Sys.info()[["release"]]),
    locale = Sys.getlocale("LC_CTYPE"),
    packages = pkg_records,
    sysreqs = as_json_array(build_sysreqs),
    toolchains = as_json_array(active_tcs)
  )
  env_core$environment_digest <- sha256_string(to_canonical_json(env_core))

  eff_seed <- if (!is.null(seed)) {
    as.integer(seed)
  } else if (length(sc$seeds_detected) > 0L) {
    as.integer(sc$seeds_detected[[1L]])
  } else {
    NULL
  }

  eff_ep <- entrypoint %||% sc$entrypoint
  tol_spec <- normalize_tolerances(tolerances)

  body <- list(
    schema_version = "1.0.0",
    rcapsule_version = as.character(utils::packageVersion("rcapsule")),
    created_at = utc_now_iso(),
    project = list(
      name = sc$project_name,
      type = sc$project_type,
      entrypoint = eff_ep,
      git = list(
        is_repo = isTRUE(sc$git$is_repo),
        commit = sc$git$commit,
        branch = sc$git$branch,
        dirty = if (is.na(sc$git$dirty)) NULL else isTRUE(sc$git$dirty),
        remote = sc$git$remote
      )
    ),
    environment = env_core,
    rng = list(
      seed = eff_seed,
      kind = as_json_array(as.character(rng_kind))
    ),
    artifacts = list(
      inputs = input_records,
      scripts = script_records,
      containers = container_records,
      outputs = output_records
    ),
    tolerances = tol_spec,
    snapshots = as_json_map(snapshots),
    metadata = as_json_map(metadata)
  )

  # Deterministic capsule_id derived from core content (project + env + artifacts)
  id_hash <- sha256_string(to_canonical_json(list(
    project = body$project$name,
    env = body$environment$environment_digest,
    artifacts = body$artifacts,
    created_at = body$created_at
  )))
  body <- c(
    list(
      schema_version = body$schema_version,
      rcapsule_version = body$rcapsule_version,
      capsule_id = paste0("cap_", substr(id_hash, 1L, 12L)),
      created_at = body$created_at
    ),
    body[setdiff(names(body), c("schema_version", "rcapsule_version", "created_at"))]
  )

  # Round-trip normalize body for canonical consistency
  canonical_json <- to_canonical_json(jsonlite::fromJSON(to_canonical_json(body), simplifyVector = FALSE))
  content_digest <- sha256_string(canonical_json)

  signed <- !is.null(key) && nzchar(key)
  sig <- if (signed) hmac_sha256(canonical_json, key) else NULL

  manifest <- c(
    body,
    list(
      integrity = list(
        algorithm = "sha256",
        signature_algorithm = if (signed) "hmac-sha256" else NULL,
        content_digest = content_digest,
        signed = signed,
        signature = sig
      )
    )
  )
  class(manifest) <- "rcapsule_manifest"

  if (!is.null(output)) {
    write_capsule_manifest(manifest, output)
  }

  manifest
}

#' Write a Capsule Manifest to `capsule.json`
#'
#' Serializes an `rcapsule_manifest` object as deterministic pretty-printed
#' JSON.
#'
#' @param manifest An `rcapsule_manifest` object.
#' @param path Output file path. Defaults to `"capsule.json"`.
#'
#' @return Invisibly returns the normalized output file path.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_wm_")
#' dir.create(tmp)
#' writeLines("x <- 1", file.path(tmp, "run.R"))
#' m <- create_capsule_manifest(tmp)
#' out <- write_capsule_manifest(m, file.path(tmp, "capsule.json"))
#' file.exists(out)
#' unlink(tmp, recursive = TRUE)
write_capsule_manifest <- function(manifest, path = "capsule.json") {
  if (!inherits(manifest, "rcapsule_manifest")) {
    cli::cli_abort("{.arg manifest} must be an {.cls rcapsule_manifest} object.")
  }
  fs::dir_create(fs::path_dir(path))
  json_str <- to_pretty_json(unclass(manifest))
  writeLines(json_str, path, useBytes = TRUE)
  invisible(as.character(fs::path_norm(path)))
}

#' Read a Capsule Manifest from `capsule.json`
#'
#' Reads and validates the structure of a serialized `capsule.json` manifest.
#'
#' @param path Path to a `capsule.json` file.
#'
#' @return An S3 object of class `rcapsule_manifest`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_rm_")
#' dir.create(tmp)
#' writeLines("x <- 1", file.path(tmp, "run.R"))
#' m <- create_capsule_manifest(tmp, output = file.path(tmp, "capsule.json"))
#' m2 <- read_capsule_manifest(file.path(tmp, "capsule.json"))
#' m2$capsule_id == m$capsule_id
#' unlink(tmp, recursive = TRUE)
read_capsule_manifest <- function(path = "capsule.json") {
  if (!is.character(path) || length(path) != 1L || !fs::file_exists(path)) {
    cli::cli_abort("Manifest file does not exist: {.path {path}}.")
  }
  obj <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) {
      cli::cli_abort("Failed to parse JSON manifest {.path {path}}: {conditionMessage(e)}")
    }
  )
  required_fields <- c("schema_version", "capsule_id", "project", "environment", "artifacts", "integrity")
  missing <- setdiff(required_fields, names(obj))
  if (length(missing) > 0L) {
    cli::cli_abort("Invalid capsule manifest; missing required field(s): {.val {missing}}.")
  }
  class(obj) <- "rcapsule_manifest"
  obj
}

#' Sign a Capsule Manifest with HMAC-SHA256
#'
#' Computes a canonical content digest and signs the manifest using a keyed
#' HMAC-SHA256 signature via `openssl::sha256()`.
#'
#' @param manifest An `rcapsule_manifest` object.
#' @param key Non-empty character string secret signing key.
#'
#' @return Updated `rcapsule_manifest` object with populated `integrity$signature`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_sign_")
#' dir.create(tmp)
#' writeLines("x <- 1", file.path(tmp, "run.R"))
#' m <- create_capsule_manifest(tmp)
#' m_signed <- sign_manifest(m, key = "demo-secret-key")
#' verify_manifest_integrity(m_signed, key = "demo-secret-key")$valid
#' unlink(tmp, recursive = TRUE)
sign_manifest <- function(manifest, key) {
  if (!inherits(manifest, "rcapsule_manifest")) {
    cli::cli_abort("{.arg manifest} must be an {.cls rcapsule_manifest} object.")
  }
  canonical_json <- manifest_canonical_body_json(manifest)
  content_digest <- sha256_string(canonical_json)
  sig <- hmac_sha256(canonical_json, key)

  manifest$integrity <- list(
    algorithm = "sha256",
    signature_algorithm = "hmac-sha256",
    content_digest = content_digest,
    signed = TRUE,
    signature = sig
  )
  class(manifest) <- "rcapsule_manifest"
  manifest
}

#' Verify Cryptographic Integrity and Signature of a Capsule Manifest
#'
#' Recomputes the canonical SHA-256 `content_digest` over the manifest body to
#' detect any tampering with project metadata, environment specifications, RNG
#' seeds, artifact hashes, or tolerances. If the manifest is signed or a `key`
#' is supplied, also verifies the HMAC-SHA256 signature using constant-time
#' comparison.
#'
#' @param manifest An `rcapsule_manifest` object or path to a `capsule.json`
#'   file.
#' @param key Optional secret signing key for verifying HMAC-SHA256 signatures.
#'
#' @return An S3 object of class `rcapsule_integrity` with fields:
#'   - `valid`: logical (`TRUE` only if both content digest and signature checks pass)
#'   - `content_valid`: logical
#'   - `signed`: logical (whether the manifest carries a signature)
#'   - `signature_valid`: logical or `NA` (when unsigned and no `key` given)
#'   - `recorded_digest`, `computed_digest`: SHA-256 hex strings
#'   - `issues`: character vector describing any integrity failures
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_int_")
#' dir.create(tmp)
#' writeLines("x <- 1", file.path(tmp, "run.R"))
#' m <- create_capsule_manifest(tmp, key = "secret")
#' verify_manifest_integrity(m, key = "secret")
#' unlink(tmp, recursive = TRUE)
verify_manifest_integrity <- function(manifest, key = NULL) {
  if (is.character(manifest) && length(manifest) == 1L) {
    manifest <- read_capsule_manifest(manifest)
  }
  if (!inherits(manifest, "rcapsule_manifest")) {
    cli::cli_abort("{.arg manifest} must be an {.cls rcapsule_manifest} or file path.")
  }

  issues <- character()
  canonical_json <- manifest_canonical_body_json(manifest)
  computed_digest <- sha256_string(canonical_json)
  recorded_digest <- manifest$integrity$content_digest %||% ""

  content_valid <- constant_time_equal(recorded_digest, computed_digest)
  if (!content_valid) {
    issues <- c(
      issues,
      paste0(
        "Content digest mismatch (manifest was modified): recorded=",
        substr(recorded_digest, 1L, 12L), ", computed=", substr(computed_digest, 1L, 12L)
      )
    )
  }

  signed <- isTRUE(manifest$integrity$signed) && !is.null(manifest$integrity$signature)
  sig_valid <- NA

  if (signed) {
    if (is.null(key) || !nzchar(key)) {
      sig_valid <- NA
      issues <- c(issues, "Manifest is HMAC-signed but no verification key was supplied.")
    } else {
      expected_sig <- hmac_sha256(canonical_json, key)
      sig_valid <- constant_time_equal(as.character(manifest$integrity$signature), expected_sig)
      if (!sig_valid) {
        issues <- c(issues, "HMAC-SHA256 signature verification failed (invalid key or tampered manifest).")
      }
    }
  } else if (!is.null(key) && nzchar(key)) {
    sig_valid <- FALSE
    issues <- c(issues, "Verification key was supplied, but manifest is unsigned.")
  }

  valid <- isTRUE(content_valid) && (isTRUE(sig_valid) || (!signed && is.null(key)))

  structure(
    list(
      valid = valid,
      content_valid = content_valid,
      signed = signed,
      signature_valid = sig_valid,
      recorded_digest = recorded_digest,
      computed_digest = computed_digest,
      issues = issues
    ),
    class = "rcapsule_integrity"
  )
}

#' @export
print.rcapsule_manifest <- function(x, ...) {
  cli::cli_h1("rcapsule Provenance Manifest ({x$capsule_id})")
  cli::cli_ul(c(
    "Schema: {.val {x$schema_version}} | Created: {.val {x$created_at}}",
    "Project: {.val {x$project$name}} ({x$project$type}) | Entrypoint: {.val {x$project$entrypoint %||% '<none>'}}",
    "Git: {if (isTRUE(x$project$git$is_repo)) paste0(substr(x$project$git$commit %||% 'unknown', 1, 7), ' (', x$project$git$branch %||% 'detached', ', dirty=', x$project$git$dirty, ')') else 'not a git repository'}",
    "Environment: R {x$environment$r_version} | Digest: {.val {substr(x$environment$environment_digest, 1, 12)}}",
    "RNG: seed={.val {x$rng$seed %||% 'unset'}} | kind={paste(unlist(x$rng$kind), collapse = '/')}",
    "Artifacts: {length(x$artifacts$inputs)} inputs, {length(x$artifacts$scripts)} scripts, {length(x$artifacts$containers)} containers, {length(x$artifacts$outputs)} outputs",
    "Integrity: digest={.val {substr(x$integrity$content_digest, 1, 12)}} | signed={.val {isTRUE(x$integrity$signed)}}"
  ))
  invisible(x)
}

#' @export
print.rcapsule_integrity <- function(x, ...) {
  lbl <- if (isTRUE(x$valid)) "VALID" else "INVALID"
  cli::cli_h1("rcapsule Manifest Integrity: {lbl}")
  cli::cli_ul(c(
    "Content digest: {if (isTRUE(x$content_valid)) 'OK' else 'MISMATCH'} ({substr(x$computed_digest, 1, 12)})",
    "Signed: {.val {x$signed}} | Signature check: {.val {if (is.na(x$signature_valid)) 'not verified' else x$signature_valid}}"
  ))
  if (length(x$issues) > 0L) {
    for (iss in x$issues) cli::cli_alert_danger(iss)
  }
  invisible(x)
}
