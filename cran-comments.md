## Test environments

* Local macOS (aarch64-apple-darwin23), R 4.6.1
* GitHub Actions (planned): ubuntu-latest (release, devel, oldrel-1), macOS-latest (release), windows-latest (release)

## R CMD check results

0 errors | 0 warnings | 0 notes

Checked with:
- `devtools::test()`: `PASS 603 | FAIL 0 | WARN 0 | SKIP 1` (1 guarded live-Docker integration skip)
- `covr::percent_coverage(covr::package_coverage())`: `93.72%`
- `rcmdcheck::rcmdcheck()` (full check including PDF manual and all 5 vignettes): `0 errors | 0 warnings | 0 notes`
- `rcmdcheck::rcmdcheck(args = c("--as-cran"), env = c("_R_CHECK_CRAN_INCOMING_REMOTE_" = "false", "_R_CHECK_LIMIT_CORES_" = "true"))`: `0 errors | 0 warnings | 0 package notes` (1 local macOS host-only note because `/usr/bin/tidy` is Apple's legacy HTML Tidy)
- `spelling::spell_check_package()` -> 0 misspellings
- Source tarball `rcapsule_0.4.0.tar.gz`: 209.6 KiB

## CRAN Policy Compliance Notes

* Release version 0.4.0 (zero new `Imports` added).
* All examples, tests, and vignettes write exclusively to `tempdir()`/`tempfile()` and clean up after themselves; no global options, `par()`, environment variables, or `.Random.seed` are mutated in the caller's R session.
* All tests and examples run offline and respect `<= 2` CPU cores (`_R_CHECK_LIMIT_CORES_=true`). Live Docker daemon integration tests are guarded with `skip_on_cran()` and `skip_if_not(docker_available())`.
