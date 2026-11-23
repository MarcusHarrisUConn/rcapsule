test_that("verify_capsule achieves verified_exact in isolated local sandbox and regenerates outputs from scratch", {
  dir <- make_runnable_pipeline_fixture(seed = 77L, stochastic_mode = "deterministic")
  outs <- c("results/summary.csv", "results/summary.tsv", "results/metrics.json", "results/model.rds")

  m <- create_capsule_manifest(
    path = dir,
    inputs = "data/input.csv",
    outputs = outs,
    seed = 77L,
    key = "audit-key",
    output = file.path(dir, "capsule.json")
  )

  # Delete local outputs completely to prove sandbox genuinely regenerates them from scratch
  unlink(file.path(dir, "results"), recursive = TRUE)
  expect_false(file.exists(file.path(dir, "results", "summary.csv")))

  v <- verify_capsule(
    manifest = file.path(dir, "capsule.json"),
    path = dir,
    runner = "sandbox",
    key = "audit-key"
  )

  expect_s3_class(v, "rcapsule_verification")
  expect_true(v$passed)
  expect_equal(v$status, "verified_exact")
  expect_equal(v$exit_status, 0L)
  expect_true(all(v$output_checks$status == "exact_match"))
  expect_true(all(v$input_checks$passed))
  expect_true(all(v$script_checks$passed))
  expect_invisible(print(v))
})

test_that("verify_capsule supports numeric-tolerance verification (Monte Carlo bounds) and detects out-of-bounds drift", {
  dir <- make_runnable_pipeline_fixture(seed = 99L, stochastic_mode = "env_perturb")
  outs <- c("results/summary.csv", "results/summary.tsv", "results/metrics.json", "results/model.rds")

  m <- create_capsule_manifest(
    path = dir,
    inputs = "data/input.csv",
    outputs = outs,
    seed = 99L,
    tolerances = list(abs_tol = 1e-3, rel_tol = 1e-3),
    embed_snapshots = TRUE
  )

  # Delete on-disk outputs to verify embedded snapshot tolerance comparison works seamlessly
  unlink(file.path(dir, "results"), recursive = TRUE)

  # Small perturbation within tolerance -> verified_within_tolerance
  v_ok <- verify_capsule(
    manifest = m,
    path = dir,
    runner = "sandbox",
    env_vars = list(RCAPSULE_TEST_PERTURB = "0.0004")
  )
  expect_true(v_ok$passed)
  expect_equal(v_ok$status, "verified_within_tolerance")
  expect_true(all(v_ok$output_checks$status == "within_tolerance"))
  expect_true(all(v_ok$output_checks$max_abs_diff < 1e-3))

  # Large perturbation exceeding tolerance -> failed
  v_bad <- verify_capsule(
    manifest = m,
    path = dir,
    runner = "sandbox",
    env_vars = list(RCAPSULE_TEST_PERTURB = "0.05")
  )
  expect_false(v_bad$passed)
  expect_equal(v_bad$status, "failed")
  expect_true(all(v_bad$output_checks$status == "mismatch"))
  expect_true(length(v_bad$failure_reasons) >= 1L)
})

test_that("verify_capsule catches tampered inputs, tampered scripts, tampered manifests, and runtime errors", {
  dir <- make_runnable_pipeline_fixture(seed = 11L)
  m <- create_capsule_manifest(
    path = dir,
    inputs = "data/input.csv",
    outputs = "results/summary.csv",
    seed = 11L,
    key = "secret"
  )

  # 1. Tampered manifest fails
  m_bad <- m
  m_bad$rng$seed <- 12L
  v_m <- verify_capsule(m_bad, path = dir, key = "secret")
  expect_false(v_m$passed)
  expect_match(paste(v_m$failure_reasons, collapse = " "), "Manifest integrity failed")

  # 2. Modified input data fails input check AND output check
  write.csv(data.frame(group = c("control", "treat"), y = c(99, 100)),
            file.path(dir, "data", "input.csv"), row.names = FALSE)
  v_in <- verify_capsule(m, path = dir, key = "secret")
  expect_false(v_in$passed)
  expect_false(v_in$input_checks$passed[[1L]])
  expect_match(paste(v_in$failure_reasons, collapse = " "), "Input artifact verification failed")

  # 3. Runtime script error fails cleanly with non-zero exit status
  dir_err <- make_runnable_pipeline_fixture(seed = 11L)
  m_err <- create_capsule_manifest(path = dir_err, outputs = "results/summary.csv", seed = 11L)
  writeLines("stop('intentional failure')", file.path(dir_err, "run.R"))
  v_err <- verify_capsule(m_err, path = dir_err)
  expect_false(v_err$passed)
  expect_false(identical(v_err$exit_status, 0L))
  expect_match(paste(v_err$failure_reasons, collapse = " "), "non-zero status")
})

