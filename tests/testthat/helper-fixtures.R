# Reusable isolated fixture project builders for rcapsule tests

make_analysis_fixture <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  dir.create(file.path(dir, "data"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(dir, "R"), showWarnings = FALSE, recursive = TRUE)

  writeLines(
    c(
      "# Spatial & data ingestion analysis",
      "# library(commented_out_pkg)",
      "library(dplyr)",
      "require('haven')",
      "pkg_var <- 'not_a_real_pkg'",
      "library(pkg_var, character.only = TRUE)",
      "set.seed(2026)",
      "x <- sf::st_as_sf(data.frame(lon = 0, lat = 0), coords = c('lon', 'lat'))",
      "doc <- xml2::read_xml('<root/>')",
      "req <- curl::curl_fetch_memory('https://example.org')",
      "if (requireNamespace('ragg', quietly = TRUE)) invisible(NULL)",
      "loadNamespace('jsonlite')",
      "internal_ref <- stats:::format.perc(0.5, 2)"
    ),
    file.path(dir, "analysis.R")
  )

  renv_lock <- list(
    R = list(
      Version = "4.4.1",
      Repositories = list(list(Name = "CRAN", URL = "https://cloud.r-project.org"))
    ),
    Packages = list(
      dplyr = list(Package = "dplyr", Version = "1.1.4", Source = "Repository"),
      sf = list(Package = "sf", Version = "1.0-16", Source = "Repository"),
      xml2 = list(Package = "xml2", Version = "1.3.6", Source = "Repository"),
      curl = list(Package = "curl", Version = "5.2.1", Source = "Repository"),
      haven = list(Package = "haven", Version = "2.5.4", Source = "Repository"),
      ragg = list(Package = "ragg", Version = "1.3.2", Source = "Repository"),
      jsonlite = list(Package = "jsonlite", Version = "1.8.8", Source = "Repository")
    )
  )
  jsonlite::write_json(renv_lock, file.path(dir, "renv.lock"), auto_unbox = TRUE, pretty = TRUE)
  write.csv(data.frame(id = 1:5, value = c(10, 20, 30, 40, 50)),
            file.path(dir, "data", "input.csv"), row.names = FALSE)
  dir
}

make_quarto_fixture <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  writeLines(
    c(
      "project:",
      "  type: manuscript",
      "format:",
      "  html: default",
      "  pdf:",
      "    pdf-engine: pdflatex"
    ),
    file.path(dir, "_quarto.yml")
  )

  writeLines(
    c(
      "---",
      "title: 'Reproducible Bayesian Climate Study'",
      "format:",
      "  pdf: default",
      "---",
      "",
      "## Methods",
      "",
      "```{r setup}",
      "#| echo: false",
      "#| warning: false",
      "library(ggplot2)",
      "library(ragg)",
      "set.seed(101)",
      "```",
      "",
      "```{python preprocess}",
      "import numpy as np",
      "from scipy import stats",
      "x = np.mean([1, 2, 3])",
      "```",
      "",
      "```{stan model}",
      "parameters { real mu; }",
      "model { mu ~ normal(0, 1); }",
      "```",
      "",
      "Inline call: `r scales::comma(1000)`."
    ),
    file.path(dir, "manuscript.qmd")
  )

  writeLines(c("numpy==1.26.4", "scipy==1.13.0", "# comment line"), file.path(dir, "requirements.txt"))
  dir
}

make_shiny_fixture <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  writeLines(
    c(
      "library(shiny)",
      "library(bslib)",
      "library(promises)",
      "library(mirai)",
      "",
      "ui <- page_sidebar(",
      "  title = 'Clinical Trial Explorer',",
      "  sidebar = sidebar('Controls'),",
      "  'Main panel'",
      ")",
      "server <- function(input, output, session) {}",
      "shinyApp(ui, server)"
    ),
    file.path(dir, "app.R")
  )
  writeLines(
    c(
      "library(mirai)",
      "daemons(2)"
    ),
    file.path(dir, "worker.R")
  )
  dir
}

