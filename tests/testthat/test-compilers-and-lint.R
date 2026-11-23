test_that("compile_dockerfile builds clean multi-stage Dockerfiles that pass lint with 0 issues", {
  # Analysis with renv.lock + sf/xml2/curl/ragg/haven
  dir_a <- make_analysis_fixture()
  df_a <- compile_dockerfile(dir_a, output = file.path(dir_a, "Dockerfile"))
  expect_s3_class(df_a, "rcapsule_dockerfile")
  expect_s3_class(df_a, "rcapsule_spec")
  expect_true(file.exists(df_a$path))
  expect_match(df_a$content, "FROM rocker/r-ver:4.4.1 AS builder", fixed = TRUE)
  expect_match(df_a$content, "FROM rocker/r-ver:4.4.1 AS runtime", fixed = TRUE)
  expect_match(df_a$content, "COPY renv.lock ./", fixed = TRUE)
  expect_match(df_a$content, "renv::restore", fixed = TRUE)
  expect_match(df_a$content, "USER capsule", fixed = TRUE)
  expect_match(df_a$content, "HEALTHCHECK", fixed = TRUE)
  expect_match(df_a$content, "libgdal-dev", fixed = TRUE)

  l_a <- lint_container_spec(df_a)
  expect_true(l_a$passed)
  expect_equal(l_a$n_errors, 0L)
  expect_equal(l_a$n_warnings, 0L)
  expect_equal(l_a$n_info, 0L)

  # Digest pinning works and :latest is rejected
  digest_hex <- paste(rep("a", 64), collapse = "")
  df_dig <- compile_dockerfile(dir_a, base_digest = digest_hex)
  expect_match(df_dig$content, paste0("rocker/r-ver:4.4.1@sha256:", digest_hex), fixed = TRUE)
  expect_error(compile_dockerfile(dir_a, base_image = "rocker/r-ver:latest"), "Unpinned base image")

  # Quarto + LaTeX + Python + Stan fixture
  dir_q <- make_quarto_fixture()
  df_q <- compile_dockerfile(dir_q, r_version = "4.4.1")
  expect_match(df_q$content, "QUARTO_VERSION=", fixed = TRUE)
  expect_match(df_q$content, "TINYTEX_DIR=/opt/TinyTeX", fixed = TRUE)
  expect_match(df_q$content, "VIRTUAL_ENV=/opt/venv", fixed = TRUE)
  expect_match(df_q$content, "CMDSTAN=", fixed = TRUE)
  expect_match(df_q$content, 'CMD ["quarto", "render"]', fixed = TRUE)
  l_q <- lint_container_spec(df_q)
  expect_true(l_q$passed)
  expect_equal(l_q$n_warnings, 0L)

  # Shiny fixture
  dir_s <- make_shiny_fixture()
  df_s <- compile_dockerfile(dir_s, r_version = "4.4.1")
  expect_match(df_s$content, "EXPOSE 3838", fixed = TRUE)
  expect_match(df_s$content, "shiny::runApp", fixed = TRUE)
  expect_true(lint_container_spec(df_s)$passed)

  # Single-stage mode also passes lint cleanly
  df_single <- compile_dockerfile(dir_a, multi_stage = FALSE)
  expect_equal(df_single$stages, "single")
  l_single <- lint_container_spec(df_single)
  expect_true(l_single$passed)
  expect_equal(l_single$n_warnings, 0L)

  # Compiled Bayesian/Rust/JAGS fixture
  dir_c <- make_compiled_fixture()
  df_c <- compile_dockerfile(dir_c, r_version = "4.4.1")
  expect_match(df_c$content, "CARGO_HOME=/opt/cargo", fixed = TRUE)
  expect_match(df_c$content, "jags", fixed = TRUE)
  expect_match(df_c$content, "CMDSTAN=", fixed = TRUE)
  expect_true(lint_container_spec(df_c)$passed)

  # Package fixture
  dir_p <- make_package_fixture()
  df_p <- compile_dockerfile(dir_p, r_version = "4.4.1")
  expect_match(df_p$content, "R CMD INSTALL", fixed = TRUE)
  expect_true(lint_container_spec(df_p)$passed)
})

test_that("compile_compose generates validated Shiny multi-service and batch stacks", {
  # Shiny stack: app + worker + pinned proxy
  dir_s <- make_shiny_fixture()
  comp_s <- compile_compose(dir_s, output = file.path(dir_s, "docker-compose.yml"))
  expect_s3_class(comp_s, "rcapsule_compose")
  expect_true(file.exists(comp_s$path))
  expect_equal(sort(comp_s$services), c("app", "proxy", "worker"))
  expect_match(comp_s$content, "caddy:2.8.4-alpine", fixed = TRUE)
  expect_match(comp_s$content, "worker.R", fixed = TRUE)
  expect_match(comp_s$content, "no-new-privileges:true", fixed = TRUE)

  l_s <- lint_container_spec(comp_s)
  expect_true(l_s$passed)
  expect_equal(l_s$n_errors, 0L)
  expect_equal(l_s$n_warnings, 0L)
  expect_equal(l_s$n_info, 0L)

  # Batch analysis stack
  dir_a <- make_analysis_fixture()
  comp_a <- compile_compose(dir_a)
  expect_length(comp_a$services, 1L)
  expect_true(lint_container_spec(comp_a)$passed)
  expect_equal(lint_container_spec(comp_a)$n_warnings, 0L)

  # Rejects :latest tags
  expect_error(compile_compose(dir_s, image_tag = "latest"), "cannot be")
  expect_error(compile_compose(dir_s, proxy_image = "caddy:latest"), "pinned tag")
})

