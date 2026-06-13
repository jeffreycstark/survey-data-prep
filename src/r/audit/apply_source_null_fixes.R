#!/usr/bin/env Rscript
# src/r/audit/apply_source_null_fixes.R
#
# Applies the safe half of 02_source_coverage_reconcile.R's output: every
# `over`-declared (concept x wave) cell — where the spec maps a raw_var that
# carries NO data in that wave (the question was not fielded) — is rewritten in
# place from
#       <wave>: <code>
# to
#       <wave>: null  # not fielded (codebook)
#
# Why null and not deletion: `key: null` parses to a NULL value, which every
# loader (harmonize preflight, validate_variable_wave, the reconciler/claim
# loaders) already treats as "no source for this wave" — identical harmonized
# output (still NA) — while keeping the wave key visible so a reader sees the
# wave was considered and is intentionally unmapped.
#
# ONLY touches `over` rows. `under` rows (data exists, concept unmapped) are
# left alone: adding a mapping needs human confirmation the raw code asks the
# same question that year. This script never adds or removes data.
#
# Edits are scoped to each variable's `source:` block by indentation tracking,
# so a wave key appearing under qc.valid_range_by_wave is never touched. An
# edit is applied only when the code on the line matches the code the CSV
# expects — a mismatch is reported and skipped, never guessed.
#
# CLI:
#   Rscript src/r/audit/apply_source_null_fixes.R --survey kinu            # dry-run
#   Rscript src/r/audit/apply_source_null_fixes.R --survey kinu --apply    # write
#   Rscript src/r/audit/apply_source_null_fixes.R --csv <path> --apply
#
# Default is dry-run: prints every planned edit as file:line OLD -> NEW and
# writes nothing. Pass --apply to write.
#
# Exit codes: 0 ok (dry-run, or applied with no mismatches); 1 mismatches /
# unlocated cells; 2 bad invocation / missing CSV.

suppressPackageStartupMessages({
  library(here)
})
here::i_am("src/r/audit/apply_source_null_fixes.R")
source(here::here("src/r/utils/spec_discovery.R"))

# Match `  <indent><wave>: <code>` with optional trailing comment. Captures
# indent, wave, code.
.SOURCE_LINE <- "^(\\s+)([A-Za-z0-9_]+):\\s+([A-Za-z0-9_.]+)\\s*(#.*)?$"
.ID_LINE     <- "^(\\s*)-\\s*id:\\s*([A-Za-z0-9_.]+)\\s*$"
.SOURCE_HEAD <- "^(\\s*)source:\\s*$"
.indent_of   <- function(line) nchar(sub("^( *).*$", "\\1", line))


# Returns a list of planned edits, each: list(file, line_no, old, new, status)
plan_edits <- function(over_df, spec_dir) {
  by_file <- split(over_df, over_df$spec_file)
  edits <- list()

  for (spec_file in names(by_file)) {
    targets <- by_file[[spec_file]]
    # key (var_id \r wave) -> expected code
    want <- setNames(as.character(targets$raw_var),
                     paste(targets$var_id, targets$wave, sep = "\r"))
    located <- setNames(rep(FALSE, length(want)), names(want))

    path <- file.path(spec_dir, spec_file)
    lines <- readLines(path, warn = FALSE)

    cur_var <- NA_character_
    in_source <- FALSE
    source_indent <- -1L

    for (i in seq_along(lines)) {
      ln <- lines[i]

      m_id <- regmatches(ln, regexec(.ID_LINE, ln))[[1]]
      if (length(m_id) == 3) { cur_var <- m_id[3]; in_source <- FALSE; next }

      m_src <- regmatches(ln, regexec(.SOURCE_HEAD, ln))[[1]]
      if (length(m_src) == 2) { in_source <- TRUE; source_indent <- nchar(m_src[2]); next }

      # Leaving the source block: a non-blank line indented <= `source:`.
      if (in_source && nzchar(trimws(ln)) && .indent_of(ln) <= source_indent) {
        in_source <- FALSE
      }
      if (!in_source || is.na(cur_var)) next

      m <- regmatches(ln, regexec(.SOURCE_LINE, ln))[[1]]
      if (length(m) != 5) next
      indent <- m[2]; wave <- m[3]; code <- m[4]
      key <- paste(cur_var, wave, sep = "\r")
      if (!key %in% names(want)) next

      status <- if (identical(code, unname(want[[key]]))) "ok" else
        sprintf("MISMATCH(found %s, expected %s)", code, want[[key]])
      located[key] <- TRUE
      if (startsWith(status, "ok")) {
        new <- sprintf("%s%s: null  # not fielded (codebook)", indent, wave)
        edits[[length(edits) + 1L]] <- list(
          file = spec_file, line_no = i, old = ln, new = new, status = "ok")
      } else {
        edits[[length(edits) + 1L]] <- list(
          file = spec_file, line_no = i, old = ln, new = NA_character_, status = status)
      }
    }

    miss <- names(located)[!located]
    for (k in miss) {
      parts <- strsplit(k, "\r")[[1]]
      edits[[length(edits) + 1L]] <- list(
        file = spec_file, line_no = NA_integer_,
        old = sprintf("%s / %s (expected %s)", parts[1], parts[2], want[[k]]),
        new = NA_character_, status = "NOT_FOUND")
    }
  }
  edits
}


