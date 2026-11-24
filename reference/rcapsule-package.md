# rcapsule: Reproducibility Capsules and Multi-Target Containerization for R

Full-stack computational reproducibility compiler and verifier for R
analysis repositories, Quarto manuscripts, R Markdown reports, R
packages, `targets` pipelines, and Shiny applications.

## Main Workflows

- **Scan projects**:
  [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md),
  [`sysreqs_db()`](https://marcusharrisphd.com/rcapsule/reference/sysreqs_db.md),
  [`resolve_sysreqs()`](https://marcusharrisphd.com/rcapsule/reference/resolve_sysreqs.md)

- **Compile & lint containers**:
  [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md),
  [`compile_compose()`](https://marcusharrisphd.com/rcapsule/reference/compile_compose.md),
  [`compile_apptainer()`](https://marcusharrisphd.com/rcapsule/reference/compile_apptainer.md),
  [`lint_container_spec()`](https://marcusharrisphd.com/rcapsule/reference/lint_container_spec.md)

- **Cryptographic manifests & diffing**:
  [`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md),
  [`read_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/read_capsule_manifest.md),
  [`write_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/write_capsule_manifest.md),
  [`sign_manifest()`](https://marcusharrisphd.com/rcapsule/reference/sign_manifest.md),
  [`verify_manifest_integrity()`](https://marcusharrisphd.com/rcapsule/reference/verify_manifest_integrity.md),
  [`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md)

- **Isolated verification & publishing**:
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md),
  [`compare_artifacts()`](https://marcusharrisphd.com/rcapsule/reference/compare_artifacts.md),
  [`render_certificate()`](https://marcusharrisphd.com/rcapsule/reference/render_certificate.md),
  [`export_capsule_bundle()`](https://marcusharrisphd.com/rcapsule/reference/export_capsule_bundle.md),
  [`build_capsule()`](https://marcusharrisphd.com/rcapsule/reference/build_capsule.md)

## See also

Useful links:

- <https://github.com/MarcusHarrisUConn/rcapsule>

- <https://marcusharrisphd.com/rcapsule/>

- Report bugs at <https://github.com/MarcusHarrisUConn/rcapsule/issues>

## Author

**Maintainer**: Marcus Harris <marcus.harris.uconn@gmail.com>
\[copyright holder\]

Authors:

- Marcus Harris <marcus.harris.uconn@gmail.com> \[copyright holder\]
