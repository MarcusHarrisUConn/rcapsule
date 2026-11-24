# Exact SHA-256 and structured numeric-tolerance artifact comparators

# Format index or matrix (row, col) coordinate for diagnostic labels
format_index_coord <- function(idx, dims = NULL) {
  if (!is.null(dims) && length(dims) == 2L) {
    pos <- arrayInd(idx, .dim = dims)
    return(paste0("[", pos[[1L]], ",", pos[[2L]], "]"))
  }
  paste0("[", idx, "]")
}

# Compare two numeric vectors/matrices/arrays element-wise under abs_tol + rel_tol * max(|a|, |b|)
compare_numeric_vectors <- function(a, b, abs_tol = 0, rel_tol = 0, label = "value", dims = NULL) {
  if (length(a) != length(b)) {
    return(list(
      ok = FALSE,
      max_abs_diff = Inf,
      max_rel_diff = Inf,
      detail = paste0(label, ": length mismatch (", length(a), " vs ", length(b), ")")
    ))
  }
  if (length(a) == 0L) {
    return(list(ok = TRUE, max_abs_diff = 0, max_rel_diff = 0, detail = NULL))
  }

  a_num <- as.numeric(a)
  b_num <- as.numeric(b)

  # Check NA / NaN alignment separately
  a_nan <- is.nan(a_num)
  b_nan <- is.nan(b_num)
  a_na <- is.na(a_num) & !a_nan
  b_na <- is.na(b_num) & !b_nan

  if (!identical(a_nan, b_nan)) {
    idx <- which(a_nan != b_nan)[[1L]]
    return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                detail = paste0(label, format_index_coord(idx, dims), ": NaN mismatch")))
  }
  if (!identical(a_na, b_na)) {
    idx <- which(a_na != b_na)[[1L]]
    return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                detail = paste0(label, format_index_coord(idx, dims), ": NA mismatch")))
  }

  # Check infinite values (+Inf / -Inf)
  a_inf <- is.infinite(a_num)
  b_inf <- is.infinite(b_num)
  if (!identical(a_inf, b_inf)) {
    idx <- which(a_inf != b_inf)[[1L]]
    return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                detail = paste0(label, format_index_coord(idx, dims), ": infinite vs finite mismatch")))
  }
  if (any(a_inf) && any(a_num[a_inf] != b_num[b_inf])) {
    inf_bad <- which(a_inf)[which(a_num[a_inf] != b_num[b_inf])[[1L]]]
    return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                detail = paste0(label, format_index_coord(inf_bad, dims), ": infinite sign mismatch (", a_num[[inf_bad]], " vs ", b_num[[inf_bad]], ")")))
  }

  fin <- is.finite(a_num) & is.finite(b_num)
  if (!any(fin)) {
    return(list(ok = TRUE, max_abs_diff = 0, max_rel_diff = 0, detail = NULL))
  }

  af <- a_num[fin]
  bf <- b_num[fin]
  abs_d <- abs(af - bf)
  scale_d <- pmax(abs(af), abs(bf))
  rel_d <- ifelse(scale_d == 0, 0, abs_d / scale_d)
  thresh <- abs_tol + rel_tol * scale_d

  bad <- abs_d > thresh
  max_abs <- max(abs_d)
  max_rel <- max(rel_d)

  if (any(bad)) {
    bad_idx <- which(fin)[which(bad)[[1L]]]
    return(list(
      ok = FALSE,
      max_abs_diff = max_abs,
      max_rel_diff = max_rel,
      detail = paste0(
        label, format_index_coord(bad_idx, dims), ": expected=", a_num[[bad_idx]],
        ", actual=", b_num[[bad_idx]],
        ", abs_diff=", signif(abs(a_num[[bad_idx]] - b_num[[bad_idx]]), 4L),
        ", rel_diff=", signif(if (max(abs(a_num[[bad_idx]]), abs(b_num[[bad_idx]])) == 0) 0 else abs(a_num[[bad_idx]] - b_num[[bad_idx]]) / max(abs(a_num[[bad_idx]]), abs(b_num[[bad_idx]])), 4L)
      )
    ))
  }

  list(ok = TRUE, max_abs_diff = max_abs, max_rel_diff = max_rel, detail = NULL)
}

