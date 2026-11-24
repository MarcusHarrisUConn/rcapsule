# Permanent regression tests for all 16 Phase 1 independent peer red-team findings (v0.5.0)

test_that("[CRITICAL-1] print.*() methods never evaluate glue expressions from untrusted data", {
  withr::local_options(list(rcapsule_qa_fired = NULL))

  # 1. print.rcapsule_lint across Dockerfile, Compose, and Apptainer
  l_df <- lint_container_spec(
    c('FROM repo/{options(rcapsule_qa_fired = "lint_df")}:latest', "USER capsule"),
    type = "dockerfile"
  )
  capture.output(suppressMessages(print(l_df)))
  expect_null(getOption("rcapsule_qa_fired"))

  l_dc <- lint_container_spec(
    c("services:", "  app:", '    image: repo/{options(rcapsule_qa_fired = "lint_dc")}:latest'),
    type = "compose"
  )
  capture.output(suppressMessages(print(l_dc)))
  expect_null(getOption("rcapsule_qa_fired"))

  l_ap <- lint_container_spec(
    c("Bootstrap: docker", 'From: repo/{options(rcapsule_qa_fired = "lint_ap")}:latest'),
    type = "apptainer"
  )
  capture.output(suppressMessages(print(l_ap)))
  expect_null(getOption("rcapsule_qa_fired"))

  # 2. print.rcapsule_verification, print.rcapsule_diagnosis, print.rcapsule_diff, print.rcapsule_integrity
  proj <- withr::local_tempdir()
  writeLines(
    'write.csv(data.frame(k = "{options(rcapsule_qa_fired = \\"verify_print\\")}"), "out.csv", row.names = FALSE)',
    file.path(proj, "run.R")
  )
  utils::write.csv(data.frame(k = "baseline"), file.path(proj, "out.csv"), row.names = FALSE)
  m1 <- create_capsule_manifest(proj, outputs = "out.csv", seed = 1L)
  v1 <- verify_capsule(m1, path = proj)

  capture.output(suppressMessages(print(v1)))
  expect_null(getOption("rcapsule_qa_fired"))

  diag1 <- diagnose_reproducibility(v1)
  capture.output(suppressMessages(print(diag1)))
  expect_null(getOption("rcapsule_qa_fired"))

  utils::write.csv(
    data.frame(k = '{options(rcapsule_qa_fired = "diff_print")}'),
    file.path(proj, "out.csv"),
    row.names = FALSE
  )
  m2 <- create_capsule_manifest(proj, outputs = "out.csv", seed = 1L)
  d12 <- diff_capsules(m1, m2, tolerances = list(atol = 1e-3))
  capture.output(suppressMessages(print(d12)))
  expect_null(getOption("rcapsule_qa_fired"))

  m_bad <- m1
  m_bad$integrity$content_digest <- '{options(rcapsule_qa_fired = "int_print")}'
  chk <- verify_manifest_integrity(m_bad)
  capture.output(suppressMessages(print(chk)))
  expect_null(getOption("rcapsule_qa_fired"))

  # 3. print.rcapsule_scan via malicious renv.lock Version field
  proj2 <- withr::local_tempdir()
  writeLines(jsonlite::toJSON(list(
    R = list(Version = "4.4.1"),
    Packages = list(
      jsonlite = list(
        Package = "jsonlite",
        Version = '{options(rcapsule_qa_fired = "scan_print")}',
        Source = "Repository",
        Repository = "CRAN"
      ),
      fakeuninstalledpkg = list(
        Package = "fakeuninstalledpkg",
        Version = '{options(rcapsule_qa_fired = "scan_print_2")}',
        Source = "Repository",
        Repository = "CRAN"
      )
    )
  ), auto_unbox = TRUE), file.path(proj2, "renv.lock"))
  sc <- scan_project(proj2)
  expect_false(grepl("options", sc$packages$version[sc$packages$package == "jsonlite"], fixed = TRUE))
  expect_true(is.na(sc$packages$version[sc$packages$package == "fakeuninstalledpkg"]))
  capture.output(suppressMessages(print(sc)))
  expect_null(getOption("rcapsule_qa_fired"))
})

