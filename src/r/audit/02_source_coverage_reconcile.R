#!/usr/bin/env Rscript
# src/r/audit/02_source_coverage_reconcile.R
#
# Layer 2 — Source-coverage reconciliation (bidirectional).
#
# F4 (02_check_codebook.R) and F5 (02_coverage_report.R) both iterate the
# YAML *claims* and ask whether the extracted codebook backs them. Neither
# walks the other direction: a (raw_var x wave) that carries real data in the
# codebook but that NO spec maps is invisible to them. That is the more
# dangerous error class — silently un-harmonized data — and it is the one this
# module adds.
#
# The extracted-codebook parquet at data/<survey>/codebook/ is an empirical
# coverage matrix: the per-survey extractor emits a (raw_var x wave) row only
# where that variable has >= 1 non-missing observation in the raw data (see
# src/r/audit/extractors/<survey>_codebook.R). So "(raw_var, wave) present in
# the parquet" == "that column carries data in that wave". This module joins
# that matrix against every spec's per-wave `source:` block and classifies each
# (concept x wave) cell:
#
#   ok    — spec maps the concept in this wave AND the mapped raw_var has data
#   over  — spec maps the concept in this wave but the mapped raw_var is empty
#           (the question was not fielded that wave; the cell harmonizes to all
#           NA and passed coverage silently — see validate_completeness()).
#           Fix: set that wave's source to null / drop the key.
#   under — the concept's raw_var carries data in this wave but the spec maps
#           the concept in no wave at all here. Fix (after confirming the code
#           matches): add the wave to the source block. NEEDS HUMAN REVIEW —
#           a concept may legitimately use a different raw code that year.
#
# Reconciliation is at the CONCEPT (var_id) grain, not raw_var: a concept that
# the spec maps via a different raw code in a given wave is correctly counted
# as covered for that wave.
#
# Survey-generic: works for any survey with an extracted codebook parquet
# (today: abs, ipus, kinu). Surveys with per-wave .sav files rarely show `over`
# cells (an unasked question is an absent column, which the harmonizer skips),
# but `under` is informative everywhere.
#
# CLI:
#   Rscript src/r/audit/02_source_coverage_reconcile.R --survey kinu
#   Rscript src/r/audit/02_source_coverage_reconcile.R --all-surveys
#   Rscript src/r/audit/02_source_coverage_reconcile.R --survey kinu --quiet
#
# Output:
#   audit/reports/<survey>/02-source-coverage.csv
#     columns: survey, direction, var_id, wave, raw_var, spec_file, message
#
# Exit codes:
#   0  no over-declared cells (spec source blocks are honest about data presence)
#   1  at least one over-declared cell (a confirmable spec error)
#   2  prerequisites missing (no extracted codebook parquet for a requested survey)
#
# See audit/01-audit-framework.md Layer 2.

suppressPackageStartupMessages({
  library(here)
  library(yaml)
  library(arrow)
  library(dplyr)
  library(tibble)
})

here::i_am("src/r/audit/02_source_coverage_reconcile.R")
source(here::here("src/r/utils/spec_discovery.R"))

`%||%` <- function(a, b) if (is.null(a)) b else a

.SUPPORTED_SURVEYS <- c("abs", "ipus", "kinu")  # surveys with an extractor today


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------

# Empirical coverage matrix: distinct (raw_var, wave) that carry data, plus the
# universe of waves the extractor produced (used to avoid mislabelling an
# unextracted wave as an over-declaration).
load_coverage <- function(survey) {
  codebook_dir <- here::here("data", survey, "codebook")
  files <- list.files(codebook_dir, pattern = "[.]parquet$", full.names = TRUE)
  if (length(files) == 0L) {
    stop(sprintf("No extracted codebook at %s. Run src/r/audit/extractors/%s_codebook.R first.",
                 codebook_dir, survey), call. = FALSE)
  }
  cov <- lapply(files, function(f) {
    df <- tryCatch(as.data.frame(arrow::read_parquet(f, col_select = c("raw_var", "wave"))),
                   error = function(e) NULL)
    if (is.null(df)) NULL else df
  })
  cov <- bind_rows(cov[!vapply(cov, is.null, logical(1))])
  if (nrow(cov) == 0L) {
    stop(sprintf("Extracted codebook at %s is empty.", codebook_dir), call. = FALSE)
  }
  cov %>%
    transmute(raw_var = as.character(raw_var), wave = as.character(wave)) %>%
    distinct()
}

# Spec claims: one row per (var_id, wave, raw_var) the YAMLs actively map.
load_claims <- function(survey) {
  spec_paths <- list_survey_specs(survey)
  rows <- list()
  for (sp in spec_paths) {
    parsed <- tryCatch(yaml::read_yaml(sp), error = function(e) NULL)
    if (is.null(parsed) || is.null(parsed$variables)) next
    spec_file <- basename(sp)
    for (v in parsed$variables) {
      src <- v$source
      if (is.null(src)) next
      for (wk in names(src)) {
        raw_var <- src[[wk]]
        if (is.null(raw_var) || (length(raw_var) == 1L && is.na(raw_var))) next
        if (!nzchar(as.character(raw_var))) next
        rows[[length(rows) + 1L]] <- tibble(
          var_id    = v$id,
          wave      = as.character(wk),
          raw_var   = as.character(raw_var),
          spec_file = spec_file
        )
      }
    }
  }
  if (length(rows) == 0L) {
    return(tibble(var_id = character(0), wave = character(0),
                  raw_var = character(0), spec_file = character(0)))
  }
  bind_rows(rows)
}


