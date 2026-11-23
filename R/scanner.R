# Full-stack R project, Quarto, Shiny, package, and toolchain static scanner

# Default directories excluded during recursive project scanning
default_scan_excludes <- function() {
  c(
    ".git", ".Rproj.user", "renv/library", "renv/staging", "renv/sandbox",
    "node_modules", "_site", "_book", "_freeze", ".quarto", "rsconnect",
    "__pycache__", ".venv", "venv"
  )
}

# Check whether a relative path falls inside excluded prefixes or patterns
is_excluded_rel_path <- function(rel, excludes) {
  if (length(rel) == 0L) {
    return(logical())
  }
  out <- rep(FALSE, length(rel))
  for (ex in excludes) {
    ex_clean <- sub("/+$", "", gsub("\\\\", "/", ex))
    pat <- paste0("(^|/)", gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", ex_clean), "(/|$)")
    out <- out | grepl(pat, rel)
  }
  out <- out | grepl("\\.Rcheck(/|$)", rel)
  out
}

# Parse R code text (AST with regex fallback) to extract packages and tool signals
parse_r_code_signals <- function(code_text, source_label = "<inline>") {
  pkgs <- character()
  signals <- list(
    cpp = character(),
    cmdstan = character(),
    tmb = character(),
    jags = character(),
    rust = character(),
    java = character(),
    python = character(),
    latex = character(),
    quarto = character(),
    shiny = character(),
    shiny_async = character(),
    python_packages = character(),
    seeds = integer()
  )
  parse_ok <- TRUE

  # Attempt exact AST parsing first
  exprs <- tryCatch(
    parse(text = code_text, keep.source = FALSE),
    error = function(e) {
      parse_ok <<- FALSE
      NULL
    }
  )

  walk_expr <- function(e) {
    if (is.call(e)) {
      fn <- e[[1L]]
      fn_name <- NULL
      fn_ns <- NULL

      if (is.symbol(fn)) {
        fn_name <- as.character(fn)
      } else if (is.call(fn) && length(fn) == 3L &&
        as.character(fn[[1L]]) %in% c("::", ":::")) {
        fn_ns <- as.character(fn[[2L]])
        fn_name <- as.character(fn[[3L]])
        pkgs <<- c(pkgs, fn_ns)
      }

      # Handle pkg::fun / pkg:::fun directly when e itself is :: or :::
      if (!is.null(fn_name) && fn_name %in% c("::", ":::") && length(e) >= 2L) {
        if (is.symbol(e[[2L]]) || is.character(e[[2L]])) {
          pkgs <<- c(pkgs, as.character(e[[2L]]))
        }
      }

      # library() / require()
      if (!is.null(fn_name) && fn_name %in% c("library", "require") && length(e) >= 2L) {
        args <- as.list(e)[-1L]
        arg_names <- names(args) %||% rep("", length(args))
        char_only <- FALSE
        co_idx <- which(arg_names == "character.only")
        if (length(co_idx) == 1L && isTRUE(args[[co_idx]])) {
          char_only <- TRUE
        }
        pkg_idx <- which(arg_names == "package")
        pkg_arg <- if (length(pkg_idx) == 1L) args[[pkg_idx]] else args[[1L]]
        if (is.character(pkg_arg) && length(pkg_arg) == 1L && nzchar(pkg_arg)) {
          pkgs <<- c(pkgs, pkg_arg)
        } else if (!char_only && is.symbol(pkg_arg)) {
          pkgs <<- c(pkgs, as.character(pkg_arg))
        }
      }

      # loadNamespace() / requireNamespace()
      if (!is.null(fn_name) && fn_name %in% c("loadNamespace", "requireNamespace") && length(e) >= 2L) {
        args <- as.list(e)[-1L]
        arg_names <- names(args) %||% rep("", length(args))
        pkg_idx <- which(arg_names == "package")
        pkg_arg <- if (length(pkg_idx) == 1L) args[[pkg_idx]] else args[[1L]]
        if (is.character(pkg_arg) && length(pkg_arg) == 1L && nzchar(pkg_arg)) {
          pkgs <<- c(pkgs, pkg_arg)
        }
      }

      # set.seed()
      if (!is.null(fn_name) && identical(fn_name, "set.seed") && length(e) >= 2L) {
        seed_arg <- e[[2L]]
        if (is.numeric(seed_arg) && length(seed_arg) == 1L && !is.na(seed_arg)) {
          signals$seeds <<- c(signals$seeds, as.integer(seed_arg))
        }
      }

      # Toolchain-specific calls
      if (!is.null(fn_name)) {
        if (fn_name %in% c("sourceCpp", "cppFunction", "cpp_source", "cpp_function")) {
          signals$cpp <<- c(signals$cpp, paste0(source_label, ":", fn_name, "()"))
        }
        if (fn_name %in% c("cmdstan_model", "install_cmdstan", "set_cmdstan_path")) {
          signals$cmdstan <<- c(signals$cmdstan, paste0(source_label, ":", fn_name, "()"))
        }
        if (fn_name %in% c("MakeADFun", "compile") && identical(fn_ns, "TMB") ||
          fn_name %in% c("MakeADFun") && identical(fn_ns, "RTMB")) {
          signals$tmb <<- c(signals$tmb, paste0(source_label, ":", fn_ns, "::", fn_name, "()"))
        }
        if (fn_name %in% c("jags.model", "run.jags") ||
          (fn_name == "jags" && identical(fn_ns, "R2jags"))) {
          signals$jags <<- c(signals$jags, paste0(source_label, ":", fn_name, "()"))
        }
        if (fn_name %in% c("use_python", "use_virtualenv", "use_condaenv", "py_install", "import", "source_python") &&
          (is.null(fn_ns) || identical(fn_ns, "reticulate"))) {
          if (identical(fn_ns, "reticulate") || fn_name %in% c("use_python", "use_virtualenv", "use_condaenv", "py_install", "source_python")) {
            signals$python <<- c(signals$python, paste0(source_label, ":", fn_name, "()"))
          }
          if (fn_name %in% c("import", "py_install") && length(e) >= 2L) {
            arg1 <- e[[2L]]
            if (is.character(arg1)) {
              signals$python_packages <<- c(signals$python_packages, arg1)
            } else if (is.call(arg1) && identical(as.character(arg1[[1L]]), "c")) {
              vals <- vapply(as.list(arg1)[-1L], function(v) if (is.character(v)) v else NA_character_, character(1L))
              signals$python_packages <<- c(signals$python_packages, vals[!is.na(vals)])
            }
          }
        }
        if (fn_name %in% c("shinyApp", "runApp", "shinyUI", "shinyServer", "fluidPage", "navbarPage", "page_sidebar", "page_fluid")) {
          signals$shiny <<- c(signals$shiny, paste0(source_label, ":", fn_name, "()"))
        }
        if (fn_name %in% c("future_promise", "mirai", "daemons", "crew_controller_local")) {
          signals$shiny_async <<- c(signals$shiny_async, paste0(source_label, ":", fn_name, "()"))
        }
        if (fn_name %in% c("pdflatex", "xelatex", "lualatex", "install_tinytex")) {
          signals$latex <<- c(signals$latex, paste0(source_label, ":", fn_name, "()"))
        }
        if (fn_name %in% c("quarto_render", "quarto_preview")) {
          signals$quarto <<- c(signals$quarto, paste0(source_label, ":", fn_name, "()"))
        }
      }

      for (i in seq_along(e)) {
        walk_expr(e[[i]])
      }
    } else if (is.pairlist(e) || is.expression(e)) {
      for (i in seq_along(e)) {
        walk_expr(e[[i]])
      }
    }
  }

  if (parse_ok && !is.null(exprs)) {
    walk_expr(exprs)
  } else {
    # Comment-stripped regex fallback for unparseable R fragments
    lines <- sub("#.*$", "", strsplit(paste(code_text, collapse = "\n"), "\n", fixed = TRUE)[[1L]])
    clean <- paste(lines, collapse = "\n")

    extract_group1 <- function(pattern) {
      m <- gregexpr(pattern, clean, perl = TRUE)
      hits <- regmatches(clean, m)[[1L]]
      if (length(hits) == 0L) return(character())
      sub(pattern, "\\1", hits, perl = TRUE)
    }

    pkgs <- c(
      pkgs,
      extract_group1("(?:library|require)\\s*\\(\\s*['\"]?([A-Za-z][A-Za-z0-9.]+)['\"]?"),
      extract_group1("(?:loadNamespace|requireNamespace)\\s*\\(\\s*['\"]([A-Za-z][A-Za-z0-9.]+)['\"]"),
      extract_group1("\\b([A-Za-z][A-Za-z0-9.]+):::?[A-Za-z._]")
    )
  }

  # Clean valid R package names
  pkgs <- unique(pkgs[grepl("^[A-Za-z][A-Za-z0-9.]*[A-Za-z0-9]$|^[A-Za-z]$", pkgs)])
  signals$python_packages <- unique(signals$python_packages[nzchar(signals$python_packages)])
  signals$seeds <- unique(signals$seeds)

  list(
    packages = pkgs,
    signals = signals,
    parse_ok = parse_ok
  )
}

# Parse Python code snippet for imported top-level package names
parse_python_imports <- function(code_lines) {
  lines <- sub("#.*$", "", code_lines)
  pkgs <- character()
  for (ln in lines) {
    if (grepl("^\\s*import\\s+", ln)) {
      rest <- sub("^\\s*import\\s+", "", ln)
      parts <- trimws(strsplit(rest, ",", fixed = TRUE)[[1L]])
      mods <- sub("\\s+as\\s+.*$", "", parts)
      mods <- sub("\\..*$", "", mods)
      pkgs <- c(pkgs, mods)
    } else if (grepl("^\\s*from\\s+([A-Za-z0-9_]+)", ln)) {
      mod <- sub("^\\s*from\\s+([A-Za-z0-9_]+).*$", "\\1", ln)
      pkgs <- c(pkgs, mod)
    }
  }
  stdlib <- c(
    "os", "sys", "re", "math", "json", "csv", "time", "datetime", "pathlib",
    "typing", "itertools", "functools", "collections", "random", "statistics",
    "subprocess", "shutil", "tempfile", "glob", "io", "logging", "argparse",
    "unittest", "dataclasses", "enum", "copy", "warnings", "hashlib", "base64"
  )
  pkgs <- unique(pkgs[nzchar(pkgs) & !(pkgs %in% stdlib)])
  pkgs
}

# Extract YAML frontmatter and fenced code chunks from .qmd or .Rmd files
parse_notebook_file <- function(file_path, rel) {
  lines <- readLines(file_path, warn = FALSE, encoding = "UTF-8")
  yaml_meta <- list()
  r_chunks <- list()
  py_chunks <- list()
  stan_chunks <- character()
  cpp_chunks <- character()
  inline_r <- character()

  # 1. YAML frontmatter
  n <- length(lines)
  start_idx <- which(grepl("^---\\s*$", lines))
  if (length(start_idx) >= 2L && start_idx[[1L]] == 1L) {
    fm_lines <- lines[(start_idx[[1L]] + 1L):(start_idx[[2L]] - 1L)]
    yaml_meta <- tryCatch(
      yaml::yaml.load(paste(fm_lines, collapse = "\n")),
      error = function(e) list()
    )
    if (!is.list(yaml_meta)) yaml_meta <- list()
    body_start <- start_idx[[2L]] + 1L
  } else {
    body_start <- 1L
  }

  # 2. Fenced code chunks
  in_chunk <- FALSE
  chunk_engine <- NULL
  chunk_fence_len <- 3L
  chunk_buf <- character()
  prose_lines <- character()

  if (body_start <= n) {
    for (i in seq(body_start, n)) {
      ln <- lines[[i]]
      if (!in_chunk) {
        m <- regexec("^\\s*(`{3,})\\s*\\{\\s*([A-Za-z0-9_+.-]+)(.*)\\}\\s*$", ln)
        parts <- regmatches(ln, m)[[1L]]
        if (length(parts) >= 3L) {
          in_chunk <- TRUE
          chunk_fence_len <- nchar(parts[[2L]])
          chunk_engine <- tolower(parts[[3L]])
          chunk_buf <- character()
          next
        }
        prose_lines <- c(prose_lines, ln)
      } else {
        close_pat <- paste0("^\\s*`{", chunk_fence_len, ",}\\s*$")
        if (grepl(close_pat, ln)) {
          # Strip Quarto `#|` YAML chunk option lines before parsing R code
          code_only <- chunk_buf[!grepl("^\\s*#\\|", chunk_buf)]
          if (chunk_engine %in% c("r", "webr")) {
            r_chunks[[length(r_chunks) + 1L]] <- paste(code_only, collapse = "\n")
          } else if (chunk_engine %in% c("python", "py")) {
            py_chunks[[length(py_chunks) + 1L]] <- code_only
          } else if (chunk_engine %in% c("stan", "cmdstan")) {
            stan_chunks <- c(stan_chunks, rel)
          } else if (chunk_engine %in% c("rcpp", "cpp", "c++", "c", "fortran")) {
            cpp_chunks <- c(cpp_chunks, rel)
          }
          in_chunk <- FALSE
          chunk_engine <- NULL
          chunk_buf <- character()
        } else {
          chunk_buf <- c(chunk_buf, ln)
        }
      }
    }
  }

  # 3. Inline R expressions `r ...`
  prose_text <- paste(prose_lines, collapse = "\n")
  im <- gregexpr("`r\\s+([^`]+)`", prose_text, perl = TRUE)
  hits <- regmatches(prose_text, im)[[1L]]
  if (length(hits) > 0L) {
    inline_r <- sub("^`r\\s+([^`]+)`$", "\\1", hits, perl = TRUE)
  }

  list(
    yaml = yaml_meta,
    r_code = c(unlist(r_chunks), inline_r),
    py_chunks = py_chunks,
    stan_chunks = unique(stan_chunks),
    cpp_chunks = unique(cpp_chunks)
  )
}

# Detect PDF/LaTeX or Shiny or Jupyter requirements from YAML metadata
inspect_yaml_metadata <- function(meta, rel) {
  out <- list(
    latex = character(),
    shiny = character(),
    python = character(),
    quarto = character()
  )
  if (!is.list(meta) || length(meta) == 0L) {
    return(out)
  }

  flat_names <- tolower(names(meta) %||% character())

  check_format_node <- function(fmt) {
    if (is.character(fmt)) {
      low <- tolower(fmt)
      if (any(grepl("(^pdf$|beamer|pdf_document|pdf_book|rticles|latex)", low))) {
        out$latex <<- c(out$latex, paste0(rel, ":format=", paste(fmt, collapse = ",")))
      }
    } else if (is.list(fmt)) {
      nms <- tolower(names(fmt) %||% character())
      if (any(grepl("(^pdf$|beamer|pdf_document|pdf_book|rticles|latex)", nms))) {
        out$latex <<- c(out$latex, paste0(rel, ":format=", paste(nms[grepl("(^pdf$|beamer|pdf_document|pdf_book|rticles|latex)", nms)], collapse = ",")))
      }
      for (child in fmt) {
        if (is.list(child)) {
          cn <- tolower(names(child) %||% character())
          if (any(cn %in% c("pdf-engine", "latex-auto-install", "latex_engine"))) {
            out$latex <<- c(out$latex, paste0(rel, ":latex-engine"))
          }
        }
      }
    }
  }

  if (!is.null(meta$format)) check_format_node(meta$format)
  if (!is.null(meta$output)) check_format_node(meta$output)
  if (any(flat_names %in% c("pdf-engine", "latex-auto-install", "header-includes"))) {
    hi <- paste(unlist(meta$`header-includes`), collapse = " ")
    if (!("header-includes" %in% flat_names) || grepl("\\\\usepackage|\\\\newcommand|\\\\documentclass", hi)) {
      out$latex <<- c(out$latex, paste0(rel, ":latex-yaml"))
    }
  }

  if (identical(tolower(as.character(meta$runtime %||% "")), "shiny") ||
    identical(tolower(as.character(meta$server %||% "")), "shiny")) {
    out$shiny <<- c(out$shiny, paste0(rel, ":shiny-runtime"))
  }

  if (identical(tolower(as.character(meta$engine %||% "")), "jupyter") ||
    !is.null(meta$jupyter)) {
    out$python <<- c(out$python, paste0(rel, ":jupyter-engine"))
  }

  out
}

# Parse requirements.txt into clean Python package specs
parse_requirements_txt <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- trimws(sub("#.*$", "", lines))
  lines <- lines[nzchar(lines) & !grepl("^-", lines)]
  unique(lines)
}

