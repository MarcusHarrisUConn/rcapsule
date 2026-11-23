# Journal-ready Markdown and standalone HTML reproducibility verification certificates

short_sha <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(x)) return("-")
  substr(as.character(x), 1L, 12L)
}

fmt_num <- function(x) {
  if (is.null(x) || is.na(x)) return("-")
  if (is.infinite(x)) return("Inf")
  trimws(formatC(x, format = "g", digits = 4L))
}

status_label <- function(status) {
  switch(
    status,
    verified_exact = "VERIFIED (EXACT)",
    verified_within_tolerance = "VERIFIED (WITHIN TOLERANCE)",
    exact_match = "EXACT MATCH",
    within_tolerance = "WITHIN TOLERANCE",
    mismatch = "MISMATCH",
    missing = "MISSING",
    "FAILED"
  )
}

# Build GitHub-Flavored Markdown reproducibility certificate (HTML/table-escaped)
build_certificate_markdown <- function(v, title) {
  m <- v$manifest
  tcs <- unlist(m$environment$toolchains)
  tc_str <- if (length(tcs) > 0L) sanitize_markdown_cell(paste(tcs, collapse = ", ")) else "Standard R"
  git_str <- if (isTRUE(m$project$git$is_repo)) {
    paste0(
      "`", sanitize_markdown_cell(short_sha(m$project$git$commit)), "` (branch `",
      sanitize_markdown_cell(m$project$git$branch %||% "detached"), "`, dirty=",
      if (isTRUE(m$project$git$dirty)) "true" else "false", ")"
    )
  } else {
    "Not a Git repository"
  }

  sig_str <- if (isTRUE(v$manifest_integrity$signed)) {
    if (isTRUE(v$manifest_integrity$signature_valid)) {
      "HMAC-SHA256 Verified"
    } else if (is.na(v$manifest_integrity$signature_valid)) {
      "HMAC-SHA256 Present (Key Not Provided)"
    } else {
      "HMAC-SHA256 INVALID"
    }
  } else {
    "Unsigned (SHA-256 Content Digest Only)"
  }

  extra_arts <- v$extra_artifacts %||% character()
  n_scrubbed <- length(v$scrubbed_env_vars %||% character())

  lines <- c(
    paste0("# ", sanitize_markdown_inline(title)),
    "",
    paste0("> **Verification Verdict:** **", status_label(v$status), "**  "),
    paste0("> **Capsule ID:** `", sanitize_markdown_inline(m$capsule_id), "` | **Verified At:** `", sanitize_markdown_inline(v$verified_at), "` | **Runner:** `", sanitize_markdown_inline(v$runner), "` (", v$duration_sec, "s)"),
    "",
    "## 1. Provenance & Environment Summary",
    "",
    "| Field | Recorded Value |",
    "| :--- | :--- |",
    paste0("| Project | `", sanitize_markdown_cell(m$project$name), "` (`", sanitize_markdown_cell(m$project$type), "`) |"),
    paste0("| Entrypoint | `", sanitize_markdown_cell(v$entrypoint), "` |"),
    paste0("| Git Revision | ", git_str, " |"),
    paste0("| Manifest R Version | `", sanitize_markdown_cell(m$environment$r_version), "` |"),
    paste0("| Verification Host | R `", sanitize_markdown_cell(v$environment$r_version), "` on `", sanitize_markdown_cell(v$environment$platform), "` (`", sanitize_markdown_cell(v$environment$os), "`) |"),
    paste0("| Environment Digest | `", sanitize_markdown_cell(short_sha(m$environment$environment_digest)), "` |"),
    paste0("| Detected Toolchains | ", tc_str, " |"),
    paste0("| OS System Libraries | ", length(m$environment$sysreqs), " apt packages |"),
    paste0("| RNG Configuration | Seed `", sanitize_markdown_cell(v$rng$seed %||% "unset"), "` (`", sanitize_markdown_cell(paste(v$rng$kind, collapse = " / ")), "`) |"),
    paste0("| Ambient Secrets Scrubbed | ", n_scrubbed, " variable(s) |"),
    paste0("| Unexpected Extra Artifacts | ", length(extra_arts), " file(s) |"),
    paste0("| Execution Exit Status | `", v$exit_status, "` |"),
    "",
    "## 2. Cryptographic Manifest Integrity",
    "",
    "| Check | Status | Details |",
    "| :--- | :--- | :--- |",
    paste0("| Canonical Content Digest | ", if (isTRUE(v$manifest_integrity$content_valid)) "PASS" else "FAIL",
           " | Recorded `", sanitize_markdown_cell(short_sha(v$manifest_integrity$recorded_digest)),
           "` vs Computed `", sanitize_markdown_cell(short_sha(v$manifest_integrity$computed_digest)), "` |"),
    paste0("| Keyed Signature | ", if (isTRUE(v$manifest_integrity$valid)) "PASS" else "FAIL", " | ", sig_str, " |"),
    ""
  )

  # Section 3: Outputs table
  lines <- c(lines, "## 3. Output Artifact Verification", "")
  if (nrow(v$output_checks) > 0L) {
    lines <- c(
      lines,
      "| Artifact | Status | Expected SHA-256 | Actual SHA-256 | Max Abs Diff | Max Rel Diff | Tolerance (abs / rel) | Details |",
      "| :--- | :--- | :--- | :--- | ---: | ---: | :--- | :--- |"
    )
    for (i in seq_len(nrow(v$output_checks))) {
      r <- v$output_checks[i, ]
      lines <- c(
        lines,
        paste0(
          "| `", sanitize_markdown_cell(r$path), "` | **", status_label(r$status), "** | `", sanitize_markdown_cell(short_sha(r$expected_sha256)),
          "` | `", sanitize_markdown_cell(short_sha(r$actual_sha256)), "` | ", fmt_num(r$max_abs_diff),
          " | ", fmt_num(r$max_rel_diff), " | ", fmt_num(r$abs_tol), " / ", fmt_num(r$rel_tol),
          " | ", sanitize_markdown_cell(r$details), " |"
        )
      )
    }
  } else {
    lines <- c(lines, "_No output artifacts recorded in manifest._")
  }

  if (length(extra_arts) > 0L) {
    lines <- c(
      lines,
      "",
      paste0("**Unexpected Extra Artifacts Detected:** ", paste0("`", vapply(extra_arts, sanitize_markdown_inline, character(1L)), "`", collapse = ", "))
    )
  }

  # Section 4: Inputs & Scripts integrity
  lines <- c(lines, "", "## 4. Input & Script Integrity", "")
  combined <- rbind(
    if (nrow(v$input_checks) > 0L) cbind(role = "input", v$input_checks) else NULL,
    if (nrow(v$script_checks) > 0L) cbind(role = "script", v$script_checks) else NULL
  )
  if (!is.null(combined) && nrow(combined) > 0L) {
    lines <- c(
      lines,
      "| Role | Path | Status | Expected SHA-256 | Actual SHA-256 |",
      "| :--- | :--- | :--- | :--- | :--- |"
    )
    for (i in seq_len(nrow(combined))) {
      r <- combined[i, ]
      lines <- c(
        lines,
        paste0(
          "| ", sanitize_markdown_cell(r$role), " | `", sanitize_markdown_cell(r$path), "` | ", status_label(r$status),
          " | `", sanitize_markdown_cell(short_sha(r$expected_sha256)), "` | `", sanitize_markdown_cell(short_sha(r$actual_sha256)), "` |"
        )
      )
    }
  } else {
    lines <- c(lines, "_No input or script artifacts recorded._")
  }

  if (length(v$failure_reasons) > 0L) {
    lines <- c(lines, "", "## 5. Failure Diagnostics", "")
    for (fr in v$failure_reasons) {
      lines <- c(lines, paste0("- ", sanitize_markdown_inline(fr)))
    }
  }

  lines <- c(
    lines,
    "",
    "---",
    paste0("_Generated by `rcapsule` ", as.character(utils::packageVersion("rcapsule")), " (schema v", sanitize_markdown_inline(m$schema_version), ")._")
  )

  paste0(paste(lines, collapse = "\n"), "\n")
}