test_that("[HIGH-1] sandbox blocks ~/.Renviron, R_ENVIRON_USER, project .Renviron/.Rprofile, and ~/.netrc", {
  fake_home <- withr::local_tempdir()
  writeLines(c(
    "GITHUB_TOKEN=LEAKED_FROM_HOME_RENVIRON",
    "OPENAI_API_KEY=LEAKED_FROM_HOME_RENVIRON_2"
  ), file.path(fake_home, ".Renviron"))
  writeLines("machine api.example.com login alice password DUMMY", file.path(fake_home, ".netrc"))

  custom_renviron <- file.path(fake_home, "custom.Renviron")
  writeLines("AWS_SECRET_ACCESS_KEY=LEAKED_FROM_CUSTOM_RENVIRON", custom_renviron)

  proj <- withr::local_tempdir()
  writeLines("PROJ_SECRET=LEAKED_FROM_PROJ_RENVIRON", file.path(proj, ".Renviron"))
  writeLines("ENV_SECRET=LEAKED_FROM_DOT_ENV", file.path(proj, ".env"))
  writeLines('Sys.setenv(PROJ_RPROFILE_RAN = "YES")', file.path(proj, ".Rprofile"))

  aud <- file.path(withr::local_tempdir(), "audit_isolation.R")
  writeLines(c(
    'cat("GITHUB_TOKEN=", Sys.getenv("GITHUB_TOKEN", "<UNSET>"), "\\n", sep = "")',
    'cat("OPENAI_API_KEY=", Sys.getenv("OPENAI_API_KEY", "<UNSET>"), "\\n", sep = "")',
    'cat("AWS_SECRET_ACCESS_KEY=", Sys.getenv("AWS_SECRET_ACCESS_KEY", "<UNSET>"), "\\n", sep = "")',
    'cat("PROJ_SECRET=", Sys.getenv("PROJ_SECRET", "<UNSET>"), "\\n", sep = "")',
    'cat("PROJ_RPROFILE_RAN=", Sys.getenv("PROJ_RPROFILE_RAN", "<UNSET>"), "\\n", sep = "")',
    'cat("STAGED_RENVIRON=", file.exists(".Renviron"), "\\n", sep = "")',
    'cat("STAGED_DOT_ENV=", file.exists(".env"), "\\n", sep = "")',
    'cat("STAGED_RPROFILE=", file.exists(".Rprofile"), "\\n", sep = "")',
    'cat("CAN_READ_NETRC=", file.exists(file.path(Sys.getenv("HOME"), ".netrc")), "\\n", sep = "")'
  ), aud)

  withr::local_envvar(c(
    HOME = fake_home,
    R_ENVIRON_USER = custom_renviron,
    R_PROFILE_USER = file.path(proj, ".Rprofile")
  ))

  # Case 1: Host ~/.Renviron + R_ENVIRON_USER + ~/.netrc isolation
  res1 <- verify_with_script(aud, path = proj, scrub_secrets = TRUE)
  expect_true(res1$passed)
  expect_match(res1$stdout, "GITHUB_TOKEN=<UNSET>", fixed = TRUE)
  expect_match(res1$stdout, "OPENAI_API_KEY=<UNSET>", fixed = TRUE)
  expect_match(res1$stdout, "AWS_SECRET_ACCESS_KEY=<UNSET>", fixed = TRUE)
  expect_match(res1$stdout, "PROJ_SECRET=<UNSET>", fixed = TRUE)
  expect_match(res1$stdout, "PROJ_RPROFILE_RAN=<UNSET>", fixed = TRUE)
  expect_match(res1$stdout, "STAGED_RENVIRON=FALSE", fixed = TRUE)
  expect_match(res1$stdout, "STAGED_DOT_ENV=FALSE", fixed = TRUE)
  expect_match(res1$stdout, "STAGED_RPROFILE=FALSE", fixed = TRUE)
  expect_match(res1$stdout, "CAN_READ_NETRC=FALSE", fixed = TRUE)
  # Internal .rcapsule_home directory must not pollute reported artifacts
  expect_false(any(grepl("\\.rcapsule_home", res1$artifacts$path)))

  # Case 2: Standard path = "." workflow executed from project directory
  res2 <- withr::with_dir(proj, verify_with_script(aud, path = ".", scrub_secrets = TRUE))
  expect_true(res2$passed)
  expect_match(res2$stdout, "PROJ_SECRET=<UNSET>", fixed = TRUE)
  expect_match(res2$stdout, "PROJ_RPROFILE_RAN=<UNSET>", fixed = TRUE)
  expect_match(res2$stdout, "STAGED_RENVIRON=FALSE", fixed = TRUE)
  expect_match(res2$stdout, "STAGED_RPROFILE=FALSE", fixed = TRUE)

  # Case 3: verify_capsule() also maintains full isolation without reporting .rcapsule_home as extra
  writeLines(c(
    'out <- data.frame(gh = Sys.getenv("GITHUB_TOKEN", "UNSET"), prof = Sys.getenv("PROJ_RPROFILE_RAN", "UNSET"))',
    'write.csv(out, "res.csv", row.names = FALSE)'
  ), file.path(proj, "run.R"))
  utils::write.csv(data.frame(gh = "UNSET", prof = "UNSET"), file.path(proj, "res.csv"), row.names = FALSE)
  mf <- create_capsule_manifest(proj, outputs = "res.csv", entrypoint = "run.R", seed = 1L)
  vr <- verify_capsule(mf, path = proj)
  expect_identical(vr$status, "verified_exact")
  expect_false(any(grepl("\\.rcapsule_home", vr$extra_artifacts)))
})

