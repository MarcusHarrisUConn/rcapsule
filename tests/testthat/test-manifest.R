test_that("create_capsule_manifest records full provenance, git state, hashes, and survives JSON round-trip", {
  dir <- make_runnable_pipeline_fixture()
  compile_dockerfile(dir, output = file.path(dir, "Dockerfile"))

  # Initialize a real local git repository inside temp fixture to test git detection
  git_bin <- Sys.which("git")
  has_git <- nzchar(git_bin)
  if (has_git) {
    run_g <- function(args) {
      processx::run(unname(git_bin), args = args, wd = dir, error_on_status = FALSE)
    }
    run_g(c("init"))
    run_g(c("config", "user.email", "test@example.com"))
    run_g(c("config", "user.name", "Test User"))
    run_g(c("add", "."))
    run_g(c("commit", "-m", "Baseline study"))
  }

  manifest_path <- file.path(dir, "capsule.json")
  m <- create_capsule_manifest(
    path = dir,
    inputs = "data/input.csv",
    outputs = c("results/summary.csv", "results/summary.tsv", "results/metrics.json", "results/model.rds"),
    seed = 42L,
    tolerances = list(
      default = list(abs_tol = 1e-6, rel_tol = 1e-5),
      files = list("results/summary.csv" = list(abs_tol = 1e-3, rel_tol = 1e-2))
    ),
    metadata = list(title = "Demo Study", journal = "JOSS"),
    key = "test-signing-key",
    output = manifest_path
  )

  expect_s3_class(m, "rcapsule_manifest")
  expect_equal(m$schema_version, "1.0.0")
  expect_match(m$capsule_id, "^cap_[0-9a-f]{12}$")
  expect_equal(m$rng$seed, 42L)
  expect_length(m$artifacts$inputs, 1L)
  expect_length(m$artifacts$outputs, 4L)
  expect_length(m$artifacts$containers, 1L)
  expect_true(length(m$snapshots) == 4L)
  expect_true(m$integrity$signed)
  expect_invisible(print(m))

  if (has_git) {
    expect_true(m$project$git$is_repo)
    expect_match(m$project$git$commit, "^[0-9a-f]{40}$")
    expect_false(m$project$git$dirty)
  }

  # In-memory integrity check passes
  chk_mem <- verify_manifest_integrity(m, key = "test-signing-key")
  expect_true(chk_mem$valid)
  expect_true(chk_mem$content_valid)
  expect_true(chk_mem$signature_valid)
  expect_invisible(print(chk_mem))

  # Round-trip from capsule.json on disk passes identically
  m_disk <- read_capsule_manifest(manifest_path)
  chk_disk <- verify_manifest_integrity(m_disk, key = "test-signing-key")
  expect_true(chk_disk$valid)
  expect_equal(chk_disk$computed_digest, m$integrity$content_digest)

  # Direct file path verification works
  expect_true(verify_manifest_integrity(manifest_path, key = "test-signing-key")$valid)

  # Unsigned manifest also round-trips cleanly (testing 0/1-length arrays too)
  m_uns <- create_capsule_manifest(
    path = dir,
    inputs = "data/input.csv",
    outputs = "results/summary.csv",
    seed = 42L,
    output = file.path(dir, "unsigned.json")
  )
  expect_true(verify_manifest_integrity(read_capsule_manifest(file.path(dir, "unsigned.json")))$valid)

  # Dirty git detection after modifying a tracked file
  if (has_git) {
    writeLines("# extra line", file.path(dir, "dirty_file.txt"))
    m_dirty <- create_capsule_manifest(path = dir, inputs = "data/input.csv")
    expect_true(m_dirty$project$git$dirty)
  }
})

test_that("verify_manifest_integrity detects tampering, forged digests, and bad keys", {
  dir <- make_runnable_pipeline_fixture()
  m <- create_capsule_manifest(
    path = dir,
    inputs = "data/input.csv",
    outputs = "results/summary.csv",
    seed = 42L,
    key = "real-secret"
  )

  # 1. Tampering with an output SHA-256 fails both digest and signature
  m_tampered <- m
  m_tampered$artifacts$outputs[[1L]]$sha256 <- paste(rep("0", 64), collapse = "")
  res1 <- verify_manifest_integrity(m_tampered, key = "real-secret")
  expect_false(res1$valid)
  expect_false(res1$content_valid)
  expect_false(res1$signature_valid)

  # 2. Tampering with seed or tolerances fails integrity
  m_seed <- m
  m_seed$rng$seed <- 999L
  expect_false(verify_manifest_integrity(m_seed, key = "real-secret")$valid)

  # 3. Attacker recomputes content_digest without knowing HMAC secret key
  m_forged <- m_tampered
  canon <- rcapsule:::manifest_canonical_body_json(m_forged)
  m_forged$integrity$content_digest <- rcapsule:::sha256_string(canon)
  res_forged <- verify_manifest_integrity(m_forged, key = "real-secret")
  expect_true(res_forged$content_valid)
  expect_false(res_forged$signature_valid)
  expect_false(res_forged$valid)

  # 4. Wrong key fails verification
  res_wrong_key <- verify_manifest_integrity(m, key = "wrong-secret")
  expect_false(res_wrong_key$valid)
  expect_false(res_wrong_key$signature_valid)

  # 5. Missing key on signed manifest fails verification
  res_no_key <- verify_manifest_integrity(m)
  expect_false(res_no_key$valid)
  expect_true(is.na(res_no_key$signature_valid))

  # 6. sign_manifest upgrades an unsigned manifest to a valid signed one
  m_uns <- create_capsule_manifest(path = dir, outputs = "results/summary.csv")
  expect_false(verify_manifest_integrity(m_uns, key = "k1")$valid)
  m_now_signed <- sign_manifest(m_uns, key = "k1")
  expect_true(verify_manifest_integrity(m_now_signed, key = "k1")$valid)
})
