#!/usr/bin/env Rscript
# src/r/audit/06_check_input_drift.R
#
# Audit ticket C5: Raw-input drift detector.
#
# Compares current sha256 of every file recorded under `inputs[]` in
# outputs/<survey>/manifest.json against the hash captured at the last
# harmonization run. Surfaces silent re-releases of raw .sav files (e.g.
# the same `data/abs/raw/wave3/ABS3 merge20250609.sav` path filled with
# new bytes) and missing input files.
#
# This is intentionally narrower than the C4 determinism check: C4 watches
# the entire manifest including engine + outputs; C5 watches *inputs* only,
# because a changed input means the existing harmonized output no longer
# corresponds to its source — even when nothing else moved.
#
# Usage:
#   Rscript src/r/audit/06_check_input_drift.R --survey abs
#   Rscript src/r/audit/06_check_input_drift.R --help
#
# Exit codes:
#   0 — every input is unchanged AND present
#   1 — at least one input is CHANGED or missing, OR manifest is missing/
#       unreadable, OR --survey was not provided

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required (renv::install('jsonlite'))")
  }
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required (renv::install('digest'))")
  }
})

# ---------------------------------------------------------------------------
# Defensive null-coalesce. Manifests written before a future field was added
# may lack keys — `%||%` lets us read those without crashing.
# ---------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a)) b else a


# ---------------------------------------------------------------------------
# CLI parsing — minimal, no extra deps. Recognizes --survey <name>, --help,
# -h. Anything else is rejected so typos don't pass through silently.
# ---------------------------------------------------------------------------
.print_usage <- function() {
  cat("Usage: Rscript src/r/audit/06_check_input_drift.R --survey <name>\n",
      "\n",
      "Compares the current sha256 of every input file recorded in\n",
      "outputs/<survey>/manifest.json against the hash captured at the\n",
      "last harmonization run.\n",
      "\n",
      "Arguments:\n",
      "  --survey <name>   Survey identifier (e.g. abs, kgss, wvs).\n",
      "  -h, --help        Print this help and exit 0.\n",
      "\n",
      "Exit codes:\n",
      "  0   no drift, no missing inputs\n",
      "  1   drift detected, inputs missing, or manifest unreadable\n",
      sep = "")
}

.parse_args <- function(args) {
  if (length(args) == 0L) {
    return(list(help = FALSE, survey = NULL, error = "no arguments provided"))
  }
  if (any(args %in% c("--help", "-h"))) {
    return(list(help = TRUE, survey = NULL, error = NULL))
  }
  survey <- NULL
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--survey") {
      if (i == length(args)) {
        return(list(help = FALSE, survey = NULL,
                    error = "--survey requires a value"))
      }
      survey <- args[[i + 1L]]
      i <- i + 2L
    } else {
      return(list(help = FALSE, survey = NULL,
                  error = sprintf("unrecognized argument: %s", a)))
    }
  }
  if (is.null(survey) || !nzchar(survey)) {
    return(list(help = FALSE, survey = NULL,
                error = "--survey is required"))
  }
  list(help = FALSE, survey = survey, error = NULL)
}


# ---------------------------------------------------------------------------
# Locate the manifest. Use here:: if available so the script works regardless
# of cwd, otherwise fall back to a relative path. Returns absolute path or
# NULL with a captured error.
# ---------------------------------------------------------------------------
.locate_manifest <- function(survey) {
  rel <- file.path("outputs", survey, "manifest.json")
  if (requireNamespace("here", quietly = TRUE)) {
    return(here::here(rel))
  }
  normalizePath(rel, mustWork = FALSE)
}


# ---------------------------------------------------------------------------
# Compute current sha256 of a file. Returns NULL if the file is missing or
# unreadable so the caller can branch on the missing case.
# ---------------------------------------------------------------------------
.current_sha256 <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(
    digest::digest(file = path, algo = "sha256"),
    error = function(e) NULL
  )
}


