# Runnable Example 1: Basic End-to-End Reproducibility Capsule Workflow
# Run via: source(system.file("examples", "basic-capsule-workflow.R", package = "rcapsule"))

library(rcapsule)

demo_dir <- tempfile("rcapsule_ex_basic_")
dir.create(file.path(demo_dir, "data"), recursive = TRUE)
dir.create(file.path(demo_dir, "results"), recursive = TRUE)

write.csv(
  data.frame(group = c("A", "A", "B", "B"), value = c(1.5, 2.1, 3.4, 3.8)),
  file.path(demo_dir, "data", "measurements.csv"),
  row.names = FALSE
)

writeLines(
  c(
    "dat <- read.csv('data/measurements.csv', stringsAsFactors = FALSE)",
    "summary_df <- aggregate(value ~ group, data = dat, FUN = mean)",
    "dir.create('results', showWarnings = FALSE)",
    "write.csv(summary_df, 'results/group_means.csv', row.names = FALSE)"
  ),
  file.path(demo_dir, "run.R")
)

# Produce baseline output cleanly
invisible(callr::rscript(
  script = NULL,
  cmdargs = c("-e", "set.seed(42L); source('run.R')"),
  wd = demo_dir,
  fail_on_status = TRUE,
  show = FALSE
))

# Scan, compile, lint, sign, verify in isolated sandbox, and render certificates
bundle <- build_capsule(
  path        = demo_dir,
  targets     = c("dockerfile", "compose", "apptainer"),
  inputs      = "data/measurements.csv",
  outputs     = "results/group_means.csv",
  seed        = 42L,
  platform    = "linux/amd64",
  use_ppm     = TRUE,
  write       = TRUE,
  lint        = TRUE,
  verify      = TRUE,
  certificate = TRUE
)

print(bundle)
unlink(demo_dir, recursive = TRUE)