# ---------------------------------------------------------------------------
# Reconciliation
# ---------------------------------------------------------------------------

reconcile_source_coverage <- function(survey) {
  coverage <- load_coverage(survey)
  claims   <- load_claims(survey)

  cov_keys   <- paste(coverage$raw_var, coverage$wave, sep = "\r")
  cov_waves  <- unique(coverage$wave)          # waves the extractor produced
  claim_keys <- paste(claims$raw_var, claims$wave, sep = "\r")

  # --- OVER: spec maps (var, wave, raw_var) but that raw_var is empty there.
  # Restrict to waves the extractor actually covered, so an unextracted wave is
  # not misread as an over-declaration.
  over <- claims %>%
    filter(wave %in% cov_waves) %>%
    filter(!paste(raw_var, wave, sep = "\r") %in% cov_keys) %>%
    transmute(survey = survey, direction = "over", var_id, wave, raw_var, spec_file,
              message = sprintf("spec maps %s in %s but it carries no data (not fielded) - set source to null",
                                raw_var, wave))

  # --- UNDER: a concept's raw_var has data in a wave the concept is not mapped
  # in at all. Concept grain: mapped-in-any-wave counts as covered.
  mapped_waves <- claims %>% distinct(var_id, wave)
  # candidate (var_id, wave, raw_var): raw_var used by the concept somewhere AND
  # has data in `wave`, joined to whether the concept is mapped in that wave.
  concept_rawvars <- claims %>% distinct(var_id, raw_var)
  under <- concept_rawvars %>%
    inner_join(coverage, by = "raw_var", relationship = "many-to-many") %>%  # waves raw_var has data
    anti_join(mapped_waves, by = c("var_id", "wave")) %>%                     # concept not mapped there
    distinct(var_id, wave, raw_var) %>%
    left_join(distinct(claims, var_id, spec_file), by = "var_id") %>%
    transmute(survey = survey, direction = "under", var_id, wave, raw_var,
              spec_file = spec_file %||% NA_character_,
              message = sprintf("%s has data in %s but concept is unmapped there - add wave (verify code)",
                                raw_var, wave))

  bind_rows(over, under) %>% arrange(direction, var_id, wave)
}


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

run_survey <- function(survey, quiet = FALSE) {
  res <- reconcile_source_coverage(survey)

  out_dir <- here::here("audit", "reports", survey)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  out_csv <- file.path(out_dir, "02-source-coverage.csv")
  utils::write.csv(res, out_csv, row.names = FALSE, na = "")

  n_over  <- sum(res$direction == "over")
  n_under <- sum(res$direction == "under")

  if (!quiet) {
    cat(sprintf("\n=== source-coverage reconciliation: %s ===\n", survey))
    cat(sprintf("  over-declared  (spec maps, no data) : %3d  -> set source null\n", n_over))
    cat(sprintf("  under-declared (data, concept unmapped): %3d  -> review & add\n", n_under))
    cat(sprintf("  CSV: %s\n", out_csv))
    if (n_over > 0) {
      cat("\n  over-declared (first 10):\n")
      ov <- head(res[res$direction == "over", ], 10)
      for (i in seq_len(nrow(ov)))
        cat(sprintf("    %-28s %-7s %-8s [%s]\n",
                    ov$var_id[i], ov$wave[i], ov$raw_var[i], ov$spec_file[i]))
    }
    if (n_under > 0) {
      cat("\n  under-declared (first 10):\n")
      ud <- head(res[res$direction == "under", ], 10)
      for (i in seq_len(nrow(ud)))
        cat(sprintf("    %-28s %-7s %-8s [%s]\n",
                    ud$var_id[i], ud$wave[i], ud$raw_var[i], ud$spec_file[i]))
    }
  }
  list(survey = survey, n_over = n_over, n_under = n_under, csv = out_csv)
}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

.main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--help" %in% args || "-h" %in% args) {
    cat("Usage: Rscript src/r/audit/02_source_coverage_reconcile.R [--survey <s> | --all-surveys] [--quiet]\n")
    cat("Supported (have an extractor):", paste(.SUPPORTED_SURVEYS, collapse = ", "), "\n")
    quit(status = 0)
  }
  quiet <- "--quiet" %in% args
  surveys <- if ("--all-surveys" %in% args) {
    .SUPPORTED_SURVEYS
  } else {
    i <- match("--survey", args)
    if (is.na(i) || i == length(args)) {
      cat("ERROR: pass --survey <name> or --all-surveys\n"); quit(status = 2)
    }
    args[i + 1L]
  }

  any_over <- FALSE; any_missing <- FALSE
  for (s in surveys) {
    r <- tryCatch(run_survey(s, quiet = quiet), error = function(e) {
      cat(sprintf("\n[%s] SKIP: %s\n", s, conditionMessage(e))); NULL
    })
    if (is.null(r)) { any_missing <- TRUE; next }
    if (r$n_over > 0) any_over <- TRUE
  }
  if (any_missing) quit(status = 2)
  quit(status = if (any_over) 1 else 0)
}

if (identical(environment(), globalenv()) && !interactive()) {
  .main()
}
