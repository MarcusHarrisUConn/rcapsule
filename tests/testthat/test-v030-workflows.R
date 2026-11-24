# Tests for v0.3.0 real-world workflows, cross-arch/PPM compilers, diff_capsules, and export_capsule_bundle

test_that("scan_project detects targets pipelines, here::here(), .Rprofile hazards, edge files, and architecture", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "data"))

  # _targets.R pipeline using here::here()
  writeLines(
    c(
      "library(targets)",
      "library(here)",
      "tar_option_set(packages = c('stats'))",
      "list(tar_target(raw, read.csv(here::here('data', 'raw data.csv'))))"
    ),
    file.path(dir, "_targets.R")
  )
  writeLines("", file.path(dir, ".here"))

  # .Rprofile with portability hazards + benign renv line
  writeLines(
    c(
      "source('renv/activate.R')",
      ".libPaths('/Users/researcher/custom_r_libs')",
      "setwd('/home/researcher/project')",
      "Sys.setenv(OPENAI_API_KEY = 'sk-hardcoded-in-rprofile')"
    ),
    file.path(dir, ".Rprofile")
  )

  # Zero-byte file, binary file, and whitespace/Unicode filename
  file.create(file.path(dir, "empty.txt"))
  writeBin(as.raw(c(137, 80, 78, 71)), file.path(dir, "fig.png"))
  write.csv(data.frame(x = 1:2), file.path(dir, "data", "raw data.csv"), row.names = FALSE)

  sc <- scan_project(dir)
  expect_true(sc$has_targets)
  expect_equal(sc$targets_file, "_targets.R")
  expect_equal(sc$entrypoint, "_targets.R")
  expect_true(sc$uses_here)
  expect_true(".here" %in% sc$here_markers)

  # .Rprofile hazards accurately detected (and renv activation line ignored)
  expect_s3_class(sc$rprofile_hazards, "tbl_df")
  expect_true(all(c("custom_libpaths", "setwd_call", "hardcoded_local_path", "secret_in_rprofile") %in% sc$rprofile_hazards$hazard))
  expect_false(any(sc$rprofile_hazards$line == 1L))
  expect_invisible(print(sc))

  # Edge-case file inventories
  expect_true("empty.txt" %in% sc$zero_byte_files)
  expect_true("fig.png" %in% sc$binary_files)
  expect_true("data/raw data.csv" %in% sc$unusual_filenames)

  # Architecture metadata populated cleanly
  expect_true(sc$architecture$host_arch %in% c("arm64", "amd64"))
  expect_equal(sc$architecture$hpc_target_platform, "linux/amd64")

  # Targets pipeline emits targets::tar_make() in Dockerfile & Apptainer
  df_tar <- compile_dockerfile(sc, r_version = "4.4.1")
  def_tar <- compile_apptainer(sc, r_version = "4.4.1")
  expect_match(df_tar$content, 'CMD ["Rscript", "-e", "targets::tar_make()"]', fixed = TRUE)
  expect_match(def_tar$content, 'exec Rscript -e "targets::tar_make()" "$@"', fixed = TRUE)
  expect_true(lint_container_spec(df_tar)$passed)
  expect_true(lint_container_spec(def_tar)$passed)

  # Clean .Rprofile with only renv activation triggers zero hazards
  dir_clean <- withr::local_tempdir()
  writeLines("source('renv/activate.R')", file.path(dir_clean, ".Rprofile"))
  writeLines("x <- 1", file.path(dir_clean, "run.R"))
  expect_equal(nrow(scan_project(dir_clean)$rprofile_hazards), 0L)
})