# Parse renv.lock safely
parse_renv_lock <- function(path) {
  lock <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(lock) || !is.list(lock)) {
    return(NULL)
  }
  r_ver <- lock$R$Version %||% NULL
  repos <- lock$R$Repositories %||% list()
  pkgs <- lock$Packages %||% list()

  pkg_rows <- lapply(names(pkgs), function(nm) {
    entry <- pkgs[[nm]]
    list(
      package = entry$Package %||% nm,
      version = as.character(entry$Version %||% NA_character_),
      source = as.character(entry$Source %||% "renv.lock")
    )
  })

  pkg_tbl <- if (length(pkg_rows) > 0L) {
    tibble::tibble(
      package = vapply(pkg_rows, `[[`, character(1L), "package"),
      version = vapply(pkg_rows, `[[`, character(1L), "version"),
      source = vapply(pkg_rows, `[[`, character(1L), "source")
    )
  } else {
    tibble::tibble(package = character(), version = character(), source = character())
  }

  list(
    r_version = r_ver,
    repositories = repos,
    packages = pkg_tbl
  )
}

#' Scan an R Project for Dependencies, System Libraries, and Scientific Toolchains
#'
#' Recursively inspects an R analysis project, Quarto manuscript, R Markdown
#' report, R package, or Shiny application. Parses R scripts, notebook code
#' chunks, `DESCRIPTION`, `renv.lock`, `_quarto.yml`, Shiny entry points, and
#' native source files to build a full-stack dependency and toolchain profile.
#'
#' @param path Path to the project root directory. Defaults to `"."`.
#' @param exclude Optional character vector of additional relative paths or
#'   directory names to ignore during scanning.
#' @param custom_sysreqs Optional named list mapping R package names to
#'   Debian/Ubuntu `apt` system packages to merge with [sysreqs_db()].
#'
#' @return An S3 object of class `rcapsule_scan` containing:
#'   - `project_path`, `project_name`, `project_type`, `roles`, `entrypoint`
#'   - `r_version`, `has_renv`, `renv_lock_path`, `has_description`, `has_quarto_yml`
#'   - `shiny_async`: logical indicating async worker patterns in Shiny apps
#'   - `files`: tibble of scanned project files
#'   - `packages`: tibble of discovered R packages (`package`, `version`, `source`, `found_in`, `is_base`, `required`)
#'   - `sysreqs`: tibble of resolved OS `apt` system dependencies (`apt_package`, `stage`, `required_by`, `source`)
#'   - `toolchains`: named list of toolchain detection summaries (`cpp`, `cmdstan`, `tmb`, `jags`, `rust`, `java`, `python`, `quarto`, `latex`)
#'   - `python_packages`: character vector of detected Python packages/requirements
#'   - `seeds_detected`: integer vector of static `set.seed()` literals discovered
#'   - `git`: list of Git repository metadata
#'   - `scanned_at`: ISO-8601 UTC timestamp
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_scan_demo_")
#' dir.create(tmp)
#' writeLines(c("library(stats)", "x <- rnorm(10)"), file.path(tmp, "analysis.R"))
#' sc <- scan_project(tmp)
#' sc
#' unlink(tmp, recursive = TRUE)
scan_project <- function(path = ".", exclude = NULL, custom_sysreqs = NULL) {
  root <- normalize_project_path(path, must_exist = TRUE)
  excludes <- unique(c(default_scan_excludes(), as.character(exclude)))

  all_entries <- tryCatch(
    fs::dir_ls(root, recurse = TRUE, all = TRUE, type = "file", fail = FALSE),
    error = function(e) character()
  )
  all_entries <- as.character(all_entries)
  rels <- if (length(all_entries) > 0L) rel_path(all_entries, root) else character()
  keep <- !is_excluded_rel_path(rels, excludes)
  all_entries <- all_entries[keep]
  rels <- rels[keep]

  ord <- order(rels)
  all_entries <- all_entries[ord]
  rels <- rels[ord]

  file_sizes <- if (length(all_entries) > 0L) {
    as.numeric(fs::file_size(all_entries))
  } else {
    numeric()
  }
  file_kinds <- vapply(rels, detect_artifact_format, character(1L), USE.NAMES = FALSE)

  files_tbl <- tibble::tibble(
    path = rels,
    kind = file_kinds,
    size_bytes = file_sizes
  )

  # Accumulators
  pkg_evidence <- list() # pkg -> list(found_in = char(), source = char(), required = lgl())
  add_pkg_evidence <- function(pkg, found_in, source = "code", required = TRUE) {
    if (is.na(pkg) || !nzchar(pkg) || identical(pkg, "R")) return(invisible(NULL))
    cur <- pkg_evidence[[pkg]]
    if (is.null(cur)) {
      pkg_evidence[[pkg]] <<- list(
        found_in = found_in,
        source = source,
        required = required
      )
    } else {
      cur$found_in <- unique(c(cur$found_in, found_in))
      cur$source <- unique(c(cur$source, source))
      cur$required <- isTRUE(cur$required) || isTRUE(required)
      pkg_evidence[[pkg]] <<- cur
    }
  }

  tc_reasons <- list(
    cpp = character(),
    cmdstan = character(),
    tmb = character(),
    jags = character(),
    rust = character(),
    java = character(),
    python = character(),
    quarto = character(),
    latex = character()
  )
  add_tc <- function(tc, reason) {
    tc_reasons[[tc]] <<- unique(c(tc_reasons[[tc]], reason))
  }

  shiny_reasons <- character()
  shiny_async_reasons <- character()
  python_pkgs <- character()
  seeds_detected <- integer()
  sysreq_strings <- character()

  # 1. Inspect DESCRIPTION
  desc_path <- file.path(root, "DESCRIPTION")
  has_description <- fs::file_exists(desc_path)
  desc_pkg_name <- NULL
  desc_is_r_package <- FALSE
  if (has_description) {
    d <- tryCatch(desc::desc(file = desc_path), error = function(e) NULL)
    if (!is.null(d)) {
      desc_pkg_name <- tryCatch(d$get_field("Package"), error = function(e) NULL)
      if (!is.null(desc_pkg_name) &&
        (fs::dir_exists(file.path(root, "R")) || fs::file_exists(file.path(root, "NAMESPACE")))) {
        desc_is_r_package <- TRUE
      }
      deps <- tryCatch(d$get_deps(), error = function(e) NULL)
      if (!is.null(deps) && nrow(deps) > 0L) {
        for (i in seq_len(nrow(deps))) {
          dp <- deps$package[[i]]
          tp <- deps$type[[i]]
          if (identical(dp, "R")) next
          is_req <- tp %in% c("Imports", "Depends", "LinkingTo")
          add_pkg_evidence(dp, "DESCRIPTION", paste0("DESCRIPTION:", tp), required = is_req)
          if (identical(tp, "LinkingTo")) {
            add_tc("cpp", paste0("DESCRIPTION:LinkingTo:", dp))
            if (dp %in% c("TMB", "RTMB")) {
              add_tc("tmb", paste0("DESCRIPTION:LinkingTo:", dp))
            }
          }
        }
      }
      sr <- tryCatch(d$get_field("SystemRequirements", default = NULL), error = function(e) NULL)
      if (!is.null(sr) && nzchar(sr)) {
        sysreq_strings <- c(sysreq_strings, sr)
        sr_low <- tolower(sr)
        if (grepl("c\\+\\+|g\\+\\+|fortran|gnu make", sr_low)) add_tc("cpp", "DESCRIPTION:SystemRequirements")
        if (grepl("cargo|rustc|rust", sr_low)) add_tc("rust", "DESCRIPTION:SystemRequirements")
        if (grepl("jags", sr_low)) add_tc("jags", "DESCRIPTION:SystemRequirements")
        if (grepl("python", sr_low)) add_tc("python", "DESCRIPTION:SystemRequirements")
        if (grepl("java|jdk", sr_low)) add_tc("java", "DESCRIPTION:SystemRequirements")
      }
    }
  }

  # 2. Inspect renv.lock
  renv_lock_path <- file.path(root, "renv.lock")
  has_renv <- fs::file_exists(renv_lock_path)
  renv_info <- if (has_renv) parse_renv_lock(renv_lock_path) else NULL
  renv_versions <- list()
  if (!is.null(renv_info) && nrow(renv_info$packages) > 0L) {
    for (i in seq_len(nrow(renv_info$packages))) {
      p <- renv_info$packages$package[[i]]
      renv_versions[[p]] <- list(
        version = renv_info$packages$version[[i]],
        source = renv_info$packages$source[[i]]
      )
      add_pkg_evidence(p, "renv.lock", paste0("renv:", renv_info$packages$source[[i]]), required = TRUE)
    }
  }

  # 3. Inspect _quarto.yml / _quarto.yaml
  quarto_yml_candidates <- file.path(root, c("_quarto.yml", "_quarto.yaml"))
  has_quarto_yml <- any(fs::file_exists(quarto_yml_candidates))
  quarto_project_type <- NULL
  if (has_quarto_yml) {
    qy_path <- quarto_yml_candidates[fs::file_exists(quarto_yml_candidates)][[1L]]
    qy_rel <- basename(qy_path)
    add_tc("quarto", qy_rel)
    qmeta <- tryCatch(yaml::read_yaml(qy_path), error = function(e) list())
    if (is.list(qmeta)) {
      quarto_project_type <- qmeta$project$type %||% NULL
      ys <- inspect_yaml_metadata(qmeta, qy_rel)
      for (r in ys$latex) add_tc("latex", r)
      for (r in ys$python) add_tc("python", r)
      shiny_reasons <- c(shiny_reasons, ys$shiny)
    }
  }

  # 4. Walk project files by extension and role
  has_app_r <- any(tolower(rels) == "app.r")
  has_ui_server <- any(tolower(rels) == "ui.r") && any(tolower(rels) == "server.r")
  if (has_app_r) shiny_reasons <- c(shiny_reasons, "app.R")
  if (has_ui_server) shiny_reasons <- c(shiny_reasons, "ui.R+server.R")
  if (any(tolower(basename(rels)) %in% c("worker.r", "workers.r"))) {
    shiny_async_reasons <- c(shiny_async_reasons, "worker.R")
  }

  qmd_files <- character()
  rmd_files <- character()
  r_files <- character()

  for (idx in seq_along(all_entries)) {
    fpath <- all_entries[[idx]]
    rel <- rels[[idx]]
    bn <- basename(rel)
    bn_low <- tolower(bn)
    ext <- tolower(tools::file_ext(bn))

    # Skip files inside renv/ infrastructure scripts (activate.R is renv boilerplate)
    if (grepl("^renv/", rel)) next

    if (ext == "r") {
      r_files <- c(r_files, rel)
      code <- readLines(fpath, warn = FALSE, encoding = "UTF-8")
      res <- parse_r_code_signals(code, source_label = rel)
      for (p in res$packages) add_pkg_evidence(p, rel, "r_script", required = TRUE)
      for (r in res$signals$cpp) add_tc("cpp", r)
      for (r in res$signals$cmdstan) add_tc("cmdstan", r)
      for (r in res$signals$tmb) add_tc("tmb", r)
      for (r in res$signals$jags) add_tc("jags", r)
      for (r in res$signals$python) add_tc("python", r)
      for (r in res$signals$latex) add_tc("latex", r)
      for (r in res$signals$quarto) add_tc("quarto", r)
      shiny_reasons <- c(shiny_reasons, res$signals$shiny)
      shiny_async_reasons <- c(shiny_async_reasons, res$signals$shiny_async)
      python_pkgs <- c(python_pkgs, res$signals$python_packages)
      seeds_detected <- c(seeds_detected, res$signals$seeds)
    } else if (ext %in% c("qmd", "rmd")) {
      if (ext == "qmd") {
        qmd_files <- c(qmd_files, rel)
        add_tc("quarto", rel)
      } else {
        rmd_files <- c(rmd_files, rel)
      }
      nb <- parse_notebook_file(fpath, rel)
      ys <- inspect_yaml_metadata(nb$yaml, rel)
      for (r in ys$latex) add_tc("latex", r)
      for (r in ys$python) add_tc("python", r)
      shiny_reasons <- c(shiny_reasons, ys$shiny)

      if (length(nb$r_code) > 0L) {
        res <- parse_r_code_signals(nb$r_code, source_label = rel)
        for (p in res$packages) add_pkg_evidence(p, rel, paste0(ext, "_chunk"), required = TRUE)
        for (r in res$signals$cpp) add_tc("cpp", r)
        for (r in res$signals$cmdstan) add_tc("cmdstan", r)
        for (r in res$signals$tmb) add_tc("tmb", r)
        for (r in res$signals$jags) add_tc("jags", r)
        for (r in res$signals$python) add_tc("python", r)
        for (r in res$signals$latex) add_tc("latex", r)
        for (r in res$signals$quarto) add_tc("quarto", r)
        shiny_reasons <- c(shiny_reasons, res$signals$shiny)
        shiny_async_reasons <- c(shiny_async_reasons, res$signals$shiny_async)
        python_pkgs <- c(python_pkgs, res$signals$python_packages)
        seeds_detected <- c(seeds_detected, res$signals$seeds)
      }
      if (length(nb$py_chunks) > 0L) {
        add_tc("python", paste0(rel, ":python-chunk"))
        for (ch in nb$py_chunks) {
          python_pkgs <- c(python_pkgs, parse_python_imports(ch))
        }
      }
      if (length(nb$stan_chunks) > 0L) add_tc("cmdstan", paste0(rel, ":stan-chunk"))
      if (length(nb$cpp_chunks) > 0L) add_tc("cpp", paste0(rel, ":cpp-chunk"))
    } else if (ext == "stan") {
      add_tc("cmdstan", rel)
    } else if (ext %in% c("jags", "bug")) {
      add_tc("jags", rel)
    } else if (ext %in% c("cpp", "cc", "cxx", "c", "hpp", "hh", "f", "f90", "f95") ||
      bn_low %in% c("makevars", "makevars.in", "makevars.win")) {
      add_tc("cpp", rel)
    } else if (ext == "rs" || bn_low == "cargo.toml") {
      add_tc("rust", rel)
    } else if (ext == "py") {
      add_tc("python", rel)
      py_lines <- readLines(fpath, warn = FALSE, encoding = "UTF-8")
      python_pkgs <- c(python_pkgs, parse_python_imports(py_lines))
    } else if (bn_low == "requirements.txt") {
      add_tc("python", rel)
      python_pkgs <- c(python_pkgs, parse_requirements_txt(fpath))
    } else if (bn_low %in% c("pyproject.toml", "environment.yml", "environment.yaml")) {
      add_tc("python", rel)
    } else if (ext == "tex") {
      add_tc("latex", rel)
    }
  }

  # 5. Build packages tibble and infer toolchains from discovered packages
  base_pkgs <- base_r_packages()
  all_pkg_names <- sort(names(pkg_evidence))
  # Exclude the package itself if scanning an R package
  if (desc_is_r_package && !is.null(desc_pkg_name)) {
    all_pkg_names <- setdiff(all_pkg_names, desc_pkg_name)
  }

  packages_tbl <- if (length(all_pkg_names) > 0L) {
    versions <- vapply(all_pkg_names, function(p) {
      if (!is.null(renv_versions[[p]])) {
        return(renv_versions[[p]]$version)
      }
      if (requireNamespace(p, quietly = TRUE)) {
        return(as.character(utils::packageVersion(p)))
      }
      NA_character_
    }, character(1L))

    sources <- vapply(all_pkg_names, function(p) {
      paste(unique(pkg_evidence[[p]]$source), collapse = ", ")
    }, character(1L))

    found_in <- vapply(all_pkg_names, function(p) {
      paste(unique(pkg_evidence[[p]]$found_in), collapse = ", ")
    }, character(1L))

    req_flag <- vapply(all_pkg_names, function(p) {
      isTRUE(pkg_evidence[[p]]$required)
    }, logical(1L))

    tibble::tibble(
      package = all_pkg_names,
      version = unname(versions),
      source = unname(sources),
      found_in = unname(found_in),
      is_base = all_pkg_names %in% base_pkgs,
      required = unname(req_flag)
    )
  } else {
    tibble::tibble(
      package = character(),
      version = character(),
      source = character(),
      found_in = character(),
      is_base = logical(),
      required = logical()
    )
  }

  # Trigger toolchains from required non-base packages using sysreqs_db
  req_pkgs <- packages_tbl$package[!packages_tbl$is_base & packages_tbl$required]
  db <- sysreqs_db()
  db_hit <- db[db$package %in% req_pkgs & !is.na(db$toolchain), , drop = FALSE]
  if (nrow(db_hit) > 0L) {
    for (i in seq_len(nrow(db_hit))) {
      add_tc(db_hit$toolchain[[i]], paste0("package:", db_hit$package[[i]]))
    }
  }

  # CmdStan and TMB also imply C++ toolchain
  if (length(tc_reasons$cmdstan) > 0L) {
    add_tc("cpp", "implied-by:cmdstan")
  }
  if (length(tc_reasons$tmb) > 0L) {
    add_tc("cpp", "implied-by:tmb")
  }

  # Async Shiny package cues
  if (any(req_pkgs %in% c("mirai", "future", "promises", "crew", "ipc"))) {
    shiny_async_reasons <- c(
      shiny_async_reasons,
      paste0("package:", intersect(req_pkgs, c("mirai", "future", "promises", "crew", "ipc")))
    )
  }
  if ("shiny" %in% req_pkgs && (has_app_r || has_ui_server)) {
    shiny_reasons <- c(shiny_reasons, "package:shiny")
  }

  # 6. Resolve OS sysreqs
  sysreqs_tbl <- resolve_sysreqs(
    packages = req_pkgs,
    system_requirements = sysreq_strings,
    custom_sysreqs = custom_sysreqs
  )

  # Add toolchain-driven apt packages even when triggered by files (e.g., .stan, .cpp, .py)
  extra_tc_pkgs <- character()
  if (length(tc_reasons$cpp) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "Rcpp")
  if (length(tc_reasons$cmdstan) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "cmdstanr")
  if (length(tc_reasons$tmb) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "RTMB")
  if (length(tc_reasons$jags) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "rjags")
  if (length(tc_reasons$rust) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "rextendr")
  if (length(tc_reasons$java) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "rJava")
  if (length(tc_reasons$python) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "reticulate")
  if (length(tc_reasons$latex) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "tinytex")
  if (length(tc_reasons$quarto) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "quarto")
  if (length(shiny_reasons) > 0L) extra_tc_pkgs <- c(extra_tc_pkgs, "shiny")

  if (length(extra_tc_pkgs) > 0L) {
    sysreqs_tbl <- resolve_sysreqs(
      packages = unique(c(req_pkgs, extra_tc_pkgs)),
      system_requirements = sysreq_strings,
      custom_sysreqs = custom_sysreqs
    )
  }

  # 7. Classify project type & roles
  roles <- character()
  if (has_app_r || has_ui_server || length(shiny_reasons) > 0L) roles <- c(roles, "shiny")
  if (desc_is_r_package) roles <- c(roles, "package")
  if (has_quarto_yml || length(qmd_files) > 0L) roles <- c(roles, "quarto")
  if (length(rmd_files) > 0L) roles <- c(roles, "rmarkdown")
  if (length(r_files) > 0L && !desc_is_r_package) roles <- c(roles, "analysis")
  if (length(roles) == 0L) roles <- "analysis"
  roles <- unique(roles)

  project_type <- if (has_app_r || has_ui_server ||
    (length(shiny_reasons) > 0L && !desc_is_r_package && !has_quarto_yml && length(qmd_files) == 0L)) {
    "shiny"
  } else if (desc_is_r_package) {
    "package"
  } else if (has_quarto_yml || length(qmd_files) > 0L) {
    "quarto"
  } else if (length(rmd_files) > 0L && length(r_files) == 0L) {
    "rmarkdown"
  } else {
    "analysis"
  }

  # 8. Infer primary entrypoint
  entrypoint <- infer_entrypoint(
    project_type = project_type,
    rels = rels,
    r_files = r_files,
    qmd_files = qmd_files,
    rmd_files = rmd_files
  )

  # 9. Structure toolchains list
  toolchains <- lapply(names(tc_reasons), function(nm) {
    reasons <- unique(tc_reasons[[nm]])
    list(
      detected = length(reasons) > 0L,
      reasons = reasons
    )
  })
  names(toolchains) <- names(tc_reasons)

  r_version <- (renv_info$r_version %||% current_r_version())
  project_name <- desc_pkg_name %||% basename(root)

  structure(
    list(
      project_path = root,
      project_name = project_name,
      project_type = project_type,
      roles = roles,
      entrypoint = entrypoint,
      r_version = as.character(r_version),
      has_renv = has_renv,
      renv_lock_path = if (has_renv) renv_lock_path else NULL,
      has_description = has_description,
      has_quarto_yml = has_quarto_yml,
      quarto_project_type = quarto_project_type,
      shiny_async = length(shiny_async_reasons) > 0L,
      shiny_async_reasons = unique(shiny_async_reasons),
      files = files_tbl,
      packages = packages_tbl,
      sysreqs = sysreqs_tbl,
      toolchains = toolchains,
      python_packages = sort(unique(python_pkgs)),
      seeds_detected = sort(unique(seeds_detected)),
      git = detect_git_info(root),
      scanned_at = utc_now_iso()
    ),
    class = "rcapsule_scan"
  )
}

