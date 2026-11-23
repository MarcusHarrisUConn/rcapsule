# Security Policy & v0.2.0 Red-Team Hardening Audit

## Threat Model

`rcapsule` frequently inspects, compiles, and verifies **untrusted or third-party research repositories** (e.g., peer-review replication packages, student submissions, or external scientific pipelines). Accordingly, `rcapsule` defends against four primary attack surfaces:

1. **Container Specification Injection**: Maliciously crafted `DESCRIPTION`, `renv.lock`, `requirements.txt`, filenames, version strings, or user-supplied parameters injecting arbitrary Dockerfile `RUN` layers, shell commands (`$(...)`, backticks, `;`, `&&`, `|`), YAML keys/anchors, or Apptainer `%post` sections.
2. **Path Traversal & Symlink Escape**: Relative `../` paths, out-of-root absolute paths, or symbolic links pointing outside the project directory (e.g., `/etc/passwd`, `~/.ssh/id_rsa`) being scanned, hashed into `capsule.json`, staged into a sandbox, or executed as entrypoints.
3. **Sandbox Secret Exfiltration & Output Spoofing**: Executed R scripts reading ambient host credentials (`AWS_*`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `*_SECRET*`, `*_TOKEN*`) inherited from the parent R session, tampering with `capsule.json`, timing side channels in MAC comparisons, or dropping undeclared extra artifacts.
4. **Report XSS & YAML Deserialization**: Untrusted project names, git branch names, file paths, diff diagnostics, or `htmltools::HTML()` objects injecting executable `<script>` / event-handler payloads into rendered HTML5 or Markdown verification certificates, or YAML `!expr` tags executing arbitrary R code during parsing.

---

## v0.2.0 Adversarial Red-Team Audit & Mitigations

All shared validation, sanitization, confinement, constant-time crypto, environment scrubbing, and HTML/Markdown escaping controls are centralized in `R/security.R`.

