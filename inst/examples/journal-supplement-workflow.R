# Runnable Example 2: Journal Peer-Review Supplement & Cross-Run Diff Workflow
# Run via: source(system.file("examples", "journal-supplement-workflow.R", package = "rcapsule"))

library(rcapsule)

demo_dir <- tempfile("rcapsule_ex_journal_")
dir.create(file.path(demo_dir, "data"), recursive = TRUE)
dir.create(file.path(demo_dir, "results"), recursive = TRUE)

write.csv(data.frame(x = 1:10, y = 2 * (1:10) + 1), file.path(demo_dir, "data", "study.csv"), row.names = FALSE)
writeLines(
  c(
    "dat <- read.csv('data/study.csv')",
    "fit <- lm(y ~ x, data = dat)",
    "dir.create('results', showWarnings = FALSE)",
    "write.csv(data.frame(term = names(coef(fit)), est = unname(coef(fit))), 'results/coefs.csv', row.names = FALSE)"
  ),
  file.path(demo_dir, "analysis.R")
)

invisible(callr::rscript(
  script = NULL,
  cmdargs = c("-e", "set.seed(2026L); source('analysis.R')"),
  wd = demo_dir,
  fail_on_status = TRUE,
  show = FALSE
))

# Record signed manifest and verify
m <- create_capsule_manifest(
  path       = demo_dir,
  inputs     = "data/study.csv",
  outputs    = "results/coefs.csv",
  seed       = 2026L,
  tolerances = list(atol = 1e-4, rtol = 1e-4),
  key        = "demo-review-key",
  output     = file.path(demo_dir, "capsule.json")
)
v <- verify_capsule(m, path = demo_dir, runner = "sandbox", key = "demo-review-key")

# Export a self-contained ZIP supplement archive
zip_file <- file.path(tempdir(), paste0(basename(demo_dir), "_supplement.zip"))
exp <- export_capsule_bundle(
  path         = demo_dir,
  output       = zip_file,
  format       = "zip",
  manifest     = m,
  verification = v,
  platform     = "linux/amd64",
  overwrite    = TRUE
)

print(exp)
unlink(c(demo_dir, zip_file), recursive = TRUE)
