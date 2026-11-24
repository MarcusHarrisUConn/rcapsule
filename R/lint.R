# Static reproducibility & security linter for Dockerfile, Compose, and Apptainer specs

#' Lint a Container Specification for Reproducibility and Security Issues
#'
#' Performs static analysis on a `Dockerfile`, `docker-compose.yml`, or
#' Apptainer `.def` recipe, accepting an `rcapsule_spec` object, a file path,
#' or a character vector of spec lines. Checks for unpinned `:latest` or
#' untagged base images, missing `apt` cache cleanup, root-only execution,
#' cache-busting `COPY` order, hardcoded secrets, privileged containers, and
#' missing safety guards.
#'
#' @param spec An `rcapsule_spec` object (from [compile_dockerfile()],
#'   [compile_compose()], or [compile_apptainer()]), a path to a spec file, or
#'   a character string/vector containing the specification text.
#' @param type Spec format: `"auto"` (default) infers from class, file name, or
#'   contents; or explicitly `"dockerfile"`, `"compose"`, or `"apptainer"`.
#'
#' @return An S3 object of class `rcapsule_lint` with fields:
#'   - `spec_type`: `"dockerfile"`, `"compose"`, or `"apptainer"`
#'   - `passed`: logical (`TRUE` when `n_errors == 0L`)
#'   - `n_errors`, `n_warnings`, `n_info`: integer counts
#'   - `issues`: [tibble::tibble()] with columns `rule_id`, `severity`, `line`,
#'     `message`, and `suggestion`
#' @export
#' @examples
#' bad_df <- c(
#'   "FROM rocker/r-ver:latest",
#'   "RUN apt-get update && apt-get install -y libcurl4-openssl-dev",
#'   "COPY . ."
#' )
#' lint_container_spec(bad_df, type = "dockerfile")
lint_container_spec <- function(spec, type = c("auto", "dockerfile", "compose", "apptainer")) {
  type <- match.arg(type)
  raw_info <- extract_spec_lines(spec, type)
  lines <- raw_info$lines
  spec_type <- raw_info$spec_type

  issues <- switch(
    spec_type,
    dockerfile = lint_dockerfile_lines(lines),
    compose = lint_compose_lines(lines),
    apptainer = lint_apptainer_lines(lines)
  )

  n_errors <- sum(issues$severity == "error")
  n_warnings <- sum(issues$severity == "warning")
  n_info <- sum(issues$severity == "info")

  structure(
    list(
      spec_type = spec_type,
      passed = identical(n_errors, 0L),
      n_errors = as.integer(n_errors),
      n_warnings = as.integer(n_warnings),
      n_info = as.integer(n_info),
      issues = issues
    ),
    class = "rcapsule_lint"
  )
}

# Normalize spec input into character lines + detected spec_type
extract_spec_lines <- function(spec, type) {
  inferred <- NULL
  lines <- NULL

  if (inherits(spec, "rcapsule_spec")) {
    inferred <- spec$spec_type
    lines <- spec$lines
  } else if (is.character(spec)) {
    if (length(spec) == 1L && !grepl("\n", spec, fixed = TRUE) && fs::file_exists(spec)) {
      bn <- tolower(basename(spec))
      if (grepl("dockerfile", bn, fixed = TRUE)) {
        inferred <- "dockerfile"
      } else if (grepl("compose|\\.ya?ml$", bn)) {
        inferred <- "compose"
      } else if (grepl("\\.def$", bn)) {
        inferred <- "apptainer"
      }
      lines <- readLines(spec, warn = FALSE, encoding = "UTF-8")
    } else {
      lines <- unlist(strsplit(spec, "\n", fixed = TRUE), use.names = FALSE)
    }
  } else {
    cli::cli_abort("{.arg spec} must be an {.cls rcapsule_spec}, file path, or character vector.")
  }

  if (type != "auto") {
    spec_type <- type
  } else if (!is.null(inferred)) {
    spec_type <- inferred
  } else {
    joined <- paste(lines, collapse = "\n")
    if (grepl("(?m)^\\s*Bootstrap\\s*:", joined, perl = TRUE)) {
      spec_type <- "apptainer"
    } else if (grepl("(?m)^\\s*FROM\\s+", joined, perl = TRUE)) {
      spec_type <- "dockerfile"
    } else if (grepl("(?m)^\\s*services\\s*:", joined, perl = TRUE)) {
      spec_type <- "compose"
    } else {
      cli::cli_abort("Could not infer container spec type; please pass {.arg type} explicitly.")
    }
  }

  list(lines = lines, spec_type = spec_type)
}

