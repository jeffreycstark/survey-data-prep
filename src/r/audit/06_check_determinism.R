#!/usr/bin/env Rscript
# src/r/audit/06_check_determinism.R
#
# Layer 6 — Determinism check (audit ticket C4).
#
# Verifies the harmonization pipeline's outputs and engine state against the
# manifest written by `write_manifest()` (src/r/utils/provenance.R).
#
# IMPORTANT: This CLI does NOT re-run the harmonization pipeline. It compares
# current on-disk state to the recorded manifest only. The "true" two-run
# determinism test (run pipeline twice, diff outputs) is Phase H (CI scope).
#
# Two modes:
#
#   --fast (default)
#     Re-hashes every file path in the manifest's inputs[]/specs[]/outputs[]
#     and engine_versions{} and reports per-path status: ok / drift / missing.
#     Catches: someone edited a YAML/raw file/engine file without re-running
#     the pipeline.
#
#   --strict
#     Calls write_manifest() afresh against the SAME inputs/specs/outputs
#     paths recorded in the existing manifest, then diffs the new manifest
#     (M2) against the saved one (M1) ignoring run_id and timestamp_utc.
#     Catches: engine non-determinism (random seeds, time-varying output,
#     hash-randomized iteration order). The new manifest is written to a
#     temp file — the existing outputs/<survey>/manifest.json is NOT touched.
#
# Exit codes:
#   0  OK (everything matches)
#   1  drift, missing, or non-determinism detected; or invalid invocation
#
# CLI:
#   Rscript src/r/audit/06_check_determinism.R --survey abs
#   Rscript src/r/audit/06_check_determinism.R --survey abs --strict
#   Rscript src/r/audit/06_check_determinism.R --help
#
# See audit/01-audit-framework.md §Layer 6 and audit/02-implementation-tickets.md ticket C4.

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required (renv::install('jsonlite'))",
         call. = FALSE)
  }
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required (renv::install('digest'))",
         call. = FALSE)
  }
})

`%||%` <- function(a, b) if (!is.null(a)) a else b


# ---------------------------------------------------------------------------
# Help text
# ---------------------------------------------------------------------------
.print_help <- function() {
  cat(
    "Usage: Rscript src/r/audit/06_check_determinism.R --survey <name> [--strict]\n",
    "\n",
    "Verifies a survey's outputs/<survey>/manifest.json against on-disk state.\n",
    "Does NOT re-run the harmonization pipeline.\n",
    "\n",
    "  --survey NAME   Survey slug (e.g. abs, kgss). Manifest must exist at\n",
    "                  outputs/<survey>/manifest.json.\n",
    "  --strict        Re-invoke write_manifest() and diff against the saved\n",
    "                  manifest (ignoring run_id, timestamp_utc). Catches\n",
    "                  engine non-determinism, not just file drift.\n",
    "  --manifest PATH Override the manifest path (default: outputs/<survey>/manifest.json).\n",
    "  -h, --help      Show this message.\n",
    "\n",
    "Exit 0 = OK, exit 1 = drift / missing / non-determinism.\n",
    sep = ""
  )
}


# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, strict = FALSE, manifest = NULL)
  i <- 1L
  while (i <= length(argv)) {
    a <- argv[i]
    if (a %in% c("-h", "--help")) {
      .print_help()
      quit(status = 0)
    }
    if (a == "--survey")   { out$survey   <- argv[i + 1L]; i <- i + 2L; next }
    if (a == "--strict")   { out$strict   <- TRUE;          i <- i + 1L; next }
    if (a == "--fast")     { out$strict   <- FALSE;         i <- i + 1L; next }
    if (a == "--manifest") { out$manifest <- argv[i + 1L]; i <- i + 2L; next }
    stop(sprintf("unknown argument: %s (see --help)", a), call. = FALSE)
  }
  if (is.null(out$survey) || !nzchar(out$survey)) {
    stop("--survey <name> is required (see --help)", call. = FALSE)
  }
  out
}


