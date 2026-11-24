# Standards-compliant CycloneDX 1.5 Software Bill of Materials (SBOM) generator & validator

# Generate an RFC 4122 version-4 UUID URN using openssl cryptographic randomness
generate_uuid_urn <- function() {
  b <- as.integer(openssl::rand_bytes(16L))
  # Set version 4 (0100xxxx) in byte 7 and RFC 4122 variant (10xxxxxx) in byte 9
  b[[7L]] <- bitwOr(bitwAnd(b[[7L]], 0x0fL), 0x40L)
  b[[9L]] <- bitwOr(bitwAnd(b[[9L]], 0x3fL), 0x80L)
  hex <- sprintf("%02x", b)
  paste0(
    "urn:uuid:",
    paste0(hex[1:4], collapse = ""), "-",
    paste0(hex[5:6], collapse = ""), "-",
    paste0(hex[7:8], collapse = ""), "-",
    paste0(hex[9:10], collapse = ""), "-",
    paste0(hex[11:16], collapse = "")
  )
}

# Build a single CycloneDX property object {name, value}
cdx_prop <- function(name, value) {
  list(name = as.character(name), value = as.character(value))
}

# Percent-encode unsafe PURL segment characters
purl_encode_seg <- function(x) {
  utils::URLencode(as.character(x), reserved = TRUE)
}

# Build Package URL (PURL) for an R package given scanner source metadata and optional renv.lock entry
build_r_package_purl <- function(pkg, version = NA_character_, source = "", is_base = FALSE,
                                 r_version = current_r_version(), renv_entry = NULL) {
  ver_str <- if (!is.null(version) && !is.na(version) && nzchar(as.character(version))) {
    as.character(version)
  } else {
    NULL
  }

  if (isTRUE(is_base)) {
    return(paste0("pkg:generic/r-base-", purl_encode_seg(pkg), "@", purl_encode_seg(r_version)))
  }

  # Prefer explicit renv.lock remote metadata when available
  if (is.list(renv_entry)) {
    rt <- tolower(as.character(renv_entry$RemoteType %||% ""))
    ru <- renv_entry$RemoteUsername %||% NULL
    rr <- renv_entry$RemoteRepo %||% NULL
    rref <- renv_entry$RemoteSha %||% renv_entry$RemoteRef %||% ver_str
    raw_src <- tolower(as.character(renv_entry$Source %||% ""))
    repo_nm <- tolower(as.character(renv_entry$Repository %||% ""))

    if (rt %in% c("github", "gitlab", "bitbucket") && !is.null(ru) && !is.null(rr)) {
      base_purl <- paste0("pkg:", rt, "/", purl_encode_seg(tolower(ru)), "/", purl_encode_seg(rr))
      return(if (!is.null(rref) && nzchar(rref)) paste0(base_purl, "@", purl_encode_seg(rref)) else base_purl)
    }
    if (identical(raw_src, "bioconductor") || grepl("bioc", repo_nm, fixed = TRUE)) {
      base_purl <- paste0("pkg:bioconductor/", purl_encode_seg(pkg))
      return(if (!is.null(ver_str)) paste0(base_purl, "@", purl_encode_seg(ver_str)) else base_purl)
    }
  }

  # Fall back to scanner source label (e.g. "GitHub (user/repo@ref)", "Bioconductor", etc.)
  src_chr <- as.character(source %||% "")
  if (grepl("GitHub\\s*\\(([^/\\)]+)/([^@\\)]+)(?:@([^\\)]+))?\\)", src_chr, ignore.case = TRUE, perl = TRUE)) {
    m <- regmatches(src_chr, regexec("GitHub\\s*\\(([^/\\)]+)/([^@\\)]+)(?:@([^\\)]+))?\\)", src_chr, ignore.case = TRUE, perl = TRUE))[[1L]]
    ref_part <- if (length(m) >= 4L && nzchar(m[[4L]])) m[[4L]] else ver_str
    base_purl <- paste0("pkg:github/", purl_encode_seg(tolower(m[[2L]])), "/", purl_encode_seg(m[[3L]]))
    return(if (!is.null(ref_part) && nzchar(ref_part)) paste0(base_purl, "@", purl_encode_seg(ref_part)) else base_purl)
  }
  if (grepl("GitLab\\s*\\(([^/\\)]+)/([^@\\)]+)(?:@([^\\)]+))?\\)", src_chr, ignore.case = TRUE, perl = TRUE)) {
    m <- regmatches(src_chr, regexec("GitLab\\s*\\(([^/\\)]+)/([^@\\)]+)(?:@([^\\)]+))?\\)", src_chr, ignore.case = TRUE, perl = TRUE))[[1L]]
    ref_part <- if (length(m) >= 4L && nzchar(m[[4L]])) m[[4L]] else ver_str
    base_purl <- paste0("pkg:gitlab/", purl_encode_seg(tolower(m[[2L]])), "/", purl_encode_seg(m[[3L]]))
    return(if (!is.null(ref_part) && nzchar(ref_part)) paste0(base_purl, "@", purl_encode_seg(ref_part)) else base_purl)
  }
  if (grepl("Bitbucket\\s*\\(([^/\\)]+)/([^@\\)]+)(?:@([^\\)]+))?\\)", src_chr, ignore.case = TRUE, perl = TRUE)) {
    m <- regmatches(src_chr, regexec("Bitbucket\\s*\\(([^/\\)]+)/([^@\\)]+)(?:@([^\\)]+))?\\)", src_chr, ignore.case = TRUE, perl = TRUE))[[1L]]
    ref_part <- if (length(m) >= 4L && nzchar(m[[4L]])) m[[4L]] else ver_str
    base_purl <- paste0("pkg:bitbucket/", purl_encode_seg(tolower(m[[2L]])), "/", purl_encode_seg(m[[3L]]))
    return(if (!is.null(ref_part) && nzchar(ref_part)) paste0(base_purl, "@", purl_encode_seg(ref_part)) else base_purl)
  }
  if (grepl("Bioconductor", src_chr, ignore.case = TRUE)) {
    base_purl <- paste0("pkg:bioconductor/", purl_encode_seg(pkg))
    return(if (!is.null(ver_str)) paste0(base_purl, "@", purl_encode_seg(ver_str)) else base_purl)
  }

  base_purl <- paste0("pkg:cran/", purl_encode_seg(pkg))
  if (!is.null(ver_str)) paste0(base_purl, "@", purl_encode_seg(ver_str)) else base_purl
}