make_issue_tbl <- function(rows) {
  if (length(rows) == 0L) {
    return(tibble::tibble(
      rule_id = character(),
      severity = character(),
      line = integer(),
      message = character(),
      suggestion = character()
    ))
  }
  tibble::tibble(
    rule_id = vapply(rows, `[[`, character(1L), "rule_id"),
    severity = vapply(rows, `[[`, character(1L), "severity"),
    line = vapply(rows, `[[`, integer(1L), "line"),
    message = vapply(rows, `[[`, character(1L), "message"),
    suggestion = vapply(rows, `[[`, character(1L), "suggestion")
  )
}

# Reassemble line-continued Dockerfile instructions with starting line numbers
parse_dockerfile_instructions <- function(lines) {
  out <- list()
  i <- 1L
  n <- length(lines)
  while (i <= n) {
    ln <- lines[[i]]
    trimmed <- trimws(ln)
    if (!nzchar(trimmed) || startsWith(trimmed, "#")) {
      i <- i + 1L
      next
    }
    start_line <- i
    buf <- trimmed
    while (grepl("\\\\\\s*$", buf) && i < n) {
      buf <- sub("\\\\\\s*$", " ", buf)
      i <- i + 1L
      next_ln <- trimws(lines[[i]])
      if (startsWith(next_ln, "#")) {
        next
      }
      buf <- paste0(buf, next_ln)
    }
    m <- regexec("^([A-Za-z]+)\\s+(.*)$", buf)
    parts <- regmatches(buf, m)[[1L]]
    if (length(parts) == 3L) {
      out[[length(out) + 1L]] <- list(
        line = start_line,
        cmd = toupper(parts[[2L]]),
        args = trimws(parts[[3L]]),
        raw = buf
      )
    }
    i <- i + 1L
  }
  out
}