# Build self-contained HTML5 reproducibility certificate using htmltools with strict XSS escaping + CSP
build_certificate_html <- function(v, title) {
  m <- v$manifest
  tcs <- unlist(m$environment$toolchains)
  tc_str <- safe_html_text(if (length(tcs) > 0L) paste(tcs, collapse = ", ") else "Standard R")
  safe_title <- safe_html_text(title)
  extra_arts <- v$extra_artifacts %||% character()
  n_scrubbed <- length(v$scrubbed_env_vars %||% character())

  theme_cls <- switch(
    v$status,
    verified_exact = "status-exact",
    verified_within_tolerance = "status-tol",
    "status-fail"
  )

  badge_tag <- function(st) {
    cls <- switch(
      st,
      exact_match = "badge badge-pass",
      within_tolerance = "badge badge-warn",
      "badge badge-fail"
    )
    htmltools::tags$span(class = cls, status_label(st))
  }

  output_rows <- if (nrow(v$output_checks) > 0L) {
    lapply(seq_len(nrow(v$output_checks)), function(i) {
      r <- v$output_checks[i, ]
      htmltools::tags$tr(
        htmltools::tags$td(htmltools::tags$code(safe_html_text(r$path))),
        htmltools::tags$td(badge_tag(r$status)),
        htmltools::tags$td(htmltools::tags$code(class = "sha", safe_html_text(short_sha(r$expected_sha256)))),
        htmltools::tags$td(htmltools::tags$code(class = "sha", safe_html_text(short_sha(r$actual_sha256)))),
        htmltools::tags$td(class = "num", fmt_num(r$max_abs_diff)),
        htmltools::tags$td(class = "num", fmt_num(r$max_rel_diff)),
        htmltools::tags$td(class = "num", paste0(fmt_num(r$abs_tol), " / ", fmt_num(r$rel_tol))),
        htmltools::tags$td(safe_html_text(r$details))
      )
    })
  } else {
    list(htmltools::tags$tr(htmltools::tags$td(colspan = "8", "No output artifacts recorded.")))
  }

  combined <- rbind(
    if (nrow(v$input_checks) > 0L) cbind(role = "input", v$input_checks) else NULL,
    if (nrow(v$script_checks) > 0L) cbind(role = "script", v$script_checks) else NULL
  )
  io_rows <- if (!is.null(combined) && nrow(combined) > 0L) {
    lapply(seq_len(nrow(combined)), function(i) {
      r <- combined[i, ]
      htmltools::tags$tr(
        htmltools::tags$td(safe_html_text(r$role)),
        htmltools::tags$td(htmltools::tags$code(safe_html_text(r$path))),
        htmltools::tags$td(badge_tag(r$status)),
        htmltools::tags$td(htmltools::tags$code(class = "sha", safe_html_text(short_sha(r$expected_sha256)))),
        htmltools::tags$td(htmltools::tags$code(class = "sha", safe_html_text(short_sha(r$actual_sha256))))
      )
    })
  } else {
    list(htmltools::tags$tr(htmltools::tags$td(colspan = "5", "No input or script artifacts recorded.")))
  }

  git_summary <- safe_html_text(if (isTRUE(m$project$git$is_repo)) {
    paste0(short_sha(m$project$git$commit), " (", m$project$git$branch %||% "detached", ", dirty=", isTRUE(m$project$git$dirty), ")")
  } else {
    "Not a Git repository"
  })

  fail_block <- if (length(v$failure_reasons) > 0L) {
    htmltools::tags$section(
      class = "card fail-box",
      htmltools::tags$h2("Failure Diagnostics"),
      htmltools::tags$ul(lapply(v$failure_reasons, function(fr) htmltools::tags$li(safe_html_text(fr))))
    )
  } else {
    NULL
  }

  extra_block <- if (length(extra_arts) > 0L) {
    htmltools::tags$section(
      class = "card",
      htmltools::tags$h2("Unexpected Extra Artifacts"),
      htmltools::tags$ul(lapply(extra_arts, function(ea) htmltools::tags$li(htmltools::tags$code(safe_html_text(ea)))))
    )
  } else {
    NULL
  }

  log_text <- safe_html_text(paste(
    c(
      if (nzchar(v$stdout %||% "")) c("=== STDOUT ===", v$stdout) else NULL,
      if (nzchar(v$stderr %||% "")) c("=== STDERR ===", v$stderr) else NULL
    ),
    collapse = "\n"
  ))

  css <- paste(
    ":root { --ink:#17212b; --muted:#52606d; --bg:#f7f9fc; --card:#ffffff; --border:#d9e2ec; --exact:#0d7a43; --exact-bg:#e6f6ee; --tol:#9c5700; --tol-bg:#fff4e0; --fail:#b42318; --fail-bg:#fdecec; }",
    "body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: var(--ink); background: var(--bg); margin: 0; padding: 28px 18px; line-height: 1.5; }",
    ".wrap { max-width: 1020px; margin: 0 auto; }",
    ".hero { border-radius: 12px; padding: 24px 28px; margin-bottom: 20px; border: 1px solid var(--border); }",
    ".status-exact { background: var(--exact-bg); border-color: #9ae0bc; }",
    ".status-tol { background: var(--tol-bg); border-color: #f4cc83; }",
    ".status-fail { background: var(--fail-bg); border-color: #f3a6a1; }",
    ".verdict { font-size: 13px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; margin-bottom: 6px; }",
    ".status-exact .verdict { color: var(--exact); } .status-tol .verdict { color: var(--tol); } .status-fail .verdict { color: var(--fail); }",
    "h1 { margin: 0 0 8px 0; font-size: 24px; }",
    "h2 { font-size: 16px; margin: 0 0 12px 0; border-bottom: 1px solid var(--border); padding-bottom: 6px; }",
    ".meta-row { display: flex; flex-wrap: wrap; gap: 16px; font-size: 13px; color: var(--muted); }",
    ".kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; margin-bottom: 20px; }",
    ".kpi { background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 14px 16px; }",
    ".kpi-label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted); }",
    ".kpi-val { font-size: 18px; font-weight: 700; margin-top: 4px; }",
    ".card { background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 18px 20px; margin-bottom: 18px; overflow-x: auto; }",
    ".fail-box { border-color: #f3a6a1; background: #fffafa; }",
    "table { width: 100%; border-collapse: collapse; font-size: 13px; }",
    "th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #edf2f7; vertical-align: top; }",
    "th { background: #f8fafc; font-weight: 600; color: #334e68; }",
    "td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }",
    "code { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 12px; background: #f1f5f9; padding: 1px 5px; border-radius: 4px; }",
    "code.sha { color: #334e68; }",
    ".badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }",
    ".badge-pass { background: var(--exact-bg); color: var(--exact); }",
    ".badge-warn { background: var(--tol-bg); color: var(--tol); }",
    ".badge-fail { background: var(--fail-bg); color: var(--fail); }",
    "pre { background: #0f172a; color: #e2e8f0; padding: 12px; border-radius: 8px; overflow-x: auto; font-size: 12px; }",
    "footer { text-align: center; font-size: 12px; color: var(--muted); margin-top: 20px; }",
    "@media print { body { background: #fff; padding: 0; } .card, .kpi, .hero { break-inside: avoid; } }",
    sep = "\n"
  )

  body_tag <- htmltools::tags$body(
    htmltools::tags$div(
      class = "wrap",
      htmltools::tags$header(
        class = paste("hero", theme_cls),
        htmltools::tags$div(class = "verdict", status_label(v$status)),
        htmltools::tags$h1(safe_title),
        htmltools::tags$div(
          class = "meta-row",
          htmltools::tags$span("Capsule ID: ", htmltools::tags$code(safe_html_text(m$capsule_id))),
          htmltools::tags$span("Project: ", htmltools::tags$strong(safe_html_text(m$project$name)), " (", safe_html_text(m$project$type), ")"),
          htmltools::tags$span("Verified: ", htmltools::tags$code(safe_html_text(v$verified_at))),
          htmltools::tags$span("Runner: ", htmltools::tags$code(safe_html_text(v$runner)), " (", v$duration_sec, "s)")
        )
      ),
      htmltools::tags$div(
        class = "kpis",
        htmltools::tags$div(
          class = "kpi",
          htmltools::tags$div(class = "kpi-label", "Outputs Verified"),
          htmltools::tags$div(class = "kpi-val", paste0(sum(v$output_checks$passed), " / ", nrow(v$output_checks)))
        ),
        htmltools::tags$div(
          class = "kpi",
          htmltools::tags$div(class = "kpi-label", "Inputs & Scripts"),
          htmltools::tags$div(
            class = "kpi-val",
            paste0(
              sum(v$input_checks$passed) + sum(v$script_checks$passed),
              " / ", nrow(v$input_checks) + nrow(v$script_checks)
            )
          )
        ),
        htmltools::tags$div(
          class = "kpi",
          htmltools::tags$div(class = "kpi-label", "Manifest Integrity"),
          htmltools::tags$div(class = "kpi-val", if (isTRUE(v$manifest_integrity$valid)) "VALID" else "INVALID")
        ),
        htmltools::tags$div(
          class = "kpi",
          htmltools::tags$div(class = "kpi-label", "Environment Digest"),
          htmltools::tags$div(class = "kpi-val", htmltools::tags$code(safe_html_text(short_sha(m$environment$environment_digest))))
        )
      ),
      fail_block,
      extra_block,
      htmltools::tags$section(
        class = "card",
        htmltools::tags$h2("Output Artifact Verification"),
        htmltools::tags$table(
          htmltools::tags$thead(
            htmltools::tags$tr(
              htmltools::tags$th("Artifact"),
              htmltools::tags$th("Status"),
              htmltools::tags$th("Expected SHA-256"),
              htmltools::tags$th("Actual SHA-256"),
              htmltools::tags$th(class = "num", "Max Abs Diff"),
              htmltools::tags$th(class = "num", "Max Rel Diff"),
              htmltools::tags$th(class = "num", "Tolerance"),
              htmltools::tags$th("Details")
            )
          ),
          htmltools::tags$tbody(output_rows)
        )
      ),
      htmltools::tags$section(
        class = "card",
        htmltools::tags$h2("Provenance & Runtime Environment"),
        htmltools::tags$table(
          htmltools::tags$tbody(
            htmltools::tags$tr(htmltools::tags$th("Entrypoint"), htmltools::tags$td(htmltools::tags$code(safe_html_text(v$entrypoint)))),
            htmltools::tags$tr(htmltools::tags$th("Git Revision"), htmltools::tags$td(git_summary)),
            htmltools::tags$tr(htmltools::tags$th("Manifest R Version"), htmltools::tags$td(safe_html_text(m$environment$r_version))),
            htmltools::tags$tr(htmltools::tags$th("Verification Host"), htmltools::tags$td(safe_html_text(paste0("R ", v$environment$r_version, " (", v$environment$platform, ", ", v$environment$os, ")")))),
            htmltools::tags$tr(htmltools::tags$th("Detected Toolchains"), htmltools::tags$td(tc_str)),
            htmltools::tags$tr(htmltools::tags$th("RNG Configuration"), htmltools::tags$td(safe_html_text(paste0("seed=", v$rng$seed %||% "unset", " (", paste(v$rng$kind, collapse = " / "), ")")))),
            htmltools::tags$tr(htmltools::tags$th("Ambient Secrets Scrubbed"), htmltools::tags$td(paste0(n_scrubbed, " variable(s)"))),
            htmltools::tags$tr(htmltools::tags$th("Content Digest"), htmltools::tags$td(htmltools::tags$code(safe_html_text(v$manifest_integrity$computed_digest)))),
            htmltools::tags$tr(htmltools::tags$th("HMAC Signature"), htmltools::tags$td(if (isTRUE(v$manifest_integrity$signed)) paste0("Signed (valid=", v$manifest_integrity$signature_valid, ")") else "Unsigned"))
          )
        )
      ),
      htmltools::tags$section(
        class = "card",
        htmltools::tags$h2("Input & Script Integrity"),
        htmltools::tags$table(
          htmltools::tags$thead(
            htmltools::tags$tr(
              htmltools::tags$th("Role"),
              htmltools::tags$th("Path"),
              htmltools::tags$th("Status"),
              htmltools::tags$th("Expected SHA-256"),
              htmltools::tags$th("Actual SHA-256")
            )
          ),
          htmltools::tags$tbody(io_rows)
        )
      ),
      if (nzchar(log_text)) {
        htmltools::tags$section(
          class = "card",
          htmltools::tags$details(
            htmltools::tags$summary(htmltools::tags$strong("Execution Log (stdout / stderr)")),
            htmltools::tags$pre(log_text)
          )
        )
      },
      htmltools::tags$footer(
        safe_html_text(paste0("Generated by rcapsule ", as.character(utils::packageVersion("rcapsule")),
                              " | Schema v", m$schema_version, " | Standalone Verification Certificate"))
      )
    )
  )

  paste0(
    "<!DOCTYPE html>\n",
    "<html lang=\"en\">\n",
    "<head>\n",
    "  <meta charset=\"utf-8\">\n",
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
    "  <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline';\">\n",
    "  <title>", escape_html_strict(safe_title), "</title>\n",
    "  <style>\n", css, "\n  </style>\n",
    "</head>\n",
    as.character(body_tag), "\n",
    "</html>\n"
  )
}