test_that("compile_apptainer generates HPC-ready .def recipes passing lint", {
  dir_a <- make_analysis_fixture()
  def_a <- compile_apptainer(dir_a, output = file.path(dir_a, "Apptainer.def"))
  expect_s3_class(def_a, "rcapsule_apptainer")
  expect_true(file.exists(def_a$path))
  expect_match(def_a$content, "Bootstrap: docker", fixed = TRUE)
  expect_match(def_a$content, "From: rocker/r-ver:4.4.1", fixed = TRUE)
  expect_match(def_a$content, "%post", fixed = TRUE)
  expect_match(def_a$content, "set -euo pipefail", fixed = TRUE)
  expect_match(def_a$content, "%environment", fixed = TRUE)
  expect_match(def_a$content, "%runscript", fixed = TRUE)
  expect_match(def_a$content, "%test", fixed = TRUE)
  expect_match(def_a$content, "mkdir -p /scratch /work /data", fixed = TRUE)

  l_a <- lint_container_spec(def_a)
  expect_true(l_a$passed)
  expect_equal(l_a$n_errors, 0L)
  expect_equal(l_a$n_warnings, 0L)
  expect_equal(l_a$n_info, 0L)

  # Quarto + CmdStan Apptainer recipe
  dir_q <- make_quarto_fixture()
  def_q <- compile_apptainer(dir_q, r_version = "4.4.1")
  expect_match(def_q$content, "quarto --version", fixed = TRUE)
  expect_match(def_q$content, "CMDSTAN=", fixed = TRUE)
  expect_true(lint_container_spec(def_q)$passed)
})

test_that("compiled Dockerfile, Compose, and Apptainer specs match snapshots", {
  base_tmp <- withr::local_tempdir()
  proj_dir <- file.path(base_tmp, "clinical-trial-app")
  dir.create(proj_dir)
  make_shiny_fixture(proj_dir)

  df <- compile_dockerfile(proj_dir, r_version = "4.4.1")
  comp <- compile_compose(proj_dir)
  def <- compile_apptainer(proj_dir, r_version = "4.4.1")

  expect_snapshot(cat(df$content))
  expect_snapshot(cat(comp$content))
  expect_snapshot(cat(def$content))
})

test_that("lint_container_spec catches security and reproducibility anti-patterns across all 3 formats", {
  # Bad Dockerfile triggering DF001, DF002, DF003, DF004, DF005, DF006, DF007, DF008, DF009, DF010
  bad_df <- c(
    "FROM rocker/r-ver:latest",
    "ENV API_KEY=supersecretvalue123",
    "RUN apt-get update && apt-get install -y libcurl4-openssl-dev",
    "RUN pip install numpy",
    "ADD local_file.txt /tmp/local_file.txt",
    "COPY . /app",
    "RUN Rscript -e \"renv::restore()\"",
    "USER root"
  )
  ldf <- lint_container_spec(bad_df, type = "dockerfile")
  expect_false(ldf$passed)
  expect_true(all(c("DF001", "DF002", "DF003", "DF004", "DF005", "DF006", "DF007", "DF008", "DF009", "DF010") %in% ldf$issues$rule_id))
  expect_invisible(print(ldf))

  # Bad docker-compose.yml triggering DC002, DC003, DC004, DC005, DC006, DC007
  bad_compose <- c(
    "services:",
    "  web:",
    "    image: rocker/shiny:latest",
    "    privileged: true",
    "    environment:",
    "      - PASSWORD=plaintextpass"
  )
  lc <- lint_container_spec(bad_compose, type = "compose")
  expect_false(lc$passed)
  expect_true(all(c("DC002", "DC003", "DC004", "DC005", "DC006", "DC007") %in% lc$issues$rule_id))

  # Invalid YAML compose triggers DC001
  lc_bad_yaml <- lint_container_spec("services: [unclosed", type = "compose")
  expect_false(lc_bad_yaml$passed)
  expect_true("DC001" %in% lc_bad_yaml$issues$rule_id)

  # Bad Apptainer.def triggering AP002, AP003, AP004, AP005, AP006
  bad_app <- c(
    "Bootstrap: docker",
    "From: rocker/r-ver:latest",
    "%post",
    "    apt-get update && apt-get install -y curl"
  )
  la <- lint_container_spec(bad_app, type = "apptainer")
  expect_false(la$passed)
  expect_true(all(c("AP002", "AP003", "AP004", "AP005", "AP006") %in% la$issues$rule_id))

  # Auto-detection from file path works
  tmp_f <- withr::local_tempfile(fileext = ".def")
  writeLines(bad_app, tmp_f)
  expect_equal(lint_container_spec(tmp_f)$spec_type, "apptainer")
})
