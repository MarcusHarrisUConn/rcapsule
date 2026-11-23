#' rcapsule: Reproducibility Capsules and Multi-Target Containerization for R
#'
#' Full-stack computational reproducibility compiler and verifier for R
#' analysis repositories, Quarto manuscripts, R Markdown reports, R packages,
#' `targets` pipelines, and Shiny applications.
#'
#' @section Main Workflows:
#' - **Scan projects**: [scan_project()], [sysreqs_db()], [resolve_sysreqs()]
#' - **Compile & lint containers**: [compile_dockerfile()],
#'   [compile_compose()], [compile_apptainer()], [lint_container_spec()]
#' - **Cryptographic manifests & diffing**: [create_capsule_manifest()],
#'   [read_capsule_manifest()], [write_capsule_manifest()], [sign_manifest()],
#'   [verify_manifest_integrity()], [diff_capsules()]
#' - **Isolated verification & publishing**: [verify_capsule()],
#'   [compare_artifacts()], [render_certificate()], [export_capsule_bundle()],
#'   [build_capsule()]
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang %||%
## usethis namespace: end
NULL
