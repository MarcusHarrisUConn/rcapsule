test_that("export_sbom generates valid CycloneDX 1.5 SBOM covering R, apt, PyPI, and toolchains", {
  tmp <- withr::local_tempdir()
  writeLines(
    c(
      "library(sf)",
      "library(cmdstanr)",
      "library(reticulate)",
      "library(rjags)",
      "py_run_string('import numpy')",
      "set.seed(7L)",
      "write.csv(data.frame(x = 1:3), 'out.csv', row.names = FALSE)"
    ),
    file.path(tmp, "run.R")
  )
  writeLines(c("numpy==1.26.4", "scipy>=1.11", "scikit_learn==1.4.0"), file.path(tmp, "requirements.txt"))
  writeLines(
    c("---", "title: 'Study'", "format: pdf", "---", "", "```{r}", "1 + 1", "```"),
    file.path(tmp, "paper.qmd")
  )
  # Add a rich renv.lock with CRAN, GitHub, GitLab, Bitbucket, Bioconductor, and MD5 Hash
  renv_lock <- list(
    R = list(Version = "4.4.2", Repositories = list(list(Name = "CRAN", URL = "https://cloud.r-project.org"))),
    Packages = list(
      sf = list(Package = "sf", Version = "1.0-19", Source = "Repository", Repository = "CRAN", Hash = "0123456789abcdef0123456789abcdef"),
      myghpkg = list(Package = "myghpkg", Version = "0.2.1", Source = "GitHub", RemoteType = "github", RemoteUsername = "StatLab", RemoteRepo = "myghpkg", RemoteRef = "main", RemoteSha = "abcdef123456"),
      myglpkg = list(Package = "myglpkg", Version = "0.1.0", Source = "GitLab", RemoteType = "gitlab", RemoteUsername = "Org", RemoteRepo = "myglpkg", RemoteRef = "v0.1.0"),
      mybbpkg = list(Package = "mybbpkg", Version = "0.1.0", Source = "Bitbucket", RemoteType = "bitbucket", RemoteUsername = "Team", RemoteRepo = "mybbpkg", RemoteRef = "HEAD"),
      Biobase = list(Package = "Biobase", Version = "2.64.0", Source = "Bioconductor", Repository = "BioCsoft")
    )
  )
  jsonlite::write_json(renv_lock, file.path(tmp, "renv.lock"), auto_unbox = TRUE, pretty = TRUE)
  write.csv(data.frame(x = 1:3), file.path(tmp, "out.csv"), row.names = FALSE)

  m <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 7L)
  out_file <- file.path(tmp, "sbom.cdx.json")
  sbom <- export_sbom(tmp, manifest = m, output = out_file, include_base = TRUE)

  expect_s3_class(sbom, "rcapsule_sbom")
  expect_true(file.exists(out_file))
  expect_equal(sbom$bom$bomFormat, "CycloneDX")
  expect_equal(sbom$bom$specVersion, "1.5")
  expect_match(sbom$serial_number, "^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
  expect_equal(sbom$bom$version, 1L)
  expect_equal(sbom$bom$metadata$component$hashes[[1L]]$content, m$integrity$content_digest)

  purls <- vapply(sbom$bom$components, function(c) c$purl %||% "", character(1L))
  expect_true(any(grepl("^pkg:cran/sf@1\\.0-19$", purls)))
  expect_true(any(grepl("^pkg:github/statlab/myghpkg@abcdef123456$", purls)))
  expect_true(any(grepl("^pkg:gitlab/org/myglpkg@v0\\.1\\.0$", purls)))
  expect_true(any(grepl("^pkg:bitbucket/team/mybbpkg@HEAD$", purls)))
  expect_true(any(grepl("^pkg:bioconductor/Biobase@2\\.64\\.0$", purls)))
  expect_true(any(grepl("^pkg:deb/debian/libgdal-dev$", purls)))
  expect_true(any(grepl("^pkg:pypi/numpy@1\\.26\\.4$", purls)))
  expect_true(any(grepl("^pkg:pypi/scikit-learn@1\\.4\\.0$", purls)))
  expect_true(any(grepl("^pkg:pypi/scipy$", purls)))
  expect_true(any(grepl("^pkg:generic/cmdstan$", purls)))
  expect_true(any(grepl("^pkg:generic/quarto$", purls)))
  expect_true(any(grepl("^pkg:generic/tinytex$", purls)))
  expect_true(any(grepl("^pkg:generic/jags$", purls)))
  expect_true(any(grepl("^pkg:generic/r@4\\.4\\.2$", purls)))

  # R -> apt dependency edge exists for sf
  dep_refs <- vapply(sbom$bom$dependencies, `[[`, character(1L), "ref")
  expect_true("r:sf" %in% dep_refs)

  # Print and as.character methods
  expect_invisible(print(sbom))
  expect_true(grepl('"bomFormat": "CycloneDX"', as.character(sbom), fixed = TRUE))

  # Validate in-memory object AND round-tripped JSON file
  val_mem <- validate_sbom(sbom)
  expect_s3_class(val_mem, "rcapsule_sbom_validation")
  expect_true(val_mem$valid)
  expect_equal(val_mem$n_errors, 0L)
  expect_invisible(print(val_mem))

  val_file <- validate_sbom(out_file)
  expect_true(val_file$valid)
  expect_equal(val_file$n_components, val_mem$n_components)
})

