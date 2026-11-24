# Package index

## End-to-End Orchestration & Supplement Export

High-level workflows for building complete reproducibility capsules and
exporting zip-slip-safe journal peer-review supplements.

- [`build_capsule()`](https://marcusharrisphd.com/rcapsule/reference/build_capsule.md)
  : Build a Complete Reproducibility Capsule for an R Project
- [`export_capsule_bundle()`](https://marcusharrisphd.com/rcapsule/reference/export_capsule_bundle.md)
  : Export a Journal-Ready Reproducibility Supplement Bundle

## Full-Stack Project & Toolchain Scanner

Static AST and project scanners resolving R packages, OS system
libraries, compiled scientific toolchains, .Rprofile hazards, and
architecture hints.

- [`scan_project()`](https://marcusharrisphd.com/rcapsule/reference/scan_project.md)
  : Scan an R Project for Dependencies, System Libraries, and Scientific
  Toolchains
- [`sysreqs_db()`](https://marcusharrisphd.com/rcapsule/reference/sysreqs_db.md)
  : Built-in OS System Dependency (sysreqs) Registry
- [`resolve_sysreqs()`](https://marcusharrisphd.com/rcapsule/reference/resolve_sysreqs.md)
  : Resolve OS System Dependencies for a Set of R Packages

## Multi-Target Container Compilers & Static Linter

Generate and audit pinned, layer-cached Dockerfiles, multi-service
docker-compose.yml stacks, and HPC-ready Apptainer recipes.

- [`compile_dockerfile()`](https://marcusharrisphd.com/rcapsule/reference/compile_dockerfile.md)
  : Compile a Layer-Cached Multi-Stage Dockerfile

- [`compile_compose()`](https://marcusharrisphd.com/rcapsule/reference/compile_compose.md)
  :

  Compile a Production Multi-Service `docker-compose.yml`

- [`compile_apptainer()`](https://marcusharrisphd.com/rcapsule/reference/compile_apptainer.md)
  : Compile an HPC-Ready Apptainer / Singularity Definition File

- [`lint_container_spec()`](https://marcusharrisphd.com/rcapsule/reference/lint_container_spec.md)
  : Lint a Container Specification for Reproducibility and Security
  Issues

## Cryptographic Provenance Manifests & Cross-Run Diffing

Create, serialize, sign, verify, and diff tamper-evident capsule.json
manifests with SHA-256 hashes and keyed HMAC-SHA256 signatures.

- [`create_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/create_capsule_manifest.md)
  :

  Create a Cryptographic Provenance Manifest (`capsule.json`)

- [`write_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/write_capsule_manifest.md)
  :

  Write a Capsule Manifest to `capsule.json`

- [`read_capsule_manifest()`](https://marcusharrisphd.com/rcapsule/reference/read_capsule_manifest.md)
  :

  Read a Capsule Manifest from `capsule.json`

- [`sign_manifest()`](https://marcusharrisphd.com/rcapsule/reference/sign_manifest.md)
  : Sign a Capsule Manifest with HMAC-SHA256

- [`verify_manifest_integrity()`](https://marcusharrisphd.com/rcapsule/reference/verify_manifest_integrity.md)
  : Verify Cryptographic Integrity and Signature of a Capsule Manifest

- [`diff_capsules()`](https://marcusharrisphd.com/rcapsule/reference/diff_capsules.md)
  : Diff Two Capsule Provenance Manifests Across Runs or Machines

## Reproducibility Verification & Certificates

Execute pipelines in isolated sandboxes or Docker containers, compare
outputs with exact and numeric-tolerance comparators, and render
publication-ready verification certificates.

- [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md)
  : Verify Computational Reproducibility Against a Capsule Manifest
- [`compare_artifacts()`](https://marcusharrisphd.com/rcapsule/reference/compare_artifacts.md)
  : Compare Two Output Artifacts with Exact SHA-256 and Numeric
  Tolerance
- [`render_certificate()`](https://marcusharrisphd.com/rcapsule/reference/render_certificate.md)
  : Render a Journal-Ready Reproducibility Verification Certificate

## Runtime Capability Checks

Detect local Docker daemon and Apptainer/Singularity CLI availability.

- [`docker_available()`](https://marcusharrisphd.com/rcapsule/reference/docker_available.md)
  : Check whether Docker daemon is available
- [`apptainer_available()`](https://marcusharrisphd.com/rcapsule/reference/apptainer_available.md)
  : Check whether Apptainer or Singularity CLI is available