lint_dockerfile_lines <- function(lines) {
  insts <- parse_dockerfile_instructions(lines)
  issues <- list()
  add_issue <- function(rule_id, severity, line, message, suggestion) {
    issues[[length(issues) + 1L]] <<- list(
      rule_id = rule_id,
      severity = severity,
      line = as.integer(line),
      message = message,
      suggestion = suggestion
    )
  }

  from_indices <- which(vapply(insts, function(x) x$cmd == "FROM", logical(1L)))
  if (length(from_indices) == 0L) {
    add_issue("DF001", "error", 1L, "Missing FROM instruction.", "Add a pinned FROM base image (e.g. FROM rocker/r-ver:4.4.1).")
    return(make_issue_tbl(issues))
  }

  # DF001: Unpinned FROM images
  for (idx in from_indices) {
    ins <- insts[[idx]]
    # Strip optional --platform=... flag
    arg_clean <- sub("^--platform=\\S+\\s+", "", ins$args)
    img <- strsplit(arg_clean, "\\s+")[[1L]][[1L]]
    if (identical(tolower(img), "scratch")) next
    is_latest <- grepl(":latest(\\z|@)", img, ignore.case = TRUE, perl = TRUE)
    if (is_latest) {
      add_issue("DF001", "error", ins$line,
        paste0("Base image '", img, "' uses mutable ':latest' tag."),
        "Pin an explicit version tag or @sha256 digest.")
    } else if (!has_pinned_image_tag_or_digest(img) && !grepl("\\A\\$\\{?[A-Za-z_]", img, perl = TRUE)) {
      add_issue("DF001", "error", ins$line,
        paste0("Base image '", img, "' has no pinned tag or digest."),
        "Pin an explicit version tag (e.g. rocker/r-ver:4.4.1) or @sha256 digest.")
    }
  }

  # Inspect RUN, ADD, COPY, ENV, ARG instructions
  copy_all_line <- NA_integer_
  renv_restore_line <- NA_integer_

  for (ins in insts) {
    if (ins$cmd == "RUN") {
      if (grepl("apt-get\\s+install", ins$args, perl = TRUE)) {
        if (!grepl("rm\\s+-rf\\s+/var/lib/apt/lists/\\*", ins$args, perl = TRUE)) {
          add_issue("DF002", "warning", ins$line,
            "apt-get install without cleaning /var/lib/apt/lists/* bloats image layers.",
            "Append '&& rm -rf /var/lib/apt/lists/*' in the same RUN layer.")
        }
        if (!grepl("--no-install-recommends", ins$args, fixed = TRUE)) {
          add_issue("DF003", "warning", ins$line,
            "apt-get install missing '--no-install-recommends'.",
            "Pass '--no-install-recommends' to keep images lean and deterministic.")
        }
      }
      if (grepl("pip3?\\s+install", ins$args, perl = TRUE) && !grepl("--no-cache-dir", ins$args, fixed = TRUE)) {
        add_issue("DF010", "warning", ins$line,
          "pip install missing '--no-cache-dir'.",
          "Pass '--no-cache-dir' to avoid caching wheel archives inside image layers.")
      }
      if (grepl("\\b(curl|wget)\\b[^\\n]*\\|\\s*(sudo\\s+)?(ba|da|z|k)?sh\\b", ins$args, ignore.case = TRUE, perl = TRUE)) {
        add_issue("DF011", "error", ins$line,
          "Piping remote script directly to shell ('curl|sh' / 'wget|bash') is an unsafe supply-chain anti-pattern.",
          "Download a pinned versioned release archive, verify its SHA-256 checksum, and then install.")
      }
      if (grepl("renv::restore", ins$args, fixed = TRUE) && is.na(renv_restore_line)) {
        renv_restore_line <- ins$line
      }
    }

    if (ins$cmd == "ADD") {
      if (!grepl("https?://|\\.tar(\\.gz|\\.bz2|\\.xz)?\\b", ins$args, ignore.case = TRUE, perl = TRUE)) {
        add_issue("DF006", "warning", ins$line,
          "Prefer COPY over ADD for local files.",
          "Replace ADD with COPY unless auto-extracting a local tar archive.")
      }
    }

    if (ins$cmd == "COPY" && is.na(copy_all_line)) {
      # Match COPY . . or COPY [--chown=...] . /capsule/
      arg_no_flags <- gsub("--[a-zA-Z0-9_-]+=\\S+\\s+", "", ins$args, perl = TRUE)
      if (grepl("^\\.\\s+\\S+", arg_no_flags, perl = TRUE)) {
        copy_all_line <- ins$line
      }
    }

    if (ins$cmd %in% c("ENV", "ARG")) {
      secret_kv_pat <- "\\b([A-Z0-9_]*(?:PASSWORD|PASSWD|SECRET|API_KEY|ACCESS_KEY|PRIVATE_KEY|SIGNING_KEY|TOKEN|PAT)|DATABASE_URL)\\s*(?:=|\\s+)\\s*['\"]?([^$\\s'\"]+)['\"]?"
      if (grepl(secret_kv_pat, ins$args, ignore.case = TRUE, perl = TRUE)) {
        add_issue("DF008", "warning", ins$line,
          paste0("Potential hardcoded secret detected in ", ins$cmd, " instruction."),
          "Pass secrets at runtime via environment variables or Docker secrets, never baked into images.")
      }
    }
  }

  # DF007: COPY . . before renv::restore()
  if (!is.na(copy_all_line) && !is.na(renv_restore_line) && copy_all_line < renv_restore_line) {
    add_issue("DF007", "warning", copy_all_line,
      "Copying full project context before renv::restore() busts Docker build cache on every edit.",
      "COPY renv.lock first, run renv::restore(), then COPY remaining project files.")
  }

  # Inspect final stage for USER, HEALTHCHECK, WORKDIR, LABEL
  last_from <- from_indices[[length(from_indices)]]
  final_stage <- insts[seq(last_from, length(insts))]
  final_cmds <- vapply(final_stage, `[[`, character(1L), "cmd")

  user_insts <- final_stage[final_cmds == "USER"]
  if (length(user_insts) == 0L) {
    add_issue("DF004", "error", insts[[last_from]]$line,
      "Final stage has no non-root USER instruction; container runs as root.",
      "Create and switch to a dedicated non-root user (e.g., USER capsule).")
  } else {
    last_user <- tolower(trimws(user_insts[[length(user_insts)]]$args))
    if (last_user %in% c("root", "0", "0:0", "root:root")) {
      add_issue("DF004", "error", user_insts[[length(user_insts)]]$line,
        "Final USER instruction drops back to root.",
        "Ensure the final active USER is a non-root user.")
    }
  }

  if (!("HEALTHCHECK" %in% final_cmds)) {
    add_issue("DF005", "info", insts[[last_from]]$line,
      "No HEALTHCHECK instruction in final stage.",
      "Add a HEALTHCHECK instruction for production container orchestration.")
  }

  if (!("WORKDIR" %in% final_cmds)) {
    add_issue("DF009", "info", insts[[last_from]]$line,
      "No WORKDIR instruction in final stage.",
      "Set an explicit WORKDIR (e.g., WORKDIR /capsule).")
  }

  make_issue_tbl(issues)
}

