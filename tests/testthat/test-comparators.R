test_that("compare_artifacts handles exact match, CSV/TSV tolerances, and failure diagnostics", {
  tmp <- withr::local_tempdir()
  f1 <- file.path(tmp, "a.csv")
  f2 <- file.path(tmp, "b.csv")
  f3 <- file.path(tmp, "c.csv")

  df_base <- data.frame(group = c("A", "B", "C"), val = c(1.0000, 10.0000, NA_real_), stringsAsFactors = FALSE)
  df_close <- data.frame(group = c("A", "B", "C"), val = c(1.0004, 10.0020, NA_real_), stringsAsFactors = FALSE)
  df_far <- data.frame(group = c("A", "B", "C"), val = c(1.0500, 10.0000, NA_real_), stringsAsFactors = FALSE)

  write.csv(df_base, f1, row.names = FALSE)
  write.csv(df_close, f2, row.names = FALSE)
  write.csv(df_far, f3, row.names = FALSE)

  # Exact SHA-256 fast path
  r_exact <- compare_artifacts(f1, f1)
  expect_equal(r_exact$status, "exact_match")
  expect_true(r_exact$passed)
  expect_equal(r_exact$max_abs_diff, 0)

  # Zero tolerance fails on tiny numeric shift
  r_zero <- compare_artifacts(f1, f2, abs_tol = 0, rel_tol = 0)
  expect_equal(r_zero$status, "mismatch")
  expect_false(r_zero$passed)

  # Within abs_tol + rel_tol passes and reports exact diffs
  r_tol <- compare_artifacts(f1, f2, abs_tol = 1e-3, rel_tol = 1e-3)
  expect_equal(r_tol$status, "within_tolerance")
  expect_true(r_tol$passed)
  expect_equal(r_tol$max_abs_diff, 0.002, tolerance = 1e-9)

  # Outside tolerance fails with clear diagnostic
  r_fail <- compare_artifacts(f1, f3, abs_tol = 1e-3, rel_tol = 1e-3)
  expect_equal(r_fail$status, "mismatch")
  expect_false(r_fail$passed)
  expect_match(r_fail$details, "val\\[1\\]")

  # TSV support
  t1 <- file.path(tmp, "a.tsv")
  t2 <- file.path(tmp, "b.tsv")
  write.table(df_base, t1, sep = "\t", row.names = FALSE)
  write.table(df_close, t2, sep = "\t", row.names = FALSE)
  r_tsv <- compare_artifacts(t1, t2, abs_tol = 5e-3)
  expect_equal(r_tsv$status, "within_tolerance")
  expect_true(r_tsv$passed)

  # Label mismatch fails even with large numeric tolerance
  f_lbl <- file.path(tmp, "lbl.csv")
  write.csv(data.frame(group = c("A", "X", "C"), val = c(1, 10, NA)), f_lbl, row.names = FALSE)
  r_lbl <- compare_artifacts(f1, f_lbl, abs_tol = 100)
  expect_false(r_lbl$passed)
  expect_match(r_lbl$details, "group")
})

test_that("compare_artifacts supports JSON, RDS, binary files, missing files, and embedded raw bytes", {
  tmp <- withr::local_tempdir()

  # JSON tolerance
  j1 <- file.path(tmp, "m1.json")
  j2 <- file.path(tmp, "m2.json")
  jsonlite::write_json(list(model = "hmc", mu = 2.5000, nested = list(sd = 0.4000)), j1, auto_unbox = TRUE)
  jsonlite::write_json(list(model = "hmc", mu = 2.5003, nested = list(sd = 0.4001)), j2, auto_unbox = TRUE)
  rj <- compare_artifacts(j1, j2, abs_tol = 1e-3)
  expect_equal(rj$status, "within_tolerance")
  expect_true(rj$passed)
  expect_false(compare_artifacts(j1, j2, abs_tol = 1e-5)$passed)

  # RDS tolerance with matrices, lists, and data.frames
  r1 <- file.path(tmp, "o1.rds")
  r2 <- file.path(tmp, "o2.rds")
  saveRDS(list(mat = matrix(c(1, 2, 3, 4), 2, 2), df = data.frame(x = 1:2, y = c(0.5, 1.5))), r1)
  saveRDS(list(mat = matrix(c(1.0001, 2, 3, 4), 2, 2), df = data.frame(x = 1:2, y = c(0.5, 1.5002))), r2)
  rr <- compare_artifacts(r1, r2, abs_tol = 1e-3)
  expect_equal(rr$status, "within_tolerance")
  expect_true(rr$passed)

  # Embedded raw bytes fallback works without expected_path on disk
  raw_ref <- readBin(r1, what = "raw", n = file.info(r1)$size)
  rr_raw <- compare_artifacts(expected_path = NULL, actual_path = r2, expected_raw = raw_ref, abs_tol = 1e-3)
  expect_equal(rr_raw$status, "within_tolerance")
  expect_true(rr_raw$passed)

  # Binary files require exact match
  b1 <- file.path(tmp, "img1.png")
  b2 <- file.path(tmp, "img2.png")
  writeBin(as.raw(c(1, 2, 3, 4)), b1)
  writeBin(as.raw(c(1, 2, 3, 5)), b2)
  rb <- compare_artifacts(b1, b2, abs_tol = 1e-2)
  expect_equal(rb$status, "mismatch")
  expect_false(rb$passed)

  # Missing actual file
  rmiss <- compare_artifacts(j1, file.path(tmp, "does_not_exist.json"))
  expect_equal(rmiss$status, "missing")
  expect_false(rmiss$passed)

  # RDS ignore_attributes and NA/Inf mismatch diagnostics
  rn1 <- file.path(tmp, "n1.rds")
  rn2 <- file.path(tmp, "n2.rds")
  saveRDS(c(a = 1.0, b = 2.0), rn1)
  saveRDS(c(x = 1.0001, y = 2.0), rn2)
  expect_false(compare_artifacts(rn1, rn2, abs_tol = 1e-2, ignore_attributes = FALSE)$passed)
  expect_true(compare_artifacts(rn1, rn2, abs_tol = 1e-2, ignore_attributes = TRUE)$passed)

  rinf1 <- file.path(tmp, "i1.rds")
  rinf2 <- file.path(tmp, "i2.rds")
  saveRDS(c(1.0, Inf, NaN), rinf1)
  saveRDS(c(1.0, -Inf, NaN), rinf2)
  expect_false(compare_artifacts(rinf1, rinf2, abs_tol = 1e-2)$passed)
})