# Compare two non-numeric atomic vectors with NA awareness
compare_exact_atomic <- function(a, b, label = "value") {
  if (length(a) != length(b)) {
    return(list(ok = FALSE, detail = paste0(label, ": length mismatch (", length(a), " vs ", length(b), ")")))
  }
  a_c <- as.character(a)
  b_c <- as.character(b)
  same <- (is.na(a_c) & is.na(b_c)) | (!is.na(a_c) & !is.na(b_c) & a_c == b_c)
  if (!all(same)) {
    idx <- which(!same)[[1L]]
    return(list(
      ok = FALSE,
      detail = paste0(label, "[", idx, "]: expected=", shQuote(a_c[[idx]]), ", actual=", shQuote(b_c[[idx]]))
    ))
  }
  list(ok = TRUE, detail = NULL)
}

# Compare two data.frames column by column (positionally to cover duplicate column names)
compare_data_frames <- function(a, b, abs_tol = 0, rel_tol = 0, ignore_attributes = FALSE, label = "table") {
  if (nrow(a) != nrow(b)) {
    return(list(
      ok = FALSE,
      max_abs_diff = Inf,
      max_rel_diff = Inf,
      detail = paste0(label, ": row count mismatch (", nrow(a), " vs ", nrow(b), " rows)")
    ))
  }
  if (ncol(a) != ncol(b) || !identical(names(a), names(b))) {
    missing_cols <- setdiff(names(a), names(b))
    extra_cols <- setdiff(names(b), names(a))
    if (length(missing_cols) > 0L || length(extra_cols) > 0L) {
      parts <- c(
        if (length(missing_cols) > 0L) paste0("missing columns: ", paste(missing_cols, collapse = ", ")) else NULL,
        if (length(extra_cols) > 0L) paste0("extra columns: ", paste(extra_cols, collapse = ", ")) else NULL
      )
      msg <- paste0(label, ": column mismatch (", paste(parts, collapse = "; "), ")")
    } else {
      msg <- paste0(label, ": column order mismatch (", paste(names(a), collapse = ","), " vs ", paste(names(b), collapse = ","), ")")
    }
    return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf, detail = msg))
  }
  if (!isTRUE(ignore_attributes) && !identical(rownames(a), rownames(b))) {
    return(list(
      ok = FALSE,
      max_abs_diff = Inf,
      max_rel_diff = Inf,
      detail = paste0(label, ": row.names mismatch")
    ))
  }

  max_abs <- 0
  max_rel <- 0
  col_names <- names(a)
  has_dup_cols <- anyDuplicated(col_names) > 0L

  for (i in seq_len(ncol(a))) {
    col <- col_names[[i]]
    ca <- a[[i]]
    cb <- b[[i]]
    col_lbl <- if (has_dup_cols) paste0(label, "$", col, "[[", i, "]]") else paste0(label, "$", col)
    if (is.numeric(ca) && is.numeric(cb)) {
      res <- compare_numeric_vectors(ca, cb, abs_tol = abs_tol, rel_tol = rel_tol, label = col_lbl)
      if (!isTRUE(res$ok)) return(res)
      max_abs <- max(max_abs, res$max_abs_diff)
      max_rel <- max(max_rel, res$max_rel_diff)
    } else if (is.factor(ca) && is.factor(cb)) {
      if (!isTRUE(ignore_attributes)) {
        if (!identical(is.ordered(ca), is.ordered(cb))) {
          return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                      detail = paste0(col_lbl, ": ordered factor mismatch")))
        }
        if (!identical(levels(ca), levels(cb))) {
          return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                      detail = paste0(col_lbl, ": factor levels mismatch")))
        }
      }
      res <- compare_exact_atomic(ca, cb, label = col_lbl)
      if (!isTRUE(res$ok)) {
        return(list(ok = FALSE, max_abs_diff = max_abs, max_rel_diff = max_rel, detail = res$detail))
      }
    } else if ((is.character(ca) && is.character(cb)) ||
      (is.logical(ca) && is.logical(cb))) {
      res <- compare_exact_atomic(ca, cb, label = col_lbl)
      if (!isTRUE(res$ok)) {
        return(list(ok = FALSE, max_abs_diff = max_abs, max_rel_diff = max_rel, detail = res$detail))
      }
    } else {
      res <- compare_r_objects(
        ca, cb,
        abs_tol = abs_tol,
        rel_tol = rel_tol,
        ignore_attributes = ignore_attributes,
        label = col_lbl
      )
      if (!isTRUE(res$ok)) return(res)
      max_abs <- max(max_abs, res$max_abs_diff)
      max_rel <- max(max_rel, res$max_rel_diff)
    }
  }

  list(ok = TRUE, max_abs_diff = max_abs, max_rel_diff = max_rel, detail = NULL)
}