lint_compose_lines <- function(lines) {
  issues <- list()
  add_issue <- function(rule_id, severity, line, message, suggestion) {
    issues[[length(issues) + 1L]] <<- list(
      rule_id = rule_id,
      severity = severity,
      line = as.integer(line),
      message = message,
      suggestion = suggestion
    )
  }

  content <- paste(lines, collapse = "\n")
  cfg <- tryCatch(safe_yaml_load(content), error = function(e) e)
  if (inherits(cfg, "error") || !is.list(cfg)) {
    add_issue("DC001", "error", 1L,
      paste0("Invalid YAML syntax: ", if (inherits(cfg, "error")) conditionMessage(cfg) else "not a mapping"),
      "Fix YAML indentation and structure.")
    return(make_issue_tbl(issues))
  }

  if (is.null(cfg$services) || !is.list(cfg$services) || length(cfg$services) == 0L) {
    add_issue("DC001", "error", 1L,
      "Missing or empty 'services:' section in docker-compose.yml.",
      "Define at least one service under 'services:'.")
    return(make_issue_tbl(issues))
  }

  find_line <- function(pattern) {
    hits <- grep(pattern, lines, perl = TRUE)
    if (length(hits) > 0L) hits[[1L]] else 1L
  }

  for (svc_name in names(cfg$services)) {
    svc <- cfg$services[[svc_name]]
    if (!is.list(svc)) next
    svc_line <- find_line(paste0("^\\s*", svc_name, "\\s*:"))

    # DC002: Unpinned :latest or untagged image (handles registry ports like localhost:5000/img)
    if (!is.null(svc$image) && is.character(svc$image)) {
      img <- svc$image[[1L]]
      if (!has_pinned_image_tag_or_digest(img)) {
        add_issue("DC002", "error", svc_line,
          paste0("Service '", svc_name, "' uses unpinned image '", img, "'."),
          "Pin an explicit version tag or @sha256 digest.")
      }
    }

    # DC003: Privileged mode
    if (isTRUE(svc$privileged)) {
      add_issue("DC003", "warning", svc_line,
        paste0("Service '", svc_name, "' runs with privileged: true."),
        "Remove 'privileged: true' and grant only minimal capabilities if needed.")
    }

    # DC004: Missing healthcheck
    if (is.null(svc$healthcheck)) {
      add_issue("DC004", "warning", svc_line,
        paste0("Service '", svc_name, "' has no healthcheck defined."),
        "Add a 'healthcheck:' block to enable reliable readiness detection.")
    }

    # DC005: Missing resource limits
    has_limits <- !is.null(svc$deploy$resources$limits) || !is.null(svc$mem_limit)
    if (!has_limits) {
      add_issue("DC005", "info", svc_line,
        paste0("Service '", svc_name, "' has no CPU/memory limits."),
        "Configure 'deploy.resources.limits' to prevent noisy-neighbor exhaustion.")
    }

    # DC006: Hardcoded secrets in environment
    env_entries <- svc$environment
    if (!is.null(env_entries)) {
      env_strs <- if (is.list(env_entries) && !is.null(names(env_entries))) {
        paste0(names(env_entries), "=", unlist(env_entries))
      } else {
        as.character(unlist(env_entries))
      }
      secret_env_pat <- "^([A-Z0-9_]*(?:PASSWORD|PASSWD|SECRET|API_KEY|ACCESS_KEY|PRIVATE_KEY|SIGNING_KEY|TOKEN|PAT)|DATABASE_URL)\\s*=\\s*['\"]?[^$\\s'\"]+"
      for (es in env_strs) {
        if (grepl(secret_env_pat, es, ignore.case = TRUE, perl = TRUE)) {
          add_issue("DC006", "warning", svc_line,
            paste0("Service '", svc_name, "' may contain a hardcoded secret in environment."),
            "Use '${VAR}' environment substitution or Docker secrets instead of literal credentials.")
        }
      }
    }

    # DC007: Missing no-new-privileges
    sec_opts <- as.character(unlist(svc$security_opt %||% character()))
    if (!any(grepl("no-new-privileges:true", sec_opts, fixed = TRUE))) {
      add_issue("DC007", "warning", svc_line,
        paste0("Service '", svc_name, "' missing 'no-new-privileges:true' security option."),
        "Add 'security_opt: [\"no-new-privileges:true\"]' to harden the container.")
    }

    # DC008: Host network/PID/IPC namespace sharing
    if (identical(tolower(as.character(svc$network_mode %||% "")), "host") ||
      identical(tolower(as.character(svc$pid %||% "")), "host") ||
      identical(tolower(as.character(svc$ipc %||% "")), "host")) {
      add_issue("DC008", "error", svc_line,
        paste0("Service '", svc_name, "' shares host namespace (network_mode/pid/ipc: host)."),
        "Use an isolated bridge network rather than sharing host namespaces.")
    }

    # DC009: Dangerous host mounts (docker.sock or host root/etc)
    vols <- as.character(unlist(svc$volumes %||% character()))
    for (v in vols) {
      host_src <- strsplit(v, ":", fixed = TRUE)[[1L]][[1L]]
      norm_src <- gsub("/+", "/", host_src)
      if (nchar(norm_src) > 1L) norm_src <- sub("/+\\z", "", norm_src, perl = TRUE)
      if (grepl("(docker|podman)\\.sock\\z", norm_src, ignore.case = TRUE, perl = TRUE) ||
        norm_src %in% c("/", "/etc", "/root", "/proc", "/sys", "/dev", "/var/run", "/run")) {
        add_issue("DC009", "warning", svc_line,
          paste0("Service '", svc_name, "' mounts sensitive host path '", host_src, "'."),
          "Avoid mounting Docker socket or sensitive host system directories into containers.")
      }
    }
  }

  make_issue_tbl(issues)
}