test_that("[HIGH-2] Git remote credentials and PATs are stripped from scan, capsule.json, and bundles", {
  # Direct unit test of URL sanitizer across HTTPS PAT, user:pass, and SCP forms
  expect_identical(
    sanitize_git_remote_url("https://ghp_DUMMYSECRETTOKEN98765@github.com/org/private-repo.git"),
    "https://github.com/org/private-repo.git"
  )
  expect_identical(
    sanitize_git_remote_url("https://alice:s3cr3t@gitlab.example.com/team/proj.git"),
    "https://gitlab.example.com/team/proj.git"
  )
  expect_identical(
    sanitize_git_remote_url("git:secretpass@github.com:org/repo.git"),
    "git@github.com:org/repo.git"
  )
  expect_identical(
    sanitize_git_remote_url("git@github.com:org/repo.git"),
    "git@github.com:org/repo.git"
  )
  expect_null(sanitize_git_remote_url(NULL))

  skip_if(Sys.which("git") == "", "git binary not available")
  gdir <- withr::local_tempdir()
  writeLines("x <- 1", file.path(gdir, "run.R"))
  withr::with_dir(gdir, {
    system2("git", c("init", "-q"))
    system2("git", c("config", "user.email", "test@example.com"))
    system2("git", c("config", "user.name", "Test"))
    system2("git", c("remote", "add", "origin", "https://ghp_DUMMYSECRETTOKEN98765@github.com/org/private-repo.git"))
    system2("git", c("add", "run.R"))
    system2("git", c("commit", "-q", "-m", "init"))
  })

  sc <- scan_project(gdir)
  expect_identical(sc$git$remote, "https://github.com/org/private-repo.git")
  expect_false(grepl("ghp_DUMMYSECRETTOKEN98765", sc$git$remote, fixed = TRUE))

  m <- create_capsule_manifest(gdir, output = file.path(gdir, "capsule.json"))
  zip_out <- file.path(withr::local_tempdir(), "supplement.zip")
  export_capsule_bundle(gdir, output = zip_out, manifest = m)
  uz <- withr::local_tempdir()
  zip::unzip(zip_out, exdir = uz)
  json_txt <- paste(readLines(file.path(uz, "capsule.json")), collapse = "\n")
  expect_false(grepl("ghp_DUMMYSECRETTOKEN98765", json_txt, fixed = TRUE))
  expect_match(json_txt, "https://github.com/org/private-repo.git", fixed = TRUE)
})