test_that("render_certificate produces valid journal-ready Markdown and HTML with HTML escaping", {
  dir <- make_runnable_pipeline_fixture(seed = 55L)
  m <- create_capsule_manifest(
    path = dir,
    inputs = "data/input.csv",
    outputs = c("results/summary.csv", "results/metrics.json"),
    seed = 55L,
    key = "cert-key"
  )
  v <- verify_capsule(m, path = dir, key = "cert-key")

  cert_base <- file.path(dir, "audit_cert")
  cert <- render_certificate(
    v,
    output = cert_base,
    format = "both",
    title = "Study <Alpha> & 'Beta'"
  )

  expect_s3_class(cert, "rcapsule_certificate")
  expect_true(file.exists(cert$files[["markdown"]]))
  expect_true(file.exists(cert$files[["html"]]))
  expect_invisible(print(cert))

  # Markdown assertions
  expect_match(cert$markdown, "VERIFIED \\(EXACT\\)")
  expect_match(cert$markdown, m$capsule_id, fixed = TRUE)
  expect_match(cert$markdown, "results/summary.csv", fixed = TRUE)
  expect_match(cert$markdown, "HMAC-SHA256 Verified", fixed = TRUE)

  # HTML assertions: doctype, self-contained CSS, XSS escaping of <Alpha> & 'Beta'
  expect_match(cert$html, "^<!DOCTYPE html>")
  expect_match(cert$html, "<style>", fixed = TRUE)
  expect_match(cert$html, "Study &lt;Alpha&gt; &amp;", fixed = TRUE)
  expect_false(grepl("<Alpha>", cert$html, fixed = TRUE))

  # Single-format rendering & failure certificate diagnostics
  md_only <- render_certificate(v, format = "markdown")
  expect_true(is.character(md_only$markdown))
  expect_null(md_only$html)
  html_only <- render_certificate(v, format = "html")
  expect_null(html_only$markdown)
  expect_true(is.character(html_only$html))

  m_bad <- m
  m_bad$rng$seed <- 999L
  v_fail <- verify_capsule(m_bad, path = dir, key = "cert-key")
  cert_fail <- render_certificate(v_fail, format = "both")
  expect_match(cert_fail$markdown, "Failure Diagnostics", fixed = TRUE)
  expect_match(cert_fail$html, "status-fail", fixed = TRUE)
  expect_match(cert_fail$html, "Failure Diagnostics", fixed = TRUE)
})

test_that("runtime capability checks return single logical values and docker runner fails cleanly when offline", {
  da <- docker_available()
  aa <- apptainer_available()
  expect_true(is.logical(da) && length(da) == 1L && !is.na(da))
  expect_true(is.logical(aa) && length(aa) == 1L && !is.na(aa))

  if (!da) {
    dir <- make_runnable_pipeline_fixture(seed = 7L)
    m <- create_capsule_manifest(dir, outputs = "results/summary.csv", seed = 7L)
    expect_error(verify_capsule(m, path = dir, runner = "docker"), "Docker daemon is not available")
  }
})

test_that("build_capsule orchestrates scanning, compilation, linting, manifest, verification, and certificates", {
  dir <- make_runnable_pipeline_fixture(seed = 123L)
  bundle <- build_capsule(
    path = dir,
    targets = c("dockerfile", "compose", "apptainer"),
    inputs = "data/input.csv",
    outputs = c("results/summary.csv", "results/metrics.json"),
    seed = 123L,
    key = "bundle-key",
    write = TRUE,
    lint = TRUE,
    verify = TRUE,
    certificate = TRUE,
    runner = "sandbox"
  )

  expect_s3_class(bundle, "rcapsule_bundle")
  expect_true(all(file.exists(file.path(dir, c(
    "Dockerfile", "docker-compose.yml", "Apptainer.def",
    "capsule.json", "capsule_certificate.md", "capsule_certificate.html"
  )))))
  expect_true(all(vapply(bundle$lint, function(x) isTRUE(x$passed), logical(1L))))
  expect_true(bundle$verification$passed)
  expect_equal(bundle$verification$status, "verified_exact")
  # Container definitions were hashed inside capsule.json
  expect_equal(length(bundle$manifest$artifacts$containers), 3L)
  expect_invisible(print(bundle))
})

test_that("verify_capsule live-Docker integration test (guarded)", {
  skip_on_cran()
  skip_if_not(docker_available(), "Docker daemon is not available on this host")

  # Verify docker_available() returns logical and check pre-pulled rocker image if present
  img_check <- processx::run(
    unname(Sys.which("docker")),
    args = c("image", "inspect", "rocker/r-ver:4.4.1"),
    error_on_status = FALSE
  )
  skip_if_not(identical(img_check$status, 0L), "Pre-pulled rocker/r-ver:4.4.1 image not present locally")

  dir <- withr::local_tempdir()
  writeLines("write.csv(data.frame(x = 1:3), 'out.csv', row.names = FALSE)", file.path(dir, "run.R"))
  write.csv(data.frame(x = 1:3), file.path(dir, "out.csv"), row.names = FALSE)
  m <- create_capsule_manifest(dir, outputs = "out.csv", seed = 1L)
  v <- verify_capsule(m, path = dir, runner = "docker", docker_image = "rocker/r-ver:4.4.1")
  expect_true(v$passed)
  expect_equal(v$status, "verified_exact")
})