test_that("validate_sbom catches malformed CycloneDX fields, PURLs, hashes, duplicates, and dangling refs", {
  bad_bom <- list(
    bomFormat = "SPDX",
    specVersion = "1.3",
    serialNumber = "not-a-uuid",
    version = 0,
    metadata = list(
      timestamp = "yesterday",
      tools = NULL,
      component = list(type = "invalid-type", `bom-ref` = "root", name = "demo")
    ),
    components = list(
      list(type = "bogus", `bom-ref` = "root", name = "", purl = "not-a-purl", hashes = list(list(alg = "FAKE", content = "xyz"))),
      list(type = "library", `bom-ref` = "r:a", name = "a", purl = "pkg:cran/a@1.0"),
      list(type = "library", `bom-ref` = "r:a", name = "a-dup", purl = "pkg:cran/a@1.0")
    ),
    dependencies = list(
      list(ref = "missing-ref", dependsOn = list("ghost-dep"))
    )
  )
  val <- validate_sbom(bad_bom)
  expect_false(val$valid)
  expect_gte(val$n_errors, 10L)
  expect_true(all(c("CDX001", "CDX002", "CDX003", "CDX004", "CDX006", "CDX007", "CDX009", "CDX011", "CDX012", "CDX013", "CDX014", "CDX015", "CDX017", "CDX018") %in% val$issues$rule))
  expect_invisible(print(val))

  # Input guards
  expect_error(export_sbom(spec_version = "1.4"), "Unsupported")
  expect_error(export_sbom(withr::local_tempdir(), serial_number = "bad"), "UUID URN")
  expect_error(validate_sbom("/nonexistent/sbom.json"), "does not exist")
  expect_error(validate_sbom(123L), "must be an")
})