test_that("[HIGH-3] compare_artifacts() detects duplicate CSV columns, char matrix dims, factor levels, attrs, and JSON {} vs []", {
  td <- withr::local_tempdir()

  # 1. Duplicate CSV column names with divergent values in 2nd column
  f1 <- file.path(td, "dup1.csv")
  f2 <- file.path(td, "dup2.csv")
  writeLines(c("a,a", "1,100", "2,200"), f1)
  writeLines(c("a,a", "1,999999", "2,-999999"), f2)
  res_dup <- compare_artifacts(f1, f2, abs_tol = 1e-6)
  expect_false(res_dup$passed)
  expect_gt(res_dup$max_abs_diff, 1e5)

  # 2. Non-numeric matrix dimensions (2x2 vs 4x1 character matrix)
  ra <- file.path(td, "a.rds")
  rb <- file.path(td, "b.rds")
  saveRDS(matrix(c("a", "b", "c", "d"), 2L, 2L), ra)
  saveRDS(matrix(c("a", "b", "c", "d"), 4L, 1L), rb)
  expect_false(compare_artifacts(ra, rb, abs_tol = 1e-6, ignore_attributes = FALSE)$passed)

  # 3. Factor with reversed reference levels and ordered vs unordered
  saveRDS(data.frame(g = factor(c("a", "b"), levels = c("a", "b"))), ra)
  saveRDS(data.frame(g = factor(c("a", "b"), levels = c("b", "a"))), rb)
  expect_false(compare_artifacts(ra, rb, abs_tol = 1e-6, ignore_attributes = FALSE)$passed)

  saveRDS(data.frame(g = factor(c("a", "b"), ordered = FALSE)), ra)
  saveRDS(data.frame(g = factor(c("a", "b"), ordered = TRUE)), rb)
  expect_false(compare_artifacts(ra, rb, abs_tol = 1e-6, ignore_attributes = FALSE)$passed)

  # 4. Data frame row.names, named character vector names, POSIXct tzone, S3 list class
  saveRDS(data.frame(x = 1:2, row.names = c("r1", "r2")), ra)
  saveRDS(data.frame(x = 1:2, row.names = c("x1", "x2")), rb)
  expect_false(compare_artifacts(ra, rb, abs_tol = 1e-6, ignore_attributes = FALSE)$passed)

  saveRDS(c(a = "x", b = "y"), ra)
  saveRDS(c(p = "x", q = "y"), rb)
  expect_false(compare_artifacts(ra, rb, abs_tol = 1e-6, ignore_attributes = FALSE)$passed)

  t_utc <- as.POSIXct("2026-01-01 12:00:00", tz = "UTC")
  t_est <- as.POSIXct("2026-01-01 12:00:00", tz = "UTC")
  attr(t_est, "tzone") <- "America/New_York"
  saveRDS(t_utc, ra)
  saveRDS(t_est, rb)
  expect_false(compare_artifacts(ra, rb, abs_tol = 1e-6, ignore_attributes = FALSE)$passed)

  saveRDS(structure(list(x = 1), class = "classA"), ra)
  saveRDS(structure(list(x = 1.00001), class = "classB"), rb)
  expect_false(compare_artifacts(ra, rb, abs_tol = 1e-3, ignore_attributes = FALSE)$passed)

  # 5. JSON {} vs [] distinction
  j1 <- file.path(td, "obj.json")
  j2 <- file.path(td, "arr.json")
  writeLines("{}", j1)
  writeLines("[]", j2)
  expect_false(compare_artifacts(j1, j2, abs_tol = 1e-6)$passed)
})

test_that("[HIGH-4] PCRE trailing newline bypass is rejected across all validators and SBOM", {
  expect_false(is_valid_r_pkg_name("jsonlite\n"))
  expect_error(validate_r_package_names("jsonlite\n"), "Invalid or unsafe R package")
  expect_error(validate_apt_package_names("libcurl4\n"), "Invalid or unsafe apt")
  expect_error(validate_python_package_specs("numpy\n"), "Invalid or unsafe Python")
  expect_error(validate_env_vars(stats::setNames(list("1"), "FOO\n")), "control character|Invalid environment")

  td <- withr::local_tempdir()
  writeLines("x <- 1", file.path(td, "run.R"))
  expect_error(
    compile_dockerfile(scan_project(td, custom_sysreqs = list(mypkg = "libcurl4\n"))),
    "Invalid or unsafe apt"
  )
  expect_error(
    compile_compose(td, env_vars = stats::setNames(list("1"), "FOO\n")),
    "control character|Invalid environment"
  )
  expect_error(
    export_sbom(td, serial_number = "urn:uuid:12345678-1234-4123-8123-123456789abc\n"),
    "UUID URN"
  )

  sb <- export_sbom(td)
  bom_nl <- sb$bom
  bom_nl$serialNumber <- paste0(bom_nl$serialNumber, "\n")
  bom_nl$metadata$timestamp <- paste0(bom_nl$metadata$timestamp, "\n")
  bom_nl$components[[1L]]$purl <- paste0(bom_nl$components[[1L]]$purl, "\n")
  val_nl <- validate_sbom(bom_nl)
  expect_false(val_nl$valid)
  expect_true(all(c("CDX003", "CDX006", "CDX014") %in% val_nl$issues$rule))
})