apply_edits <- function(edits, spec_dir) {
  ok <- Filter(function(e) e$status == "ok" && !is.na(e$line_no), edits)
  by_file <- split(ok, vapply(ok, function(e) e$file, character(1)))
  for (spec_file in names(by_file)) {
    path <- file.path(spec_dir, spec_file)
    lines <- readLines(path, warn = FALSE)
    for (e in by_file[[spec_file]]) lines[e$line_no] <- e$new
    writeLines(lines, path)
  }
  invisible(length(ok))
}


.main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--help" %in% args || "-h" %in% args) {
    cat("Usage: Rscript src/r/audit/apply_source_null_fixes.R --survey <s> [--apply]\n")
    cat("       Rscript src/r/audit/apply_source_null_fixes.R --csv <path> --apply\n")
    quit(status = 0)
  }
  do_apply <- "--apply" %in% args

  i <- match("--survey", args); j <- match("--csv", args)
  if (!is.na(i) && i < length(args)) {
    survey <- args[i + 1L]
    csv <- here::here("audit", "reports", survey, "02-source-coverage.csv")
  } else if (!is.na(j) && j < length(args)) {
    csv <- args[j + 1L]
    survey <- basename(dirname(csv))
  } else {
    cat("ERROR: pass --survey <name> (or --csv <path>)\n"); quit(status = 2)
  }
  if (!file.exists(csv)) {
    cat(sprintf("ERROR: no reconciler CSV at %s — run 02_source_coverage_reconcile.R first\n", csv))
    quit(status = 2)
  }

  spec_dir <- find_survey_spec_dir(survey)
  recon <- utils::read.csv(csv, stringsAsFactors = FALSE)
  over <- recon[recon$direction == "over", , drop = FALSE]
  cat(sprintf("Survey %s: %d over-declared cells to null out\n", survey, nrow(over)))
  if (nrow(over) == 0) quit(status = 0)

  edits <- plan_edits(over, spec_dir)
  n_ok       <- sum(vapply(edits, function(e) e$status == "ok", logical(1)))
  n_mismatch <- sum(vapply(edits, function(e) startsWith(e$status, "MISMATCH"), logical(1)))
  n_missing  <- sum(vapply(edits, function(e) e$status == "NOT_FOUND", logical(1)))

  cat(sprintf("  planned: %d ok | %d mismatch | %d not-found\n\n", n_ok, n_mismatch, n_missing))
  for (e in edits) {
    if (e$status == "ok") {
      cat(sprintf("  %s:%d\n      - %s\n      + %s\n", e$file, e$line_no, trimws(e$old), trimws(e$new)))
    } else {
      cat(sprintf("  [%s] %s: %s\n", e$status, e$file, trimws(e$old)))
    }
  }

  if (do_apply) {
    if (n_mismatch > 0 || n_missing > 0) {
      cat("\nREFUSING to apply: resolve mismatches / not-found cells first.\n")
      quit(status = 1)
    }
    n <- apply_edits(edits, spec_dir)
    cat(sprintf("\nAPPLIED %d edits across %d files.\n", n,
                length(unique(vapply(Filter(function(e) e$status=="ok", edits),
                                     function(e) e$file, character(1))))))
  } else {
    cat("\n(dry-run — pass --apply to write)\n")
  }
  quit(status = if (n_mismatch > 0 || n_missing > 0) 1 else 0)
}

if (identical(environment(), globalenv()) && !interactive()) {
  .main()
}