# Parse a Python PEP 508 requirement line (or VCS/URL spec) into canonical SBOM fields
# Returns NULL for empty, comment-only, flag-only, or marker-only lines that have no package name
parse_pypi_spec <- function(spec) {
  clean <- trimws(as.character(spec))
  # Strip environment markers after ';'
  clean <- trimws(sub(";.*$", "", clean))
  if (!nzchar(clean) || startsWith(clean, "-") || startsWith(clean, "#")) {
    return(NULL)
  }

  # Handle PEP 508 direct URL reference: "pkg[extra] @ https://..." or "pkg @ git+https://..."
  if (grepl("\\A([A-Za-z0-9][A-Za-z0-9._-]*)\\s*(?:\\[[^\\]]*\\])?\\s*@\\s*\\S+", clean, perl = TRUE)) {
    m <- regmatches(
      clean,
      regexec("\\A([A-Za-z0-9][A-Za-z0-9._-]*)\\s*(?:\\[[^\\]]*\\])?\\s*@\\s*(\\S+)", clean, perl = TRUE)
    )[[1L]]
    raw_name <- m[[2L]]
    norm_name <- tolower(gsub("[-_.]+", "-", raw_name))
    return(list(name = raw_name, purl_name = norm_name, purl_type = "pypi", version = NA_character_, spec = spec))
  }

  # Handle bare VCS or HTTP(S) URLs (e.g., git+https://github.com/org/repo.git@v1#egg=pkg)
  if (grepl("\\A(?:(?:git|hg|svn|bzr)\\+)?https?://", clean, ignore.case = TRUE, perl = TRUE)) {
    ver <- NA_character_
    # Extract optional @ref before #fragment (after host path)
    no_frag <- sub("#.*$", "", clean)
    path_after_scheme <- sub("\\A(?:(?:git|hg|svn|bzr)\\+)?https?://[^/]+", "", no_frag, ignore.case = TRUE, perl = TRUE)
    if (grepl("@([A-Za-z0-9._+-]+)\\z", path_after_scheme, perl = TRUE)) {
      vm <- regmatches(path_after_scheme, regexec("@([A-Za-z0-9._+-]+)\\z", path_after_scheme, perl = TRUE))[[1L]]
      if (length(vm) >= 2L && nzchar(vm[[2L]])) {
        ver <- vm[[2L]]
      }
    }
    # Prefer explicit #egg=<name> fragment when present
    if (grepl("#[^\\s]*egg=([A-Za-z0-9][A-Za-z0-9._-]*)", clean, perl = TRUE)) {
      em <- regmatches(clean, regexec("#[^\\s]*egg=([A-Za-z0-9][A-Za-z0-9._-]*)", clean, perl = TRUE))[[1L]]
      raw_name <- em[[2L]]
      norm_name <- tolower(gsub("[-_.]+", "-", raw_name))
      return(list(name = raw_name, purl_name = norm_name, purl_type = "pypi", version = ver, spec = spec))
    }
    # Fall back to repository slug as a generic PURL component
    base_url <- sub("@[^@/]*\\z", "", path_after_scheme, perl = TRUE)
    base_url <- sub("\\.git\\z", "", base_url, ignore.case = TRUE, perl = TRUE)
    segs <- strsplit(base_url, "/", fixed = TRUE)[[1L]]
    segs <- segs[nzchar(segs)]
    if (length(segs) == 0L) {
      return(NULL)
    }
    slug <- gsub("[^A-Za-z0-9._-]+", "-", segs[[length(segs)]])
    slug <- gsub("\\A[-._]+|[-._]+\\z", "", slug, perl = TRUE)
    if (!nzchar(slug)) {
      return(NULL)
    }
    return(list(
      name = slug,
      purl_name = tolower(gsub("[-_.]+", "-", slug)),
      purl_type = "generic",
      version = ver,
      spec = spec
    ))
  }

  # Standard PEP 508 distribution requirement (e.g., numpy==1.26.4, scipy[all]>=1.11)
  if (!grepl("\\A([A-Za-z0-9][A-Za-z0-9._-]*)", clean, perl = TRUE)) {
    return(NULL)
  }
  m_name <- regmatches(clean, regexec("\\A([A-Za-z0-9][A-Za-z0-9._-]*)", clean, perl = TRUE))[[1L]]
  raw_name <- m_name[[2L]]
  norm_name <- tolower(gsub("[-_.]+", "-", raw_name))
  ver <- NA_character_
  if (grepl("==\\s*([A-Za-z0-9._+-]+)", clean, perl = TRUE)) {
    m <- regmatches(clean, regexec("==\\s*([A-Za-z0-9._+-]+)", clean, perl = TRUE))[[1L]]
    if (length(m) >= 2L && nzchar(m[[2L]])) {
      ver <- m[[2L]]
    }
  }
  list(name = raw_name, purl_name = norm_name, purl_type = "pypi", version = ver, spec = spec)
}