# ---------------------------------------------------------------------------
# Cheap n_rows lookup for a CHANGED input. Only attempted for .rds and .sav;
# everything else returns NULL. .sav can be expensive on large multi-country
# files — we read it via haven::read_sav() since that's what the rest of the
# pipeline uses, but if haven isn't available we degrade to NULL rather than
# failing the audit.
# ---------------------------------------------------------------------------
.input_n_rows <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "rds") {
    return(tryCatch({
      obj <- readRDS(path)
      NROW(obj)
    }, error = function(e) NULL))
  }
  if (ext == "sav") {
    if (!requireNamespace("haven", quietly = TRUE)) return(NULL)
    return(tryCatch({
      d <- haven::read_sav(path)
      NROW(d)
    }, error = function(e) NULL))
  }
  NULL
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  parsed <- .parse_args(args)

  if (parsed$help) {
    .print_usage()
    quit(status = 0)
  }
  if (!is.null(parsed$error)) {
    cat("ERROR:", parsed$error, "\n\n", sep = " ")
    .print_usage()
    quit(status = 1)
  }

  survey <- parsed$survey
  manifest_path <- .locate_manifest(survey)

  if (!file.exists(manifest_path)) {
    cat(sprintf(
      "ERROR: manifest not found at %s\n",
      manifest_path
    ))
    cat("Run the survey's 99_create_final_dataset.R first to write a manifest.\n")
    quit(status = 1)
  }

  manifest <- tryCatch(
    jsonlite::read_json(manifest_path, simplifyVector = FALSE),
    error = function(e) e
  )
  if (inherits(manifest, "error")) {
    cat(sprintf("ERROR: cannot parse manifest %s: %s\n",
                manifest_path, conditionMessage(manifest)))
    quit(status = 1)
  }

  inputs <- manifest$inputs %||% list()
  if (length(inputs) == 0L) {
    cat(sprintf(
      "WARNING: manifest %s contains no inputs[] — nothing to check.\n",
      manifest_path
    ))
    cat("unchanged: 0 files\nCHANGED: 0 files\nmissing: 0 files\n")
    quit(status = 0)
  }

  unchanged_paths <- character()
  changed_entries <- list()
  missing_paths   <- character()

  for (entry in inputs) {
    path <- entry$path %||% NA_character_
    old_sha <- entry$sha256 %||% NA_character_

    if (is.na(path) || !nzchar(path)) {
      # Skip malformed entry; record as missing-shaped so the user notices.
      missing_paths <- c(missing_paths, "<unknown path in manifest>")
      next
    }

    if (!file.exists(path)) {
      missing_paths <- c(missing_paths, path)
      next
    }

    new_sha <- .current_sha256(path)
    if (is.null(new_sha)) {
      # File exists but unreadable — treat as missing for the audit's purpose.
      missing_paths <- c(missing_paths, path)
      next
    }

    if (is.na(old_sha) || !nzchar(old_sha)) {
      # Manifest never recorded a hash for this file. Surface it as CHANGED
      # so the user re-records — `unchanged` would be a false reassurance.
      changed_entries[[length(changed_entries) + 1L]] <- list(
        path     = path,
        old_sha  = NA_character_,
        new_sha  = new_sha,
        n_rows   = .input_n_rows(path)
      )
      next
    }

    if (identical(new_sha, old_sha)) {
      unchanged_paths <- c(unchanged_paths, path)
    } else {
      changed_entries[[length(changed_entries) + 1L]] <- list(
        path     = path,
        old_sha  = old_sha,
        new_sha  = new_sha,
        n_rows   = .input_n_rows(path)
      )
    }
  }

  # ---- Print structured summary -----------------------------------------
  n_unchanged <- length(unchanged_paths)
  n_changed   <- length(changed_entries)
  n_missing   <- length(missing_paths)

  cat(sprintf("unchanged: %d files\n", n_unchanged))
  cat(sprintf("CHANGED: %d files\n",   n_changed))
  if (n_changed > 0L) {
    for (e in changed_entries) {
      cat(sprintf("  %s\n", e$path))
      cat(sprintf("    old sha256: %s\n",
                  if (is.na(e$old_sha)) "<not recorded>" else e$old_sha))
      cat(sprintf("    new sha256: %s\n", e$new_sha))
      nr <- if (is.null(e$n_rows)) "null (skipped)" else as.character(e$n_rows)
      cat(sprintf("    new n_rows: %s\n", nr))
    }
  }
  cat(sprintf("missing: %d files\n", n_missing))
  if (n_missing > 0L) {
    for (p in missing_paths) cat(sprintf("  %s\n", p))
  }

  if (n_changed > 0L || n_missing > 0L) {
    quit(status = 1)
  }
  quit(status = 0)
}

main()