test_that("diagnose_reproducibility classifies every verification and diff root cause accurately", {
  # 1. Exact verification -> zero findings
  dir_ok <- make_runnable_pipeline_fixture(seed = 42L)
  m_ok <- create_capsule_manifest(dir_ok, inputs = "data/input.csv", outputs = c("results/summary.csv", "results/metrics.json"), seed = 42L)
  v_ok <- verify_capsule(m_ok, path = dir_ok, runner = "sandbox")
  d_ok <- diagnose_reproducibility(v_ok)
  expect_s3_class(d_ok, "rcapsule_diagnosis")
  expect_equal(d_ok$n_findings, 0L)
  expect_equal(d_ok$primary_cause, "none")
  expect_invisible(print(d_ok))
  expect_equal(summary(d_ok)$n_findings, 0L)

  # 2. HMAC signature failure + tampered manifest
  m_signed <- sign_manifest(m_ok, key = "secret-k")
  v_bad_key <- verify_capsule(m_signed, path = dir_ok, key = "wrong-k")
  d_hmac <- diagnose_reproducibility(v_bad_key)
  expect_equal(d_hmac$primary_cause, "hmac_signature_failure")
  expect_invisible(print(d_hmac))

  m_tamp <- m_ok
  m_tamp$rng$seed <- 777L
  v_tamp <- verify_capsule(m_tamp, path = dir_ok, seed = 42L)
  d_tamp <- diagnose_reproducibility(v_tamp)
  expect_true("manifest_tampering" %in% d_tamp$findings$category)

  # 3. Line-ending drift (CRLF vs LF)
  dir_crlf <- withr::local_tempdir()
  writeLines("writeLines(c('a,b', '1,2'), 'out.csv', sep = '\\n')", file.path(dir_crlf, "run.R"))
  # Reference file written with Windows CRLF
  writeBin(charToRaw("a,b\r\n1,2\r\n"), file.path(dir_crlf, "out.csv"))
  m_crlf <- create_capsule_manifest(dir_crlf, outputs = "out.csv", seed = 1L)
  v_crlf <- verify_capsule(m_crlf, path = dir_crlf, runner = "sandbox")
  expect_false(v_crlf$passed)
  d_crlf <- diagnose_reproducibility(v_crlf)
  expect_equal(d_crlf$primary_cause, "line_ending_drift")
  expect_match(d_crlf$remediations[[1L]], "gitattributes|eol")

  # 4. Binary/PDF metadata drift
  dir_pdf <- withr::local_tempdir()
  writeLines("writeBin(as.raw(c(37, 80, 68, 70, 99)), 'fig.pdf')", file.path(dir_pdf, "run.R"))
  writeBin(as.raw(c(37, 80, 68, 70, 10)), file.path(dir_pdf, "fig.pdf"))
  m_pdf <- create_capsule_manifest(dir_pdf, outputs = "fig.pdf", seed = 1L)
  v_pdf <- verify_capsule(m_pdf, path = dir_pdf)
  d_pdf <- diagnose_reproducibility(v_pdf)
  expect_equal(d_pdf$primary_cause, "binary_metadata_drift")

  # 5. Schema drift (column / row mismatch)
  dir_sch <- withr::local_tempdir()
  writeLines("write.csv(data.frame(a = 1:2, extra_col = 3:4), 'out.csv', row.names = FALSE)", file.path(dir_sch, "run.R"))
  write.csv(data.frame(a = 1:3, b = 4:6), file.path(dir_sch, "out.csv"), row.names = FALSE)
  m_sch <- create_capsule_manifest(dir_sch, outputs = "out.csv", seed = 1L)
  v_sch <- verify_capsule(m_sch, path = dir_sch)
  d_sch <- diagnose_reproducibility(v_sch)
  expect_equal(d_sch$primary_cause, "schema_drift")

  # 6. Small Monte Carlo / BLAS numeric drift vs. Large unseeded divergence
  dir_num <- withr::local_tempdir()
  writeLines("write.csv(data.frame(x = c(1.0002, 2.0)), 'out.csv', row.names = FALSE)", file.path(dir_num, "run.R"))
  write.csv(data.frame(x = c(1.0, 2.0)), file.path(dir_num, "out.csv"), row.names = FALSE)
  m_small <- create_capsule_manifest(dir_num, outputs = "out.csv", seed = 1L)
  v_small <- verify_capsule(m_small, path = dir_num)
  d_small <- diagnose_reproducibility(v_small, small_tol = 1e-2)
  expect_equal(d_small$primary_cause, "monte_carlo_small_drift")

  # Within-tolerance verification yields info-level monte_carlo_small_drift
  v_wt <- verify_capsule(m_small, path = dir_num, tolerances = list(atol = 1e-3))
  expect_equal(v_wt$status, "verified_within_tolerance")
  d_wt <- diagnose_reproducibility(v_wt)
  expect_equal(d_wt$primary_cause, "monte_carlo_small_drift")
  expect_equal(d_wt$findings$severity[[1L]], "info")

  # Large divergence with seed changed -> rng_drift + unseeded_large_divergence
  writeLines("write.csv(data.frame(x = rnorm(3, sd = 10)), 'out.csv', row.names = FALSE)", file.path(dir_num, "run.R"))
  set.seed(1L)
  write.csv(data.frame(x = rnorm(3, sd = 10)), file.path(dir_num, "out.csv"), row.names = FALSE)
  m_big <- create_capsule_manifest(dir_num, outputs = "out.csv", seed = 1L)
  v_big <- verify_capsule(m_big, path = dir_num, seed = 999L)
  d_big <- diagnose_reproducibility(v_big)
  expect_true(all(c("rng_drift", "unseeded_large_divergence") %in% d_big$findings$category))

  # 7. Execution failure (missing package clue + missing file clue) + missing output + extra artifact
  dir_err <- withr::local_tempdir()
  writeLines("library(nonexistentpkg99999)", file.path(dir_err, "run.R"))
  writeLines("ok", file.path(dir_err, "out.txt"))
  m_err <- create_capsule_manifest(dir_err, outputs = "out.txt", seed = 1L)
  v_err <- verify_capsule(m_err, path = dir_err)
  d_err <- diagnose_reproducibility(v_err)
  expect_equal(d_err$primary_cause, "execution_failure")
  expect_true("missing_output" %in% d_err$findings$category)
  expect_match(d_err$findings$remediation[d_err$findings$category == "execution_failure"], "nonexistentpkg99999")

  # 8. Input drift, script drift, environment drift, and unexpected extra artifacts
  dir_drift <- make_runnable_pipeline_fixture(seed = 42L)
  m_dr <- create_capsule_manifest(dir_drift, inputs = "data/input.csv", outputs = "results/summary.csv", seed = 42L)
  writeLines("group,x\nA,999", file.path(dir_drift, "data", "input.csv"))
  writeLines(c(readLines(file.path(dir_drift, "run.R")), "writeLines('extra', 'scratch.txt')"), file.path(dir_drift, "run.R"))
  m_dr_fake_env <- m_dr
  m_dr_fake_env$environment$r_version <- "3.6.3"
  v_dr <- verify_capsule(m_dr_fake_env, path = dir_drift, strict_outputs = TRUE)
  d_dr <- diagnose_reproducibility(v_dr)
  expect_true(all(c("input_drift", "script_drift", "environment_or_arch_drift", "unexpected_extra_artifacts") %in% d_dr$findings$category))

  # 9. Diagnose rcapsule_diff (identical & diverged with env/rng/input/script/output/container drift)
  d_same <- diff_capsules(m_ok, m_ok)
  diag_diff_same <- diagnose_reproducibility(d_same)
  expect_equal(diag_diff_same$n_findings, 0L)

  m_other <- m_ok
  m_other$environment$r_version <- "4.5.0"
  m_other$environment$platform <- "x86_64-pc-linux-gnu"
  m_other$rng$seed <- 99L
  m_other$project$git$commit <- "deadbeef"
  m_other$artifacts$inputs[[1L]]$sha256 <- strrep("a", 64L)
  m_other$artifacts$scripts[[1L]]$sha256 <- strrep("b", 64L)
  m_other$artifacts$containers <- list(list(path = "Dockerfile", sha256 = strrep("c", 64L), bytes = 100L, format = "dockerfile"))
  m_other$artifacts$outputs[[2L]] <- list(path = "results/added.csv", sha256 = strrep("d", 64L), bytes = 10L, format = "csv")
  diff_big <- diff_capsules(m_ok, m_other)
  diag_diff <- diagnose_reproducibility(diff_big)
  expect_true(all(c("input_drift", "script_drift", "rng_drift", "environment_or_arch_drift", "missing_output", "unexpected_extra_artifacts", "container_drift", "git_revision_drift") %in% diag_diff$findings$category))
  expect_invisible(print(diag_diff))
  sm <- summary(diag_diff)
  expect_equal(sm$source_type, "diff")
  expect_gte(sm$n_findings, 7L)

  # Input guards
  expect_error(diagnose_reproducibility(list()), "must be an")
  expect_error(diagnose_reproducibility(v_ok, small_tol = -1), "positive number")
})