# Canonical metadata for detected compiled & scientific toolchains
toolchain_sbom_catalog <- function() {
  list(
    cmdstan = list(name = "CmdStan", slug = "cmdstan", type = "application"),
    tmb = list(name = "TMB/RTMB", slug = "tmb", type = "framework"),
    jags = list(name = "JAGS", slug = "jags", type = "application"),
    cpp = list(name = "C++ Toolchain", slug = "cpp-toolchain", type = "platform"),
    rust = list(name = "Rust Toolchain", slug = "rust", type = "platform"),
    python = list(name = "Python", slug = "python", type = "platform"),
    quarto = list(name = "Quarto", slug = "quarto", type = "application"),
    latex = list(name = "TinyTeX", slug = "tinytex", type = "application"),
    java = list(name = "OpenJDK", slug = "openjdk", type = "platform")
  )
}

#' Export a CycloneDX 1.5 Software Bill of Materials (SBOM)
#'
#' Generates a standards-compliant CycloneDX 1.5 JSON Software Bill of Materials
#' (`bomFormat: "CycloneDX"`, `specVersion: "1.5"`) enumerating every dependency
#' layer of an R research project:
#' - R packages with Package URLs (`pkg:cran/...`, `pkg:github/...`,
#'   `pkg:gitlab/...`, `pkg:bioconductor/...`) and `renv.lock` hashes when
#'   present.
#' - OS `apt` system libraries (`pkg:deb/debian/...`) linked to the R packages
#'   that require them.
#' - Python packages (`pkg:pypi/...`) discovered from `requirements.txt` or
#'   `reticulate` imports.
#' - Scientific and compiled toolchains (`R`, `CmdStan`, `Quarto`, `TinyTeX`,
#'   `JAGS`, `TMB/RTMB`, `C++`, `Rust`, `Python`, `Java`).
#'
#' @param path Path to the project root directory. Defaults to `"."`.
#' @param scan Optional pre-computed `rcapsule_scan` object from
#'   [scan_project()]. If `NULL`, scans `path`.
#' @param manifest Optional `rcapsule_manifest` object or path to `capsule.json`
#'   whose `capsule_id` and `SHA-256` content digest are bound into the SBOM
#'   root component metadata.
#' @param output Optional file path to write the CycloneDX JSON document (for
#'   example, `"sbom.cdx.json"`). If `NULL`, returns the SBOM object in memory.
#' @param format SBOM output format; currently `"cyclonedx"` (default).
#' @param spec_version CycloneDX specification version; defaults to `"1.5"`.
#' @param include_base Logical; if `TRUE`, also includes base R packages as
#'   components. Defaults to `FALSE`.
#' @param serial_number Optional RFC 4122 UUID URN (`"urn:uuid:..."`) for the
#'   BOM serial number. If `NULL`, generates a fresh cryptographic UUID v4 URN.
#'
#' @return An S3 object of class `rcapsule_sbom` containing `bom` (structured
#'   CycloneDX 1.5 list), `json` (pretty UTF-8 JSON string), `path` (written
#'   file path or `NULL`), `spec_version`, `serial_number`, and `summary`
#'   (component counts by ecosystem).
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_sbom_")
#' dir.create(tmp)
#' writeLines(c("library(jsonlite)", "library(stats)", "x <- 1:5"), file.path(tmp, "run.R"))
#' sbom <- export_sbom(tmp)
#' sbom
#' validate_sbom(sbom)
#' unlink(tmp, recursive = TRUE)
export_sbom <- function(path = ".",
                        scan = NULL,
                        manifest = NULL,
                        output = NULL,
                        format = c("cyclonedx"),
                        spec_version = "1.5",
                        include_base = FALSE,
                        serial_number = NULL) {
  format <- match.arg(format)
  if (!identical(as.character(spec_version), "1.5")) {
    cli::cli_abort("Unsupported CycloneDX {.arg spec_version} {.val {spec_version}}; only {.val 1.5} is supported.")
  }

  sc <- if (is.null(scan)) {
    scan_project(normalize_project_path(path, must_exist = TRUE))
  } else {
    as_rcapsule_scan(scan)
  }

  if (is.character(manifest) && length(manifest) == 1L) {
    manifest <- read_capsule_manifest(manifest)
  }
  if (!is.null(manifest) && !inherits(manifest, "rcapsule_manifest")) {
    cli::cli_abort("{.arg manifest} must be an {.cls rcapsule_manifest} or path to capsule.json.")
  }

  if (is.null(serial_number)) {
    serial_number <- generate_uuid_urn()
  } else {
    serial_number <- as.character(serial_number)
    uuid_pat <- "\\Aurn:uuid:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z"
    if (length(serial_number) != 1L || is.na(serial_number) ||
      grepl("[\\x00-\\x1f\\x7f]", serial_number, perl = TRUE) ||
      !grepl(uuid_pat, serial_number, perl = TRUE)) {
      cli::cli_abort("{.arg serial_number} must be a valid RFC 4122 UUID URN (e.g., {.val urn:uuid:...}).")
    }
  }

  # Read raw renv.lock entries when present to enrich PURLs and MD5 hashes
  renv_raw_pkgs <- list()
  if (isTRUE(sc$has_renv) && !is.null(sc$renv_lock_path) && fs::file_exists(sc$renv_lock_path)) {
    raw_lock <- tryCatch(jsonlite::read_json(sc$renv_lock_path, simplifyVector = FALSE), error = function(e) NULL)
    if (is.list(raw_lock) && is.list(raw_lock$Packages)) {
      renv_raw_pkgs <- raw_lock$Packages
    }
  }

  # Build root project metadata component
  root_ref <- paste0("project:", sanitize_slug(sc$project_name))
  root_type <- if (identical(sc$project_type, "package")) "library" else "application"
  root_ver <- if (!is.null(manifest$capsule_id)) {
    as.character(manifest$capsule_id)
  } else if (!is.null(sc$git$short_commit)) {
    as.character(sc$git$short_commit)
  } else {
    "0.0.0-unversioned"
  }

  root_props <- list(
    cdx_prop("rcapsule:project_type", sc$project_type),
    cdx_prop("rcapsule:r_version", sc$r_version),
    cdx_prop("rcapsule:has_renv", tolower(as.character(isTRUE(sc$has_renv))))
  )
  if (!is.null(sc$git$commit)) {
    root_props[[length(root_props) + 1L]] <- cdx_prop("rcapsule:git_commit", sc$git$commit)
  }
  if (!is.null(manifest$capsule_id)) {
    root_props[[length(root_props) + 1L]] <- cdx_prop("rcapsule:capsule_id", manifest$capsule_id)
  }
  if (!is.null(manifest$integrity$content_digest)) {
    root_props[[length(root_props) + 1L]] <- cdx_prop("rcapsule:manifest_content_digest", manifest$integrity$content_digest)
  }

  root_component <- list(
    type = root_type,
    `bom-ref` = root_ref,
    name = sc$project_name,
    version = root_ver,
    properties = unname(root_props)
  )
  if (!is.null(manifest$integrity$content_digest)) {
    root_component$hashes <- list(list(
      alg = "SHA-256",
      content = as.character(manifest$integrity$content_digest)
    ))
  }

  components <- list()
  direct_refs <- character()
  dep_edges <- list()

  # 1. R runtime component (always present)
  r_runtime_ref <- "toolchain:r"
  components[[length(components) + 1L]] <- list(
    type = "platform",
    `bom-ref` = r_runtime_ref,
    name = "R",
    version = sc$r_version,
    purl = paste0("pkg:generic/r@", purl_encode_seg(sc$r_version)),
    scope = "required",
    properties = list(
      cdx_prop("rcapsule:ecosystem", "toolchain"),
      cdx_prop("rcapsule:toolchain_id", "r")
    )
  )
  direct_refs <- c(direct_refs, r_runtime_ref)

  # 2. R packages
  pkg_tbl <- sc$packages
  if (!isTRUE(include_base)) {
    pkg_tbl <- pkg_tbl[!pkg_tbl$is_base, , drop = FALSE]
  }
  n_r_pkgs <- nrow(pkg_tbl)
  if (n_r_pkgs > 0L) {
    for (i in seq_len(n_r_pkgs)) {
      p_name <- as.character(pkg_tbl$package[[i]])
      p_ver <- as.character(pkg_tbl$version[[i]])
      p_src <- as.character(pkg_tbl$source[[i]])
      p_req <- isTRUE(pkg_tbl$required[[i]])
      p_base <- isTRUE(pkg_tbl$is_base[[i]])
      renv_entry <- renv_raw_pkgs[[p_name]] %||% NULL

      bref <- paste0("r:", p_name)
      purl <- build_r_package_purl(
        pkg = p_name,
        version = p_ver,
        source = p_src,
        is_base = p_base,
        r_version = sc$r_version,
        renv_entry = renv_entry
      )

      comp <- list(
        type = "library",
        `bom-ref` = bref,
        name = p_name
      )
      if (!is.na(p_ver) && nzchar(p_ver)) {
        comp$version <- p_ver
      } else if (p_base) {
        comp$version <- sc$r_version
      }
      comp$purl <- purl
      comp$scope <- if (p_req) "required" else "optional"
      if (is.list(renv_entry) && is.character(renv_entry$Hash) && length(renv_entry$Hash) == 1L &&
        !is.na(renv_entry$Hash) && grepl("\\A[0-9a-fA-F]{32}\\z", renv_entry$Hash, perl = TRUE)) {
        comp$hashes <- list(list(alg = "MD5", content = tolower(as.character(renv_entry$Hash))))
      }
      comp$properties <- list(
        cdx_prop("rcapsule:ecosystem", "r"),
        cdx_prop("rcapsule:source", p_src),
        cdx_prop("rcapsule:required", tolower(as.character(p_req)))
      )

      components[[length(components) + 1L]] <- comp
      direct_refs <- c(direct_refs, bref)
    }
  }

  # 3. OS apt system dependencies
  apt_tbl <- sc$sysreqs
  unique_apts <- if (nrow(apt_tbl) > 0L) sort(unique(apt_tbl$apt_package)) else character()
  n_apt_pkgs <- length(unique_apts)
  pkg_to_apt_refs <- list()

  if (n_apt_pkgs > 0L) {
    for (ap in unique_apts) {
      sub_rows <- apt_tbl[apt_tbl$apt_package == ap, , drop = FALSE]
      stages <- sort(unique(sub_rows$stage))
      triggers <- sort(unique(trimws(unlist(strsplit(as.character(sub_rows$required_by), ",\\s*")))))
      triggers <- triggers[nzchar(triggers)]
      bref <- paste0("apt:", ap)

      comp <- list(
        type = "library",
        `bom-ref` = bref,
        name = ap,
        purl = paste0("pkg:deb/debian/", purl_encode_seg(ap)),
        scope = "required",
        properties = list(
          cdx_prop("rcapsule:ecosystem", "apt"),
          cdx_prop("rcapsule:stages", paste(stages, collapse = ",")),
          cdx_prop("rcapsule:triggered_by", paste(triggers, collapse = ","))
        )
      )
      components[[length(components) + 1L]] <- comp
      direct_refs <- c(direct_refs, bref)

      for (tr in triggers) {
        if (tr %in% pkg_tbl$package) {
          r_ref <- paste0("r:", tr)
          pkg_to_apt_refs[[r_ref]] <- unique(c(pkg_to_apt_refs[[r_ref]], bref))
        }
      }
    }
  }

  # 4. Python packages (PyPI / VCS)
  py_specs <- sc$python_packages %||% character()
  n_py_pkgs <- 0L
  seen_py_refs <- character()
  if (length(py_specs) > 0L) {
    for (sp in py_specs) {
      parsed <- parse_pypi_spec(sp)
      if (is.null(parsed) || !nzchar(parsed$purl_name) || !nzchar(parsed$name)) next
      ptype <- parsed$purl_type %||% "pypi"
      bref <- paste0(ptype, ":", parsed$purl_name)
      if (bref %in% seen_py_refs) next
      seen_py_refs <- c(seen_py_refs, bref)
      n_py_pkgs <- n_py_pkgs + 1L

      purl <- paste0("pkg:", ptype, "/", purl_encode_seg(parsed$purl_name))
      if (!is.na(parsed$version) && nzchar(parsed$version)) {
        purl <- paste0(purl, "@", purl_encode_seg(parsed$version))
      }
      comp <- list(
        type = "library",
        `bom-ref` = bref,
        name = parsed$name
      )
      if (!is.na(parsed$version) && nzchar(parsed$version)) {
        comp$version <- parsed$version
      }
      comp$purl <- purl
      comp$scope <- "required"
      comp$properties <- list(
        cdx_prop("rcapsule:ecosystem", "python"),
        cdx_prop("rcapsule:requirement_spec", parsed$spec)
      )
      components[[length(components) + 1L]] <- comp
      direct_refs <- c(direct_refs, bref)
    }
  }

  # 5. Compiled and scientific toolchains
  tc_cat <- toolchain_sbom_catalog()
  n_toolchains <- 1L # includes R runtime
  for (tc_key in names(tc_cat)) {
    tc_obj <- sc$toolchains[[tc_key]]
    if (!is.null(tc_obj) && isTRUE(tc_obj$detected)) {
      info <- tc_cat[[tc_key]]
      bref <- paste0("toolchain:", tc_key)
      reasons_str <- paste(tc_obj$reasons, collapse = "; ")
      comp <- list(
        type = info$type,
        `bom-ref` = bref,
        name = info$name,
        purl = paste0("pkg:generic/", purl_encode_seg(info$slug)),
        scope = "required",
        properties = list(
          cdx_prop("rcapsule:ecosystem", "toolchain"),
          cdx_prop("rcapsule:toolchain_id", tc_key),
          cdx_prop("rcapsule:detected_reasons", reasons_str)
        )
      )
      components[[length(components) + 1L]] <- comp
      direct_refs <- c(direct_refs, bref)
      n_toolchains <- n_toolchains + 1L
    }
  }

  # 6. Dependency graph (root -> direct components; R packages -> their apt sysreqs)
  dep_edges[[1L]] <- list(
    ref = root_ref,
    dependsOn = as_json_array(unique(direct_refs))
  )
  for (r_ref in sort(names(pkg_to_apt_refs))) {
    dep_edges[[length(dep_edges) + 1L]] <- list(
      ref = r_ref,
      dependsOn = as_json_array(sort(unique(pkg_to_apt_refs[[r_ref]])))
    )
  }

  pkg_ver <- as.character(utils::packageVersion("rcapsule"))
  bom <- list(
    bomFormat = "CycloneDX",
    specVersion = spec_version,
    serialNumber = serial_number,
    version = 1L,
    metadata = list(
      timestamp = utc_now_iso(),
      tools = list(
        components = list(list(
          type = "application",
          name = "rcapsule",
          version = pkg_ver,
          purl = paste0("pkg:cran/rcapsule@", pkg_ver)
        ))
      ),
      component = root_component
    ),
    components = unname(components),
    dependencies = unname(dep_edges)
  )

  json_text <- paste0(to_pretty_json(bom), "\n")
  written_path <- NULL
  if (!is.null(output)) {
    assert_no_control_chars(output, arg = "output")
    fs::dir_create(fs::path_dir(output))
    writeLines(enc2utf8(json_text), output, useBytes = TRUE)
    written_path <- as.character(fs::path_norm(output))
  }

  structure(
    list(
      bom = bom,
      json = json_text,
      path = written_path,
      format = format,
      spec_version = spec_version,
      serial_number = serial_number,
      summary = list(
        r_packages = n_r_pkgs,
        apt_packages = n_apt_pkgs,
        python_packages = n_py_pkgs,
        toolchains = n_toolchains,
        total_components = length(components)
      )
    ),
    class = "rcapsule_sbom"
  )
}