| ID | Surface | Vulnerability Found in v0.1.0 | Mitigation Implemented in v0.2.0 |
| :--- | :--- | :--- | :--- |
| **VULN-01** | `compile_dockerfile()`, `compile_apptainer()`, `resolve_sysreqs()` | `apt` sysreq names were interpolated into `RUN apt-get install` without allowlist validation, allowing shell command or newline injection via `custom_sysreqs`. | Enforced strict Debian package grammar (`^[a-z0-9][a-z0-9+.-]+$`) in `validate_apt_package_names()` across both `resolve_sysreqs()` and `format_apt_run_block()`. |
| **VULN-02** | `scan_project()`, `compile_dockerfile()`, `compile_apptainer()` | `DESCRIPTION` and `renv.lock` package names were not validated against CRAN identifier rules before interpolation into `Rscript -e "install.packages(c(...))"` and Apptainer `%test`. | Enforced strict CRAN identifier allowlist (`is_valid_r_pkg_name()` / `validate_r_package_names()`) on all `DESCRIPTION`, `renv.lock`, AST, and compiler inputs. |
| **VULN-03** | `compile_dockerfile()`, `compile_apptainer()` | Unvalidated `r_version`, `quarto_version`, `cmdstan_version`, `base_image`, `base_digest`, `cran_repo`, `user`, `workdir`, `entrypoint`, `python_packages`, `project_name`, and `git$commit` allowed newline/shell/label/section injection (including `%post` breakout in Apptainer `%labels`). | Added dedicated allowlist validators (`validate_version_string()`, `validate_docker_image_ref()`, `validate_image_digest()`, `validate_cran_repo_url()`, `validate_linux_username()` forbidding `root`, `validate_container_workdir()`, `validate_safe_rel_spec_path()`, `validate_python_package_specs()` with single-quoted `pip` args) and strict label/comment sanitizers (`escape_dockerfile_label()`, `escape_apptainer_label()`, `sanitize_single_line_text()`). |
| **VULN-04** | `compile_compose()`, `scan_project()`, `lint_container_spec()` | Project names with newlines could inject raw YAML top-level keys via header comments; unvalidated `service_name`, `image_tag`, `env_vars`, `volumes` (e.g., `/var/run/docker.sock` or `../`), and `yaml::yaml.load()` without `eval.expr = FALSE` posed injection/deserialization risks. | Validated `service_name`, `image_tag`, `dockerfile`, `proxy_image`, `port`, `proxy_port`, `cpus`, `memory_limit`, `restart_policy`, `env_vars`, and `volumes` (blocking `..`, host `/` mounts, and `docker.sock`); sanitized YAML comments; enforced `eval.expr = FALSE` via `safe_yaml_load()` and `safe_yaml_read()`. |
| **VULN-05** | `scan_project()` | Recursive scanning did not verify whether symlinks pointed outside the project root, allowing external files to be read. | Enforced canonical real-path confinement (`is_confined_existing_path()` using `fs::path_real()` and `fs::link_path()`), skipping external/dangling symlinks and reporting them in `scan$skipped_external_symlinks`. |
| **VULN-06** | `create_capsule_manifest()` | `hash_artifact_paths()` accepted `../` traversal, external absolute paths, and external symlinks, allowing out-of-root host files to be hashed into `capsule.json`. | Enforced `assert_confined_path()` and `assert_safe_manifest_rel_path()` on every input, script, container, output, and directory expansion. |
| **VULN-07** | `verify_capsule()` | Crafted `capsule.json` paths (`../../outside.csv`, absolute paths) or external symlinks could escape the project root or sandbox during staging, bootstrap execution, or output comparison. | Validated every manifest `entrypoint`, input, script, output, and reference path with `assert_safe_manifest_rel_path()` and `assert_confined_path()`; excluded external symlinks during `stage_clean_sandbox()`. |
| **VULN-08** | `verify_manifest_integrity()`, `verify_capsule()`, `compare_artifacts()` | `constant_time_equal()` short-circuited on length mismatch without UTF-8 normalization, and file/snapshot SHA-256 checks used standard `identical()`. | Upgraded `constant_time_equal()` to normalize via `enc2utf8()`, use fixed-length SHA-256 fallback on length mismatch, and accumulate differences via bitwise OR (`bitwOr`/`bitwXor`); applied it across all digest and HMAC checks; enforced UTF-8 canonical key-ordered JSON hashing. |
| **VULN-09** | `verify_capsule()` | Unexpected extra files emitted during execution were not tracked or flagged. | Recorded pre-run vs. post-run sandbox file sets to detect and report `extra_artifacts` (excluding internal runner/cache files) and added `strict_outputs = TRUE` mode to fail audits on undeclared outputs. |
| **VULN-10** | `verify_capsule()` (`runner = "sandbox"`) | `build_sandbox_env()` inherited all host `Sys.getenv()` variables (and `callr::rscript()` merges `env` over the parent environment unless variables are explicitly unset via `NA_character_`), exposing cloud/API/VCS tokens to executed scripts. | Implemented `scrub_sandbox_env()` explicitly mapping `AWS_*`, `GITHUB_*`, `GH_*`, `GITLAB_*`, `OPENAI_*`, `ANTHROPIC_*`, `GEMINI_*`, `GOOGLE_API*`, `AZURE_*`, `GCP_*`, `CAPSULE_SIGNING_KEY`, and `*_SECRET*`/`*_TOKEN*`/`*_PASSWORD*`/`*_API_KEY*`/`*_PRIVATE_KEY*`/`*_PAT` variables to `NA_character_` before `callr::rscript()` (`scrub_secrets = TRUE`), removing them from the child OS environment and recording scrubbed variable names (never values) in `scrubbed_env_vars`. |
| **VULN-11** | `render_certificate()` | Passing `htmltools::HTML()`-classed strings or malicious project/path/git/diff metadata could bypass escaping in HTML or break Markdown tables. | Added `safe_html_text()` (stripping `"html"` class before escaping), `escape_html_strict()`, `sanitize_markdown_cell()`, `sanitize_markdown_inline()`, and a strict `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline';">` header in standalone HTML5 certificates. |

---

## Container Linter Security Coverage

`lint_container_spec()` statically audits both generated and third-party specifications:

- **Dockerfile**: `DF001` (unpinned/latest base), `DF002` (apt cache cleanup), `DF003` (`--no-install-recommends`), `DF004` (root-only execution), `DF005` (`HEALTHCHECK`), `DF006` (`ADD` vs `COPY`), `DF007` (`COPY .` before `renv::restore()`), `DF008` (baked secrets in `ENV`/`ARG`), `DF009` (`WORKDIR`), `DF010` (`pip --no-cache-dir`), `DF011` (`curl|sh` / `wget|bash` remote script execution).
- **Docker Compose**: `DC001` (YAML validity / `services`), `DC002` (unpinned `:latest`), `DC003` (`privileged: true`), `DC004` (`healthcheck`), `DC005` (resource limits), `DC006` (hardcoded secrets in `environment`), `DC007` (`no-new-privileges:true`), `DC008` (`network_mode`/`pid`/`ipc: host`), `DC009` (dangerous host mounts like `docker.sock` or `/`).
- **Apptainer**: `AP001` (required headers), `AP002` (unpinned `From:`), `AP003` (apt cleanup), `AP004` (`set -e` in `%post`), `AP005` (`%labels`/`%environment`/`%test`), `AP006` (`%runscript`), `AP007` (`curl|sh` / `wget|bash`), `AP008` (`--no-install-recommends`).

---

## Reporting a Vulnerability

Please report security issues privately to **Marcus Harris** (`marcus.harris.uconn@gmail.com`) or open a security advisory on <https://github.com/MarcusHarrisUConn/rcapsule/security/advisories>.
