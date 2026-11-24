# Regression tests for covr-identified latent bugs and high-coverage edge branches

test_that("compare_r_objects fixes factor-vs-integer false positive and duplicate/partially-named list bugs", {
  tmp <- withr::local_tempdir()

  # Bug 1 regression: factor("1") vs integer 1L must NEVER match (both have typeof == "integer")
  f_fac <- file.path(tmp, "fac.rds")
  f_int <- file.path(tmp, "int.rds")
  saveRDS(factor("1"), f_fac)
  saveRDS(1L, f_int)
  r_fi <- compare_artifacts(f_fac, f_int, abs_tol = 1e-2)
  expect_false(r_fi$passed)
  expect_match(r_fi$details, "type/class mismatch")

  # Factor vs integer inside a data.frame column must also fail
  df_fac <- file.path(tmp, "df_fac.rds")
  df_int <- file.path(tmp, "df_int.rds")
  saveRDS(data.frame(k = factor("1"), v = 1.0), df_fac)
  saveRDS(data.frame(k = 1L, v = 1.0), df_int)
  expect_false(compare_artifacts(df_fac, df_int, abs_tol = 1e-2)$passed)

  # Character vs numeric inside a data.frame column must also fail
  df_chr <- file.path(tmp, "df_chr.rds")
  saveRDS(data.frame(k = "1", v = 1.0, stringsAsFactors = FALSE), df_chr)
  expect_false(compare_artifacts(df_chr, df_int, abs_tol = 1e-2)$passed)

  # Bug 2 regression: duplicate list keys must compare ALL elements positionally, not just first key
  l_dup1 <- file.path(tmp, "dup1.rds")
  l_dup2 <- file.path(tmp, "dup2.rds")
  l_dup3 <- file.path(tmp, "dup3.rds")
  saveRDS(list(x = 1.0, x = 2.0), l_dup1)
  saveRDS(list(x = 1.0, x = 99.0), l_dup2)
  saveRDS(list(x = 1.0, x = 2.0001), l_dup3)
  expect_false(compare_artifacts(l_dup1, l_dup2, abs_tol = 1e-2)$passed)
  expect_true(compare_artifacts(l_dup1, l_dup3, abs_tol = 1e-2)$passed)

  # Partially-named lists must compare unnamed elements too
  l_part1 <- file.path(tmp, "part1.rds")
  l_part2 <- file.path(tmp, "part2.rds")
  l_part3 <- file.path(tmp, "part3.rds")
  saveRDS(list(a = 1.0, 10.0), l_part1)
  saveRDS(list(a = 1.0, 50.0), l_part2)
  saveRDS(list(a = 1.0, b = 10.0), l_part3)
  expect_false(compare_artifacts(l_part1, l_part2, abs_tol = 1e-2)$passed)
  expect_false(compare_artifacts(l_part1, l_part3, abs_tol = 1e-2)$passed)

  # Additional comparator edge branches: Dates, POSIXct, empty vectors, positional lists, NULL mismatch, column order, dimnames, bad formats
  d1 <- file.path(tmp, "d1.rds")
  d2 <- file.path(tmp, "d2.rds")
  saveRDS(list(dt = as.Date("2026-01-01"), ts = as.POSIXct("2026-01-01 00:00:00", tz = "UTC"), empty = numeric(0), pos = list(1, 2)), d1)
  saveRDS(list(dt = as.Date("2026-01-01"), ts = as.POSIXct("2026-01-01 00:00:00", tz = "UTC"), empty = numeric(0), pos = list(1.0001, 2)), d2)
  expect_true(compare_artifacts(d1, d2, abs_tol = 1e-2)$passed)

  # NULL vs non-NULL, column order mismatch, dimnames mismatch, numeric length mismatch, atomic length mismatch, parse error
  saveRDS(list(a = NULL), file.path(tmp, "n1.rds"))
  saveRDS(list(a = 1), file.path(tmp, "n2.rds"))
  expect_match(compare_artifacts(file.path(tmp, "n1.rds"), file.path(tmp, "n2.rds"), abs_tol = 1)$details, "NULL")

  saveRDS(data.frame(a = 1, b = 2), file.path(tmp, "co1.rds"))
  saveRDS(data.frame(b = 2, a = 1), file.path(tmp, "co2.rds"))
  expect_match(compare_artifacts(file.path(tmp, "co1.rds"), file.path(tmp, "co2.rds"), abs_tol = 1)$details, "column order")

  m1 <- matrix(1:4, 2, 2, dimnames = list(c("r1", "r2"), c("c1", "c2")))
  m2 <- matrix(1:4, 2, 2, dimnames = list(c("x1", "x2"), c("c1", "c2")))
  saveRDS(m1, file.path(tmp, "dm1.rds"))
  saveRDS(m2, file.path(tmp, "dm2.rds"))
  expect_match(compare_artifacts(file.path(tmp, "dm1.rds"), file.path(tmp, "dm2.rds"), abs_tol = 1)$details, "dimnames")

  saveRDS(c(1, Inf), file.path(tmp, "if1.rds"))
  saveRDS(c(1, 2), file.path(tmp, "if2.rds"))
  expect_match(compare_artifacts(file.path(tmp, "if1.rds"), file.path(tmp, "if2.rds"), abs_tol = 1)$details, "infinite vs finite")

  saveRDS(list(1, 2), file.path(tmp, "pl1.rds"))
  saveRDS(list(1, 2, 3), file.path(tmp, "pl2.rds"))
  expect_match(compare_artifacts(file.path(tmp, "pl1.rds"), file.path(tmp, "pl2.rds"), abs_tol = 1)$details, "list length")

  saveRDS(c("a", "b"), file.path(tmp, "al1.rds"))
  saveRDS(c("a"), file.path(tmp, "al2.rds"))
  expect_match(compare_artifacts(file.path(tmp, "al1.rds"), file.path(tmp, "al2.rds"), abs_tol = 1)$details, "length mismatch")

  bad_json <- file.path(tmp, "bad.json")
  good_json <- file.path(tmp, "good.json")
  writeLines("{not valid json", bad_json)
  writeLines('{"a": 1}', good_json)
  expect_match(compare_artifacts(good_json, bad_json, abs_tol = 1)$details, "Failed to parse")
  expect_error(compare_artifacts(good_json, good_json, rtol = -0.1), "non-negative")
  expect_match(compare_artifacts(expected_path = NULL, actual_path = good_json, expected_sha256 = strrep("0", 64), abs_tol = 1)$details, "no reference artifact")
})