# ---------------------------------------------------------------------------
# Find the manifest. Prefers an explicit override; otherwise resolves
# `outputs/<survey>/manifest.json` against the repo root via `here::here()`
# when available, falling back to the cwd.
# ---------------------------------------------------------------------------
.resolve_manifest_path <- function(survey, override = NULL) {
  if (!is.null(override) && nzchar(override)) {
    return(override)
  }
  rel <- file.path("outputs", survey, "manifest.json")
  if (requireNamespace("here", quietly = TRUE)) {
    return(here::here(rel))
  }
  rel
}


# ---------------------------------------------------------------------------
# Hash a file. Mirrors `.hash_file()` in src/r/utils/provenance.R: returns
# NULL when the file is missing/unreadable, plus a captured error message.
# Use the same algo (sha256) so values are directly comparable.
# ---------------------------------------------------------------------------
.hash_file <- function(path) {
  if (is.null(path) || is.na(path) || !nzchar(path)) {
    return(list(sha256 = NULL, error = "empty path"))
  }
  if (!file.exists(path)) {
    return(list(sha256 = NULL, error = "missing"))
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


# ---------------------------------------------------------------------------
# Manifest reader. Defensively handles missing fields so an old version of
# this script doesn't crash when a future field is added.
# ---------------------------------------------------------------------------
.read_manifest <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf(
      "manifest not found at %s — run the harmonization pipeline first\n  (outputs/<survey>/manifest.json is written by 99_create_final_dataset.R)",
      path
    ), call. = FALSE)
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}