#' Render a Journal-Ready Reproducibility Verification Certificate
#'
#' Produces a publication-ready Markdown and/or standalone self-contained HTML5
#' reproducibility verification certificate from an `rcapsule_verification`
#' audit result. Suitable for journal peer-review supplements, Zenodo/OSF
#' archival packages, and CI reproducibility gates.
#'
#' @param verification An `rcapsule_verification` object returned by
#'   [verify_capsule()].
#' @param output Optional base output path (or exact file path when rendering a
#'   single format). When `format = "both"`, writes `<base>.md` and
#'   `<base>.html`. If `NULL`, returns rendered strings in memory without
#'   writing files.
#' @param format Output format: `"both"` (default), `"markdown"`, or `"html"`.
#' @param title Optional report title. Defaults to
#'   `"Reproducibility Verification Certificate: <project_name>"`.
#'
#' @return An S3 object of class `rcapsule_certificate` with fields `markdown`,
#'   `html`, `files` (named character vector of written paths), and
#'   `verification`.
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_cert_")
#' dir.create(tmp)
#' writeLines("write.csv(data.frame(a = 1:2), 'out.csv', row.names = FALSE)",
#'            file.path(tmp, "run.R"))
#' write.csv(data.frame(a = 1:2), file.path(tmp, "out.csv"), row.names = FALSE)
#' m <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
#' v <- verify_capsule(m, path = tmp)
#' cert <- render_certificate(v, output = file.path(tmp, "certificate"))
#' cert$files
#' unlink(tmp, recursive = TRUE)
render_certificate <- function(verification,
                               output = NULL,
                               format = c("both", "markdown", "html"),
                               title = NULL) {
  if (!inherits(verification, "rcapsule_verification")) {
    cli::cli_abort("{.arg verification} must be an {.cls rcapsule_verification} object.")
  }
  format <- match.arg(format)
  cert_title <- title %||% paste0("Reproducibility Verification Certificate: ", verification$manifest$project$name)

  md_str <- if (format %in% c("both", "markdown")) build_certificate_markdown(verification, cert_title) else NULL
  html_str <- if (format %in% c("both", "html")) build_certificate_html(verification, cert_title) else NULL

  written <- character()
  if (!is.null(output)) {
    fs::dir_create(fs::path_dir(output))
    if (identical(format, "both")) {
      base <- sub("\\.(md|html?)$", "", output, ignore.case = TRUE)
      md_path <- paste0(base, ".md")
      html_path <- paste0(base, ".html")
      writeLines(md_str, md_path, useBytes = TRUE)
      writeLines(html_str, html_path, useBytes = TRUE)
      written <- c(markdown = as.character(fs::path_norm(md_path)), html = as.character(fs::path_norm(html_path)))
    } else if (identical(format, "markdown")) {
      md_path <- if (grepl("\\.md$", output, ignore.case = TRUE)) output else paste0(output, ".md")
      writeLines(md_str, md_path, useBytes = TRUE)
      written <- c(markdown = as.character(fs::path_norm(md_path)))
    } else {
      html_path <- if (grepl("\\.html?$", output, ignore.case = TRUE)) output else paste0(output, ".html")
      writeLines(html_str, html_path, useBytes = TRUE)
      written <- c(html = as.character(fs::path_norm(html_path)))
    }
  }

  structure(
    list(
      title = cert_title,
      markdown = md_str,
      html = html_str,
      files = written,
      verification = verification
    ),
    class = "rcapsule_certificate"
  )
}

#' @export
print.rcapsule_certificate <- function(x, ...) {
  cli::cli_h1("rcapsule Verification Certificate")
  cli::cli_ul(c(
    "Title: {.val {x$title}}",
    "Verdict: {.val {status_label(x$verification$status)}}",
    "Markdown: {if (!is.null(x$markdown)) paste0(nchar(x$markdown), ' chars') else 'not rendered'}",
    "HTML: {if (!is.null(x$html)) paste0(nchar(x$html), ' chars') else 'not rendered'}",
    "Files: {if (length(x$files) > 0L) paste(x$files, collapse = ', ') else '<in-memory>'}"
  ))
  invisible(x)
}