test_that("[HIGH-5] as_apptainer_spec() and compile_apptainer() expose full HPC interop schema and respect all overrides", {
  td <- withr::local_tempdir()
  writeLines(c("library(jsonlite)", 'cat("ok\\n")'), file.path(td, "run.R"))

  # 1. Default as_apptainer_spec(dir) provides rcapsule class, binds, content_digest, and sif_path
  sp_dir <- as_apptainer_spec(td)
  expect_s3_class(sp_dir, c("rcapsule_apptainer_spec", "rcapsule"))
  expect_identical(sp_dir$binds, sp_dir$bind_paths)
  expect_identical(sp_dir$content_digest, sp_dir$def_sha256)
  expect_true(is.character(sp_dir$sif_path) && nzchar(sp_dir$sif_path) && grepl("\\.sif$", sp_dir$sif_path))

  # 2. compile_apptainer() exposes def_path, sif_path, binds, r_version, and content_digest
  def_file <- file.path(td, "Apptainer.def")
  app_w <- compile_apptainer(td, output = def_file)
  expect_identical(app_w$def_path, app_w$path)
  expect_true(grepl("\\.sif$", app_w$sif_path))
  expect_identical(app_w$content_digest, app_w$def_sha256)
  expect_true(length(app_w$binds) >= 1L)
  expect_true(nzchar(app_w$r_version))

  # 3. Overrides in as_apptainer_spec() apply cran_repo, quarto_version, cmdstan_version AND preserve def_path
  sp_ov1 <- as_apptainer_spec(app_w, cran_repo = "https://packagemanager.posit.co/cran/2025-06-01")
  expect_match(sp_ov1$def_content, "2025-06-01", fixed = TRUE)
  expect_identical(sp_ov1$def_path, app_w$path)

  sp_ov2 <- as_apptainer_spec(app_w, r_version = "4.4.0")
  expect_identical(sp_ov2$r_version, "4.4.0")
  expect_match(sp_ov2$base_image, "4.4.0", fixed = TRUE)
  expect_identical(sp_ov2$def_path, app_w$path)

  # 4. output override writes updated recipe to disk
  def_alt <- file.path(td, "Apptainer_custom.def")
  sp_ov3 <- as_apptainer_spec(app_w, r_version = "4.4.2", output = def_alt)
  expect_true(file.exists(def_alt))
  expect_identical(sp_ov3$def_path, as.character(fs::path_norm(def_alt)))
  expect_identical(basename(sp_ov3$sif_path), "Apptainer_custom.sif")
})

test_that("[HIGH-6] Docker verification rejects CLI flag injection in docker_image/docker_tag and hardens docker run argv", {
  td <- withr::local_tempdir()
  writeLines("FROM rocker/r-ver:4.4.1", file.path(td, "Dockerfile"))
  mock_run <- function(command, args, timeout, error_on_status) {
    list(status = 0L, stdout = "", stderr = "")
  }

  expect_error(
    run_in_docker(
      td, td,
      docker_image = "--privileged", docker_tag = NULL,
      seed = 1L, env_vars = list(), timeout = 10,
      runner_fn = mock_run, check_available = function() TRUE
    ),
    "Invalid or unsafe container image"
  )
  expect_error(
    run_in_docker(
      td, td,
      docker_image = NULL, docker_tag = "--network=host",
      seed = 1L, env_vars = list(), timeout = 10,
      runner_fn = mock_run, check_available = function() TRUE
    ),
    "Invalid or unsafe container image"
  )
  expect_error(
    build_docker_run_args("/tmp/bad:dir", "rocker/r-ver:4.4.1", seed = 1L),
    "Unsafe ':' character"
  )
  expect_error(
    build_docker_run_args("C:\\Users\\bad:dir\\box", "rocker/r-ver:4.4.1", seed = 1L),
    "Unsafe ':' character"
  )
  # Valid Windows drive-letter prefix (C:\...) is permitted and slash-normalized for Docker Desktop
  argv_win <- build_docker_run_args("C:\\Users\\RUNNER~1\\Temp\\box", "rocker/r-ver:4.4.1", seed = 42L)
  expect_true("C:/Users/RUNNER~1/Temp/box:/capsule" %in% argv_win)

  argv <- build_docker_run_args(td, "rocker/r-ver:4.4.1", seed = 42L)
  expect_true("--network=none" %in% argv)
  expect_true("--cap-drop=ALL" %in% argv)
  expect_true("--security-opt=no-new-privileges:true" %in% argv)
  expect_true("--vanilla" %in% argv)
})