test_that("as_apptainer_spec exports structured HPC descriptor from path, scan, apptainer, and bundle", {
  tmp <- withr::local_tempdir()
  writeLines(c("library(sf)", "library(cmdstanr)", "cat('hi\\n')"), file.path(tmp, "run.R"))

  spec_path <- as_apptainer_spec(tmp, bind_paths = c("/scratch", "/work", "/projects"))
  expect_s3_class(spec_path, "rcapsule_apptainer_spec")
  expect_equal(spec_path$schema_version, "1.0.0")
  expect_equal(spec_path$bootstrap, "docker")
  expect_true("sf" %in% spec_path$r_packages)
  expect_true("cmdstanr" %in% spec_path$r_packages)
  expect_true("libgdal-dev" %in% spec_path$apt_packages)
  expect_true("cmdstan" %in% spec_path$toolchains)
  expect_equal(spec_path$bind_paths, c("/scratch", "/work", "/projects"))
  expect_equal(spec_path$env_vars$TZ, "UTC")
  expect_true(nzchar(spec_path$env_vars$CMDSTAN %||% ""))
  expect_match(spec_path$def_sha256, "^[0-9a-f]{64}$")
  expect_true(length(spec_path$runscript) >= 1L)
  expect_true(length(spec_path$test_commands) >= 2L)
  expect_invisible(print(spec_path))

  # Zero-dependency plain list conversion
  plain <- as.list(spec_path)
  expect_true(is.list(plain))
  expect_false(inherits(plain, "rcapsule_apptainer_spec"))
  expect_equal(plain$def_sha256, spec_path$def_sha256)

  # From rcapsule_scan, rcapsule_apptainer, and rcapsule_bundle
  sc <- scan_project(tmp)
  app <- compile_apptainer(sc)
  spec_app <- as_apptainer_spec(app)
  expect_equal(spec_app$def_sha256, spec_path$def_sha256)

  bnd <- build_capsule(tmp, targets = "apptainer", write = FALSE, lint = FALSE, verify = FALSE)
  spec_bnd <- as_apptainer_spec(bnd)
  expect_equal(spec_bnd$def_sha256, spec_path$def_sha256)

  # Validation guards
  expect_error(as_apptainer_spec(123L), "must be an")
  expect_error(as_apptainer_spec(tmp, bind_paths = "relative/path"), "Invalid or unsafe container path")
  expect_error(as_apptainer_spec(tmp, bind_paths = 123L), "character vector")
})