# Recursive comparator for arbitrary R objects (RDS and parsed JSON trees)
compare_r_objects <- function(a, b, abs_tol = 0, rel_tol = 0, ignore_attributes = FALSE, label = "root") {
  # Fast exact digest check via digest::digest()
  if (identical(digest::digest(a, algo = "sha256"), digest::digest(b, algo = "sha256"))) {
    return(list(ok = TRUE, max_abs_diff = 0, max_rel_diff = 0, detail = NULL))
  }

  if (is.null(a) && is.null(b)) {
    return(list(ok = TRUE, max_abs_diff = 0, max_rel_diff = 0, detail = NULL))
  }
  if (is.null(a) || is.null(b)) {
    return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                detail = paste0(label, ": NULL vs non-NULL mismatch")))
  }

  # Data frames (including tibbles)
  if (is.data.frame(a) && is.data.frame(b)) {
    return(compare_data_frames(
      a, b,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      ignore_attributes = ignore_attributes,
      label = label
    ))
  }

  # Date / POSIXt objects
  if (inherits(a, "Date") && inherits(b, "Date")) {
    return(compare_numeric_vectors(as.numeric(a), as.numeric(b), abs_tol = abs_tol, rel_tol = rel_tol, label = label))
  }
  if (inherits(a, "POSIXt") && inherits(b, "POSIXt")) {
    if (!isTRUE(ignore_attributes)) {
      tza <- as.character(attr(as.POSIXct(a), "tzone") %||% "")[[1L]]
      tzb <- as.character(attr(as.POSIXct(b), "tzone") %||% "")[[1L]]
      if (!identical(tza, tzb)) {
        return(list(
          ok = FALSE,
          max_abs_diff = Inf,
          max_rel_diff = Inf,
          detail = paste0(label, ": POSIXt timezone mismatch ('", tza, "' vs '", tzb, "')")
        ))
      }
    }
    return(compare_numeric_vectors(as.numeric(a), as.numeric(b), abs_tol = abs_tol, rel_tol = rel_tol, label = label))
  }

  # Guard factor vs non-factor (both factor and integer have typeof() == "integer")
  if (xor(is.factor(a), is.factor(b))) {
    return(list(
      ok = FALSE,
      max_abs_diff = Inf,
      max_rel_diff = Inf,
      detail = paste0(label, ": object type/class mismatch (", paste(class(a), collapse = "/"), " vs ", paste(class(b), collapse = "/"), ")")
    ))
  }

  # Numeric vectors / matrices / arrays
  if (is.numeric(a) && is.numeric(b)) {
    if (!identical(dim(a), dim(b))) {
      da_s <- paste(dim(a) %||% length(a), collapse = "x")
      db_s <- paste(dim(b) %||% length(b), collapse = "x")
      return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                  detail = paste0(label, ": dimension mismatch (", da_s, " vs ", db_s, ")")))
    }
    if (!isTRUE(ignore_attributes)) {
      if (!identical(names(a), names(b))) {
        return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                    detail = paste0(label, ": vector names mismatch")))
      }
      if (!identical(dimnames(a), dimnames(b))) {
        return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                    detail = paste0(label, ": dimnames mismatch")))
      }
    }
    return(compare_numeric_vectors(a, b, abs_tol = abs_tol, rel_tol = rel_tol, label = label, dims = dim(a)))
  }

  # Recursive lists (named or positional, including deeply nested JSON/RDS objects)
  if (is.list(a) && is.list(b)) {
    if (!isTRUE(ignore_attributes) && !identical(class(a), class(b))) {
      return(list(
        ok = FALSE,
        max_abs_diff = Inf,
        max_rel_diff = Inf,
        detail = paste0(label, ": object type/class mismatch (", paste(class(a), collapse = "/"), " vs ", paste(class(b), collapse = "/"), ")")
      ))
    }
    # Distinguish empty JSON object {} (named empty list) from empty JSON array [] (unnamed list)
    if (length(a) == 0L && length(b) == 0L) {
      if (!identical(is.null(names(a)), is.null(names(b)))) {
        return(list(
          ok = FALSE,
          max_abs_diff = Inf,
          max_rel_diff = Inf,
          detail = paste0(label, ": list object vs array mismatch (empty named list vs unnamed list)")
        ))
      }
      return(list(ok = TRUE, max_abs_diff = 0, max_rel_diff = 0, detail = NULL))
    }

    na <- names(a)
    nb <- names(b)
    has_names_a <- !is.null(na) && any(nzchar(na))
    has_names_b <- !is.null(nb) && any(nzchar(nb))

    if (has_names_a || has_names_b) {
      keys_a <- na %||% character()
      keys_b <- nb %||% character()
      has_partial_or_dup <- any(!nzchar(keys_a)) || anyDuplicated(keys_a) > 0L ||
        any(!nzchar(keys_b)) || anyDuplicated(keys_b) > 0L ||
        length(keys_a) != length(a) || length(keys_b) != length(b)
      if (has_partial_or_dup) {
        if (length(a) != length(b) || !identical(keys_a, keys_b)) {
          return(list(
            ok = FALSE,
            max_abs_diff = Inf,
            max_rel_diff = Inf,
            detail = paste0(label, ": list names/length mismatch for duplicate or partially named list")
          ))
        }
        max_abs <- 0
        max_rel <- 0
        for (i in seq_along(a)) {
          elem_lbl <- if (nzchar(keys_a[[i]])) {
            paste0(label, "$", keys_a[[i]], "[[", i, "]]")
          } else {
            paste0(label, "[[", i, "]]")
          }
          res <- compare_r_objects(
            a[[i]], b[[i]],
            abs_tol = abs_tol, rel_tol = rel_tol,
            ignore_attributes = ignore_attributes, label = elem_lbl
          )
          if (!isTRUE(res$ok)) return(res)
          max_abs <- max(max_abs, res$max_abs_diff)
          max_rel <- max(max_rel, res$max_rel_diff)
        }
        return(list(ok = TRUE, max_abs_diff = max_abs, max_rel_diff = max_rel, detail = NULL))
      }

      missing_k <- setdiff(keys_a, keys_b)
      extra_k <- setdiff(keys_b, keys_a)
      if (length(missing_k) > 0L || length(extra_k) > 0L || length(a) != length(b)) {
        parts <- c(
          if (length(missing_k) > 0L) paste0("missing keys: ", paste(missing_k, collapse = ", ")) else NULL,
          if (length(extra_k) > 0L) paste0("extra keys: ", paste(extra_k, collapse = ", ")) else NULL
        )
        detail_msg <- if (length(parts) > 0L) {
          paste0(label, ": list key mismatch (", paste(parts, collapse = "; "), ")")
        } else {
          paste0(label, ": list length mismatch (", length(a), " vs ", length(b), ")")
        }
        return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf, detail = detail_msg))
      }
      max_abs <- 0
      max_rel <- 0
      for (k in keys_a) {
        res <- compare_r_objects(a[[k]], b[[k]], abs_tol = abs_tol, rel_tol = rel_tol,
                                 ignore_attributes = ignore_attributes, label = paste0(label, "$", k))
        if (!isTRUE(res$ok)) return(res)
        max_abs <- max(max_abs, res$max_abs_diff)
        max_rel <- max(max_rel, res$max_rel_diff)
      }
      return(list(ok = TRUE, max_abs_diff = max_abs, max_rel_diff = max_rel, detail = NULL))
    } else {
      if (length(a) != length(b)) {
        return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                    detail = paste0(label, ": list length mismatch (", length(a), " vs ", length(b), ")")))
      }
      max_abs <- 0
      max_rel <- 0
      for (i in seq_along(a)) {
        res <- compare_r_objects(a[[i]], b[[i]], abs_tol = abs_tol, rel_tol = rel_tol,
                                 ignore_attributes = ignore_attributes, label = paste0(label, "[[", i, "]]"))
        if (!isTRUE(res$ok)) return(res)
        max_abs <- max(max_abs, res$max_abs_diff)
        max_rel <- max(max_rel, res$max_rel_diff)
      }
      return(list(ok = TRUE, max_abs_diff = max_abs, max_rel_diff = max_rel, detail = NULL))
    }
  }

  # Atomic non-numeric types (character, logical, factor, matrices/arrays)
  if (is.atomic(a) && is.atomic(b) && (identical(typeof(a), typeof(b)) || (is.factor(a) && is.factor(b)))) {
    if (!identical(dim(a), dim(b))) {
      da_s <- paste(dim(a) %||% length(a), collapse = "x")
      db_s <- paste(dim(b) %||% length(b), collapse = "x")
      return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                  detail = paste0(label, ": dimension mismatch (", da_s, " vs ", db_s, ")")))
    }
    if (!isTRUE(ignore_attributes)) {
      if (!identical(names(a), names(b))) {
        return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                    detail = paste0(label, ": vector names mismatch")))
      }
      if (!identical(dimnames(a), dimnames(b))) {
        return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                    detail = paste0(label, ": dimnames mismatch")))
      }
      if (is.factor(a) && is.factor(b)) {
        if (!identical(is.ordered(a), is.ordered(b))) {
          return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                      detail = paste0(label, ": ordered factor mismatch")))
        }
        if (!identical(levels(a), levels(b))) {
          return(list(ok = FALSE, max_abs_diff = Inf, max_rel_diff = Inf,
                      detail = paste0(label, ": factor levels mismatch")))
        }
      }
    }
    res <- compare_exact_atomic(a, b, label = label)
    return(list(
      ok = res$ok,
      max_abs_diff = if (res$ok) 0 else Inf,
      max_rel_diff = if (res$ok) 0 else Inf,
      detail = res$detail
    ))
  }

  list(
    ok = FALSE,
    max_abs_diff = Inf,
    max_rel_diff = Inf,
    detail = paste0(label, ": object type/class mismatch (", paste(class(a), collapse = "/"), " vs ", paste(class(b), collapse = "/"), ")")
  )
}