test_that("[HIGH-7] AST scanner parses higher-order namespaced calls like scales::col_numeric(...)(0.5)", {
  td <- withr::local_tempdir()
  writeLines(c(
    'pal <- scales::col_numeric("Blues", c(0, 1))(0.5)',
    'fn <- purrr::partial(mean, na.rm = TRUE)(1:5)'
  ), file.path(td, "run.R"))
  sc <- scan_project(td)
  expect_true("scales" %in% sc$packages$package)
  expect_true("purrr" %in% sc$packages$package)
})

test_that("[MEDIUM-1] Ambient secret scrubbing catches all 18 expanded credential/DSN env var patterns", {
  secrets <- c(
    MY_APIKEY = "v", DB_PASS = "v", PROD_DATABASE_URL = "v", POSTGRES_URL = "v",
    REDIS_URL = "v", MONGO_URI = "v", SSH_KEY = "v", HMAC_KEY = "v",
    PGPASSFILE = "v", NETRC = "v", AUTHORIZATION = "v", JWT_VALUE = "v",
    S3_KEY = "v", COHERE_APIKEY = "v", GROQ_KEY = "v", KUBECONFIG = "v",
    CONN_STR = "v", PAT_GITHUB = "v"
  )
  expect_true(all(is_secret_env_var(names(secrets))))

  withr::local_envvar(secrets)
  sdir <- withr::local_tempdir()
  aud <- file.path(withr::local_tempdir(), "check_secrets.R")
  writeLines(c(
    sprintf("nms <- %s", paste(deparse(names(secrets)), collapse = "")),
    'vals <- Sys.getenv(nms, unset = "<SCRUBBED>")',
    'cat(sum(vals != "<SCRUBBED>"), "\\n")'
  ), aud)
  res <- verify_with_script(aud, path = sdir, scrub_secrets = TRUE)
  expect_true(res$passed)
  expect_identical(trimws(res$stdout), "0")
  expect_true(all(names(secrets) %in% res$scrubbed_env))
})

test_that("[MEDIUM-2] compile_compose() and lint_container_spec() reject/flag dangerous and malformed volume mounts", {
  td <- withr::local_tempdir()
  writeLines("x <- 1", file.path(td, "run.R"))
  bad_vols <- c(
    "//:/host:rw",
    "/etc:/host_etc:rw",
    "/root:/host_root:rw",
    "/var/run/docker.sock/:/sock:rw",
    "./data::ro",
    "./data:relative_dst:ro",
    "./data:/capsule/data:exec"
  )
  for (v in bad_vols) {
    expect_error(compile_compose(td, volumes = v), info = paste("Failed to reject volume:", v))
  }

  # Linter DC009 also catches // and /var/run/docker.sock/
  yaml_bad <- c(
    "services:",
    "  app:",
    "    image: myimg:1.0.0",
    "    volumes:",
    "      - //:/host:rw",
    "      - /var/run/docker.sock/:/sock:rw"
  )
  lr <- lint_container_spec(yaml_bad, type = "compose")
  expect_true("DC009" %in% lr$issues$rule_id)
  expect_gte(sum(lr$issues$rule_id == "DC009"), 2L)
})

test_that("[MEDIUM-3] Registry port prefix (localhost:5000/img) does not bypass image tag pinning", {
  expect_false(has_pinned_image_tag_or_digest("localhost:5000/caddy"))
  expect_false(has_pinned_image_tag_or_digest("localhost:5000/caddy:latest"))
  expect_true(has_pinned_image_tag_or_digest("localhost:5000/caddy:2.8.4"))
  expect_true(has_pinned_image_tag_or_digest(paste0("localhost:5000/caddy@sha256:", strrep("a", 64L))))

  td <- withr::local_tempdir()
  writeLines(c("library(shiny)", 'shinyApp(fluidPage("hi"), function(i, o) {})'), file.path(td, "app.R"))
  expect_error(compile_compose(td, proxy_image = "localhost:5000/caddy"), "pinned tag")

  comp_ok <- compile_compose(td, proxy_image = "localhost:5000/caddy:2.8.4")
  expect_true(lint_container_spec(comp_ok)$passed)

  l_dc <- lint_container_spec(
    c("services:", "  app:", "    image: localhost:5000/myimg"),
    type = "compose"
  )
  expect_false(l_dc$passed)
  expect_true("DC002" %in% l_dc$issues$rule_id)

  l_ap <- lint_container_spec(
    c("Bootstrap: docker", "From: localhost:5000/myimage", "%runscript", "  R"),
    type = "apptainer"
  )
  expect_false(l_ap$passed)
  expect_true("AP002" %in% l_ap$issues$rule_id)
})