#' @export
as.character.rcapsule_sbom <- function(x, ...) {
  x$json
}

#' @export
print.rcapsule_sbom <- function(x, ...) {
  cli::cli_h1("rcapsule CycloneDX {x$spec_version} SBOM: {x$bom$metadata$component$name}")
  cli::cli_ul(c(
    "Serial number: {.val {x$serial_number}}",
    "Total components: {.val {x$summary$total_components}} (R={x$summary$r_packages}, apt={x$summary$apt_packages}, PyPI={x$summary$python_packages}, toolchains={x$summary$toolchains})",
    "Dependencies graph entries: {.val {length(x$bom$dependencies)}}",
    "Output file: {if (is.null(x$path)) '<in memory>' else x$path}"
  ))
  invisible(x)
}

#' Validate a CycloneDX 1.5 SBOM Document
#'
#' Validates an `rcapsule_sbom` object, a parsed CycloneDX list, or a JSON file
#' path against CycloneDX 1.5 structural, Package URL (PURL), hash, unique
#' `bom-ref`, and dependency graph referential integrity rules.
#'
#' @param sbom An `rcapsule_sbom` object from [export_sbom()], a parsed list,
#'   or a file path to a CycloneDX JSON file.
#' @param require_spec_version Expected CycloneDX specification version
#'   (defaults to `"1.5"`).
#'
#' @return An S3 object of class `rcapsule_sbom_validation` containing `valid`
#'   (logical), `bom_format`, `spec_version`, `n_components`, `n_dependencies`,
#'   `n_errors`, and `issues` (a tibble with columns `rule`, `severity`,
#'   `path`, and `message`).
#' @export
#' @examples
#' tmp <- tempfile("rcapsule_sbom_val_")
#' dir.create(tmp)
#' writeLines("library(jsonlite)", file.path(tmp, "run.R"))
#' sbom <- export_sbom(tmp)
#' val <- validate_sbom(sbom)
#' val$valid
#' unlink(tmp, recursive = TRUE)
validate_sbom <- function(sbom, require_spec_version = "1.5") {
  bom <- if (inherits(sbom, "rcapsule_sbom")) {
    sbom$bom
  } else if (is.character(sbom) && length(sbom) == 1L) {
    if (!fs::file_exists(sbom)) {
      cli::cli_abort("SBOM file does not exist: {.path {sbom}}.")
    }
    tryCatch(
      jsonlite::read_json(sbom, simplifyVector = FALSE),
      error = function(e) cli::cli_abort("Failed to parse SBOM JSON: {conditionMessage(e)}")
    )
  } else if (is.list(sbom)) {
    sbom
  } else {
    cli::cli_abort("{.arg sbom} must be an {.cls rcapsule_sbom} object, list, or JSON file path.")
  }

  issues <- list()
  add_issue <- function(rule, path, message, severity = "error") {
    issues[[length(issues) + 1L]] <<- list(
      rule = rule,
      severity = severity,
      path = path,
      message = message
    )
  }

  # 1. Top-level CycloneDX header fields
  bom_format <- as.character(bom$bomFormat %||% NA_character_)
  if (!identical(bom_format, "CycloneDX")) {
    add_issue("CDX001", "bomFormat", paste0("bomFormat must be 'CycloneDX', found '", bom_format, "'."))
  }

  spec_ver <- as.character(bom$specVersion %||% NA_character_)
  if (!identical(spec_ver, as.character(require_spec_version))) {
    add_issue("CDX002", "specVersion", paste0("specVersion must be '", require_spec_version, "', found '", spec_ver, "'."))
  }

  serial <- bom$serialNumber %||% ""
  uuid_pat <- "\\Aurn:uuid:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z"
  if (!is.character(serial) || length(serial) != 1L || is.na(serial) ||
    grepl("[\\x00-\\x1f\\x7f]", serial, perl = TRUE) ||
    !grepl(uuid_pat, serial, perl = TRUE)) {
    add_issue("CDX003", "serialNumber", "serialNumber must be a valid RFC 4122 UUID URN ('urn:uuid:...').")
  }

  ver_num <- bom$version
  if (is.null(ver_num) || !is.numeric(ver_num) || length(ver_num) != 1L || is.na(ver_num) || ver_num < 1 || ver_num != floor(ver_num)) {
    add_issue("CDX004", "version", "version must be a positive integer >= 1.")
  }

  # 2. Metadata & root component
  valid_types <- c(
    "application", "framework", "library", "container", "platform",
    "operating-system", "device", "device-driver", "firmware", "file",
    "machine-learning-model", "data"
  )
  declared_refs <- character()

  meta <- bom$metadata
  if (!is.list(meta)) {
    add_issue("CDX005", "metadata", "metadata object is missing or not a JSON object.")
  } else {
    ts <- meta$timestamp %||% ""
    if (!is.character(ts) || length(ts) != 1L || is.na(ts) ||
      grepl("[\\x00-\\x1f\\x7f]", ts, perl = TRUE) ||
      !grepl("\\A\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+-]\\d{2}:?\\d{2})?\\z", ts, perl = TRUE)) {
      add_issue("CDX006", "metadata.timestamp", "metadata.timestamp must be an ISO-8601 UTC timestamp.")
    }
    if (is.null(meta$tools) || !is.list(meta$tools)) {
      add_issue("CDX007", "metadata.tools", "metadata.tools is missing.")
    }
    rc <- meta$component
    if (!is.list(rc) || !nzchar(as.character(rc$name %||% "")[[1L]])) {
      add_issue("CDX008", "metadata.component", "metadata.component must define a non-empty name.")
    } else {
      rc_type <- as.character(rc$type %||% "")[[1L]]
      if (!(rc_type %in% valid_types)) {
        add_issue("CDX009", "metadata.component.type", paste0("Invalid root component type: '", rc_type, "'."))
      }
      rref <- as.character(rc[["bom-ref"]] %||% "")[[1L]]
      if (nzchar(rref)) {
        declared_refs <- c(declared_refs, rref)
      }
    }
  }

  # 3. Components list
  comps <- bom$components
  n_components <- 0L
  purl_pat <- "\\Apkg:[a-z][a-z0-9.+-]*/[^\\s\\x00-\\x1f\\x7f]+\\z"
  valid_algs <- c("MD5", "SHA-1", "SHA-256", "SHA-384", "SHA-512", "SHA3-256", "SHA3-512", "BLAKE2b-256", "BLAKE2b-512", "BLAKE3")

  if (!is.null(comps)) {
    if (!is.list(comps)) {
      add_issue("CDX010", "components", "components must be a JSON array of component objects.")
    } else {
      n_components <- length(comps)
      seen_refs <- character()
      for (i in seq_along(comps)) {
        cobj <- comps[[i]]
        cpath <- paste0("components[", i, "]")
        if (!is.list(cobj)) {
          add_issue("CDX010", cpath, "Component entry must be an object.")
          next
        }
        ctype <- if (is.character(cobj$type) && length(cobj$type) == 1L && !is.na(cobj$type)) cobj$type else ""
        cname <- if (is.character(cobj$name) && length(cobj$name) == 1L && !is.na(cobj$name)) cobj$name else ""
        cref <- if (is.character(cobj[["bom-ref"]]) && length(cobj[["bom-ref"]]) == 1L && !is.na(cobj[["bom-ref"]])) cobj[["bom-ref"]] else ""

        if (!(ctype %in% valid_types)) {
          add_issue("CDX011", paste0(cpath, ".type"), paste0("Invalid CycloneDX component type: '", ctype, "'."))
        }
        if (!nzchar(cname)) {
          add_issue("CDX012", paste0(cpath, ".name"), "Component name must be non-empty.")
        }
        if (nzchar(cref)) {
          if (cref %in% seen_refs || cref %in% declared_refs) {
            add_issue("CDX013", paste0(cpath, ".bom-ref"), paste0("Duplicate bom-ref detected: '", cref, "'."))
          } else {
            seen_refs <- c(seen_refs, cref)
            declared_refs <- c(declared_refs, cref)
          }
        }
        if (!is.null(cobj$purl)) {
          cpurl <- as.character(cobj$purl)
          if (length(cpurl) != 1L || is.na(cpurl) ||
            grepl("[\\x00-\\x1f\\x7f]", cpurl, perl = TRUE) ||
            !grepl(purl_pat, cpurl, perl = TRUE)) {
            add_issue("CDX014", paste0(cpath, ".purl"), paste0("Malformed Package URL (purl): '", paste(cpurl, collapse = ","), "'."))
          }
        }
        if (!is.null(cobj$hashes)) {
          if (!is.list(cobj$hashes)) {
            add_issue("CDX015", paste0(cpath, ".hashes"), "hashes must be an array of {alg, content} objects.")
          } else {
            for (j in seq_along(cobj$hashes)) {
              h <- cobj$hashes[[j]]
              if (!is.list(h)) {
                add_issue("CDX015", paste0(cpath, ".hashes[", j, "]"), "Hash entry must be a {alg, content} object.")
                next
              }
              alg <- if (is.character(h$alg) && length(h$alg) == 1L && !is.na(h$alg)) h$alg else ""
              content <- if (is.character(h$content) && length(h$content) == 1L && !is.na(h$content)) h$content else ""
              if (!(alg %in% valid_algs) || !grepl("\\A[0-9a-fA-F]{32,128}\\z", content, perl = TRUE)) {
                add_issue("CDX015", paste0(cpath, ".hashes[", j, "]"), paste0("Invalid hash entry (alg='", alg, "')."))
              }
            }
          }
        }
      }
    }
  }

  # 4. Dependency graph referential integrity
  deps <- bom$dependencies
  n_deps <- 0L
  if (!is.null(deps)) {
    if (!is.list(deps)) {
      add_issue("CDX016", "dependencies", "dependencies must be a JSON array.")
    } else {
      n_deps <- length(deps)
      for (i in seq_along(deps)) {
        dobj <- deps[[i]]
        dpath <- paste0("dependencies[", i, "]")
        if (!is.list(dobj)) {
          add_issue("CDX016", dpath, "Dependency entry must be an object with 'ref' and optional 'dependsOn'.")
          next
        }
        ref <- if (is.character(dobj$ref) && length(dobj$ref) == 1L && !is.na(dobj$ref)) dobj$ref else ""
        if (!nzchar(ref) || !(ref %in% declared_refs)) {
          add_issue("CDX017", paste0(dpath, ".ref"), paste0("Dependency ref '", ref, "' does not match any declared bom-ref."))
        }
        dep_on <- as.character(unlist(dobj$dependsOn %||% list()))
        if (length(dep_on) > 0L) {
          dangling <- setdiff(dep_on, declared_refs)
          if (length(dangling) > 0L) {
            add_issue("CDX018", paste0(dpath, ".dependsOn"), paste0("Unresolved dependsOn bom-ref(s): ", paste(dangling, collapse = ", "), "."))
          }
        }
      }
    }
  }

  issues_tbl <- if (length(issues) > 0L) {
    tibble::tibble(
      rule = vapply(issues, `[[`, character(1L), "rule"),
      severity = vapply(issues, `[[`, character(1L), "severity"),
      path = vapply(issues, `[[`, character(1L), "path"),
      message = vapply(issues, `[[`, character(1L), "message")
    )
  } else {
    tibble::tibble(
      rule = character(),
      severity = character(),
      path = character(),
      message = character()
    )
  }

  n_errors <- sum(issues_tbl$severity == "error")
  structure(
    list(
      valid = n_errors == 0L,
      bom_format = bom_format,
      spec_version = spec_ver,
      n_components = n_components,
      n_dependencies = n_deps,
      n_errors = n_errors,
      issues = issues_tbl
    ),
    class = "rcapsule_sbom_validation"
  )
}

#' @export
print.rcapsule_sbom_validation <- function(x, ...) {
  badge <- if (isTRUE(x$valid)) "VALID" else "INVALID"
  cli::cli_h1("CycloneDX SBOM Validation: {badge}")
  cli::cli_ul(c(
    "Format: {.val {x$bom_format}} | Spec version: {.val {x$spec_version}}",
    "Components: {.val {x$n_components}} | Dependency entries: {.val {x$n_dependencies}} | Errors: {.val {x$n_errors}}"
  ))
  if (nrow(x$issues) > 0L) {
    for (i in seq_len(nrow(x$issues))) {
      cli::cli_alert_danger("[{x$issues$rule[[i]]}] {x$issues$path[[i]]}: {x$issues$message[[i]]}")
    }
  }
  invisible(x)
}