test_that("verify_with_script executes external audit scripts in secret-scrubbed sandbox and hashes artifacts", {
  proj <- withr::local_tempdir()
  write.csv(data.frame(id = 1:4, val = c(10, 20, 30, 40)), file.path(proj, "data.csv"), row.names = FALSE)

  ext_dir <- withr::local_tempdir()
  pass_script <- file.path(ext_dir, "audit_pass.R")
  writeLines(
    c(
      "df <- read.csv('data.csv')",
      "stopifnot(nrow(df) == 4L)",
      "secret_val <- Sys.getenv('AWS_SECRET_ACCESS_KEY', unset = '')",
      "stopifnot(!nzchar(secret_val))",
      "custom_val <- Sys.getenv('AUDIT_MODE', unset = '')",
      "args_raw <- Sys.getenv('RCAPSULE_AUDIT_ARGS', unset = '')",
      "writeLines(c(paste0('mode=', custom_val), paste0('args=', args_raw), paste0('rng=', round(runif(1), 6))), 'audit_out.txt')",
      "write.csv(transform(df, val = val * 2), 'data.csv', row.names = FALSE)"
    ),
    pass_script
  )

  res <- withr::with_envvar(c(AWS_SECRET_ACCESS_KEY = "super-secret-value-123"), {
    verify_with_script(
      script = pass_script,
      path = proj,
      seed = 123L,
      env_vars = list(AUDIT_MODE = "strict"),
      expected_outputs = "audit_out.txt",
      args = c("--check-ci", "level=2"),
      scrub_secrets = TRUE
    )
  })

  expect_s3_class(res, "rcapsule_script_audit")
  expect_true(res$passed)
  expect_equal(res$status, "passed")
  expect_equal(res$exit_status, 0L)
  expect_true("AWS_SECRET_ACCESS_KEY" %in% res$scrubbed_env_vars)
  expect_true("audit_out.txt" %in% res$artifacts$path)
  expect_equal(res$artifacts$change[res$artifacts$path == "audit_out.txt"], "created")
  expect_equal(res$artifacts$change[res$artifacts$path == "data.csv"], "modified")
  expect_true(all(res$expected_checks$exists))
  expect_invisible(print(res))

  # Original project directory was NEVER mutated by the sandboxed script
  expect_equal(read.csv(file.path(proj, "data.csv"))$val, c(10, 20, 30, 40))
  expect_false(file.exists(file.path(proj, "audit_out.txt")))

  # Failing script + missing expected output
  fail_script <- file.path(ext_dir, "audit_fail.R")
  writeLines("stop('intentional audit failure')", fail_script)
  res_fail <- verify_with_script(fail_script, path = proj, expected_outputs = "missing.txt")
  expect_false(res_fail$passed)
  expect_equal(res_fail$status, "failed")
  expect_false(res_fail$expected_checks$exists[[1L]])
  expect_invisible(print(res_fail))

  # Validation guards
  txt_file <- file.path(ext_dir, "not_r.txt")
  writeLines("hi", txt_file)
  expect_error(verify_with_script(txt_file, path = proj), "\\.R")
  expect_error(verify_with_script(file.path(ext_dir, "nope.R"), path = proj), "does not exist")
  expect_error(verify_with_script(pass_script, path = proj, expected_outputs = "../escape.txt"), "Path traversal")
})