make_compiled_fixture <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  dir.create(file.path(dir, "src", "rust"), showWarnings = FALSE, recursive = TRUE)
  writeLines(
    c(
      "library(cmdstanr)",
      "library(RTMB)",
      "library(rjags)",
      "library(Rcpp)",
      "library(reticulate)",
      "m <- cmdstanr::cmdstan_model('model.stan')",
      "obj <- RTMB::MakeADFun(function(p) sum(p^2), list(x = 1))",
      "j <- rjags::jags.model('model.jags')",
      "Rcpp::sourceCpp('src/fast.cpp')",
      "np <- reticulate::import('numpy')"
    ),
    file.path(dir, "run.R")
  )
  writeLines("parameters { real theta; } model { theta ~ normal(0, 1); }", file.path(dir, "model.stan"))
  writeLines("model { x ~ dnorm(0, 1) }", file.path(dir, "model.jags"))
  writeLines("#include <Rcpp.h>\n// [[Rcpp::export]]\ndouble add1(double x) { return x + 1.0; }",
             file.path(dir, "src", "fast.cpp"))
  writeLines("[package]\nname = 'fastcore'\nversion = '0.1.0'", file.path(dir, "src", "rust", "Cargo.toml"))
  dir
}

make_package_fixture <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  dir.create(file.path(dir, "R"), showWarnings = FALSE)
  dir.create(file.path(dir, "src"), showWarnings = FALSE)
  writeLines(
    c(
      "Package: demopkg",
      "Title: Demo Scientific Package",
      "Version: 0.2.0",
      "Description: Demo fixture package.",
      "License: MIT",
      "Imports:",
      "    xml2,",
      "    jsonlite",
      "LinkingTo:",
      "    Rcpp",
      "Suggests:",
      "    testthat",
      "SystemRequirements: C++17, GDAL (>= 3.0)"
    ),
    file.path(dir, "DESCRIPTION")
  )
  writeLines("export(hello)", file.path(dir, "NAMESPACE"))
  writeLines("hello <- function() jsonlite::toJSON(list(ok = TRUE))", file.path(dir, "R", "hello.R"))
  writeLines("#include <Rcpp.h>", file.path(dir, "src", "code.cpp"))
  dir
}

make_runnable_pipeline_fixture <- function(dir = withr::local_tempdir(.local_envir = parent.frame()),
                                           seed = 42L,
                                           stochastic_mode = c("deterministic", "env_perturb")) {
  stochastic_mode <- match.arg(stochastic_mode)
  dir.create(file.path(dir, "data"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(dir, "results"), showWarnings = FALSE, recursive = TRUE)

  input_df <- data.frame(
    group = c("control", "control", "treat", "treat", "treat"),
    y = c(1.2, 1.5, 2.4, 2.8, 2.6),
    stringsAsFactors = FALSE
  )
  write.csv(input_df, file.path(dir, "data", "input.csv"), row.names = FALSE)

  perturb_code <- if (stochastic_mode == "env_perturb") {
    "eps <- as.numeric(Sys.getenv('RCAPSULE_TEST_PERTURB', '0'))"
  } else {
    "eps <- 0"
  }

  script_lines <- c(
    "dat <- read.csv('data/input.csv', stringsAsFactors = FALSE)",
    perturb_code,
    "draws <- rnorm(100, mean = mean(dat$y), sd = 0.25)",
    "summary_df <- data.frame(",
    "  metric = c('mean_y', 'mc_mean', 'mc_sd'),",
    "  estimate = c(mean(dat$y) + eps, mean(draws) + eps, sd(draws)),",
    "  stringsAsFactors = FALSE",
    ")",
    "dir.create('results', showWarnings = FALSE, recursive = TRUE)",
    "write.csv(summary_df, 'results/summary.csv', row.names = FALSE)",
    "write.table(summary_df, 'results/summary.tsv', sep = '\\t', row.names = FALSE, quote = FALSE)",
    "jsonlite::write_json(",
    "  list(n = nrow(dat), mean_y = mean(dat$y) + eps, mc_mean = mean(draws) + eps),",
    "  'results/metrics.json', auto_unbox = TRUE, digits = 10, pretty = TRUE",
    ")",
    "saveRDS(list(table = summary_df, draws_head = draws[1:5] + eps), 'results/model.rds')"
  )
  writeLines(script_lines, file.path(dir, "run.R"))

  # Execute baseline run cleanly using the same RNG & seed
  res <- callr::rscript(
    script = NULL,
    cmdargs = c("-e", sprintf("set.seed(%dL); source('run.R')", as.integer(seed))),
    wd = dir,
    fail_on_status = TRUE,
    show = FALSE
  )
  invisible(res)
  dir
}
