test_that("sysreqs_db returns curated registry with expected columns and key packages", {
  db <- sysreqs_db()
  expect_s3_class(db, "tbl_df")
  expect_named(db, c("package", "apt_build", "apt_runtime", "toolchain", "notes"))
  expect_true(all(c("sf", "xml2", "curl", "ragg", "haven", "Rcpp", "cmdstanr", "RTMB", "rjags", "rextendr", "reticulate") %in% db$package))
})

test_that("resolve_sysreqs resolves built-in, DESCRIPTION SystemRequirements, and custom overrides", {
  res <- resolve_sysreqs(
    packages = c("sf", "xml2", "curl", "ragg", "haven", "cmdstanr", "rjags", "RTMB"),
    system_requirements = c("C++17, Cargo (rustc), GNU make"),
    custom_sysreqs = list(custompkg = c("libcustom-dev", "libcurl4-openssl-dev"))
  )

  expect_s3_class(res, "tbl_df")
  expect_named(res, c("apt_package", "stage", "required_by", "source"))

  build_pkgs <- res$apt_package[res$stage == "build"]
  runtime_pkgs <- res$apt_package[res$stage == "runtime"]

  expect_true(all(c(
    "libgdal-dev", "libgeos-dev", "libproj-dev", "libudunits2-dev",
    "libxml2-dev", "libcurl4-openssl-dev", "libssl-dev",
    "libfreetype6-dev", "libharfbuzz-dev", "zlib1g-dev",
    "build-essential", "g++", "gfortran", "jags", "libjags-dev",
    "cargo", "rustc", "libcustom-dev"
  ) %in% build_pkgs))

  expect_true(all(c("libgdal30", "libxml2", "libcurl4", "jags", "libcustom-dev") %in% runtime_pkgs))

  # Deduplication: libcurl4-openssl-dev should appear once in build stage with merged sources
  curl_build <- res[res$apt_package == "libcurl4-openssl-dev" & res$stage == "build", ]
  expect_equal(nrow(curl_build), 1L)
  expect_match(curl_build$source, "builtin_db")
  expect_match(curl_build$source, "custom")
})

test_that("resolve_sysreqs handles empty input and validates custom_sysreqs", {
  empty <- resolve_sysreqs(character())
  expect_equal(nrow(empty), 0L)

  expect_error(
    resolve_sysreqs("dplyr", custom_sysreqs = c("libfoo-dev")),
    "named list"
  )
})
