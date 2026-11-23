# High-level end-to-end reproducibility capsule orchestrator

#' Build a Complete Reproducibility Capsule for an R Project
#'
#' End-to-end orchestrator that scans an R project, compiles multi-target
#' container definitions (`Dockerfile`, `docker-compose.yml`, `Apptainer.def`),
#' statically lints every generated spec, records a cryptographically verifiable
#' `capsule.json` provenance manifest, and optionally runs an isolated
#' reproducibility verification audit and renders journal-ready certificates.
#'
#' @param path Path to the project root directory. Defaults to `"."`.
#' @param targets Character vector of container targets to compile: any subset
#'   of `c("dockerfile", "compose", "apptainer")`.
#' @param inputs Optional character vector of input data file/directory paths.
#' @param outputs Optional character vector of output artifact paths to hash
#'   and verify.
#' @param entrypoint Optional runnable entrypoint override.
#' @param seed Optional integer RNG seed.
#' @param tolerances Optional numeric tolerance configuration passed to
#'   [create_capsule_manifest()].
#' @param key Optional HMAC-SHA256 secret key for signing `capsule.json`.
#' @param write Logical; if `TRUE` (default), writes compiled container specs
#'   and `capsule.json` into `path`.
#' @param lint Logical; if `TRUE` (default), runs [lint_container_spec()] on
#'   every compiled container target.
#' @param verify Logical; if `TRUE`, executes [verify_capsule()] immediately
#'   after building the manifest. Defaults to `FALSE`.
#' @param certificate Logical; if `TRUE` (and `verify = TRUE`), renders
#'   Markdown and HTML certificates via [render_certificate()]. Defaults to
#'   `FALSE`.
#' @param runner Verification runner backend when `verify = TRUE`: `"sandbox"`
#'   (default) or `"docker"`.
#' @param custom_sysreqs Optional custom system dependency overrides forwarded
#'   to [scan_project()].
#' @param platform Optional target container platform (`"linux/amd64"`,
#'   `"linux/arm64"`, or `NULL`) forwarded to [compile_dockerfile()] and
#'   [compile_compose()].
#' @param use_ppm Logical; if `TRUE` (default), enables Posit Package Manager
#'   Linux binary repositories in [compile_dockerfile()].
#' @param metadata Optional metadata list forwarded to
#'   [create_capsule_manifest()].
#'
#' @return An S3 object of class `rcapsule_bundle` containing `scan`, `specs`,
#'   `lint`, `manifest`, `verification`, and `certificate`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_bundle_")
#' dir.create(tmp)
#' writeLines(
#'   c("write.csv(data.frame(x = 1:3, y = c(2, 4, 6)), 'out.csv', row.names = FALSE)"),
#'   file.path(tmp, "run.R")
#' )
#' write.csv(data.frame(x = 1:3, y = c(2, 4, 6)), file.path(tmp, "out.csv"), row.names = FALSE)
#' bundle <- build_capsule(tmp, outputs = "out.csv", seed = 42L, verify = TRUE, certificate = TRUE)
#' bundle$verification$status
#' unlink(tmp, recursive = TRUE)
build_capsule <- function(path = ".",
                          targets = c("dockerfile", "compose", "apptainer"),
                          inputs = NULL,
                          outputs = NULL,
                          entrypoint = NULL,
                          seed = NULL,
                          tolerances = NULL,
                          key = NULL,
                          write = TRUE,
                          lint = TRUE,
                          verify = FALSE,
                          certificate = FALSE,
                          runner = c("sandbox", "docker"),
                          custom_sysreqs = NULL,
                          platform = NULL,
                          use_ppm = TRUE,
                          metadata = list()) {
  root <- normalize_project_path(path, must_exist = TRUE)
  runner <- match.arg(runner)
  valid_targets <- c("dockerfile", "compose", "apptainer")
  targets <- unique(match.arg(targets, valid_targets, several.ok = TRUE))

  # 1. Scan project
  scan <- scan_project(root, custom_sysreqs = custom_sysreqs)

  # 2. Compile container specs
  specs <- list()
  container_paths <- character()

  if ("dockerfile" %in% targets) {
    out_p <- if (isTRUE(write)) file.path(root, "Dockerfile") else NULL
    specs$dockerfile <- compile_dockerfile(
      scan,
      output = out_p,
      entrypoint = entrypoint,
      platform = platform,
      use_ppm = use_ppm
    )
    if (!is.null(out_p)) container_paths <- c(container_paths, "Dockerfile")
  }
  if ("compose" %in% targets) {
    out_p <- if (isTRUE(write)) file.path(root, "docker-compose.yml") else NULL
    specs$compose <- compile_compose(scan, output = out_p, platform = platform)
    if (!is.null(out_p)) container_paths <- c(container_paths, "docker-compose.yml")
  }
  if ("apptainer" %in% targets) {
    out_p <- if (isTRUE(write)) file.path(root, "Apptainer.def") else NULL
    specs$apptainer <- compile_apptainer(scan, output = out_p, entrypoint = entrypoint)
    if (!is.null(out_p)) container_paths <- c(container_paths, "Apptainer.def")
  }

  # 3. Lint compiled specs
  lint_results <- list()
  if (isTRUE(lint)) {
    for (nm in names(specs)) {
      lint_results[[nm]] <- lint_container_spec(specs[[nm]])
    }
  }

  # 4. Create cryptographic manifest (capturing newly written container specs)
  manifest_out <- if (isTRUE(write)) file.path(root, "capsule.json") else NULL
  manifest <- create_capsule_manifest(
    path = root,
    scan = scan,
    inputs = inputs,
    outputs = outputs,
    containers = if (length(container_paths) > 0L) container_paths else NULL,
    entrypoint = entrypoint,
    seed = seed,
    tolerances = tolerances,
    metadata = metadata,
    key = key,
    output = manifest_out
  )

  # 5. Optional isolated verification
  verification <- NULL
  cert <- NULL
  if (isTRUE(verify)) {
    verification <- verify_capsule(
      manifest = manifest,
      path = root,
      runner = runner,
      entrypoint = entrypoint,
      seed = seed,
      key = key
    )
    if (isTRUE(certificate)) {
      cert_out <- if (isTRUE(write)) file.path(root, "capsule_certificate") else NULL
      cert <- render_certificate(verification, output = cert_out, format = "both")
    }
  }

  structure(
    list(
      scan = scan,
      specs = specs,
      lint = lint_results,
      manifest = manifest,
      verification = verification,
      certificate = cert
    ),
    class = "rcapsule_bundle"
  )
}

#' @export
print.rcapsule_bundle <- function(x, ...) {
  cli::cli_h1("rcapsule Bundle: {x$scan$project_name}")
  lint_summary <- if (length(x$lint) > 0L) {
    paste(
      vapply(names(x$lint), function(nm) {
        paste0(nm, "=", if (isTRUE(x$lint[[nm]]$passed)) "PASS" else "FAIL")
      }, character(1L)),
      collapse = ", "
    )
  } else {
    "skipped"
  }
  cli::cli_ul(c(
    "Project type: {.val {x$scan$project_type}} | Targets: {paste(names(x$specs), collapse = ', ')}",
    "Lint status: {lint_summary}",
    "Manifest ID: {.val {x$manifest$capsule_id}} (signed={x$manifest$integrity$signed})",
    "Verification: {.val {if (!is.null(x$verification)) x$verification$status else 'not run'}}",
    "Certificate: {if (!is.null(x$certificate)) 'rendered' else 'not rendered'}"
  ))
  invisible(x)
}
