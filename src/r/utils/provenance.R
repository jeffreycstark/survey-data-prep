# src/r/utils/provenance.R
# Run manifest writer (audit ticket C1).
#
# Captures sha256 of every input/spec/output file, plus engine versions,
# git commit, and dirty-tree status, for a single harmonization run.
# This is the foundation for Layer 6 (provenance and determinism); without
# it, no harmonization run is reproducible — papers cannot cite "version X"
# because there is no X.
#
# Public API:
#   write_manifest(survey, inputs, specs, outputs, output_path = NULL)
#
# C1 is purely additive: this file is not yet called from any pipeline.
# C2 wires it into per-survey final-dataset scripts.

library(here)


# ---------------------------------------------------------------------------
# Engine files whose hashes we record on every run. Stable paths; changes to
# any of these change harmonization behavior, so they must be in the manifest.
# ---------------------------------------------------------------------------
.PROVENANCE_ENGINE_FILES <- c(
  "src/r/harmonize/harmonize.R",
  "src/r/utils/recoding.R",
  "src/r/harmonize/validate_spec.R",
  "src/r/utils/validation.R"
)

# Manifest schema_version below tracks the harmonize-spec schema (the YAML
# spec format, currently v1). If the manifest format itself ever evolves,
# add a separate `manifest_format_version` field rather than bumping this.
.MANIFEST_SPEC_SCHEMA_VERSION <- 1L


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Compute sha256 of a file. Returns NULL with a captured error message if
# the file is missing or unreadable, so the manifest can record the failure
# without crashing the run.
.hash_file <- function(path) {
  if (!file.exists(path)) {
    return(list(sha256 = NULL, error = sprintf("file not found: %s", path)))
  }
  res <- tryCatch(
    digest::digest(file = path, algo = "sha256"),
    error = function(e) e
  )
  if (inherits(res, "error")) {
    return(list(sha256 = NULL, error = conditionMessage(res)))
  }
  list(sha256 = res, error = NULL)
}

# Try to read just nrow from an .rds without holding the data alive longer
# than needed. R has no metadata-only API for RDS, so we readRDS, take nrow,
# discard. Wrapped in tryCatch so a corrupt rds doesn't kill the manifest.
.rds_nrow_ncol <- function(path, want_ncol = FALSE) {
  res <- tryCatch({
    obj <- readRDS(path)
    out <- list(n_rows = NROW(obj))
    if (want_ncol) out$n_cols <- NCOL(obj)
    out
  }, error = function(e) list(error = conditionMessage(e)))
  res
}

# Parquet metadata (rows/cols) without loading the full table when possible.
.parquet_nrow_ncol <- function(path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    return(list(n_rows = NULL, n_cols = NULL,
                error = "arrow package not available"))
  }
  tryCatch({
    # open_dataset is cheap and gives schema + num_rows without materializing
    ds <- arrow::open_dataset(path, format = "parquet")
    list(n_rows = ds$num_rows, n_cols = length(ds$schema$names))
  }, error = function(e) list(n_rows = NULL, n_cols = NULL,
                              error = conditionMessage(e)))
}


# Build an entry for an input file. .rds → adds n_rows. Other formats just
# get the hash; we don't crack open .sav/.dta/.csv here (the wave-loader
# scripts already do that work upstream and write .rds).
.build_input_entry <- function(path) {
  entry <- list(path = path)
  h <- .hash_file(path)
  entry$sha256 <- h$sha256
  if (!is.null(h$error)) {
    entry$error <- h$error
    entry$n_rows <- NULL
    return(entry)
  }
  if (grepl("\\.rds$", path, ignore.case = TRUE)) {
    nr <- .rds_nrow_ncol(path, want_ncol = FALSE)
    if (!is.null(nr$error)) {
      entry$error <- nr$error
      entry$n_rows <- NULL
    } else {
      entry$n_rows <- nr$n_rows
    }
  } else {
    entry$n_rows <- NULL
  }
  entry
}


# Spec entry: hash + count of `variables:` from parsed YAML.
.build_spec_entry <- function(path) {
  entry <- list(path = path)
  h <- .hash_file(path)
  entry$sha256 <- h$sha256
  if (!is.null(h$error)) {
    entry$error <- h$error
    entry$n_variables <- NULL
    return(entry)
  }
  parsed <- tryCatch(
    yaml::read_yaml(path),
    error = function(e) e
  )
  if (inherits(parsed, "error")) {
    entry$error <- conditionMessage(parsed)
    entry$n_variables <- NULL
  } else {
    vars <- parsed$variables
    entry$n_variables <- if (is.null(vars)) 0L else length(vars)
  }
  entry
}


# Output entry: hash + nrow/ncol where format permits.
.build_output_entry <- function(path) {
  entry <- list(path = path)
  h <- .hash_file(path)
  entry$sha256 <- h$sha256
  if (!is.null(h$error)) {
    entry$error <- h$error
    entry$n_rows <- NULL
    entry$n_cols <- NULL
    return(entry)
  }
  ext <- tolower(tools::file_ext(path))
  if (ext == "rds") {
    nr <- .rds_nrow_ncol(path, want_ncol = TRUE)
    if (!is.null(nr$error)) {
      entry$error <- nr$error
      entry$n_rows <- NULL
      entry$n_cols <- NULL
    } else {
      entry$n_rows <- nr$n_rows
      entry$n_cols <- nr$n_cols
    }
  } else if (ext == "parquet") {
    nr <- .parquet_nrow_ncol(path)
    entry$n_rows <- nr$n_rows
    entry$n_cols <- nr$n_cols
    if (!is.null(nr$error)) entry$error <- nr$error
  } else {
    # CSV and others: skip dimensions to keep the manifest cheap. We may
    # add a trivial CSV peek later if a downstream consumer needs it.
    entry$n_rows <- NULL
    entry$n_cols <- NULL
  }
  entry
}