test_that("compile_dockerfile and compile_compose support cross-arch platform pinning and Posit PPM binary mode", {
  dir <- make_shiny_fixture()

  # PPM binary mode (default) + explicit linux/amd64 platform
  df_ppm <- compile_dockerfile(dir, r_version = "4.4.1", platform = "linux/amd64", use_ppm = TRUE, ppm_distro = "jammy", ppm_date = "2026-01-15")
  expect_equal(df_ppm$platform, "linux/amd64")
  expect_true(df_ppm$use_ppm)
  expect_match(df_ppm$content, "FROM --platform=linux/amd64 rocker/r-ver:4.4.1 AS builder", fixed = TRUE)
  expect_match(df_ppm$content, "FROM --platform=linux/amd64 rocker/r-ver:4.4.1 AS runtime", fixed = TRUE)
  expect_match(df_ppm$content, "https://packagemanager.posit.co/cran/__linux__/jammy/2026-01-15", fixed = TRUE)
  l_ppm <- lint_container_spec(df_ppm)
  expect_true(l_ppm$passed)
  expect_equal(l_ppm$n_warnings, 0L)

  # Source CRAN snapshot mode (use_ppm = FALSE)
  df_src <- compile_dockerfile(dir, r_version = "4.4.1", use_ppm = FALSE, ppm_date = "2026-01-15")
  expect_false(df_src$use_ppm)
  expect_match(df_src$content, "https://packagemanager.posit.co/cran/2026-01-15", fixed = TRUE)
  expect_false(grepl("__linux__", df_src$content, fixed = TRUE))

  # Compose platform pinning on app & worker services
  comp_amd <- compile_compose(dir, platform = "linux/amd64")
  expect_equal(comp_amd$platform, "linux/amd64")
  expect_equal(comp_amd$config$services$app$platform, "linux/amd64")
  expect_equal(comp_amd$config$services$worker$platform, "linux/amd64")
  expect_true(lint_container_spec(comp_amd)$passed)
  expect_equal(lint_container_spec(comp_amd)$n_warnings, 0L)

  # Invalid platform / distro / date rejected
  expect_error(compile_dockerfile(dir, platform = "windows/amd64"), "must be NULL or one of")
  expect_error(compile_dockerfile(dir, ppm_distro = "invalid_os"), "must be one of")
  expect_error(compile_dockerfile(dir, ppm_date = "not-a-date"), "ISO date")
})

test_that("diff_capsules accurately compares manifests across environments, inputs, and tolerance-shifted outputs", {
  dir <- make_runnable_pipeline_fixture(seed = 42L)
  m1 <- create_capsule_manifest(
    dir,
    inputs = "data/input.csv",
    outputs = c("results/summary.csv", "results/metrics.json"),
    seed = 42L,
    tolerances = list(atol = 1e-3, rtol = 1e-3)
  )

  # 1. Identical manifest comparison
  d_same <- diff_capsules(m1, m1, label_a = "Author", label_b = "Reviewer")
  expect_s3_class(d_same, "rcapsule_diff")
  expect_true(d_same$identical)
  expect_true(d_same$outputs_equivalent)
  expect_false(d_same$has_env_drift)
  expect_invisible(print(d_same))
  sm_same <- summary(d_same)
  expect_true(sm_same$identical)
  expect_equal(sm_same$n_output_changes, 0L)

  # 2. Small numerical shift within tolerance + cross-machine environment drift
  df_s <- read.csv(file.path(dir, "results", "summary.csv"), stringsAsFactors = FALSE)
  df_s$estimate <- df_s$estimate + 0.0002
  write.csv(df_s, file.path(dir, "results", "summary.csv"), row.names = FALSE)

  m2 <- create_capsule_manifest(
    dir,
    inputs = "data/input.csv",
    outputs = c("results/summary.csv", "results/metrics.json"),
    seed = 42L,
    tolerances = list(atol = 1e-3, rtol = 1e-3)
  )
  # Simulate HPC environment differences in m2 (guaranteed distinct from host R/platform on all CI runners)
  alt_r_ver <- if (identical(paste0(R.version$major, ".", R.version$minor), "4.5.0")) "4.4.1" else "4.5.0"
  alt_platform <- if (grepl("linux", R.version$platform, ignore.case = TRUE)) {
    "aarch64-apple-darwin23"
  } else {
    "x86_64-pc-linux-gnu"
  }
  m2$environment$r_version <- alt_r_ver
  m2$environment$platform <- alt_platform
  m2$environment$packages <- list(list(package = "jsonlite", version = "2.1.0", source = "renv"))
  m2$environment$toolchains <- list("cpp")

  d_tol <- diff_capsules(m1, m2, label_a = "Laptop (arm64)", label_b = "HPC (amd64)")
  expect_false(d_tol$identical)
  expect_true(d_tol$has_env_drift)
  expect_true(d_tol$env_diff$r_version_changed)
  expect_true(d_tol$env_diff$platform_changed)
  expect_equal(d_tol$env_diff$toolchains$added, "cpp")
  expect_true(d_tol$outputs_equivalent)
  expect_equal(d_tol$artifact_diffs$outputs$status[d_tol$artifact_diffs$outputs$path == "results/summary.csv"], "within_tolerance")
  expect_equal(d_tol$artifact_diffs$outputs$status[d_tol$artifact_diffs$outputs$path == "results/metrics.json"], "unchanged")
  expect_invisible(print(d_tol))

  # 3. Large output drift + added/removed artifact fails outputs_equivalent
  df_s$estimate <- df_s$estimate + 5.0
  write.csv(df_s, file.path(dir, "results", "summary.csv"), row.names = FALSE)
  write.csv(data.frame(z = 1), file.path(dir, "results", "extra.csv"), row.names = FALSE)
  m3 <- create_capsule_manifest(
    dir,
    inputs = "data/input.csv",
    outputs = c("results/summary.csv", "results/extra.csv"),
    seed = 99L
  )
  d_div <- diff_capsules(m1, m3, tolerances = list(atol = 1e-3))
  expect_false(d_div$outputs_equivalent)
  expect_true(d_div$rng_diff$seed_changed)
  out_tbl <- d_div$artifact_diffs$outputs
  expect_equal(out_tbl$status[out_tbl$path == "results/summary.csv"], "modified")
  expect_equal(out_tbl$status[out_tbl$path == "results/extra.csv"], "added")
  expect_equal(out_tbl$status[out_tbl$path == "results/metrics.json"], "removed")
})