lint_apptainer_lines <- function(lines) {
  issues <- list()
  add_issue <- function(rule_id, severity, line, message, suggestion) {
    issues[[length(issues) + 1L]] <<- list(
      rule_id = rule_id,
      severity = severity,
      line = as.integer(line),
      message = message,
      suggestion = suggestion
    )
  }

  boot_idx <- grep("^\\s*Bootstrap\\s*:", lines, ignore.case = TRUE)
  from_idx <- grep("^\\s*From\\s*:", lines, ignore.case = TRUE)

  if (length(boot_idx) == 0L || length(from_idx) == 0L) {
    add_issue("AP001", "error", 1L,
      "Apptainer recipe missing required 'Bootstrap:' or 'From:' header.",
      "Specify 'Bootstrap: docker' and a pinned 'From:' image at the top of the recipe.")
  } else {
    from_val <- trimws(sub("^\\s*From\\s*:\\s*", "", lines[[from_idx[[1L]]]], ignore.case = TRUE))
    if (!has_pinned_image_tag_or_digest(from_val)) {
      add_issue("AP002", "error", from_idx[[1L]],
        paste0("Apptainer 'From:' image '", from_val, "' is not pinned to a version tag or digest."),
        "Pin an explicit version tag (e.g. rocker/r-ver:4.4.1) or @sha256 digest.")
    }
  }

  # Extract sections
  sec_starts <- grep("^\\s*%[a-zA-Z]+\\s*$", lines)
  sections <- list()
  if (length(sec_starts) > 0L) {
    for (k in seq_along(sec_starts)) {
      s_line <- sec_starts[[k]]
      e_line <- if (k < length(sec_starts)) sec_starts[[k + 1L]] - 1L else length(lines)
      sec_name <- tolower(trimws(lines[[s_line]]))
      body <- if (e_line > s_line) lines[(s_line + 1L):e_line] else character()
      sections[[sec_name]] <- list(line = s_line, body = body)
    }
  }

  if (!is.null(sections[["%post"]])) {
    post_text <- paste(sections[["%post"]]$body, collapse = "\n")
    post_line <- sections[["%post"]]$line
    if (grepl("apt-get\\s+install", post_text, perl = TRUE)) {
      if (!grepl("rm\\s+-rf\\s+/var/lib/apt/lists/\\*", post_text, perl = TRUE)) {
        add_issue("AP003", "warning", post_line,
          "%post installs apt packages without cleaning /var/lib/apt/lists/*.",
          "Add 'rm -rf /var/lib/apt/lists/*' at the end of the apt-get command.")
      }
      if (!grepl("--no-install-recommends", post_text, fixed = TRUE)) {
        add_issue("AP008", "warning", post_line,
          "%post apt-get install missing '--no-install-recommends'.",
          "Pass '--no-install-recommends' to keep Apptainer SIF images lean and deterministic.")
      }
    }
    if (!grepl("set\\s+-[a-zA-Z]*e", post_text, perl = TRUE)) {
      add_issue("AP004", "warning", post_line,
        "%post lacks 'set -e' / 'set -euo pipefail' fail-fast guard.",
        "Add 'set -euo pipefail' at the start of %post so build errors abort cleanly.")
    }
    if (grepl("\\b(curl|wget)\\b[^\\n]*\\|\\s*(sudo\\s+)?(ba|da|z|k)?sh\\b", post_text, ignore.case = TRUE, perl = TRUE)) {
      add_issue("AP007", "error", post_line,
        "%post pipes remote script directly to shell ('curl|sh' / 'wget|bash').",
        "Download a pinned archive and verify its checksum before installing.")
    }
  }

  if (is.null(sections[["%runscript"]])) {
    add_issue("AP006", "warning", 1L,
      "Apptainer recipe missing %runscript section.",
      "Add a %runscript section defining the default container execution command.")
  }

  missing_meta <- setdiff(c("%labels", "%environment", "%test"), names(sections))
  if (length(missing_meta) > 0L) {
    add_issue("AP005", "info", 1L,
      paste0("Apptainer recipe missing recommended section(s): ", paste(missing_meta, collapse = ", "), "."),
      "Include %labels, %environment, and %test for full HPC provenance and verification.")
  }

  make_issue_tbl(issues)
}

#' @export
print.rcapsule_lint <- function(x, ...) {
  status_lbl <- if (isTRUE(x$passed)) "PASS" else "FAIL"
  cli::cli_h1("rcapsule Container Lint ({x$spec_type}): {status_lbl}")
  cli::cli_text(
    "Errors: {.val {x$n_errors}} | Warnings: {.val {x$n_warnings}} | Info: {.val {x$n_info}}"
  )
  if (nrow(x$issues) == 0L) {
    cli::cli_alert_success("No issues found.")
  } else {
    for (i in seq_len(nrow(x$issues))) {
      row <- x$issues[i, ]
      msg <- paste0("[", row$rule_id, "] (line ", row$line, ") ", row$message)
      if (row$severity == "error") {
        cli::cli_alert_danger("{msg}")
      } else if (row$severity == "warning") {
        cli::cli_alert_warning("{msg}")
      } else {
        cli::cli_alert_info("{msg}")
      }
    }
  }
  invisible(x)
}
