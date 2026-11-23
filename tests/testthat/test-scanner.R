test_that("scan_project accurately parses R scripts, renv.lock, and sysreqs", {
  dir <- make_analysis_fixture()
  sc <- scan_project(dir)

  expect_s3_class(sc, "rcapsule_scan")
  expect_equal(sc$project_type, "analysis")
  expect_equal(sc$r_version, "4.4.1")
  expect_true(sc$has_renv)
  expect_equal(sc$entrypoint, "analysis.R")
  expect_equal(sc$seeds_detected, 2026L)

  pkgs <- sc$packages$package
  expect_true(all(c("dplyr", "haven", "sf", "xml2", "curl", "ragg", "jsonlite") %in% pkgs))
  # Commented out package and character.only variable must NOT be detected
  expect_false("commented_out_pkg" %in% pkgs)
  expect_false("pkg_var" %in% pkgs)
  # Base package stats detected from ::: is marked is_base = TRUE
  expect_true(sc$packages$is_base[sc$packages$package == "stats"])

  # renv.lock versions propagated
  expect_equal(sc$packages$version[sc$packages$package == "sf"], "1.0-16")

  # OS sysreqs resolved for sf, xml2, curl, ragg, haven
  build_apt <- sc$sysreqs$apt_package[sc$sysreqs$stage == "build"]
  expect_true(all(c("libgdal-dev", "libxml2-dev", "libcurl4-openssl-dev", "libfreetype6-dev", "zlib1g-dev") %in% build_apt))

  # Print and summary methods run cleanly
  expect_invisible(print(sc))
  sm <- summary(sc)
  expect_equal(sm$project_type, "analysis")
  expect_true(sm$has_renv)
})

test_that("scan_project parses Quarto manuscripts, YAML formats, Python/Stan chunks, and requirements.txt", {
  dir <- make_quarto_fixture()
  sc <- scan_project(dir)

  expect_equal(sc$project_type, "quarto")
  expect_true(sc$has_quarto_yml)
  expect_equal(sc$quarto_project_type, "manuscript")
  expect_equal(sc$entrypoint, "manuscript.qmd")
  expect_equal(sc$seeds_detected, 101L)

  pkgs <- sc$packages$package
  expect_true(all(c("ggplot2", "ragg", "scales") %in% pkgs))

  expect_true(sc$toolchains$quarto$detected)
  expect_true(sc$toolchains$latex$detected)
  expect_true(sc$toolchains$python$detected)
  expect_true(sc$toolchains$cmdstan$detected)
  expect_true(sc$toolchains$cpp$detected)
  expect_true(all(c("numpy", "scipy", "numpy==1.26.4", "scipy==1.13.0") %in% sc$python_packages))
})

test_that("scan_project detects Shiny applications and async workers", {
  dir <- make_shiny_fixture()
  sc <- scan_project(dir)

  expect_equal(sc$project_type, "shiny")
  expect_equal(sc$entrypoint, "app.R")
  expect_true(sc$shiny_async)
  expect_true(all(c("shiny", "bslib", "promises", "mirai") %in% sc$packages$package))

  # Also test ui.R + server.R layout
  dir2 <- withr::local_tempdir()
  writeLines("library(shiny)\nfluidPage('Hello')", file.path(dir2, "ui.R"))
  writeLines("function(input, output, session) {}", file.path(dir2, "server.R"))
  sc2 <- scan_project(dir2)
  expect_equal(sc2$project_type, "shiny")
  expect_false(sc2$shiny_async)
})

test_that("scan_project detects CmdStan, RTMB, JAGS, C++, Rust, and reticulate toolchains", {
  dir <- make_compiled_fixture()
  sc <- scan_project(dir)

  expect_true(sc$toolchains$cmdstan$detected)
  expect_true(sc$toolchains$tmb$detected)
  expect_true(sc$toolchains$jags$detected)
  expect_true(sc$toolchains$cpp$detected)
  expect_true(sc$toolchains$rust$detected)
  expect_true(sc$toolchains$python$detected)
  expect_true("numpy" %in% sc$python_packages)

  build_apt <- sc$sysreqs$apt_package[sc$sysreqs$stage == "build"]
  expect_true(all(c("build-essential", "g++", "gfortran", "jags", "libjags-dev", "cargo", "rustc", "python3") %in% build_apt))
})

test_that("scan_project inspects R package DESCRIPTION, LinkingTo, and SystemRequirements", {
  dir <- make_package_fixture()
  sc <- scan_project(dir)

  expect_equal(sc$project_type, "package")
  expect_equal(sc$project_name, "demopkg")
  expect_true(sc$has_description)
  expect_true(sc$toolchains$cpp$detected)
  expect_true(all(c("xml2", "jsonlite", "Rcpp", "testthat") %in% sc$packages$package))
  # Suggests marked required = FALSE, Imports marked required = TRUE
  expect_true(sc$packages$required[sc$packages$package == "xml2"])
  expect_false(sc$packages$required[sc$packages$package == "testthat"])
  # SystemRequirements GDAL mapped to libgdal-dev
  expect_true("libgdal-dev" %in% sc$sysreqs$apt_package)
})

test_that("scan_project falls back gracefully on syntactically incomplete R scripts", {
  dir <- withr::local_tempdir()
  writeLines(c("library(jsonlite)", "x <- tibble::tibble(a = 1", "# missing closing paren"),
             file.path(dir, "broken.R"))
  sc <- scan_project(dir)
  expect_true(all(c("jsonlite", "tibble") %in% sc$packages$package))
})

test_that("scan_project handles R Markdown PDF reports and exclude directories", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "scratch_ignore"))
  writeLines("library(ignoredpkg)", file.path(dir, "scratch_ignore", "draft.R"))
  writeLines(
    c(
      "---",
      "title: 'Annual Report'",
      "output: pdf_document",
      "---",
      "",
      "```{r}",
      "library(rmarkdown)",
      "x <- tibble::tibble(a = 1)",
      "```"
    ),
    file.path(dir, "report.Rmd")
  )

  sc <- scan_project(dir, exclude = "scratch_ignore")
  expect_equal(sc$project_type, "rmarkdown")
  expect_equal(sc$entrypoint, "report.Rmd")
  expect_true(sc$toolchains$latex$detected)
  expect_true(all(c("rmarkdown", "tibble") %in% sc$packages$package))
  expect_false("ignoredpkg" %in% sc$packages$package)
})
