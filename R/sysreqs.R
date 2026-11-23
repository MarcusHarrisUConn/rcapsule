# Curated OS system dependencies (sysreqs) and compiled toolchain registry

#' Built-in OS System Dependency (sysreqs) Registry
#'
#' Returns the curated built-in mapping from R packages to Debian/Ubuntu
#' `apt` system packages, runtime-only `apt` packages, associated scientific
#' toolchains, and explanatory notes.
#'
#' @return A [tibble::tibble()] with columns `package`, `apt_build`,
#'   `apt_runtime`, `toolchain`, and `notes`.
#' @export
#' @examples
#' db <- sysreqs_db()
#' head(db)
#' db[db$package %in% c("sf", "cmdstanr", "ragg"), ]
sysreqs_db <- function() {
  entries <- list(
    # Spatial & GIS
    list("sf", c("libgdal-dev", "libgeos-dev", "libproj-dev", "libudunits2-dev", "libsqlite3-dev", "gdal-bin"),
         c("libgdal30", "libgeos-c1v5", "libproj22", "libudunits2-0", "libsqlite3-0", "gdal-bin"),
         NA_character_, "GDAL/GEOS/PROJ/UDUNITS geospatial stack"),
    list("terra", c("libgdal-dev", "libgeos-dev", "libproj-dev", "gdal-bin"),
         c("libgdal30", "libgeos-c1v5", "libproj22", "gdal-bin"),
         NA_character_, "Spatial raster/vector C++ engine"),
    list("s2", c("libssl-dev", "cmake", "build-essential"),
         c("libssl3"), "cpp", "Spherical geometry C++ library"),
    list("units", c("libudunits2-dev"), c("libudunits2-0"), NA_character_, "UDUNITS2 physical units"),
    list("lwgeom", c("libgeos-dev", "libproj-dev"), c("libgeos-c1v5", "libproj22"), NA_character_, "PostGIS lwgeom"),
    list("rgdal", c("libgdal-dev", "libproj-dev"), c("libgdal30", "libproj22"), NA_character_, "Legacy GDAL bindings"),

    # HTTP, XML, Crypto, Network
    list("curl", c("libcurl4-openssl-dev", "libssl-dev"), c("libcurl4", "libssl3"), NA_character_, "libcurl HTTP client"),
    list("httr", c("libcurl4-openssl-dev", "libssl-dev"), c("libcurl4", "libssl3"), NA_character_, "HTTP client"),
    list("httr2", c("libcurl4-openssl-dev", "libssl-dev"), c("libcurl4", "libssl3"), NA_character_, "Modern HTTP client"),
    list("xml2", c("libxml2-dev"), c("libxml2"), NA_character_, "libxml2 XML parser"),
    list("rvest", c("libxml2-dev", "libcurl4-openssl-dev"), c("libxml2", "libcurl4"), NA_character_, "Web scraping"),
    list("openssl", c("libssl-dev"), c("libssl3"), NA_character_, "OpenSSL cryptography"),
    list("sodium", c("libsodium-dev"), c("libsodium23"), NA_character_, "libsodium cryptography"),
    list("ssh", c("libssh-dev"), c("libssh-4"), NA_character_, "SSH client bindings"),
    list("gert", c("libgit2-dev", "libssh2-1-dev", "libssl-dev"), c("libgit2-1.1", "libssh2-1", "libssl3"), NA_character_, "libgit2 Git client"),
    list("git2r", c("libgit2-dev", "libssh2-1-dev", "libssl-dev"), c("libgit2-1.1", "libssh2-1", "libssl3"), NA_character_, "Git bindings"),
    list("V8", c("libnode-dev"), c("libnode72"), NA_character_, "Embedded V8 JavaScript engine"),

    # Graphics, Fonts, Documents, Imaging
    list("ragg", c("libfreetype6-dev", "libpng-dev", "libtiff5-dev", "libjpeg-dev", "libharfbuzz-dev", "libfribidi-dev"),
         c("libfreetype6", "libpng16-16", "libtiff5", "libjpeg8", "libharfbuzz0b", "libfribidi0"),
         NA_character_, "AGG high-DPI raster graphics"),
    list("systemfonts", c("libfontconfig1-dev", "libfreetype6-dev"),
         c("libfontconfig1", "libfreetype6"), NA_character_, "System font discovery"),
    list("textshaping", c("libharfbuzz-dev", "libfribidi-dev", "libfreetype6-dev"),
         c("libharfbuzz0b", "libfribidi0", "libfreetype6"), NA_character_, "Text shaping"),
    list("svglite", c("libpng-dev"), c("libpng16-16"), NA_character_, "SVG graphics device"),
    list("magick", c("libmagick++-dev", "gsfonts"), c("libmagick++-6.q16-8", "gsfonts"), NA_character_, "ImageMagick++ bindings"),
    list("pdftools", c("libpoppler-cpp-dev"), c("libpoppler-cpp0v5"), NA_character_, "Poppler PDF rendering"),
    list("Cairo", c("libcairo2-dev", "libxt-dev"), c("libcairo2", "libxt6"), NA_character_, "Cairo graphics device"),
    list("png", c("libpng-dev"), c("libpng16-16"), NA_character_, "libpng support"),
    list("jpeg", c("libjpeg-dev"), c("libjpeg8"), NA_character_, "libjpeg support"),
    list("tiff", c("libtiff5-dev"), c("libtiff5"), NA_character_, "libtiff support"),
    list("webp", c("libwebp-dev"), c("libwebp7"), NA_character_, "libwebp image IO"),

    # Data IO, Databases, Compression, Scientific Formats
    list("haven", c("zlib1g-dev"), c("zlib1g"), NA_character_, "SPSS/Stata/SAS reader"),
    list("data.table", c("zlib1g-dev"), c("zlib1g"), NA_character_, "Fast tabular engine"),
    list("arrow", c("cmake", "libssl-dev", "libcurl4-openssl-dev"), c("libssl3", "libcurl4"), "cpp", "Apache Arrow / Parquet"),
    list("RPostgres", c("libpq-dev"), c("libpq5"), NA_character_, "PostgreSQL client"),
    list("RPostgreSQL", c("libpq-dev"), c("libpq5"), NA_character_, "PostgreSQL client"),
    list("RMariaDB", c("libmariadb-dev"), c("libmariadb3"), NA_character_, "MariaDB/MySQL client"),
    list("odbc", c("unixodbc-dev"), c("unixodbc"), NA_character_, "ODBC database interface"),
    list("RODBC", c("unixodbc-dev"), c("unixodbc"), NA_character_, "ODBC database interface"),
    list("archive", c("libarchive-dev"), c("libarchive13"), NA_character_, "Multi-format archive compression"),
    list("fst", c("liblz4-dev"), c("liblz4-1"), NA_character_, "Fast serialization"),
    list("hdf5r", c("libhdf5-dev"), c("libhdf5-103-1"), NA_character_, "HDF5 scientific data format"),
    list("ncdf4", c("libnetcdf-dev"), c("libnetcdf19"), NA_character_, "NetCDF4 arrays"),
    list("RNetCDF", c("libnetcdf-dev", "libudunits2-dev"), c("libnetcdf19", "libudunits2-0"), NA_character_, "NetCDF and UDUNITS"),
    list("duckdb", c("build-essential", "g++"), character(), "cpp", "DuckDB embedded analytical engine"),

    # Compiled Scientific Toolchains & Optimization
    list("Rcpp", c("build-essential", "g++", "make"), character(), "cpp", "C++ R integration"),
    list("RcppArmadillo", c("build-essential", "g++", "gfortran", "liblapack-dev", "libblas-dev"),
         c("liblapack3", "libblas3"), "cpp", "Armadillo linear algebra C++"),
    list("RcppEigen", c("build-essential", "g++"), character(), "cpp", "Eigen linear algebra C++"),
    list("cpp11", c("build-essential", "g++"), character(), "cpp", "Modern C++11 bindings"),
    list("cmdstanr", c("build-essential", "g++", "make", "curl", "libtbb-dev"),
         c("build-essential", "g++", "make", "libtbb12"), "cmdstan", "CmdStan Bayesian HMC compiler"),
    list("rstan", c("build-essential", "g++", "make", "libv8-dev"),
         c("build-essential", "g++", "make"), "cpp", "Stan C++ compiler"),
    list("brms", c("build-essential", "g++", "make", "libv8-dev"),
         c("build-essential", "g++", "make"), "cpp", "Bayesian regression models via Stan"),
    list("TMB", c("build-essential", "g++", "gfortran"),
         c("build-essential", "g++", "gfortran"), "tmb", "Template Model Builder AD engine"),
    list("RTMB", c("build-essential", "g++", "gfortran"),
         c("build-essential", "g++", "gfortran"), "tmb", "Native R Template Model Builder"),
    list("glmmTMB", c("build-essential", "g++", "gfortran"),
         c("libgfortran5"), "tmb", "Generalized linear mixed models"),
    list("rjags", c("jags", "libjags-dev"), c("jags"), "jags", "JAGS Gibbs sampler"),
    list("R2jags", c("jags", "libjags-dev"), c("jags"), "jags", "JAGS interface"),
    list("runjags", c("jags", "libjags-dev"), c("jags"), "jags", "Parallel JAGS runner"),
    list("rextendr", c("cargo", "rustc"), character(), "rust", "Rust extendr toolchain"),
    list("savvy", c("cargo", "rustc"), character(), "rust", "Rust savvy toolchain"),
    list("gifski", c("cargo", "rustc"), character(), "rust", "Rust GIF encoder"),
    list("rJava", c("default-jdk"), c("default-jre-headless"), "java", "Java JDK/JNI runtime"),
    list("reticulate", c("python3", "python3-dev", "python3-venv", "python3-pip"),
         c("python3", "python3-venv"), "python", "Python interoperability"),
    list("tinytex", c("perl", "wget", "xz-utils"), c("perl", "xz-utils"), "latex", "TinyTeX LaTeX distribution"),
    list("quarto", c("curl", "ca-certificates"), c("curl", "ca-certificates"), "quarto", "Quarto publishing CLI"),
    list("rmarkdown", c("pandoc"), c("pandoc"), NA_character_, "R Markdown / Pandoc rendering"),
    list("nloptr", c("cmake", "libnlopt-dev"), c("libnlopt0"), NA_character_, "NLopt nonlinear optimization"),
    list("igraph", c("libglpk-dev", "libxml2-dev", "libgmp-dev"),
         c("libglpk40", "libxml2", "libgmp10"), NA_character_, "Network graph algorithms"),
    list("gmp", c("libgmp-dev"), c("libgmp10"), NA_character_, "GNU Multiple Precision arithmetic"),
    list("Rmpfr", c("libmpfr-dev", "libgmp-dev"), c("libmpfr6", "libgmp10"), NA_character_, "MPFR floating-point"),
    list("gsl", c("libgsl-dev"), c("libgsl27"), NA_character_, "GNU Scientific Library"),
    list("glpkAPI", c("libglpk-dev"), c("libglpk40"), NA_character_, "GLPK linear programming"),
    list("shiny", c("curl"), c("curl"), NA_character_, "Shiny web runtime (curl for healthcheck)")
  )

  tibble::tibble(
    package = vapply(entries, `[[`, character(1L), 1L),
    apt_build = lapply(entries, `[[`, 2L),
    apt_runtime = lapply(entries, `[[`, 3L),
    toolchain = vapply(entries, `[[`, character(1L), 4L),
    notes = vapply(entries, `[[`, character(1L), 5L)
  )
}