# Infer default runnable entrypoint from scanned files
infer_entrypoint <- function(project_type, rels, r_files, qmd_files, rmd_files) {
  rel_low <- tolower(rels)
  if (project_type == "shiny") {
    if ("app.r" %in% rel_low) return(rels[rel_low == "app.r"][[1L]])
    if ("server.r" %in% rel_low) return(".")
  }
  if (project_type == "quarto") {
    for (cand in c("index.qmd", "manuscript.qmd", "report.qmd", "paper.qmd")) {
      if (cand %in% tolower(qmd_files)) {
        return(qmd_files[tolower(qmd_files) == cand][[1L]])
      }
    }
    if (length(qmd_files) > 0L) return(qmd_files[[1L]])
  }
  if (project_type == "rmarkdown" && length(rmd_files) > 0L) {
    return(rmd_files[[1L]])
  }
  if (project_type == "package") {
    return(NULL)
  }

  # Analysis scripts priority
  priority <- c("_targets.r", "run.r", "main.r", "analysis.r", "run_all.r", "pipeline.r")
  r_low <- tolower(r_files)
  for (cand in priority) {
    if (cand %in% r_low) return(r_files[r_low == cand][[1L]])
  }
  top_level_r <- r_files[!grepl("/", r_files, fixed = TRUE)]
  if (length(top_level_r) > 0L) return(top_level_r[[1L]])
  if (length(r_files) > 0L) return(r_files[[1L]])
  NULL
}