# Normalize CRLF (\r\n) to LF (\n) on a raw vector safely (handles embedded NULs)
normalize_crlf_raw <- function(x) {
  n <- length(x)
  if (n < 2L) return(x)
  is_cr <- x[-n] == as.raw(0x0d)
  is_lf <- x[-1L] == as.raw(0x0a)
  drop_idx <- which(is_cr & is_lf)
  if (length(drop_idx) == 0L) return(x)
  x[-drop_idx]
}

# Check whether two text-like files differ exclusively in CRLF vs LF line endings
differs_only_in_line_endings <- function(ref_file, actual_path, fmt, max_bytes = 5242880L) {
  text_fmts <- c("csv", "tsv", "json", "text", "markdown", "html", "yaml", "r", "quarto", "rmarkdown", "stan")
  if (!(fmt %in% text_fmts) || is.null(ref_file) || !fs::file_exists(ref_file) || !fs::file_exists(actual_path)) {
    return(FALSE)
  }
  sz_a <- as.numeric(file.info(ref_file)$size)
  sz_b <- as.numeric(file.info(actual_path)$size)
  if (is.na(sz_a) || is.na(sz_b) || sz_a > max_bytes || sz_b > max_bytes) {
    return(FALSE)
  }
  raw_a <- readBin(ref_file, what = "raw", n = sz_a)
  raw_b <- readBin(actual_path, what = "raw", n = sz_b)
  if (any(raw_a == as.raw(0x00)) || any(raw_b == as.raw(0x00))) {
    return(FALSE)
  }
  constant_time_equal(sha256_raw(normalize_crlf_raw(raw_a)), sha256_raw(normalize_crlf_raw(raw_b)))
}