test_that("[MEDIUM-4] compile_compose() aborts on service_name collisions with worker or proxy", {
  td <- withr::local_tempdir()
  writeLines(c("library(shiny)", 'shinyApp(fluidPage("hi"), function(i, o) {})'), file.path(td, "app.R"))
  expect_error(compile_compose(td, service_name = "worker"), "cannot be.*worker")
  expect_error(compile_compose(td, service_name = "proxy"), "cannot be.*proxy")

  # Allowed when the conflicting companion service is disabled
  expect_true("worker" %in% compile_compose(td, service_name = "worker", include_worker = FALSE)$services)
  expect_true("proxy" %in% compile_compose(td, service_name = "proxy", include_proxy = FALSE)$services)
})

test_that("[MEDIUM-5] Backtick code-span breakout and HTML tags are escaped in certificates and README_REPRODUCE.md", {
  # Direct sanitizer checks run on every OS (including Windows where '<'/'>'/':' are illegal in filenames)
  raw_payload <- "out`[link](javascript:alert(1))`<img src=x>.csv"
  esc_inline <- sanitize_markdown_inline(raw_payload)
  esc_cell <- sanitize_markdown_cell(paste0(raw_payload, "|col"))
  expect_false(grepl("<img src=x>", esc_inline, fixed = TRUE))
  expect_match(esc_inline, "&lt;img src=x&gt;", fixed = TRUE)
  expect_match(esc_inline, "&#96;", fixed = TRUE)
  expect_false(grepl("`", esc_inline, fixed = TRUE))
  expect_false(grepl("<img src=x>", esc_cell, fixed = TRUE))
  expect_match(esc_cell, "\\\\|", perl = TRUE)
  expect_match(esc_cell, "&#96;", fixed = TRUE)

  # Cross-platform end-to-end test using a filename valid on Windows NTFS, macOS APFS, and Linux ext4
  td <- withr::local_tempdir()
  bad_win <- "out`[link](bad)`.csv"
  writeLines(sprintf("write.csv(data.frame(x = 1), %s, row.names = FALSE)", deparse(bad_win)), file.path(td, "run.R"))
  utils::write.csv(data.frame(x = 1), file.path(td, bad_win), row.names = FALSE)

  m <- create_capsule_manifest(td, outputs = bad_win, entrypoint = "run.R", seed = 1L)
  v <- verify_capsule(m, path = td)
  cert <- render_certificate(v, format = "both")

  expect_false(grepl("`out`\\[link\\]", cert$markdown, perl = TRUE))
  expect_match(cert$markdown, "&#96;", fixed = TRUE)

  exp_dir <- file.path(withr::local_tempdir(), "bundle_out")
  export_capsule_bundle(td, output = exp_dir, format = "dir", manifest = m, verification = v)
  readme <- paste(readLines(file.path(exp_dir, "README_REPRODUCE.md")), collapse = "\n")
  expect_match(readme, "&#96;", fixed = TRUE)

  # Full HTML-tag filename round-trip on POSIX filesystems (NTFS forbids '<', '>', ':' in filenames)
  if (!identical(.Platform$OS.type, "windows")) {
    td_posix <- withr::local_tempdir()
    writeLines(sprintf("write.csv(data.frame(x = 1), %s, row.names = FALSE)", deparse(raw_payload)), file.path(td_posix, "run.R"))
    utils::write.csv(data.frame(x = 1), file.path(td_posix, raw_payload), row.names = FALSE)

    m_p <- create_capsule_manifest(td_posix, outputs = raw_payload, entrypoint = "run.R", seed = 1L)
    v_p <- verify_capsule(m_p, path = td_posix)
    cert_p <- render_certificate(v_p, format = "both")
    expect_false(grepl("<img src=x>", cert_p$markdown, fixed = TRUE))
    expect_match(cert_p$markdown, "&#96;", fixed = TRUE)

    exp_p <- file.path(withr::local_tempdir(), "bundle_posix")
    export_capsule_bundle(td_posix, output = exp_p, format = "dir", manifest = m_p, verification = v_p)
    readme_p <- paste(readLines(file.path(exp_p, "README_REPRODUCE.md")), collapse = "\n")
    expect_false(grepl("<img src=x>", readme_p, fixed = TRUE))
    expect_match(readme_p, "&lt;img src=x&gt;", fixed = TRUE)
    expect_match(readme_p, "&#96;", fixed = TRUE)
  }
})