test_that("assert_confined_path fixes macOS symlinked-root missing-file error and catches dangling symlink ancestors", {
  tmp <- withr::local_tempdir()
  # Bug 3 regression: non-existent absolute path inside tmp (which may live under /var -> /private/var on macOS)
  # must report missing artifact, NOT a false security escape error
  missing_abs <- file.path(tmp, "does_not_exist.csv")
  expect_error(
    rcapsule:::assert_confined_path(missing_abs, root = tmp, must_exist = TRUE),
    "Artifact path does not exist"
  )

  # Outside absolute path still gives security rejection
  outside_abs <- file.path(dirname(tmp), "outside_nonexistent_file.csv")
  expect_error(
    rcapsule:::assert_confined_path(outside_abs, root = tmp, must_exist = TRUE),
    "outside project root"
  )

  # Dangling symlink pointing outside root is rejected even for child path under it
  dangling_link <- file.path(tmp, "bad_dir_link")
  ok_link <- tryCatch({
    fs::link_create("/nonexistent_outside_rcapsule_target", dangling_link)
    TRUE
  }, error = function(e) FALSE)
  if (isTRUE(ok_link)) {
    expect_error(
      rcapsule:::assert_confined_path(file.path("bad_dir_link", "child.csv"), root = tmp, must_exist = FALSE),
      "escapes project root"
    )
  }

  # Security validator edge checks
  expect_error(rcapsule:::validate_env_vars(list("123BAD" = "val")), "Invalid environment variable")
  expect_error(rcapsule:::validate_env_vars(list("OK_VAR" = "bad\nline")), "control")
  expect_error(rcapsule:::validate_container_workdir("relative/dir"), "Invalid or unsafe container path")
  expect_error(rcapsule:::validate_cran_repo_url("ftp://example.com"), "Invalid or unsafe repository URL")
  expect_error(rcapsule:::validate_version_string("4.4.0; rm -rf /"), "Invalid")
  expect_false(rcapsule:::constant_time_equal("abc", NA_character_))
  expect_false(rcapsule:::constant_time_equal("abc", "abcd"))
})