# Parse and compare structured formats (csv, tsv, json, rds)
compare_structured_files <- function(ref_file, actual_path, fmt, abs_tol, rel_tol, ignore_attributes = FALSE) {
  tryCatch(
    {
      if (fmt == "csv") {
        da <- utils::read.csv(ref_file, stringsAsFactors = FALSE, check.names = FALSE)
        db <- utils::read.csv(actual_path, stringsAsFactors = FALSE, check.names = FALSE)
        compare_data_frames(da, db, abs_tol = abs_tol, rel_tol = rel_tol, ignore_attributes = ignore_attributes, label = basename(actual_path))
      } else if (fmt == "tsv") {
        da <- utils::read.delim(ref_file, stringsAsFactors = FALSE, check.names = FALSE)
        db <- utils::read.delim(actual_path, stringsAsFactors = FALSE, check.names = FALSE)
        compare_data_frames(da, db, abs_tol = abs_tol, rel_tol = rel_tol, ignore_attributes = ignore_attributes, label = basename(actual_path))
      } else if (fmt == "json") {
        ja <- jsonlite::fromJSON(ref_file, simplifyVector = TRUE)
        jb <- jsonlite::fromJSON(actual_path, simplifyVector = TRUE)
        compare_r_objects(ja, jb, abs_tol = abs_tol, rel_tol = rel_tol, ignore_attributes = TRUE, label = basename(actual_path))
      } else if (fmt == "rds") {
        ra <- readRDS(ref_file)
        rb <- readRDS(actual_path)
        compare_r_objects(ra, rb, abs_tol = abs_tol, rel_tol = rel_tol, ignore_attributes = ignore_attributes, label = basename(actual_path))
      } else {
        list(
          ok = FALSE,
          max_abs_diff = NA_real_,
          max_rel_diff = NA_real_,
          detail = paste0("SHA-256 mismatch for non-numeric format '", fmt, "' (exact match required).")
        )
      }
    },
    error = function(e) {
      list(
        ok = FALSE,
        max_abs_diff = NA_real_,
        max_rel_diff = NA_real_,
        detail = paste0("Failed to parse artifact as ", fmt, ": ", conditionMessage(e))
      )
    }
  )
}