#' @export
print.rcapsule_scan <- function(x, ...) {
  cli::cli_h1("rcapsule Project Scan: {x$project_name}")
  cli::cli_ul(c(
    "Path: {.path {x$project_path}}",
    "Project type: {.val {x$project_type}} (roles: {paste(x$roles, collapse = ', ')})",
    "R version: {.val {x$r_version}} | renv.lock: {.val {x$has_renv}} | DESCRIPTION: {.val {x$has_description}}",
    "Entrypoint: {.val {x$entrypoint %||% '<none detected>'}}",
    "Files scanned: {nrow(x$files)}"
  ))

  non_base <- x$packages[!x$packages$is_base, , drop = FALSE]
  cli::cli_h2("R Packages ({nrow(non_base)} non-base)")
  if (nrow(non_base) > 0L) {
    pkg_labels <- paste0(
      non_base$package,
      ifelse(is.na(non_base$version), "", paste0("@", non_base$version))
    )
    cli::cli_text(paste(pkg_labels, collapse = ", "))
  } else {
    cli::cli_text("{.emph None detected (base R only)}")
  }

  active_tc <- names(x$toolchains)[vapply(x$toolchains, function(t) isTRUE(t$detected), logical(1L))]
  cli::cli_h2("Detected Toolchains ({length(active_tc)})")
  if (length(active_tc) > 0L) {
    cli::cli_text(paste(active_tc, collapse = ", "))
  } else {
    cli::cli_text("{.emph Standard R runtime only}")
  }

  build_apt <- unique(x$sysreqs$apt_package[x$sysreqs$stage == "build"])
  cli::cli_h2("OS System Dependencies ({length(build_apt)} apt packages)")
  if (length(build_apt) > 0L) {
    cli::cli_text(paste(build_apt, collapse = ", "))
  } else {
    cli::cli_text("{.emph None required}")
  }
  invisible(x)
}

#' @export
summary.rcapsule_scan <- function(object, ...) {
  active_tc <- names(object$toolchains)[vapply(object$toolchains, function(t) isTRUE(t$detected), logical(1L))]
  list(
    project_name = object$project_name,
    project_type = object$project_type,
    r_version = object$r_version,
    n_files = nrow(object$files),
    n_packages = sum(!object$packages$is_base),
    n_sysreqs_build = sum(object$sysreqs$stage == "build"),
    n_sysreqs_runtime = sum(object$sysreqs$stage == "runtime"),
    toolchains = active_tc,
    has_renv = object$has_renv,
    entrypoint = object$entrypoint
  )
}