test_that("[MEDIUM-6] export_sbom() handles PEP 508 markers & VCS URLs cleanly and validate_sbom() handles atomic JSON arrays", {
  td <- withr::local_tempdir()
  writeLines(c(
    'numpy >= 1.24; python_version >= "3.9"',
    "git+https://github.com/org/repo.git",
    "git+https://github.com/org/other.git@v1.2.3#egg=custom_pkg",
    "my-direct @ https://example.org/pkg-1.0.tar.gz",
    "; only_marker"
  ), file.path(td, "requirements.txt"))
  writeLines("x <- 1", file.path(td, "run.R"))

  sb <- export_sbom(td)
  val <- validate_sbom(sb)
  expect_true(val$valid)
  expect_identical(val$n_errors, 0L)
  comp_names <- vapply(sb$bom$components, `[[`, character(1L), "name")
  expect_true(all(c("numpy", "repo", "custom_pkg", "my-direct") %in% comp_names))

  bad_bom <- list(
    bomFormat = "CycloneDX",
    specVersion = "1.5",
    serialNumber = "urn:uuid:12345678-1234-4123-8123-123456789abc",
    version = 1L,
    metadata = list(
      timestamp = "2026-01-01T00:00:00Z",
      tools = list(),
      component = list(type = "application", name = "p", `bom-ref` = "p")
    ),
    components = list(list(type = "library", name = "x", `bom-ref` = "x", hashes = list("atomic"))),
    dependencies = list("atomic")
  )
  val_bad <- validate_sbom(bad_bom)
  expect_false(val_bad$valid)
  expect_true(all(c("CDX015", "CDX016") %in% val_bad$issues$rule))
})

test_that("[LOW-1] parse_renv_lock() ignores atomic entries and compile_dockerfile() skips .Rprofile with secrets", {
  td <- withr::local_tempdir()
  writeLines('{"R":{"Version":"4.4.1"},"Packages":{"bad":"not_a_list","jsonlite":{"Package":"jsonlite","Version":"1.8.8","Source":"Repository","Repository":"CRAN"}}}', file.path(td, "renv.lock"))
  writeLines("x <- 1", file.path(td, "run.R"))
  sc_atomic <- scan_project(td)
  expect_true("jsonlite" %in% sc_atomic$packages$package)
  expect_false("bad" %in% sc_atomic$packages$package)

  writeLines('{"R":{"Version":"4.4.1"},"Packages":{}}', file.path(td, "renv.lock"))
  writeLines('Sys.setenv(OPENAI_API_KEY = "sk-dummy12345")', file.path(td, ".Rprofile"))
  sc_sec <- scan_project(td)
  expect_true("secret_in_rprofile" %in% sc_sec$rprofile_hazards$hazard)
  expect_warning(
    df <- compile_dockerfile(sc_sec),
    "Skipping.*COPY \\.Rprofile"
  )
  expect_false(any(grepl("^COPY \\.Rprofile", df$lines)))
  expect_true(any(grepl("Skipped COPY \\.Rprofile", df$lines)))
})

test_that("[LOW-2] verify_with_script() accepts named character env_vars + args with zero warnings", {
  td <- withr::local_tempdir()
  aud <- file.path(withr::local_tempdir(), "check_env_args.R")
  writeLines(c(
    'cat("FOO=", Sys.getenv("FOO"), "\\n", sep = "")',
    'cat("ARGS=", Sys.getenv("RCAPSULE_AUDIT_ARGS"), "\\n", sep = "")'
  ), aud)
  res <- expect_no_warning(
    verify_with_script(aud, path = td, env_vars = c(FOO = "bar"), args = c("--mode", "fast"))
  )
  expect_true(res$passed)
  expect_match(res$stdout, "FOO=bar", fixed = TRUE)
  expect_match(res$stdout, "--mode", fixed = TRUE)
})