# Engine-version map. Always keys by the engine path (relative to repo
# root) so the manifest is portable across machines.
#
# `engine_files` defaults to the shared harmonize engine, which is correct for
# every YAML-spec survey. NON-SURVEY modules (V-Dem, MARPOR, UNGA, UNSC,
# OECD-DAC) never call harmonize_all() and have no specs, so recording those
# four hashes would mark them STALE every time recoding.R changes — a false
# positive on a file they do not read. Those modules pass their OWN scripts
# instead, which is what actually determines their output.
.collect_engine_versions <- function(engine_files = .PROVENANCE_ENGINE_FILES) {
  out <- list()
  for (rel in engine_files) {
    abs <- here::here(rel)
    h <- .hash_file(abs)
    if (is.null(h$error)) {
      out[[rel]] <- h$sha256
    } else {
      # Preserve the key but signal the failure with NA so JSON renders null.
      out[[rel]] <- NA_character_
    }
  }
  out
}


# Git short SHA, or NULL if the working dir isn't a git repo / git missing.
.git_commit <- function() {
  res <- tryCatch(
    suppressWarnings(system2(
      "git",
      c("rev-parse", "--short", "HEAD"),
      stdout = TRUE, stderr = FALSE
    )),
    error = function(e) NULL
  )
  if (is.null(res) || length(res) == 0L || !nzchar(res[[1]])) return(NULL)
  res[[1]]
}


# git status --porcelain; non-empty stdout → dirty.
.git_dirty <- function() {
  res <- tryCatch(
    suppressWarnings(system2(
      "git",
      c("status", "--porcelain"),
      stdout = TRUE, stderr = FALSE
    )),
    error = function(e) NULL
  )
  if (is.null(res)) return(NA)            # git unavailable; can't tell
  length(res) > 0L
}


.run_id <- function() {
  ts <- format(Sys.time(), "%Y%m%d%H%M%S")
  rand <- paste(sample(c(0:9, letters[1:6]), 4, replace = TRUE), collapse = "")
  paste0(ts, "-", rand)
}


.timestamp_utc <- function() {
  format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

#' Write a run manifest for a harmonization run.
#'
#' @param survey Character: survey name (e.g. "abs", "kgss"). Used to
#'   derive the default `output_path`.
#' @param inputs Character vector of paths to raw inputs (.sav/.dta/.csv)
#'   or processed wave .rds files consumed by the run.
#' @param specs Character vector of paths to YAML harmonization specs
#'   used in the run. Use `list_survey_specs(survey)` from spec_discovery.R.
#' @param outputs Character vector of paths to harmonized output files
#'   (.rds, .parquet, .csv) produced by the run.
#' @param output_path Character: where to write the manifest JSON. Defaults
#'   to `outputs/<survey>/manifest.json` under the project root. The parent
#'   directory is created if missing.
#'
#' @return The manifest list, returned invisibly. Side effect: writes JSON
#'   to `output_path`.
#'
#' @details
#' If `output_path` is also present in `outputs`, it is stripped before
#' hashing — the manifest cannot self-reference its own hash (chicken/egg).
#' Missing input/spec/output paths do not crash the run; the corresponding
#' entry records `sha256: null` and an `error:` field.
#'
#' Re-running with identical arguments produces a manifest that differs
#' only in `run_id` and `timestamp_utc`. Every sha256 and every
#' n_rows/n_cols field is deterministic.
#'
#' @export
write_manifest <- function(survey,
                           inputs = character(),
                           specs = character(),
                           outputs = character(),
                           output_path = NULL,
                           engine = NULL) {

  if (missing(survey) || is.null(survey) || !nzchar(survey)) {
    stop("write_manifest(): `survey` must be a non-empty string", call. = FALSE)
  }

  inputs  <- as.character(inputs  %||% character())
  specs   <- as.character(specs   %||% character())
  outputs <- as.character(outputs %||% character())

  if (is.null(output_path)) {
    output_path <- here::here("outputs", survey, "manifest.json")
  }

  # Strip the manifest's own path from outputs[] before hashing, to avoid
  # a self-reference cycle. Compare via normalized path so a relative vs
  # absolute spelling of the same file still matches.
  out_norm     <- normalizePath(outputs,    winslash = "/", mustWork = FALSE)
  manifest_abs <- normalizePath(output_path, winslash = "/", mustWork = FALSE)
  outputs <- outputs[out_norm != manifest_abs]

  # Build entries.
  input_entries  <- lapply(inputs,  .build_input_entry)
  spec_entries   <- lapply(specs,   .build_spec_entry)
  output_entries <- lapply(outputs, .build_output_entry)

  manifest <- list(
    run_id          = .run_id(),
    timestamp_utc   = .timestamp_utc(),
    git_commit      = .git_commit(),
    git_dirty       = .git_dirty(),
    schema_version  = .MANIFEST_SPEC_SCHEMA_VERSION,
    inputs          = input_entries,
    specs           = spec_entries,
    outputs         = output_entries,
    engine_versions = .collect_engine_versions(
      if (is.null(engine)) .PROVENANCE_ENGINE_FILES else as.character(engine))
  )

  # Ensure parent dir exists, then write.
  parent <- dirname(output_path)
  if (!dir.exists(parent)) {
    dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  }

  jsonlite::write_json(
    manifest,
    output_path,
    pretty     = TRUE,
    auto_unbox = TRUE,
    null       = "null",
    na         = "null"
  )

  invisible(manifest)
}


# Local null-coalesce: %||% is base in R 4.4+, but many production renvs
# pin earlier versions. Define defensively.
`%||%` <- function(a, b) if (is.null(a)) b else a