test_that("export_capsule_bundle packages journal-ready zip and dir bundles safely without zip-slip", {
  dir <- make_runnable_pipeline_fixture(seed = 88L)
  m <- create_capsule_manifest(
    dir,
    inputs = "data/input.csv",
    outputs = c("results/summary.csv", "results/metrics.json"),
    seed = 88L,
    output = file.path(dir, "capsule.json")
  )
  v <- verify_capsule(m, path = dir, runner = "sandbox")

  out_tmp <- withr::local_tempdir()
  zip_path <- file.path(out_tmp, "journal_supplement.zip")

  exp_zip <- export_capsule_bundle(
    path = dir,
    output = zip_path,
    format = "zip",
    manifest = m,
    verification = v,
    platform = "linux/amd64"
  )

  expect_s3_class(exp_zip, "rcapsule_export")
  expect_true(file.exists(exp_zip$output_path))
  expect_match(exp_zip$sha256, "^[0-9a-f]{64}$")
  expect_true(all(c(
    "Dockerfile", "docker-compose.yml", "Apptainer.def",
    "capsule.json", "capsule_certificate.md", "capsule_certificate.html",
    "README_REPRODUCE.md", "data/input.csv", "run.R",
    "results/summary.csv", "results/metrics.json"
  ) %in% exp_zip$files))
  expect_invisible(print(exp_zip))

  # Inspect actual ZIP entries to guarantee zero zip-slip paths (no .. or leading /)
  entries <- zip::zip_list(exp_zip$output_path)$filename
  expect_false(any(grepl("^/|\\.\\.", entries)))

  # Refuses overwrite = FALSE when archive already exists
  expect_error(
    export_capsule_bundle(dir, output = zip_path, manifest = m, overwrite = FALSE),
    "already exists"
  )

  # Directory export format works and README_REPRODUCE.md includes platform & verification verdict
  dir_out <- file.path(out_tmp, "supplement_dir")
  exp_dir <- export_capsule_bundle(
    path = dir,
    output = dir_out,
    format = "dir",
    manifest = m,
    verification = v,
    platform = "linux/amd64"
  )
  expect_true(dir.exists(dir_out))
  readme_txt <- paste(readLines(file.path(dir_out, "README_REPRODUCE.md")), collapse = "\n")
  expect_match(readme_txt, "VERIFIED \\(EXACT\\)")
  expect_match(readme_txt, "--platform=linux/amd64", fixed = TRUE)
  expect_match(readme_txt, "apptainer build capsule.sif Apptainer.def", fixed = TRUE)

  # Crafted manifest with traversal path is blocked from entering exported bundle
  m_evil <- m
  m_evil$artifacts$inputs[[1L]]$path <- "../../etc/passwd"
  expect_error(
    export_capsule_bundle(dir, output = file.path(out_tmp, "evil.zip"), manifest = m_evil),
    "Path traversal"
  )
})

test_that("whitespace filenames reproduce cleanly and package workflows do not mutate caller global state", {
  dir <- withr::local_tempdir()
  write.csv(data.frame(a = 1:3), file.path(dir, "my input.csv"), row.names = FALSE)
  writeLines(
    c(
      "d <- read.csv('my input.csv')",
      "write.csv(data.frame(total = sum(d$a)), 'my output.csv', row.names = FALSE)"
    ),
    file.path(dir, "run study.R")
  )
  write.csv(data.frame(total = 6L), file.path(dir, "my output.csv"), row.names = FALSE)

  opts_before <- options()
  env_before <- Sys.getenv()
  seed_before <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  } else {
    NULL
  }

  m <- create_capsule_manifest(
    dir,
    inputs = "my input.csv",
    outputs = "my output.csv",
    entrypoint = "run study.R",
    seed = 5L
  )
  v <- verify_capsule(m, path = dir, runner = "sandbox")
  expect_true(v$passed)
  expect_equal(v$status, "verified_exact")

  # Verify caller global state untouched
  expect_identical(options(), opts_before)
  expect_identical(Sys.getenv(), env_before)
  seed_after <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  } else {
    NULL
  }
  expect_identical(seed_after, seed_before)
})