test_that("verify runner bootstrap, Docker arg builder, and mocked run_in_docker branches are fully covered", {
  tmp <- withr::local_tempdir()

  # Bootstrap generation for _targets.R, .qmd, .Rmd, and unsupported extensions
  writeLines("list()", file.path(tmp, "_targets.R"))
  p_tar <- rcapsule:::write_runner_bootstrap(tmp, "_targets.R", seed = 10L, rng_kind = RNGkind())
  expect_true(any(grepl("targets::tar_make", readLines(p_tar), fixed = TRUE)))

  writeLines("---\ntitle: t\n---", file.path(tmp, "doc.qmd"))
  p_qmd <- rcapsule:::write_runner_bootstrap(tmp, "doc.qmd", seed = NULL, rng_kind = "short")
  expect_true(any(grepl("quarto::quarto_render", readLines(p_qmd), fixed = TRUE)))

  writeLines("---\ntitle: t\n---", file.path(tmp, "doc.Rmd"))
  p_rmd <- rcapsule:::write_runner_bootstrap(tmp, "doc.Rmd", seed = 5L, rng_kind = RNGkind())
  expect_true(any(grepl("rmarkdown::render", readLines(p_rmd), fixed = TRUE)))

  writeLines("hi", file.path(tmp, "notes.txt"))
  expect_error(
    rcapsule:::write_runner_bootstrap(tmp, "notes.txt", seed = 1L, rng_kind = RNGkind()),
    "Unsupported entrypoint"
  )

  # Missing input file check via verify_file_hashes
  rec <- list(list(path = "missing_input.csv", sha256 = strrep("a", 64L)))
  vh <- rcapsule:::verify_file_hashes(rec, tmp)
  expect_equal(vh$status, "missing")
  expect_false(vh$passed)

  # Docker run args builder
  dargs <- rcapsule:::build_docker_run_args(tmp, "rocker/r-ver:4.4.2", seed = 42L, env_vars = list(FOO = "bar"))
  expect_true(all(c("run", "--rm", "CAPSULE_SEED=42", "FOO=bar", "rocker/r-ver:4.4.2", ".rcapsule_runner.R") %in% dargs))

  # Mocked run_in_docker: unavailable, missing Dockerfile, build failure, build+run success
  expect_error(
    rcapsule:::run_in_docker(tmp, tmp, NULL, NULL, 1L, list(), 10, check_available = function() FALSE),
    "Docker daemon is not available"
  )
  expect_error(
    rcapsule:::run_in_docker(tmp, tmp, NULL, NULL, 1L, list(), 10, check_available = function() TRUE),
    "no Dockerfile found"
  )

  writeLines("FROM rocker/r-ver:4.4.2", file.path(tmp, "Dockerfile"))
  res_bfail <- rcapsule:::run_in_docker(
    tmp, tmp, NULL, NULL, 1L, list(), 10,
    runner_fn = function(command, args, ...) list(status = 1L, stdout = "step 1", stderr = "build err"),
    check_available = function() TRUE
  )
  expect_equal(res_bfail$exit_status, 1L)
  expect_match(res_bfail$stderr, "docker build failed")

  calls <- 0L
  res_ok <- rcapsule:::run_in_docker(
    tmp, tmp, NULL, "mytag:v1", 42L, list(A = "1"), 10,
    runner_fn = function(command, args, ...) {
      calls <<- calls + 1L
      list(status = 0L, stdout = paste("call", calls), stderr = "")
    },
    check_available = function() TRUE
  )
  expect_equal(res_ok$exit_status, 0L)
  expect_equal(calls, 2L)
})

test_that("bundle, diff, and utils edge branches work cleanly", {
  # Bundle: auto-append .zip, manifest = NULL auto-discovery/creation, explicit certificate arg, overwrite = TRUE for dir
  proj <- make_runnable_pipeline_fixture(seed = 11L)
  m <- create_capsule_manifest(proj, inputs = "data/input.csv", outputs = "results/summary.csv", seed = 11L, output = file.path(proj, "capsule.json"))
  v <- verify_capsule(m, path = proj)
  cert <- render_certificate(v, output = NULL, format = "both")

  out_dir <- withr::local_tempdir()
  zip_no_ext <- file.path(out_dir, "my_bundle")
  exp1 <- export_capsule_bundle(proj, output = zip_no_ext, format = "zip", manifest = NULL, certificate = cert)
  expect_match(exp1$output_path, "\\.zip$")
  expect_true("capsule_certificate.md" %in% exp1$files)

  dir_dest <- file.path(out_dir, "dir_bundle")
  exp2 <- export_capsule_bundle(proj, output = dir_dest, format = "dir", manifest = file.path(proj, "capsule.json"), overwrite = FALSE)
  exp3 <- export_capsule_bundle(proj, output = dir_dest, format = "dir", manifest = m, overwrite = TRUE)
  expect_true(dir.exists(exp3$output_path))

  # Bundle with no capsule.json creates manifest automatically
  unlink(file.path(proj, "capsule.json"))
  exp4 <- export_capsule_bundle(proj, output = file.path(out_dir, "auto.zip"), format = "zip", manifest = NULL, include_certificate = FALSE)
  expect_true(file.exists(exp4$output_path))

  # diff_manifest_packages added/removed/changed branches
  pa <- list(list(package = "a", version = "1.0"), list(package = "b", version = "1.0"))
  pb <- list(list(package = "b", version = "2.0"), list(package = "c", version = "0.5"))
  pd <- rcapsule:::diff_manifest_packages(pa, pb)
  expect_equal(pd$status[pd$package == "a"], "removed")
  expect_equal(pd$status[pd$package == "b"], "version_changed")
  expect_equal(pd$status[pd$package == "c"], "added")

  # utils format detection and slug edge cases
  expect_equal(rcapsule:::detect_artifact_format("Dockerfile.prod"), "dockerfile")
  expect_equal(rcapsule:::detect_artifact_format("docker-compose.prod.yaml"), "compose")
  expect_equal(rcapsule:::detect_artifact_format("model.stan"), "stan")
  expect_equal(rcapsule:::detect_artifact_format("README"), "binary")
  expect_equal(rcapsule:::sanitize_slug(""), "capsule")
  expect_equal(rcapsule:::sanitize_slug("!!!"), "capsule")
})