# ---------------------------------------------------------------------------
# Iterate the recorded entries in a manifest section (inputs/specs/outputs)
# and return a tidy data.frame with: section, path, recorded_sha, status.
#
# `status` values:
#   "ok"      sha matches
#   "drift"   sha differs (file changed)
#   "missing" recorded entry but file no longer on disk
#   "skipped" recorded entry has no sha (manifest writer couldn't hash it,
#             usually because the file was missing at write time — nothing
#             to compare against)
# ---------------------------------------------------------------------------
.check_section <- function(entries, section) {
  if (is.null(entries) || length(entries) == 0L) {
    return(data.frame(
      section = character(0), path = character(0),
      recorded_sha = character(0), current_sha = character(0),
      status = character(0), stringsAsFactors = FALSE
    ))
  }
  rows <- lapply(entries, function(e) {
    p   <- e$path %||% NA_character_
    rec <- e$sha256 %||% NA_character_
    cur <- NA_character_
    status <- "ok"
    if (is.na(rec) || is.null(rec) || !nzchar(rec)) {
      # Recorded entry has no hash — can't compare. Treat as skipped.
      status <- "skipped"
    } else {
      h <- .hash_file(p)
      if (is.null(h$sha256)) {
        status <- if (identical(h$error, "missing")) "missing" else "drift"
        cur <- NA_character_
      } else {
        cur <- h$sha256
        status <- if (identical(cur, rec)) "ok" else "drift"
      }
    }
    data.frame(
      section = section,
      path = p %||% NA_character_,
      recorded_sha = rec %||% NA_character_,
      current_sha = cur %||% NA_character_,
      status = status,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}


# Engine versions are stored as a named list of {path: sha}, not as a
# parallel list of {path, sha} entries. Adapt to the .check_section shape.
.check_engine_versions <- function(engine_versions) {
  if (is.null(engine_versions) || length(engine_versions) == 0L) {
    return(.check_section(list(), "engine_versions"))
  }
  entries <- lapply(names(engine_versions), function(rel) {
    sha <- engine_versions[[rel]]
    # Engine paths are stored relative to repo root (see provenance.R).
    abs_path <- if (requireNamespace("here", quietly = TRUE)) here::here(rel) else rel
    list(path = abs_path, sha256 = if (is.null(sha) || is.na(sha)) NA_character_ else sha)
  })
  out <- .check_section(entries, "engine_versions")
  # Replace the absolute path with the relative path used in the manifest,
  # for cleaner reporting.
  out$path <- names(engine_versions)
  out
}


# ---------------------------------------------------------------------------
# Fast mode: re-hash everything in the manifest, report per-path status.
# ---------------------------------------------------------------------------
.run_fast <- function(manifest_path) {
  m <- .read_manifest(manifest_path)

  inputs_df  <- .check_section(m$inputs  %||% list(), "inputs")
  specs_df   <- .check_section(m$specs   %||% list(), "specs")
  outputs_df <- .check_section(m$outputs %||% list(), "outputs")
  engine_df  <- .check_engine_versions(m$engine_versions %||% list())

  all_df <- rbind(inputs_df, specs_df, outputs_df, engine_df)

  cat(sprintf("[determinism: fast] manifest=%s\n", manifest_path))
  cat(sprintf("  recorded: %d inputs, %d specs, %d outputs, %d engine files\n",
              nrow(inputs_df), nrow(specs_df), nrow(outputs_df), nrow(engine_df)))

  # Per-section status counts.
  for (sec in c("inputs", "specs", "outputs", "engine_versions")) {
    sub <- all_df[all_df$section == sec, , drop = FALSE]
    if (nrow(sub) == 0) next
    counts <- table(factor(sub$status,
                           levels = c("ok", "drift", "missing", "skipped")))
    cat(sprintf("  %-16s ok=%d drift=%d missing=%d skipped=%d\n",
                sec,
                counts[["ok"]], counts[["drift"]],
                counts[["missing"]], counts[["skipped"]]))
  }

  problems <- all_df[all_df$status %in% c("drift", "missing"), , drop = FALSE]
  if (nrow(problems) > 0) {
    cat(sprintf("\n  *** %d path(s) failed determinism check:\n", nrow(problems)))
    for (i in seq_len(nrow(problems))) {
      r <- problems[i, ]
      cat(sprintf("    [%s] %s  (%s)\n", r$status, r$path, r$section))
      if (r$status == "drift") {
        cat(sprintf("        recorded: %s\n", substr(r$recorded_sha, 1, 12)))
        cat(sprintf("        current : %s\n", substr(r$current_sha,  1, 12)))
      }
    }
    cat("\n  Drift in `inputs/specs` means a file was edited after the last\n")
    cat("  harmonization run. Re-run the pipeline to refresh the manifest.\n")
    cat("  Drift in `engine_versions` means engine code changed since the\n")
    cat("  manifest was written — every output is potentially stale.\n")
    cat("  Drift in `outputs` means somebody hand-edited a harmonized file.\n\n")
    quit(status = 1)
  }

  cat("\n  OK — all paths match recorded sha256.\n")
  quit(status = 0)
}


# ---------------------------------------------------------------------------
# Strict mode: rebuild the manifest in-process against the same paths and
# diff. We never overwrite the saved manifest — we write the rebuilt one
# to a temp file (so write_manifest()'s side effects don't damage state).
#
# Diff ignores run_id and timestamp_utc (those vary by definition). Every
# other field — sha256, n_rows, n_cols, git_commit, git_dirty, engine
# hashes — must match.
# ---------------------------------------------------------------------------
.normalize_manifest_for_diff <- function(m) {
  # Strip volatile fields. Use NULL not NA so the structure is consistent.
  m$run_id        <- NULL
  m$timestamp_utc <- NULL
  m
}


.deep_diff <- function(a, b, path = "$") {
  diffs <- list()
  if (identical(a, b)) return(diffs)

  # Both lists: walk keys (named) or indices (unnamed).
  if (is.list(a) && is.list(b)) {
    keys_a <- names(a); keys_b <- names(b)
    if (!is.null(keys_a) || !is.null(keys_b)) {
      keys <- union(keys_a %||% character(0), keys_b %||% character(0))
      for (k in keys) {
        sub_path <- sprintf("%s.%s", path, k)
        if (!(k %in% names(a))) {
          diffs[[length(diffs) + 1L]] <- list(path = sub_path,
                                              note = "key only in M2",
                                              a = NULL, b = b[[k]])
          next
        }
        if (!(k %in% names(b))) {
          diffs[[length(diffs) + 1L]] <- list(path = sub_path,
                                              note = "key only in M1",
                                              a = a[[k]], b = NULL)
          next
        }
        diffs <- c(diffs, .deep_diff(a[[k]], b[[k]], sub_path))
      }
    } else {
      n <- max(length(a), length(b))
      for (i in seq_len(n)) {
        sub_path <- sprintf("%s[%d]", path, i)
        if (i > length(a)) {
          diffs[[length(diffs) + 1L]] <- list(path = sub_path,
                                              note = "index only in M2",
                                              a = NULL, b = b[[i]])
          next
        }
        if (i > length(b)) {
          diffs[[length(diffs) + 1L]] <- list(path = sub_path,
                                              note = "index only in M1",
                                              a = a[[i]], b = NULL)
          next
        }
        diffs <- c(diffs, .deep_diff(a[[i]], b[[i]], sub_path))
      }
    }
    return(diffs)
  }

  # Scalar mismatch.
  diffs[[length(diffs) + 1L]] <- list(
    path = path,
    note = "value differs",
    a = a, b = b
  )
  diffs
}


.run_strict <- function(manifest_path, survey) {
  m1 <- .read_manifest(manifest_path)

  # Source the manifest writer. Resolve via `here` if available; fall back
  # to a relative path (works when invoked from the repo root).
  prov_rel <- "src/r/utils/provenance.R"
  prov_path <- if (requireNamespace("here", quietly = TRUE)) here::here(prov_rel) else prov_rel
  if (!file.exists(prov_path)) {
    stop(sprintf("cannot locate %s — strict mode requires the manifest writer",
                 prov_rel), call. = FALSE)
  }
  source(prov_path)  # exposes write_manifest()

  inputs  <- vapply(m1$inputs  %||% list(), function(e) e$path %||% NA_character_, character(1))
  specs   <- vapply(m1$specs   %||% list(), function(e) e$path %||% NA_character_, character(1))
  outputs <- vapply(m1$outputs %||% list(), function(e) e$path %||% NA_character_, character(1))

  inputs  <- inputs[!is.na(inputs)]
  specs   <- specs[!is.na(specs)]
  outputs <- outputs[!is.na(outputs)]

  # Write M2 to a temp file so we don't overwrite the saved manifest.
  tmp <- tempfile(pattern = "manifest_strict_", fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)

  # write_manifest() lives in the sourced env; call it directly.
  m2 <- write_manifest(survey  = survey,
                       inputs  = inputs,
                       specs   = specs,
                       outputs = outputs,
                       output_path = tmp)

  m1n <- .normalize_manifest_for_diff(m1)
  m2n <- .normalize_manifest_for_diff(m2)

  diffs <- .deep_diff(m1n, m2n)

  cat(sprintf("[determinism: strict] manifest=%s\n", manifest_path))
  cat(sprintf("  rebuilt manifest: %s\n", tmp))
  cat(sprintf("  inputs=%d specs=%d outputs=%d\n",
              length(inputs), length(specs), length(outputs)))

  if (length(diffs) == 0L) {
    cat("\n  OK — manifests are identical (ignoring run_id, timestamp_utc).\n")
    cat("       Engine is deterministic against the recorded inputs.\n")
    quit(status = 0)
  }

  cat(sprintf("\n  *** %d field(s) differ between recorded and rebuilt manifest:\n",
              length(diffs)))
  for (d in diffs) {
    cat(sprintf("    %s  [%s]\n", d$path, d$note))
    a_str <- if (is.null(d$a)) "<absent>" else paste(deparse(d$a), collapse = " ")
    b_str <- if (is.null(d$b)) "<absent>" else paste(deparse(d$b), collapse = " ")
    if (nchar(a_str) > 80) a_str <- paste0(substr(a_str, 1, 77), "...")
    if (nchar(b_str) > 80) b_str <- paste0(substr(b_str, 1, 77), "...")
    cat(sprintf("        M1: %s\n", a_str))
    cat(sprintf("        M2: %s\n", b_str))
  }
  cat("\n  Strict-mode failure means the manifest writer is non-deterministic\n")
  cat("  given identical inputs. Investigate before trusting the audit chain.\n")
  cat("  (Note: changes in `git_dirty` or `git_commit` between M1 and now\n")
  cat("   are real differences — commit or stash before re-running strict.)\n\n")
  quit(status = 1)
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
.main <- function(argv) {
  args <- .parse_cli_args(argv)
  manifest_path <- .resolve_manifest_path(args$survey, args$manifest)
  if (args$strict) {
    .run_strict(manifest_path, survey = args$survey)
  } else {
    .run_fast(manifest_path)
  }
}


# Only run the CLI when invoked as a script (not when sourced for testing).
if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) == 0L) {
    .print_help()
    quit(status = 1)
  }
  .main(argv)
}