#' Resolve OS System Dependencies for a Set of R Packages
#'
#' Maps R package names (and optional `DESCRIPTION` `SystemRequirements` strings
#' or user overrides) to deduplicated Debian/Ubuntu `apt` packages for both
#' build and runtime container stages.
#'
#' @param packages Character vector of R package names.
#' @param system_requirements Optional character vector of raw `SystemRequirements`
#'   strings (e.g., from a `DESCRIPTION` file).
#' @param custom_sysreqs Optional named list mapping R package names to
#'   character vectors of `apt` packages (e.g., `list(mypkg = c("libfoo-dev"))`).
#'
#' @return A [tibble::tibble()] with columns `apt_package`, `stage`,
#'   `required_by`, and `source`.
#' @export
#' @examples
#' resolve_sysreqs(c("sf", "xml2", "cmdstanr"))
#' resolve_sysreqs(c("dplyr", "mypkg"), custom_sysreqs = list(mypkg = "libfoo-dev"))
resolve_sysreqs <- function(packages = character(),
                            system_requirements = NULL,
                            custom_sysreqs = NULL) {
  packages <- unique(as.character(packages[!is.na(packages) & nzchar(packages)]))
  db <- sysreqs_db()

  rows <- list()
  add_req <- function(apt_pkg, stage, req_by, src) {
    rows[[length(rows) + 1L]] <<- list(
      apt_package = apt_pkg,
      stage = stage,
      required_by = req_by,
      source = src
    )
  }

  # 1. Built-in database matches
  matched <- db[db$package %in% packages, , drop = FALSE]
  if (nrow(matched) > 0L) {
    for (i in seq_len(nrow(matched))) {
      pkg <- matched$package[[i]]
      for (ap in matched$apt_build[[i]]) {
        add_req(ap, "build", pkg, "builtin_db")
      }
      for (ap in matched$apt_runtime[[i]]) {
        add_req(ap, "runtime", pkg, "builtin_db")
      }
    }
  }

  # 2. DESCRIPTION SystemRequirements heuristics
  if (!is.null(system_requirements) && length(system_requirements) > 0L) {
    sr_text <- tolower(paste(system_requirements, collapse = " "))
    sr_rules <- list(
      "gdal" = c("libgdal-dev", "gdal-bin"),
      "geos" = c("libgeos-dev"),
      "proj" = c("libproj-dev"),
      "udunits" = c("libudunits2-dev"),
      "libxml2" = c("libxml2-dev"),
      "libcurl" = c("libcurl4-openssl-dev"),
      "openssl" = c("libssl-dev"),
      "cmake" = c("cmake"),
      "gnu make" = c("make"),
      "c\\+\\+1[147]|c\\+\\+20|g\\+\\+" = c("build-essential", "g++"),
      "fortran|gfortran" = c("gfortran"),
      "cargo|rustc|rust" = c("cargo", "rustc"),
      "jags" = c("jags", "libjags-dev"),
      "python" = c("python3", "python3-dev", "python3-venv"),
      "java|jdk" = c("default-jdk"),
      "imagemagick" = c("libmagick++-dev"),
      "poppler" = c("libpoppler-cpp-dev"),
      "pandoc" = c("pandoc"),
      "gsl" = c("libgsl-dev"),
      "netcdf" = c("libnetcdf-dev"),
      "hdf5" = c("libhdf5-dev"),
      "cairo" = c("libcairo2-dev"),
      "nlopt" = c("libnlopt-dev")
    )
    for (pat in names(sr_rules)) {
      if (grepl(pat, sr_text, perl = TRUE)) {
        for (ap in sr_rules[[pat]]) {
          add_req(ap, "build", "DESCRIPTION:SystemRequirements", "description")
        }
      }
    }
  }

  # 3. User custom overrides
  if (!is.null(custom_sysreqs)) {
    if (!is.list(custom_sysreqs) || is.null(names(custom_sysreqs))) {
      cli::cli_abort("{.arg custom_sysreqs} must be a named list mapping package names to apt packages.")
    }
    for (pkg in names(custom_sysreqs)) {
      aps <- as.character(custom_sysreqs[[pkg]])
      aps <- aps[!is.na(aps) & nzchar(aps)]
      for (ap in aps) {
        add_req(ap, "build", pkg, "custom")
        add_req(ap, "runtime", pkg, "custom")
      }
    }
  }

  if (length(rows) == 0L) {
    return(tibble::tibble(
      apt_package = character(),
      stage = character(),
      required_by = character(),
      source = character()
    ))
  }

  raw_tbl <- tibble::tibble(
    apt_package = vapply(rows, `[[`, character(1L), "apt_package"),
    stage = vapply(rows, `[[`, character(1L), "stage"),
    required_by = vapply(rows, `[[`, character(1L), "required_by"),
    source = vapply(rows, `[[`, character(1L), "source")
  )

  # Deduplicate by (apt_package, stage) combining required_by & source cleanly
  keys <- paste(raw_tbl$apt_package, raw_tbl$stage, sep = "::")
  uniq_keys <- sort(unique(keys))

  out_apt <- character(length(uniq_keys))
  out_stage <- character(length(uniq_keys))
  out_req <- character(length(uniq_keys))
  out_src <- character(length(uniq_keys))

  for (i in seq_along(uniq_keys)) {
    idx <- which(keys == uniq_keys[[i]])
    out_apt[[i]] <- raw_tbl$apt_package[[idx[[1L]]]]
    out_stage[[i]] <- raw_tbl$stage[[idx[[1L]]]]
    out_req[[i]] <- paste(sort(unique(raw_tbl$required_by[idx])), collapse = ", ")
    out_src[[i]] <- paste(sort(unique(raw_tbl$source[idx])), collapse = ", ")
  }

  ord <- order(out_stage, out_apt)
  tibble::tibble(
    apt_package = out_apt[ord],
    stage = out_stage[ord],
    required_by = out_req[ord],
    source = out_src[ord]
  )
}