#' Compare Two Output Artifacts with Exact SHA-256 and Numeric Tolerance
#'
#' Fast-paths exact bit-for-bit verification via SHA-256. When digests differ
#' and numeric tolerances (`abs_tol`/`atol > 0` or `rel_tol`/`rtol > 0`) are
#' permitted, recursively parses `csv`, `tsv`, `json`, or `rds` artifacts
#' (including nested lists, data frames, matrices, and arrays) and verifies that
#' every numeric element satisfies `abs(a - b) <= abs_tol + rel_tol * max(|a|, |b|)`
#' while preserving exact `NA`/`NaN`/`Inf` alignment and exact equality for all
#' non-numeric keys, columns, dimensions, and labels.
#'
#' @param expected_path Path to the expected reference artifact (may be `NULL`
#'   if `expected_sha256` and/or `expected_raw` is supplied).
#' @param actual_path Path to the freshly reproduced artifact.
#' @param expected_sha256 Optional recorded SHA-256 hex digest of the expected
#'   artifact.
#' @param abs_tol Non-negative absolute numeric tolerance (default `0`).
#' @param rel_tol Non-negative relative numeric tolerance (default `0`).
#' @param atol Optional alias for `abs_tol`; overrides `abs_tol` if non-`NULL`.
#' @param rtol Optional alias for `rel_tol`; overrides `rel_tol` if non-`NULL`.
#' @param format Artifact format: `"auto"` (default), `"csv"`, `"tsv"`,
#'   `"json"`, `"rds"`, `"text"`, or `"binary"`.
#' @param ignore_attributes Logical; if `TRUE`, ignores vector/matrix name
#'   attributes during RDS comparison.
#' @param expected_raw Optional raw vector of the expected artifact bytes (e.g.,
#'   decoded from an embedded manifest snapshot).
#'
#' @return A list with fields `status` (`"exact_match"`, `"within_tolerance"`,
#'   `"mismatch"`, or `"missing"`), `passed` (logical), `expected_sha256`,
#'   `actual_sha256`, `max_abs_diff`, `max_rel_diff`, `abs_tol`, `rel_tol`, and
#'   `details`.
#' @export
#' @examples
#' f1 <- tempfile(fileext = ".csv")
#' f2 <- tempfile(fileext = ".csv")
#' write.csv(data.frame(k = c("a", "b"), est = c(1.0000, 2.0000)), f1, row.names = FALSE)
#' write.csv(data.frame(k = c("a", "b"), est = c(1.0002, 1.9999)), f2, row.names = FALSE)
#' compare_artifacts(f1, f2, atol = 1e-3, rtol = 1e-3)
#' unlink(c(f1, f2))
compare_artifacts <- function(expected_path = NULL,
                              actual_path,
                              expected_sha256 = NULL,
                              abs_tol = 0,
                              rel_tol = 0,
                              atol = NULL,
                              rtol = NULL,
                              format = "auto",
                              ignore_attributes = FALSE,
                              expected_raw = NULL) {
  abs_tol <- as.numeric(atol %||% abs_tol %||% 0)
  rel_tol <- as.numeric(rtol %||% rel_tol %||% 0)
  if (length(abs_tol) != 1L || is.na(abs_tol) || !is.finite(abs_tol) || abs_tol < 0) {
    cli::cli_abort("{.arg abs_tol}/{.arg atol} must be a single finite non-negative number.")
  }
  if (length(rel_tol) != 1L || is.na(rel_tol) || !is.finite(rel_tol) || rel_tol < 0) {
    cli::cli_abort("{.arg rel_tol}/{.arg rtol} must be a single finite non-negative number.")
  }

  if (is.null(expected_sha256) && !is.null(expected_path) && fs::file_exists(expected_path)) {
    expected_sha256 <- sha256_file(expected_path)
  }

  if (is.null(actual_path) || !fs::file_exists(actual_path)) {
    return(list(
      status = "missing",
      passed = FALSE,
      expected_sha256 = expected_sha256 %||% NA_character_,
      actual_sha256 = NA_character_,
      max_abs_diff = NA_real_,
      max_rel_diff = NA_real_,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      details = "Expected output artifact was not produced."
    ))
  }

  actual_sha256 <- sha256_file(actual_path)

  # Fast path: constant-time exact SHA-256 match
  if (!is.null(expected_sha256) && constant_time_equal(actual_sha256, as.character(expected_sha256))) {
    return(list(
      status = "exact_match",
      passed = TRUE,
      expected_sha256 = expected_sha256,
      actual_sha256 = actual_sha256,
      max_abs_diff = 0,
      max_rel_diff = 0,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      details = "Exact SHA-256 bit-for-bit match."
    ))
  }

  # Resolve reference file (used for CRLF/structural diagnostics and tolerance checks)
  ref_file <- NULL
  temp_ref <- NULL
  if (!is.null(expected_path) && fs::file_exists(expected_path)) {
    ref_file <- expected_path
  } else if (!is.null(expected_raw) && is.raw(expected_raw)) {
    ext <- tools::file_ext(actual_path)
    temp_ref <- tempfile("rcapsule_ref_", fileext = if (nzchar(ext)) paste0(".", ext) else "")
    writeBin(expected_raw, temp_ref)
    on.exit(unlink(temp_ref), add = TRUE)
    ref_file <- temp_ref
  }
  fmt <- if (identical(format, "auto")) detect_artifact_format(actual_path) else tolower(format)

  # Zero tolerance requested -> fail on digest mismatch, with optional diagnostic hint
  if (abs_tol <= 0 && rel_tol <= 0) {
    if (!is.null(ref_file) && differs_only_in_line_endings(ref_file, actual_path, fmt)) {
      return(list(
        status = "mismatch",
        passed = FALSE,
        expected_sha256 = expected_sha256 %||% NA_character_,
        actual_sha256 = actual_sha256,
        max_abs_diff = 0,
        max_rel_diff = 0,
        abs_tol = abs_tol,
        rel_tol = rel_tol,
        details = "SHA-256 digest mismatch (exact match required; files differ only in CRLF vs LF line endings)."
      ))
    }
    if (!is.null(ref_file) && fmt %in% c("csv", "tsv", "json", "rds")) {
      diag_comp <- compare_structured_files(ref_file, actual_path, fmt, abs_tol = 0, rel_tol = 0, ignore_attributes = ignore_attributes)
      diag_note <- if (!is.null(diag_comp$detail) && nzchar(diag_comp$detail)) {
        paste0("SHA-256 digest mismatch (exact match required; ", diag_comp$detail, ").")
      } else {
        "SHA-256 digest mismatch (exact match required; parsed content identical but serialization differs)."
      }
      return(list(
        status = "mismatch",
        passed = FALSE,
        expected_sha256 = expected_sha256 %||% NA_character_,
        actual_sha256 = actual_sha256,
        max_abs_diff = diag_comp$max_abs_diff %||% NA_real_,
        max_rel_diff = diag_comp$max_rel_diff %||% NA_real_,
        abs_tol = abs_tol,
        rel_tol = rel_tol,
        details = diag_note
      ))
    }
    return(list(
      status = "mismatch",
      passed = FALSE,
      expected_sha256 = expected_sha256 %||% NA_character_,
      actual_sha256 = actual_sha256,
      max_abs_diff = NA_real_,
      max_rel_diff = NA_real_,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      details = "SHA-256 digest mismatch (exact match required)."
    ))
  }

  if (is.null(ref_file)) {
    return(list(
      status = "mismatch",
      passed = FALSE,
      expected_sha256 = expected_sha256 %||% NA_character_,
      actual_sha256 = actual_sha256,
      max_abs_diff = NA_real_,
      max_rel_diff = NA_real_,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      details = "SHA-256 mismatch and no reference artifact or snapshot available for tolerance comparison."
    ))
  }

  comp <- compare_structured_files(ref_file, actual_path, fmt, abs_tol = abs_tol, rel_tol = rel_tol, ignore_attributes = ignore_attributes)

  if (isTRUE(comp$ok)) {
    list(
      status = "within_tolerance",
      passed = TRUE,
      expected_sha256 = expected_sha256 %||% NA_character_,
      actual_sha256 = actual_sha256,
      max_abs_diff = comp$max_abs_diff,
      max_rel_diff = comp$max_rel_diff,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      details = paste0(
        "Verified within tolerance (max_abs_diff=", signif(comp$max_abs_diff, 4L),
        ", max_rel_diff=", signif(comp$max_rel_diff, 4L), ")."
      )
    )
  } else {
    list(
      status = "mismatch",
      passed = FALSE,
      expected_sha256 = expected_sha256 %||% NA_character_,
      actual_sha256 = actual_sha256,
      max_abs_diff = comp$max_abs_diff %||% NA_real_,
      max_rel_diff = comp$max_rel_diff %||% NA_real_,
      abs_tol = abs_tol,
      rel_tol = rel_tol,
      details = comp$detail %||% "Artifact values exceeded numeric tolerance."
    )
  }
}
